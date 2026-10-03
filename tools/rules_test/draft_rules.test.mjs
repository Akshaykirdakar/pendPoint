// Firestore-rules test for draft bills, run in the Firestore emulator
// against the project's firestore.rules. Every write mirrors what
// FirestoreRepository.nextDraftNumber() / saveDraft() / deleteDraft() and
// the draft part of commitStock() send.
import fs from 'node:fs';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, deleteDoc, collection, runTransaction, query, where,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE ?? new URL('../../firestore.rules', import.meta.url);
const env = await initializeTestEnvironment({
  projectId: 'demo-pend-rules',
  firestore: { rules: fs.readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8085 },
});

const now = () => new Date().toISOString();
const S = 'STORE001';
let pass = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log(`PASS ${name}`); }
  catch (e) { console.log(`FAIL ${name}\n  ${e?.stack ?? e}`); process.exitCode = 1; }
}

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'stores/STORE001'), { storeCode: 'STORE001', storeName: 'Main', status: 'ACTIVE' });
    await setDoc(doc(db, 'staff/owner1'), { name: 'Owner', role: 'admin', active: true, storeId: S });
    await setDoc(doc(db, 'staff/staff1'), { name: 'Counter', role: 'staff', active: true, storeId: S });
    await setDoc(doc(db, 'stores/STORE001/meta/counters'), { bill: 1000, purchase: 0, draft: 1000 });
  });
}

const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

// DraftBill.toMap()
function draftDoc({ number = 1001, version = 1, status = 'draft' } = {}) {
  return {
    status, number, customerId: 'c1', customerName: 'ABC Traders',
    lines: [{ productId: 'p1', saleType: 'bag', qty: 5, catalogRate: 42, rate: 40 }],
    payments: [{ mode: 'cash', amount: 195 }, { mode: 'credit', amount: 5 }],
    totalAmount: 200, createdAt: now(), updatedAt: now(),
    createdBy: 'staff1', updatedBy: 'staff1', version, storeId: S,
  };
}

// FirestoreRepository.nextDraftNumber()
function nextDraftNumber(db) {
  return runTransaction(db, async (tx) => {
    const ref = doc(db, 'stores/STORE001/meta/counters');
    const snap = await tx.get(ref);
    const next = (snap.data()?.draft ?? 1000) + 1;
    tx.set(ref, { draft: next }, { merge: true });
    return next;
  });
}

// FirestoreRepository.saveDraft(draft, expectedVersion)
function saveDraft(db, id, data, expectedVersion) {
  return runTransaction(db, async (tx) => {
    const ref = doc(db, `draftBills/${id}`);
    const snap = await tx.get(ref);
    if (expectedVersion == null ? snap.exists() : snap.data()?.version !== expectedVersion) {
      throw new Error('conflict');
    }
    tx.set(ref, data);
  });
}

// The draft part of FirestoreRepository.commitStock(): read the draft,
// write the bill, delete the draft — one transaction.
function finalizeDraft(db, id, billId) {
  return runTransaction(db, async (tx) => {
    const ref = doc(db, `draftBills/${id}`);
    if (!(await tx.get(ref)).exists()) throw new Error('draft gone');
    const bref = doc(db, `bills/${billId}`);
    tx.set(bref, {
      billNumber: 1001, customerId: 'c1', customerName: 'ABC Traders', subtotal: 200,
      discountTotal: 10, totalAmount: 200, payments: [], status: 'final', createdAt: now(),
      createdBy: 'staff1', branchId: 'br1', revision: 0, storeId: S,
    });
    tx.set(doc(db, `bills/${billId}/billItems/0`), { productId: 'p1', rate: 40, storeId: S });
    tx.delete(ref);
  });
}

await seed();

await check('signed out: cannot read or create drafts', async () => {
  const db = as(null);
  await assertFails(getDocs(query(collection(db, 'draftBills'), where('storeId', '==', S))));
  await assertFails(setDoc(doc(db, 'draftBills/DRAFT1'), draftDoc()));
});

await check('staff: next draft number + create draft v1', async () => {
  const db = as('staff1');
  const n = await assertSucceeds(nextDraftNumber(db));
  if (n !== 1001) throw new Error(`expected 1001, got ${n}`);
  await assertSucceeds(saveDraft(db, 'DRAFT1001', draftDoc({ number: n })));
  await assertSucceeds(getDocs(query(collection(db, 'draftBills'), where('storeId', '==', S))));
});

await check('create must start at version 1 and be a draft', async () => {
  const db = as('staff1');
  await assertFails(setDoc(doc(db, 'draftBills/DRAFTX'), draftDoc({ number: 5, version: 2 })));
  await assertFails(setDoc(doc(db, 'draftBills/DRAFTY'), draftDoc({ number: 6, status: 'final' })));
});

await check('update must be exactly the next version (stale copy refused)', async () => {
  const db = as('staff1');
  await assertSucceeds(saveDraft(db, 'DRAFT1001', draftDoc({ version: 2 }), 1));
  // A phone still holding version 1 tries to write "version 2" again.
  await assertFails(setDoc(doc(db, 'draftBills/DRAFT1001'), draftDoc({ version: 2 })));
  // Skipping ahead or renumbering is refused too.
  await assertFails(setDoc(doc(db, 'draftBills/DRAFT1001'), draftDoc({ version: 9 })));
  await assertFails(setDoc(doc(db, 'draftBills/DRAFT1001'), draftDoc({ number: 77, version: 3 })));
});

await check('owner can also continue a staff draft', async () => {
  const db = as('owner1');
  await assertSucceeds(saveDraft(db, 'DRAFT1001', draftDoc({ version: 3 }), 2));
});

await check('staff: finalize = bill written + draft removed atomically', async () => {
  const db = as('staff1');
  await assertSucceeds(finalizeDraft(db, 'DRAFT1001', 'BILL1001'));
  const gone = await getDoc(doc(db, 'draftBills/DRAFT1001'));
  if (gone.exists()) throw new Error('draft still there');
  const bill = await getDoc(doc(db, 'bills/BILL1001'));
  if (!bill.exists()) throw new Error('bill missing');
  // Finalizing the same draft again (second phone) is refused inside the
  // transaction — no second bill is written.
  const again = await finalizeDraft(db, 'DRAFT1001', 'BILL1002').then(() => 'saved', (e) => e.message);
  if (again !== 'draft gone') throw new Error(`expected refusal, got ${again}`);
  if ((await getDoc(doc(db, 'bills/BILL1002'))).exists()) throw new Error('duplicate bill');
});

await check('staff: delete a draft; signed out cannot', async () => {
  const db = as('staff1');
  await assertSucceeds(saveDraft(db, 'DRAFT1002', draftDoc({ number: 1002 })));
  await assertFails(deleteDoc(doc(as(null), 'draftBills/DRAFT1002')));
  await assertSucceeds(deleteDoc(doc(db, 'draftBills/DRAFT1002')));
});

await check('drafts never grant extra rights: staff still cannot void a bill', async () => {
  const db = as('staff1');
  await assertFails(setDoc(doc(db, 'bills/BILL1001'), { status: 'void' }, { merge: true }));
});

console.log(`\n${pass} passed${process.exitCode ? ', some FAILED' : ''}`);
await env.cleanup();
