// Multi-store migration: puts every existing (pre multi-store) record into
// the original store, STORE001, and creates that store.
//
// SAFE BY DEFAULT: without --apply it only reports what it would change.
// IDEMPOTENT: it only touches records that have no storeId yet, so running
// it again changes nothing (and reports 0 migrated).
//
//   # 1. Back up first (Console → Firestore → Import/Export, or:
//   #    gcloud firestore export gs://<bucket>/pre-multistore)
//   cd tools && npm install && cd ..
//   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\service-account.json'
//   node tools/migrate_multistore.mjs                       # dry run + report
//   node tools/migrate_multistore.mjs --apply               # migrate
//   node tools/migrate_multistore.mjs --apply --super-admin-email you@x.com
//
// Options:
//   --store STORE001        store id/code for the existing data
//   --name "Pune Main"      store name (default: the shop name in settings)
//   --super-admin-email E   make this existing Firebase Auth user SUPER_ADMIN
//   --super-admin-name N    its staff name (default: its display name, else
//                           "Super Admin")
//   --report FILE           where to write the report (default
//                           migration-report-<time>.md)
//
// Against the emulator: set FIRESTORE_EMULATOR_HOST (and
// FIREBASE_AUTH_EMULATOR_HOST for --super-admin-email) and GCLOUD_PROJECT.

import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { initAdmin } from './admin_init.mjs';

/** Store-owned top-level collections (see the architecture document). */
export const STORE_COLLECTIONS = [
  'brands', 'branches', 'suppliers', 'products', 'stock', 'batches',
  'stockLogs', 'bills', 'purchases', 'customers', 'draftBills',
];

/** Store-owned subcollections: [parent collection, subcollection]. */
export const STORE_SUBCOLLECTIONS = [
  ['bills', 'billItems'],
  ['purchases', 'purchaseItems'],
  ['customers', 'ledgerEntries'],
];

/** Totals that must be identical before and after (only a field is added). */
const SUMS = {
  bills: 'totalAmount',
  purchases: 'totalAmount',
  customers: 'outstandingBalance',
  stock: 'bagsRemaining',
  batches: 'bagsAvailable',
};

const BATCH = 400;

async function writeInBatches(db, refs, data) {
  for (let i = 0; i < refs.length; i += BATCH) {
    const b = db.batch();
    for (const r of refs.slice(i, i + BATCH)) b.update(r, data);
    await b.commit();
  }
}

/** Counts and totals of every store-owned collection (for validation). */
async function census(db, storeId) {
  const out = {};
  for (const col of STORE_COLLECTIONS) {
    const snap = await db.collection(col).get();
    const sumField = SUMS[col];
    let missing = 0, here = 0, other = 0, sum = 0;
    for (const d of snap.docs) {
      const s = d.get('storeId');
      if (s === undefined || s === null || s === '') missing++;
      else if (s === storeId) here++;
      else other++;
      if (sumField) sum += Number(d.get(sumField) ?? 0);
    }
    out[col] = { total: snap.size, missing, here, other, sum: sumField ? Math.round(sum * 100) / 100 : null };
  }
  for (const [parent, sub] of STORE_SUBCOLLECTIONS) {
    const parents = await db.collection(parent).get();
    let total = 0, missing = 0;
    for (const p of parents.docs) {
      const kids = await p.ref.collection(sub).get();
      total += kids.size;
      missing += kids.docs.filter((k) => !k.get('storeId')).length;
    }
    out[`${parent}/${sub}`] = { total, missing };
  }
  const staff = await db.collection('staff').get();
  out.staff = {
    total: staff.size,
    missing: staff.docs.filter((d) => d.get('role') !== 'super_admin' && !d.get('storeId')).length,
  };
  return out;
}

/**
 * Runs the migration. Returns { report, before, after, rows }.
 * With apply=false nothing is written.
 */
