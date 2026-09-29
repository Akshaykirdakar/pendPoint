// Firestore-rules test for the purchase workflow, run in the Firestore
// emulator against the project's firestore.rules. Every write mirrors what
// FirestoreRepository.nextPurchaseNumber() / commitStock() send for a
// purchase (same collections, same fields, one transaction).
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, collection, query, orderBy, limit,
  runTransaction, increment,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE ?? new URL('../../firestore.rules', import.meta.url);
const env = await initializeTestEnvironment({
  projectId: 'demo-pend-rules',
  firestore: { rules: fs.readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8085 },
});

const now = () => new Date().toISOString();
let pass = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log(`PASS ${name}`); }
  catch (e) { console.log(`FAIL ${name}\n  ${e?.stack ?? e}`); process.exitCode = 1; }
}

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'staff/owner1'), { name: 'Owner', role: 'admin', active: true });
    await setDoc(doc(db, 'staff/staff1'), { name: 'Counter', role: 'staff', active: true });
    await setDoc(doc(db, 'products/p1'), { name: 'Milk Booster', brandId: 'b1', bagWeightKg: 50 });
    await setDoc(doc(db, 'suppliers/sup1'), { name: 'ABC Traders' });
    await setDoc(doc(db, 'stock/p1'), { bagsRemaining: 5, looseKgRemaining: 0 });
    await setDoc(doc(db, 'meta/counters'), { bill: 1000, purchase: 0 });
  });
}

const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

// FirestoreRepository.nextPurchaseNumber()
function nextPurchaseNumber(db) {
  return runTransaction(db, async (tx) => {
    const ref = doc(db, 'meta/counters');
    const snap = await tx.get(ref);
    const next = (snap.data()?.purchase ?? 0) + 1;
    tx.set(ref, { purchase: next }, { merge: true });
    return next;
  });
}

function batchDoc({ bags, loose = 0 }) {
  return {
    branchId: 'br1', productId: 'p1', supplierId: 'sup1', batchNo: 'W-1',
    manufactureDate: null, expiry: '2026-12-31T00:00:00.000', unitCost: 1200,
    bagsReceived: bags, bagsAvailable: bags, looseKgAvailable: loose,
    bagsSold: 0, looseKgSold: 0, bagsReturned: 0, looseKgReturned: 0,
    bagsAdjusted: 0, looseKgAdjusted: 0, status: 'active', sourceBatchId: null,
    createdAt: now(), updatedAt: now(),
  };
}

// FirestoreRepository.commitStock() for a new purchase of [bags] bags.
function commitPurchase(db, { id, bags = 10, status = 'final', batch } = {}) {
  return runTransaction(db, async (tx) => {
    const batchId = `B-${id}`;
    tx.set(doc(db, `batches/${batchId}`), batch ?? batchDoc({ bags }));
    tx.set(doc(db, 'stock/p1'),
      { bagsRemaining: increment(bags), looseKgRemaining: increment(0) }, { merge: true });
    tx.set(doc(db, `stockLogs/L-${id}`), {
      productId: 'p1', type: 'purchase', bagsDelta: bags, looseKgDelta: 0, cost: 1200,
      batchNo: 'W-1', note: `purchase #${id}`, createdAt: now(), branchId: 'br1',
      batchId, supplierId: 'sup1',
    });
    const pref = doc(db, `purchases/${id}`);
    tx.set(pref, {
      purchaseNumber: 1, supplierId: 'sup1', supplierName: 'ABC Traders',
      supplierBillNo: 'INV-1', purchaseDate: now(), subtotal: bags * 1200,
      otherCharges: 0, totalAmount: bags * 1200, status, branchId: 'br1',
      createdBy: 'x', createdAt: now(), revision: 0, originalPurchaseId: null,
      replacedByPurchaseId: null, billPhotoUrl: null, billPhotoPath: null,
    });
    tx.set(doc(pref, 'purchaseItems/000'), {
      productId: 'p1', brandId: 'b1', bags, purchaseRate: 1200, amount: bags * 1200,
      batchId, batchNo: 'W-1', expiry: '2026-12-31T00:00:00.000',
      manufactureDate: null, sellingRateAtPurchase: 1450,
    });
  });
}

