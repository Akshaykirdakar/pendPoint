// READ-ONLY reference / orphan / duplicate check before migrating.
import { initAdmin } from './admin_init.mjs';
const { db } = initAdmin();
const ids = async (c) => new Set((await db.collection(c).get()).docs.map((d) => d.id));
const products = await ids('products'), customers = await ids('customers'),
  bills = await ids('bills'), purchases = await ids('purchases');
const out = {};
for (const [group, parentCol, parents] of [['billItems', 'bills', bills], ['purchaseItems', 'purchases', purchases], ['ledgerEntries', 'customers', customers]]) {
  const snap = await db.collectionGroup(group).get();
  const orphans = snap.docs.filter((d) => !parents.has(d.ref.parent.parent.id) || d.ref.parent.parent.parent.id !== parentCol);
  out[group] = { total: snap.size, orphanChildren: orphans.map((d) => d.ref.path) };
  if (group !== 'ledgerEntries') {
    out[group].missingProduct = snap.docs.filter((d) => d.get('productId') && !products.has(d.get('productId'))).map((d) => `${d.ref.path} → ${d.get('productId')}`);
  }
}
const billSnap = await db.collection('bills').get();
const withItems = new Set((await db.collectionGroup('billItems').get()).docs.map((d) => d.ref.parent.parent.id));
out.billsWithoutItems = billSnap.docs.filter((d) => !withItems.has(d.id)).map((d) => `${d.id} (#${d.get('billNumber')}, ${d.get('status')}, total ${d.get('totalAmount')}, revision ${d.get('revision') ?? 0})`);
const numbers = {};
for (const d of billSnap.docs) {
  if (d.get('replacedByBillId') || (d.get('revision') ?? 0) > 0) continue; // revisions share a number by design
  (numbers[d.get('billNumber')] ??= []).push(d.id);
}
out.duplicateBillNumbers = Object.entries(numbers).filter(([, v]) => v.length > 1);
out.billsMissingCustomer = billSnap.docs.filter((d) => d.get('customerId') && !customers.has(d.get('customerId'))).map((d) => d.id);
const batchSnap = await db.collection('batches').get();
out.batchesMissingProduct = batchSnap.docs.filter((d) => !products.has(d.get('productId'))).map((d) => d.id);
out.stockWithoutProduct = [...await ids('stock')].filter((id) => !products.has(id));
console.log(JSON.stringify(out, null, 2));
