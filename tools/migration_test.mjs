// Tests tools/migrate_multistore.mjs in the Firestore + Auth emulators:
// legacy (single-shop) data → STORE001, dry run writes nothing, apply keeps
// every count and total, a second run changes nothing, other stores' data
// is never touched, and the super admin is set up.
//
//   cd tools && npm run test:migration
import assert from 'node:assert/strict';
import admin from 'firebase-admin';
import { migrate, STORE_COLLECTIONS } from './migrate_multistore.mjs';

admin.initializeApp({ projectId: 'demo-pend-mig' });
const db = admin.firestore();
const auth = admin.auth();

let pass = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log(`PASS ${name}`); }
  catch (e) { console.log(`FAIL ${name}\n  ${e?.stack ?? e}`); process.exitCode = 1; }
}

async function clear() {
  for (const col of [...STORE_COLLECTIONS, 'staff', 'stores', 'meta']) {
    const snap = await db.collection(col).get();
    for (const d of snap.docs) await db.recursiveDelete(d.ref);
  }
}

// The shop as it is today: no storeId anywhere.
async function seedLegacy() {
  await clear();
  await db.doc('meta/settings').set({ shop: 'Shri Ganesh Pend' });
  await db.doc('meta/counters').set({ bill: 1030, purchase: 2, draft: 1003 });
  await db.doc('staff/owner1').set({ name: 'Owner', role: 'admin', active: true });
  await db.doc('staff/staff1').set({ name: 'Counter', role: 'staff', active: true });
  await db.doc('brands/b1').set({ name: 'Godrej' });
  await db.doc('branches/br1').set({ name: 'Main' });
  await db.doc('suppliers/sup1').set({ name: 'ABC' });
  for (let i = 1; i <= 3; i++) {
    await db.doc(`products/p${i}`).set({ name: `Feed ${i}`, brandId: 'b1' });
    await db.doc(`stock/p${i}`).set({ bagsRemaining: 10 * i, looseKgRemaining: 0 });
    await db.doc(`batches/bt${i}`).set({ productId: `p${i}`, bagsAvailable: 10 * i, looseKgAvailable: 0 });
    await db.doc(`stockLogs/l${i}`).set({ type: 'purchase', createdAt: new Date().toISOString() });
  }
  for (let i = 1; i <= 5; i++) {
    await db.doc(`bills/BILL100${i}`).set({ billNumber: 1000 + i, totalAmount: 1450 * i, status: 'final' });
    await db.doc(`bills/BILL100${i}/billItems/0`).set({ productId: 'p1', lineTotal: 1450 * i });
  }
  await db.doc('purchases/PUR1').set({ purchaseNumber: 1, totalAmount: 12000, status: 'final' });
  await db.doc('purchases/PUR1/purchaseItems/000').set({ productId: 'p1', bags: 10 });
  await db.doc('customers/c1').set({ name: 'Ramesh', outstandingBalance: 2380 });
  await db.doc('customers/c1/ledgerEntries/e1').set({ type: 'credit-sale', amount: 2380 });
  await db.doc('draftBills/DRAFT1001').set({ status: 'draft', number: 1001, version: 1, lines: [], payments: [] });
}

await check('dry run: reports, writes nothing', async () => {
  await seedLegacy();
  const r = await migrate({ db, auth, apply: false });
  assert.equal(r.rows.find((x) => x.col === 'bills').migrated, 5);
  assert.equal((await db.doc('stores/STORE001').get()).exists, false);
  assert.equal((await db.doc('bills/BILL1001').get()).get('storeId'), undefined);
});

await check('apply: every record in STORE001; counts and totals unchanged', async () => {
  const r = await migrate({ db, auth, apply: true });
  assert.deepEqual(r.problems, []);
  const store = (await db.doc('stores/STORE001').get()).data();
  assert.equal(store.storeName, 'Shri Ganesh Pend');
  assert.equal(store.status, 'ACTIVE');
  assert.equal((await db.doc('stores/STORE001/meta/settings').get()).get('shop'), 'Shri Ganesh Pend');
  assert.deepEqual((await db.doc('stores/STORE001/meta/counters').get()).data(),
    { bill: 1030, purchase: 2, draft: 1003 });
  for (const col of STORE_COLLECTIONS) {
    const snap = await db.collection(col).get();
    for (const d of snap.docs) assert.equal(d.get('storeId'), 'STORE001', `${col}/${d.id}`);
  }
  assert.equal((await db.doc('bills/BILL1003/billItems/0').get()).get('storeId'), 'STORE001');
  assert.equal((await db.doc('purchases/PUR1/purchaseItems/000').get()).get('storeId'), 'STORE001');
  assert.equal((await db.doc('customers/c1/ledgerEntries/e1').get()).get('storeId'), 'STORE001');
  assert.equal((await db.doc('staff/owner1').get()).get('storeId'), 'STORE001');
  assert.equal((await db.doc('customers/c1').get()).get('outstandingBalance'), 2380);
  assert.equal(r.after.bills.sum, r.before.bills.sum);
  assert.equal(r.after.stock.sum, 60);
});

await check('idempotent: a second run migrates nothing', async () => {
  const r = await migrate({ db, auth, apply: true });
  assert.deepEqual(r.problems, []);
  for (const row of r.rows) assert.equal(row.migrated, 0, row.col);
});

await check('never touches another store, never moves counters back', async () => {
  await db.doc('stores/STR002').set({ storeCode: 'STR002', storeName: 'Satara', status: 'ACTIVE' });
  await db.doc('products/pB').set({ name: 'B feed', storeId: 'STR002' });
  await db.doc('bills/STR002_BILL1001').set({ billNumber: 1001, totalAmount: 99, status: 'final', storeId: 'STR002' });
  await db.doc('stores/STORE001/meta/counters').set({ bill: 1040 }, { merge: true });
  const r = await migrate({ db, auth, apply: true });
  assert.deepEqual(r.problems, []);
  assert.equal((await db.doc('products/pB').get()).get('storeId'), 'STR002');
  assert.equal((await db.doc('bills/STR002_BILL1001').get()).get('storeId'), 'STR002');
  assert.equal((await db.doc('stores/STORE001/meta/counters').get()).get('bill'), 1040);
});

await check('super admin set up from an existing login', async () => {
  let user;
  try { user = await auth.getUserByEmail('boss@example.com'); }
  catch { user = await auth.createUser({ email: 'boss@example.com', password: 'secret12' }); }
  await migrate({ db, auth, apply: true, superAdminEmail: 'boss@example.com' });
  const me = (await db.doc(`staff/${user.uid}`).get()).data();
  assert.equal(me.role, 'super_admin');
  assert.equal(me.storeId, null);
  assert.equal(me.active, true);
});

console.log(`\n${pass} migration checks passed${process.exitCode ? ' — SOME FAILED' : ''}`);
