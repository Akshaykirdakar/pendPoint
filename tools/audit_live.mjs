// READ-ONLY inventory of the live Firestore database (writes nothing).
// Lists every root collection and every subcollection found, with counts,
// storeId coverage, key totals, counters, settings presence and staff
// roles — the baseline the migration is reconciled against.
//
//   $env:PEND_ACCESS_TOKEN = (gcloud auth print-access-token)
//   node tools/audit_live.mjs --out <file.json>
import fs from 'node:fs';
import { initAdmin, PROJECT_ID } from './admin_init.mjs';

const { db } = initAdmin();
const out = process.argv.includes('--out') ? process.argv[process.argv.indexOf('--out') + 1] : null;

const SUMS = {
  bills: ['totalAmount'], purchases: ['totalAmount'], customers: ['outstandingBalance'],
  stock: ['bagsRemaining', 'looseKgRemaining'], batches: ['bagsAvailable', 'looseKgAvailable'],
};
const r2 = (v) => Math.round(v * 1000) / 1000;

const result = { project: PROJECT_ID, at: new Date().toISOString(), collections: {}, sub: {}, counters: null, settings: null, staff: [] };

const roots = await db.listCollections();
for (const col of roots) {
  const snap = await col.get();
  const info = { count: snap.size, withStoreId: 0, storeIds: {}, sums: {}, subcollections: {} };
  for (const f of SUMS[col.id] ?? []) info.sums[f] = 0;
  const statuses = {};
  for (const d of snap.docs) {
    const s = d.get('storeId');
    if (s) { info.withStoreId++; info.storeIds[s] = (info.storeIds[s] ?? 0) + 1; }
    for (const f of SUMS[col.id] ?? []) info.sums[f] = r2(info.sums[f] + Number(d.get(f) ?? 0));
    if (d.get('status') !== undefined) statuses[d.get('status')] = (statuses[d.get('status')] ?? 0) + 1;
    for (const sc of await d.ref.listCollections()) {
      const k = sc.id;
      const kids = await sc.get();
      const e = (info.subcollections[k] ??= { parents: 0, count: 0, withStoreId: 0 });
      e.parents++; e.count += kids.size;
      e.withStoreId += kids.docs.filter((x) => x.get('storeId')).length;
    }
  }
  if (Object.keys(statuses).length) info.statuses = statuses;
  if (col.id === 'bills' || col.id === 'purchases' || col.id === 'draftBills') {
    const nums = snap.docs.map((d) => Number(d.get(col.id === 'bills' ? 'billNumber' : col.id === 'purchases' ? 'purchaseNumber' : 'number') ?? 0));
    info.maxNumber = nums.length ? Math.max(...nums) : null;
    info.ids = snap.docs.map((d) => d.id).sort().slice(0, 5).concat(snap.size > 5 ? ['…'] : []);
  }
  if (col.id === 'staff') {
    result.staff = snap.docs.map((d) => ({
      uid: d.id, role: d.get('role') ?? null, active: d.get('active') ?? null,
      storeId: d.get('storeId') ?? null, hasEmail: !!d.get('email'),
    }));
  }
  result.collections[col.id] = info;
}
const counters = await db.doc('meta/counters').get();
result.counters = counters.exists ? counters.data() : null;
const settings = await db.doc('meta/settings').get();
result.settings = settings.exists ? { exists: true, shop: settings.get('shop') ?? null } : { exists: false };

console.log(JSON.stringify(result, null, 2));
if (out) fs.writeFileSync(out, JSON.stringify(result, null, 2));
