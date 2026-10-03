// Multi-store isolation — Firestore rules security matrix, run in the
// emulator against the project's firestore.rules. Store A users must never
// read, list, create, update, delete or re-home Store B data (and vice
// versa), even knowing a Store B document id; a super admin sees all.
import fs from 'node:fs';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where,
  runTransaction,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE ?? new URL('../../firestore.rules', import.meta.url);
const env = await initializeTestEnvironment({
  projectId: 'demo-pend-rules',
  firestore: { rules: fs.readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8085 },
});

const A = 'STR_A', B = 'STR_B', OFF = 'STR_OFF';
const now = () => new Date().toISOString();
let pass = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log(`PASS ${name}`); }
  catch (e) { console.log(`FAIL ${name}\n  ${e?.stack ?? e}`); process.exitCode = 1; }
}
const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

// Store-owned top-level collections and one sample doc each.
const COLLECTIONS = {
  products: (s) => ({ name: `Feed ${s}`, brandId: `b-${s}`, storeId: s }),
  brands: (s) => ({ name: `Brand ${s}`, storeId: s }),
  branches: (s) => ({ name: `Branch ${s}`, storeId: s }),
  suppliers: (s) => ({ name: `Supplier ${s}`, storeId: s }),
  customers: (s) => ({ name: `Ramesh ${s}`, outstandingBalance: 100, storeId: s }),
  bills: (s) => ({ billNumber: 1001, status: 'final', totalAmount: 500, createdAt: now(), storeId: s }),
  purchases: (s) => ({ purchaseNumber: 1, status: 'final', totalAmount: 900, createdAt: now(), storeId: s }),
  stock: (s) => ({ bagsRemaining: 5, looseKgRemaining: 0, storeId: s }),
  batches: (s) => ({ bagsAvailable: 5, looseKgAvailable: 0, storeId: s }),
  stockLogs: (s) => ({ type: 'sale', createdAt: now(), storeId: s }),
  draftBills: (s) => ({ status: 'draft', number: 1001, version: 1, lines: [], payments: [], storeId: s }),
};

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const store = (id, status) => setDoc(doc(db, `stores/${id}`),
      { storeCode: id, storeName: `Store ${id}`, status, createdAt: now(), createdBy: 'super1' });
    await store(A, 'ACTIVE');
    await store(B, 'ACTIVE');
    await store(OFF, 'INACTIVE');
    const staff = (uid, role, storeId, active = true) =>
      setDoc(doc(db, `staff/${uid}`), { name: uid, role, storeId, active });
    await staff('adminA', 'admin', A);
    await staff('staffA', 'staff', A);
    await staff('adminB', 'admin', B);
    await staff('staffB', 'staff', B);
    await staff('super1', 'super_admin', null);
    await staff('disabledA', 'staff', A, false);
    await staff('offStaff', 'staff', OFF);
    for (const [col, make] of Object.entries(COLLECTIONS)) {
      await setDoc(doc(db, `${col}/${col}-A`), make(A));
      await setDoc(doc(db, `${col}/${col}-B`), make(B));
    }
    await setDoc(doc(db, 'bills/bills-A/billItems/0'), { productId: 'products-A', storeId: A });
    await setDoc(doc(db, 'bills/bills-B/billItems/0'), { productId: 'products-B', storeId: B });
    await setDoc(doc(db, 'purchases/purchases-B/purchaseItems/000'), { productId: 'products-B', storeId: B });
    await setDoc(doc(db, 'customers/customers-A/ledgerEntries/e1'), { type: 'credit-sale', amount: 100, storeId: A });
    await setDoc(doc(db, 'customers/customers-B/ledgerEntries/e1'), { type: 'credit-sale', amount: 100, storeId: B });
    await setDoc(doc(db, `stores/${A}/meta/counters`), { bill: 1000 });
    await setDoc(doc(db, `stores/${B}/meta/counters`), { bill: 1000 });
    await setDoc(doc(db, `stores/${A}/meta/settings`), { shop: 'A' });
    await setDoc(doc(db, `stores/${B}/meta/settings`), { shop: 'B' });
    await setDoc(doc(db, 'auditLogs/aA'), { storeId: A, userId: 'staffA', action: 'BILL_FINALIZED', timestamp: now() });
    await setDoc(doc(db, 'auditLogs/aB'), { storeId: B, userId: 'staffB', action: 'BILL_FINALIZED', timestamp: now() });
    await setDoc(doc(db, 'meta/settings'), { shop: 'legacy' });
    // A record that was never migrated (no storeId) — no store user sees it.
    await setDoc(doc(db, 'products/legacy-unmigrated'), { name: 'old' });
  });
}

await seed();