export async function migrate({ db, auth, storeId = 'STORE001', name, apply = false, superAdminEmail, superAdminName }) {
  const log = [];
  const say = (line) => { log.push(line); console.log(line); };
  const now = new Date().toISOString();
  say(`# Multi-store migration ${apply ? '(APPLY)' : '(DRY RUN — nothing written)'}`);
  say(`Store: ${storeId} · ${now}`);

  const before = await census(db, storeId);

  // ---- 1. the store and its settings/counters ----
  const legacySettings = (await db.doc('meta/settings').get()).data() ?? {};
  const legacyCounters = (await db.doc('meta/counters').get()).data() ?? {};
  const storeRef = db.doc(`stores/${storeId}`);
  const storeSnap = await storeRef.get();
  if (!storeSnap.exists) {
    say(`- create stores/${storeId} ("${name ?? legacySettings.shop ?? 'Main store'}")`);
    if (apply) {
      await storeRef.set({
        storeCode: storeId,
        storeName: name ?? legacySettings.shop ?? 'Main store',
        legalName: '', address: '', city: '', state: '', pincode: '',
        phone: '', email: '', gstNumber: '',
        status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata',
        createdAt: now, updatedAt: now, createdBy: 'migration',
      });
    }
  } else {
    say(`- stores/${storeId} already exists (kept)`);
  }
  const settingsRef = db.doc(`stores/${storeId}/meta/settings`);
  if (!(await settingsRef.get()).exists) {
    say(`- copy meta/settings → stores/${storeId}/meta/settings`);
    if (apply) await settingsRef.set(legacySettings);
  }
  const countersRef = db.doc(`stores/${storeId}/meta/counters`);
  const current = (await countersRef.get()).data() ?? {};
  const merged = {};
  for (const k of new Set([...Object.keys(legacyCounters), ...Object.keys(current)])) {
    merged[k] = Math.max(Number(legacyCounters[k] ?? 0), Number(current[k] ?? 0));
  }
  // Never move a counter backwards: numbers already used stay used.
  if (JSON.stringify(merged) !== JSON.stringify(current)) {
    say(`- counters → ${JSON.stringify(merged)}`);
    if (apply) await countersRef.set(merged, { merge: true });
  }

  // ---- 2. every store-owned record without a storeId ----
  const rows = [];
  for (const col of STORE_COLLECTIONS) {
    const snap = await db.collection(col).get();
    const todo = snap.docs.filter((d) => !d.get('storeId')).map((d) => d.ref);
    let failed = 0;
    if (apply && todo.length) {
      try { await writeInBatches(db, todo, { storeId }); } catch (e) { failed = todo.length; say(`  ! ${col}: ${e}`); }
    }
    rows.push({ col, before: snap.size, migrated: apply ? todo.length - failed : todo.length, failed });
  }
  for (const [parent, sub] of STORE_SUBCOLLECTIONS) {
    const parents = await db.collection(parent).get();
    let total = 0, todoCount = 0, failed = 0;
    for (const p of parents.docs) {
      const kids = await p.ref.collection(sub).get();
      total += kids.size;
      // A child always belongs to its parent's store.
      const owner = p.get('storeId') || storeId;
      const todo = kids.docs.filter((k) => !k.get('storeId')).map((k) => k.ref);
      todoCount += todo.length;
      if (apply && todo.length) {
        try { await writeInBatches(db, todo, { storeId: owner }); } catch (e) { failed += todo.length; say(`  ! ${parent}/${p.id}/${sub}: ${e}`); }
      }
    }
    rows.push({ col: `${parent}/*/${sub}`, before: total, migrated: apply ? todoCount - failed : todoCount, failed });
  }

  // ---- 3. staff: existing store users → this store ----
  const staffSnap = await db.collection('staff').get();
  const staffTodo = staffSnap.docs
    .filter((d) => d.get('role') !== 'super_admin' && !d.get('storeId'))
    .map((d) => d.ref);
  if (apply && staffTodo.length) await writeInBatches(db, staffTodo, { storeId });
  rows.push({ col: 'staff', before: staffSnap.size, migrated: staffTodo.length, failed: 0 });

  // ---- 4. optional: the super admin ----
  if (superAdminEmail) {
    const user = await auth.getUserByEmail(superAdminEmail);
    say(`- SUPER_ADMIN: ${superAdminEmail} (uid ${user.uid})`);
    if (apply) {
      await db.doc(`staff/${user.uid}`).set({
        name: superAdminName ?? user.displayName ?? 'Super Admin',
        email: superAdminEmail,
        role: 'super_admin',
        storeId: null,
        active: true,
      }, { merge: true });
    }
  }

  // ---- 5. validation ----
  const after = apply ? await census(db, storeId) : before;
  const problems = [];
  if (apply) {
    for (const col of STORE_COLLECTIONS) {
      if (after[col].total !== before[col].total) problems.push(`${col}: count ${before[col].total} → ${after[col].total}`);
      if (after[col].missing !== 0) problems.push(`${col}: ${after[col].missing} record(s) still without storeId`);
      if (before[col].sum !== null && after[col].sum !== before[col].sum) {
        problems.push(`${col}: total ${before[col].sum} → ${after[col].sum}`);
      }
    }
    for (const [parent, sub] of STORE_SUBCOLLECTIONS) {
      const k = `${parent}/${sub}`;
      if (after[k].total !== before[k].total) problems.push(`${k}: count changed`);
      if (after[k].missing !== 0) problems.push(`${k}: ${after[k].missing} without storeId`);
    }
    if (after.staff.missing !== 0) problems.push(`staff: ${after.staff.missing} without a store`);
  }

  say('');
  say('| Collection | Before | Migrated | Failed |');
  say('|---|---:|---:|---:|');
  for (const r of rows) say(`| ${r.col} | ${r.before} | ${r.migrated} | ${r.failed} |`);
  say('');
  say('| Check | Before | After |');
  say('|---|---:|---:|');
  for (const col of Object.keys(SUMS)) {
    say(`| ${col} total ${SUMS[col]} | ${before[col].sum} | ${after[col].sum} |`);
  }
  say('');
  if (!apply) say('DRY RUN — run again with --apply to migrate.');
  else if (problems.length) {
    say('VALIDATION FAILED:');
    for (const p of problems) say(`- ${p}`);
  } else {
    say('VALIDATION PASSED: same record counts and totals; every record has a storeId.');
  }
  return { report: log.join('\n'), before, after, rows, problems };
}

// ---- CLI ----
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const arg = (k) => {
    const i = process.argv.indexOf(k);
    return i > 0 ? process.argv[i + 1] : undefined;
  };
  // Emulator, a service-account key, or an owner's gcloud token — see
  // admin_init.mjs.
  const { db, auth } = initAdmin();
  const result = await migrate({
    db,
    auth,
    storeId: arg('--store') ?? 'STORE001',
    name: arg('--name'),
    apply: process.argv.includes('--apply'),
    superAdminEmail: arg('--super-admin-email'),
    superAdminName: arg('--super-admin-name'),
  });
  const file = arg('--report') ?? `migration-report-${Date.now()}.md`;
  fs.writeFileSync(file, result.report);
  console.log(`\nReport written to ${file}`);
  if (result.problems.length) process.exitCode = 1;
}