// Loading purchase history, as FirestoreRepository.loadHistory() does.
async function readHistory(db) {
  const snap = await getDocs(query(collection(db, 'purchases'), orderBy('createdAt', 'desc'), limit(500)));
  for (const d of snap.docs) await getDocs(collection(d.ref, 'purchaseItems'));
  return snap.size;
}

async function stockBags() {
  let v;
  await env.withSecurityRulesDisabled(async (ctx) => {
    v = (await getDoc(doc(ctx.firestore(), 'stock/p1'))).data().bagsRemaining;
  });
  return v;
}
async function exists(path) {
  let e;
  await env.withSecurityRulesDisabled(async (ctx) => {
    e = (await getDoc(doc(ctx.firestore(), path))).exists();
  });
  return e;
}

// ---------------------------------------------------------------------------
for (const [who, uid] of [['owner', 'owner1'], ['staff', 'staff1']]) {
  await check(`${who}: purchase history loads (purchases + purchaseItems)`, async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => commitPurchase(ctx.firestore(), { id: 'PUR0' }));
    assert.equal(await assertSucceeds(readHistory(as(uid))), 1);
  });

  await check(`${who}: save purchase = counter + full stock transaction`, async () => {
    await seed();
    const db = as(uid);
    const n = await assertSucceeds(nextPurchaseNumber(db));
    assert.equal(n, 1);
    await assertSucceeds(commitPurchase(db, { id: `PUR${n}`, bags: 10 }));
    assert.ok(await exists(`purchases/PUR${n}`), 'purchase doc');
    assert.ok(await exists(`purchases/PUR${n}/purchaseItems/000`), 'purchase item');
    assert.ok(await exists(`batches/B-PUR${n}`), 'batch');
    assert.ok(await exists(`stockLogs/L-PUR${n}`), 'stock log');
    assert.equal(await stockBags(), 15, 'stock +10 exactly once');
  });

  await check(`${who}: saving the SAME purchase again is refused — stock not added twice`, async () => {
    await seed();
    const db = as(uid);
    await assertSucceeds(commitPurchase(db, { id: 'PUR1', bags: 10 }));
    await assertFails(commitPurchase(db, { id: 'PUR1', bags: 10 }));
    assert.equal(await stockBags(), 15);
  });

  await check(`${who}: a rejected transaction leaves NO partial data`, async () => {
    await seed();
    const db = as(uid);
    // One bad write (a batch below zero) sinks the whole transaction.
    await assertFails(commitPurchase(db, { id: 'PURX', batch: batchDoc({ bags: -1 }) }));
    assert.equal(await stockBags(), 5, 'stock unchanged');
    assert.equal(await exists('purchases/PURX'), false);
    assert.equal(await exists('purchases/PURX/purchaseItems/000'), false);
    assert.equal(await exists('stockLogs/L-PURX'), false);
    assert.equal(await exists('batches/B-PURX'), false);
    // A purchase saved as anything but "final" is refused the same way.
    await assertFails(commitPurchase(db, { id: 'PURY', status: 'void' }));
    assert.equal(await stockBags(), 5);
  });
}

await check('owner: edit = void original + create revision in one transaction', async () => {
  await seed();
  const db = as('owner1');
  await assertSucceeds(commitPurchase(db, { id: 'PUR1', bags: 10 }));
  await assertSucceeds(runTransaction(db, async (tx) => {
    tx.update(doc(db, 'purchases/PUR1'),
      { status: 'void', replacedByPurchaseId: 'PUR1-R1', statusChangedAt: now() });
  }));
  assert.equal(await exists('purchases/PUR1'), true);
});