// ---------------------------------------------------------------------------
// 1. Reads: own store yes; other store no — for every store collection.
for (const col of Object.keys(COLLECTIONS)) {
  await check(`${col}: Store A reads A, not B (by id or by query)`, async () => {
    const a = as('staffA');
    await assertSucceeds(getDoc(doc(a, `${col}/${col}-A`)));
    await assertFails(getDoc(doc(a, `${col}/${col}-B`)));
    await assertSucceeds(getDocs(query(collection(a, col), where('storeId', '==', A))));
    await assertFails(getDocs(query(collection(a, col), where('storeId', '==', B))));
    await assertFails(getDocs(collection(a, col))); // unfiltered = all stores
  });
  await check(`${col}: Store B cannot read A`, async () => {
    const b = as('staffB');
    await assertFails(getDoc(doc(b, `${col}/${col}-A`)));
    await assertSucceeds(getDoc(doc(b, `${col}/${col}-B`)));
  });
}

await check('nested: bill items / purchase items / khata follow their parent store', async () => {
  const a = as('staffA');
  await assertSucceeds(getDocs(collection(a, 'bills/bills-A/billItems')));
  await assertFails(getDocs(collection(a, 'bills/bills-B/billItems')));
  await assertFails(getDoc(doc(a, 'bills/bills-B/billItems/0')));
  await assertFails(getDocs(collection(a, 'purchases/purchases-B/purchaseItems')));
  await assertSucceeds(getDocs(collection(a, 'customers/customers-A/ledgerEntries')));
  await assertFails(getDocs(collection(a, 'customers/customers-B/ledgerEntries')));
});

await check('unmigrated record (no storeId) is invisible to store users', async () => {
  await assertFails(getDoc(doc(as('adminA'), 'products/legacy-unmigrated')));
});

await check('a missing id reads as empty (transactions check existence)', async () => {
  const snap = await assertSucceeds(getDoc(doc(as('staffA'), 'draftBills/does-not-exist')));
  if (snap.exists()) throw new Error('should not exist');
});

// ---------------------------------------------------------------------------
// 2. Writes: create/update/delete only in your own store; never re-home.
await check('create: own store yes, other store no', async () => {
  await seed();
  const a = as('staffA');
  await assertSucceeds(setDoc(doc(a, 'customers/newA'), { name: 'x', storeId: A }));
  await assertFails(setDoc(doc(a, 'customers/newB'), { name: 'x', storeId: B }));
  await assertFails(setDoc(doc(a, 'customers/newNone'), { name: 'x' }));
  await assertFails(setDoc(doc(a, 'draftBills/dB'), COLLECTIONS.draftBills(B)));
  await assertFails(setDoc(doc(a, 'bills/bX'), COLLECTIONS.bills(B)));
  await assertFails(setDoc(doc(a, 'stockLogs/lX'), COLLECTIONS.stockLogs(B)));
});

await check('update: own store yes; other store no; storeId can never change', async () => {
  await seed();
  const a = as('staffA');
  await assertSucceeds(updateDoc(doc(a, 'customers/customers-A'), { outstandingBalance: 50 }));
  await assertFails(updateDoc(doc(a, 'customers/customers-B'), { outstandingBalance: 0 }));
  await assertFails(updateDoc(doc(a, 'customers/customers-A'), { storeId: B }));
  await assertFails(setDoc(doc(a, 'customers/customers-B'), { name: 'mine', storeId: A }));
  const admin = as('adminA');
  await assertSucceeds(updateDoc(doc(admin, 'products/products-A'), { name: 'renamed' }));
  await assertFails(updateDoc(doc(admin, 'products/products-A'), { storeId: B }));
  await assertFails(updateDoc(doc(admin, 'products/products-B'), { name: 'hijack' }));
});

await check('delete: owner of own store only; never another store by id', async () => {
  await seed();
  await assertFails(deleteDoc(doc(as('adminA'), 'products/products-B')));
  await assertFails(deleteDoc(doc(as('staffA'), 'products/products-A'))); // owner-only
  await assertSucceeds(deleteDoc(doc(as('adminA'), 'products/products-A')));
  await assertFails(deleteDoc(doc(as('staffA'), 'draftBills/draftBills-B')));
  await assertSucceeds(deleteDoc(doc(as('staffA'), 'draftBills/draftBills-A')));
});

await check('nested writes: no items / khata entries under another store', async () => {
  await seed();
  const a = as('staffA');
  await assertFails(setDoc(doc(a, 'bills/bills-B/billItems/9'), { productId: 'x', storeId: A }));
  await assertFails(setDoc(doc(a, 'customers/customers-B/ledgerEntries/x'), { type: 'repayment', amount: 1, storeId: A }));
  await assertSucceeds(setDoc(doc(a, 'customers/customers-A/ledgerEntries/x'), { type: 'repayment', amount: 1, storeId: A }));
  await assertFails(setDoc(doc(a, 'customers/customers-A/ledgerEntries/y'), { type: 'repayment', amount: 1, storeId: B }));
});

await check('a full sale in store A cannot touch a store B batch', async () => {
  await seed();
  const a = as('staffA');
  await assertFails(runTransaction(a, async (tx) => {
    await tx.get(doc(a, 'batches/batches-B'));
    tx.set(doc(a, 'bills/BILLX'), COLLECTIONS.bills(A));
  }));
  await assertSucceeds(runTransaction(a, async (tx) => {
    const ref = doc(a, `stores/${A}/meta/counters`);
    const n = ((await tx.get(ref)).data()?.bill ?? 1000) + 1;
    tx.set(ref, { bill: n }, { merge: true });
    const bref = doc(a, `bills/BILL${n}`);
    tx.set(bref, { ...COLLECTIONS.bills(A), billNumber: n });
    tx.set(doc(bref, 'billItems/0'), { productId: 'products-A', storeId: A });
    tx.set(doc(a, 'batches/batches-A'), { ...COLLECTIONS.batches(A), bagsAvailable: 4 });
  }));
});

// ---------------------------------------------------------------------------
// 3. Existing role permissions still apply INSIDE the store (AND, not OR).
await check('staff still cannot write masters or void bills in their own store', async () => {
  await seed();
  const a = as('staffA');
  await assertFails(setDoc(doc(a, 'products/pNew'), { name: 'x', storeId: A }));
  await assertFails(updateDoc(doc(a, 'bills/bills-A'), { status: 'void', statusChangedAt: now() }));
  await assertSucceeds(updateDoc(doc(as('adminA'), 'bills/bills-A'), { status: 'void', statusChangedAt: now() }));
  await assertFails(updateDoc(doc(as('adminA'), 'bills/bills-A'), { totalAmount: 1 }));
});

await check('counters: store users of that store; settings: its owner', async () => {
  await seed();
  await assertSucceeds(setDoc(doc(as('staffA'), `stores/${A}/meta/counters`), { bill: 1001 }, { merge: true }));
  await assertFails(setDoc(doc(as('staffA'), `stores/${B}/meta/counters`), { bill: 1001 }, { merge: true }));
  await assertFails(getDoc(doc(as('staffA'), `stores/${B}/meta/settings`)));
  await assertFails(setDoc(doc(as('staffA'), `stores/${A}/meta/settings`), { shop: 'x' }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('adminA'), `stores/${A}/meta/settings`), { shop: 'x' }, { merge: true }));
  await assertFails(setDoc(doc(as('adminB'), `stores/${A}/meta/settings`), { shop: 'x' }, { merge: true }));
});

// ---------------------------------------------------------------------------
// 4. Staff records: store admins manage only their store; nobody escalates.
await check('staff records: list own store only; store admin manages own store only', async () => {
  await seed();
  await assertSucceeds(getDocs(query(collection(as('staffA'), 'staff'), where('storeId', '==', A))));
  await assertFails(getDocs(query(collection(as('staffA'), 'staff'), where('storeId', '==', B))));
  await assertFails(getDocs(collection(as('adminA'), 'staff')));
  await assertFails(getDoc(doc(as('staffA'), 'staff/staffB')));
  await assertSucceeds(getDoc(doc(as('staffB'), 'staff/staffB'))); // own profile
  const admin = as('adminA');
  await assertSucceeds(setDoc(doc(admin, 'staff/newA'), { name: 'n', role: 'staff', storeId: A, active: true }));
  await assertFails(setDoc(doc(admin, 'staff/newB'), { name: 'n', role: 'staff', storeId: B, active: true }));
  await assertFails(setDoc(doc(admin, 'staff/evil'), { name: 'n', role: 'super_admin', storeId: A, active: true }));
  await assertFails(updateDoc(doc(admin, 'staff/staffA'), { storeId: B }));
  await assertFails(updateDoc(doc(admin, 'staff/staffA'), { role: 'super_admin' }));
  await assertFails(updateDoc(doc(admin, 'staff/staffB'), { active: false }));
  await assertFails(updateDoc(doc(admin, 'staff/adminA'), { active: false })); // not self
  await assertSucceeds(updateDoc(doc(admin, 'staff/staffA'), { active: false }));
  await assertFails(updateDoc(doc(as('staffB'), 'staff/staffB'), { role: 'admin' }));
});