await check('staff: may NOT void/edit a purchase or change its amounts', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => commitPurchase(ctx.firestore(), { id: 'PUR1' }));
  const db = as('staff1');
  await assertFails(setDoc(doc(db, 'purchases/PUR1'),
    { status: 'void', replacedByPurchaseId: 'x', statusChangedAt: now() }, { merge: true }));
  const owner = as('owner1');
  await assertFails(setDoc(doc(owner, 'purchases/PUR1'), { totalAmount: 1 }, { merge: true }));
  await assertFails(setDoc(doc(db, 'purchases/PUR1/purchaseItems/000'), { bags: 99 }, { merge: true }));
});

await check('staff: still cannot write masters (products / suppliers)', async () => {
  await seed();
  const db = as('staff1');
  await assertFails(setDoc(doc(db, 'products/p9'), { name: 'x' }));
  await assertFails(setDoc(doc(db, 'suppliers/s9'), { name: 'x' }));
});

await check('signed-out: no reads, no purchase writes', async () => {
  await seed();
  const db = as(null);
  await assertFails(readHistory(db));
  await assertFails(commitPurchase(db, { id: 'PURZ' }));
  assert.equal(await stockBags(), 5);
});

// ---- sales must keep working under the same rules ----
function commitSale(db, { id, bags = 2, batchId = 'B-PUR1' }) {
  return runTransaction(db, async (tx) => {
    const bref = doc(db, `batches/${batchId}`);
    const b = (await tx.get(bref)).data();
    tx.set(bref, { ...b, bagsAvailable: b.bagsAvailable - bags, bagsSold: b.bagsSold + bags, updatedAt: now() });
    tx.set(doc(db, 'stock/p1'),
      { bagsRemaining: increment(-bags), looseKgRemaining: increment(0) }, { merge: true });
    tx.set(doc(db, `stockLogs/S-${id}`), { productId: 'p1', type: 'sale', bagsDelta: -bags, createdAt: now(), billId: id });
    const ref = doc(db, `bills/${id}`);
    tx.set(ref, { billNumber: 1001, customerId: null, customerName: '', subtotal: 2900, discountTotal: 0,
      totalAmount: 2900, payments: [{ mode: 'cash', amount: 2900 }], status: 'final', createdAt: now(),
      createdBy: 'x', branchId: 'br1', revision: 0, originalBillId: null, replacedByBillId: null });
    tx.set(doc(ref, 'billItems/0'), { productId: 'p1', saleType: 'bag', quantityOrWeight: bags, rate: 1450,
      catalogRateAtSale: 1450, lineTotal: 2900, batchId });
  });
}

for (const [who, uid] of [['owner', 'owner1'], ['staff', 'staff1']]) {
  await check(`${who}: sale (bill + items + batch + stock + log) still saves`, async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => commitPurchase(ctx.firestore(), { id: 'PUR1', bags: 10 }));
    const db = as(uid);
    await assertSucceeds(runTransaction(db, async (tx) => {
      const ref = doc(db, 'meta/counters');
      const n = ((await tx.get(ref)).data()?.bill ?? 1000) + 1;
      tx.set(ref, { bill: n }, { merge: true });
    }));
    await assertSucceeds(commitSale(db, { id: 'BILL1001' }));
    assert.equal(await stockBags(), 13);
    // Overselling (batch below zero) is refused and nothing is written.
    await assertFails(commitSale(db, { id: 'BILL1002', bags: 99 }));
    assert.equal(await stockBags(), 13);
    assert.equal(await exists('bills/BILL1002'), false);
  });
}

await check('owner voids a bill (status only); staff cannot', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await commitPurchase(ctx.firestore(), { id: 'PUR1', bags: 10 });
    await commitSale(ctx.firestore(), { id: 'BILL1001' });
  });
  const voidIt = (db) => runTransaction(db, async (tx) =>
    tx.update(doc(db, 'bills/BILL1001'), { status: 'void', statusChangedAt: now() }));
  await assertFails(voidIt(as('staff1')));
  await assertSucceeds(voidIt(as('owner1')));
});

console.log(`\n${pass} checks passed${process.exitCode ? ' — SOME FAILED' : ''}`);
await env.cleanup();