// ---------------------------------------------------------------------------
// 5. Super admin: every store, stores and users.
await check('super admin: reads every store, manages stores and users', async () => {
  await seed();
  const s = as('super1');
  for (const col of Object.keys(COLLECTIONS)) {
    await assertSucceeds(getDoc(doc(s, `${col}/${col}-A`)));
    await assertSucceeds(getDoc(doc(s, `${col}/${col}-B`)));
  }
  await assertSucceeds(getDocs(collection(s, 'stores')));
  await assertSucceeds(getDocs(collection(s, 'staff')));
  await assertSucceeds(getDocs(collection(s, 'bills/bills-B/billItems')));
  await assertSucceeds(runTransaction(s, async (tx) => {
    const ref = doc(s, 'stores/STR_NEW');
    if ((await tx.get(ref)).exists()) throw new Error('exists');
    tx.set(ref, { storeCode: 'STR_NEW', storeName: 'New', status: 'ACTIVE', createdAt: now(), createdBy: 'super1' });
    tx.set(doc(s, 'stores/STR_NEW/meta/settings'), { shop: 'New' });
    tx.set(doc(s, 'stores/STR_NEW/meta/counters'), { bill: 1000, purchase: 0, draft: 1000 });
  }));
  await assertSucceeds(updateDoc(doc(s, `stores/${B}`), { status: 'INACTIVE', updatedAt: now() }));
  await assertFails(updateDoc(doc(s, `stores/${A}`), { storeCode: 'X' }));
  await assertFails(deleteDoc(doc(s, `stores/${A}`)));
  await assertSucceeds(setDoc(doc(s, 'staff/newAdminB'), { name: 'n', role: 'admin', storeId: B, active: true }));
  await assertFails(setDoc(doc(s, 'staff/anotherSuper'), { name: 'n', role: 'super_admin', storeId: null, active: true }));
  await assertSucceeds(getDoc(doc(s, 'meta/settings'))); // legacy, read-only
  await assertFails(setDoc(doc(s, 'meta/settings'), { shop: 'x' }));
});

await check('store users: no store list, no store creation, own store doc only', async () => {
  await seed();
  await assertFails(getDocs(collection(as('adminA'), 'stores')));
  await assertSucceeds(getDoc(doc(as('adminA'), `stores/${A}`)));
  await assertFails(getDoc(doc(as('adminA'), `stores/${B}`)));
  await assertFails(setDoc(doc(as('adminA'), 'stores/STR_MINE'), { storeCode: 'STR_MINE', status: 'ACTIVE' }));
  await assertFails(updateDoc(doc(as('adminA'), `stores/${A}`), { status: 'INACTIVE' }));
  await assertFails(getDoc(doc(as('adminA'), 'meta/settings')));
});

// ---------------------------------------------------------------------------
// 6. Disabled users, inactive stores, missing profiles, signed out.
await check('disabled user / inactive store / no profile / signed out: no data', async () => {
  await seed();
  for (const uid of ['disabledA', 'offStaff', 'ghost', null]) {
    const db = as(uid);
    await assertFails(getDoc(doc(db, 'products/products-A')));
    await assertFails(setDoc(doc(db, 'customers/x'), { name: 'x', storeId: uid === 'offStaff' ? OFF : A }));
  }
  await assertFails(getDocs(query(collection(as('offStaff'), 'products'), where('storeId', '==', OFF))));
  // ...but they can see why: their own profile, and (inactive store) its status.
  await assertSucceeds(getDoc(doc(as('offStaff'), 'staff/offStaff')));
  await assertSucceeds(getDoc(doc(as('offStaff'), `stores/${OFF}`)));
  await assertSucceeds(getDoc(doc(as('ghost'), 'staff/ghost')));
});

// ---------------------------------------------------------------------------
// 7. Audit trail: append-only, own store, own identity; owners read.
await check('audit logs: append own-store entries as yourself; owners read; never edited', async () => {
  await seed();
  const a = as('staffA');
  await assertSucceeds(addDoc(collection(a, 'auditLogs'), { storeId: A, userId: 'staffA', action: 'X', timestamp: now() }));
  await assertFails(addDoc(collection(a, 'auditLogs'), { storeId: B, userId: 'staffA', action: 'X', timestamp: now() }));
  await assertFails(addDoc(collection(a, 'auditLogs'), { storeId: A, userId: 'adminA', action: 'X', timestamp: now() }));
  await assertFails(getDocs(query(collection(a, 'auditLogs'), where('storeId', '==', A))));
  await assertSucceeds(getDocs(query(collection(as('adminA'), 'auditLogs'), where('storeId', '==', A))));
  await assertFails(getDocs(query(collection(as('adminA'), 'auditLogs'), where('storeId', '==', B))));
  await assertFails(updateDoc(doc(as('adminA'), 'auditLogs/aA'), { action: 'Y' }));
  await assertFails(deleteDoc(doc(as('super1'), 'auditLogs/aA')));
  await assertSucceeds(getDocs(collection(as('super1'), 'auditLogs')));
});

console.log(`\n${pass} checks passed${process.exitCode ? ' — SOME FAILED' : ''}`);
await env.cleanup();
