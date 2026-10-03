// LIVE cross-store security test against the deployed rules, signed in as
// real users (ID tokens) through the Firestore / Storage REST APIs — so the
// server's rules decide, not the app. Writes only ever target the TEST store
// STR002 (or are expected to be denied).
//
//   PEND_WEB_API_KEY=... node tools/live_security_test.mjs --secrets <test-accounts.json>
import fs from 'node:fs';

const PROJECT = 'senior-citizen-app-2454f';
const BUCKET = `${PROJECT}.firebasestorage.app`;
const KEY = process.env.PEND_WEB_API_KEY;
const secrets = JSON.parse(fs.readFileSync(process.argv[process.argv.indexOf('--secrets') + 1], 'utf8'));
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let pass = 0, fail = 0;
const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`);
}

async function signIn({ email, password }) {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`sign-in ${email}: ${j?.error?.message}`);
  return j.idToken;
}

// ---- Firestore REST value encoding ----
const enc = (v) => v === null ? { nullValue: null }
  : typeof v === 'string' ? { stringValue: v }
  : typeof v === 'boolean' ? { booleanValue: v }
  : Number.isInteger(v) ? { integerValue: String(v) }
  : typeof v === 'number' ? { doubleValue: v }
  : Array.isArray(v) ? { arrayValue: { values: v.map(enc) } }
  : { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, enc(v)]));
const dec = (f) => f == null ? null : 'integerValue' in f ? Number(f.integerValue) : 'doubleValue' in f ? f.doubleValue
  : 'stringValue' in f ? f.stringValue : 'booleanValue' in f ? f.booleanValue : null;

async function call(token, method, url, body) {
  const r = await fetch(url, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  let j = null; try { j = await r.json(); } catch { /* empty */ }
  return { status: r.status, body: j };
}
const get = (t, path) => call(t, 'GET', `${FS}/${path}`);
const query = (t, col, storeId, parent = '') => call(t, 'POST', `${FS}${parent ? `/${parent}` : ''}:runQuery`, {
  structuredQuery: {
    from: [{ collectionId: col }],
    ...(storeId ? { where: { fieldFilter: { field: { fieldPath: 'storeId' }, op: 'EQUAL', value: { stringValue: storeId } } } } : {}),
    limit: 50,
  },
});
const listSub = (t, path) => call(t, 'GET', `${FS}/${path}`);
const create = (t, col, id, data) => call(t, 'POST', `${FS}/${col}?documentId=${encodeURIComponent(id)}`, { fields: fields(data) });
const patch = (t, path, data) => call(t, 'PATCH',
  `${FS}/${path}?${Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join('&')}&currentDocument.exists=true`,
  { fields: fields(data) });
const denied = (r) => r.status === 403;
const okStatus = (r) => r.status === 200;
const rows = (r) => Array.isArray(r.body) ? r.body.filter((x) => x.document).length : -1;

const A = await signIn(secrets.store001Staff); // STORE001 staff
const B = await signIn(secrets.str002Admin);   // STR002 store admin
const aUid = secrets.store001Staff.uid, bUid = secrets.str002Admin.uid;

// ---------------- reads ----------------
let r = await query(A, 'products', 'STORE001');
check('STORE001 user reads STORE001 products', okStatus(r) && rows(r) === 12, `${r.status}, ${rows(r)} docs`);
r = await query(A, 'bills', 'STORE001');
check('STORE001 user reads STORE001 bills', okStatus(r) && rows(r) > 0, `${r.status}, ${rows(r)} docs`);
check('STORE001 user reads its store record', okStatus(await get(A, 'stores/STORE001')));
check('STORE001 user CANNOT read STR002 store record', denied(await get(A, 'stores/STR002')));
check('STORE001 user CANNOT query STR002 products', denied(await query(A, 'products', 'STR002')));
check('STORE001 user CANNOT query all products (no store filter)', denied(await query(A, 'products', null)));
check('STORE001 user CANNOT list stores', denied(await call(A, 'GET', `${FS}/stores`)));
check('STORE001 user CANNOT read STR002 counters', denied(await get(A, 'stores/STR002/meta/counters')));

const store001Product = (await query(A, 'products', 'STORE001')).body.find((x) => x.document).document.name.split('/documents/')[1];
const store001Bill = (await query(A, 'bills', 'STORE001')).body.find((x) => x.document).document.name.split('/documents/')[1];
const store001Cust = (await query(A, 'customers', 'STORE001')).body.find((x) => x.document).document.name.split('/documents/')[1];

check('STR002 admin reads STR002 store record', okStatus(await get(B, 'stores/STR002')));
r = await query(B, 'products', 'STR002');
check('STR002 admin reads STR002 products (empty at start or test-only)', okStatus(r), `${r.status}, ${rows(r)} docs`);
check('STR002 admin CANNOT query STORE001 products', denied(await query(B, 'products', 'STORE001')));
check('STR002 admin CANNOT read a STORE001 product by id', denied(await get(B, store001Product)));
check('STR002 admin CANNOT read a STORE001 bill by id', denied(await get(B, store001Bill)));
check('STR002 admin CANNOT list STORE001 bill items', denied(await listSub(B, `${store001Bill}/billItems`)));
check('STR002 admin CANNOT list STORE001 khata entries', denied(await listSub(B, `${store001Cust}/ledgerEntries`)));
check('STR002 admin CANNOT query STORE001 customers', denied(await query(B, 'customers', 'STORE001')));
check('STR002 admin CANNOT query STORE001 staff', denied(await query(B, 'staff', 'STORE001')));
check('STR002 admin CANNOT read STORE001 settings', denied(await get(B, 'stores/STORE001/meta/settings')));
check('signed out CANNOT read a STORE001 product', denied(await get(null, store001Product)));

// ---------------- writes ----------------
check('STR002 admin CANNOT create a customer in STORE001',
  denied(await create(B, 'customers', 'zz_test_cross', { name: 'x', storeId: 'STORE001' })));
check('STR002 admin CANNOT edit a STORE001 product', denied(await patch(B, store001Product, { name: 'hijack' })));
check('STORE001 user CANNOT create a customer in STR002',
  denied(await create(A, 'customers', 'zz_test_cross2', { name: 'x', storeId: 'STR002' })));
check('STORE001 user CANNOT move a STORE001 product to STR002', denied(await patch(A, store001Product, { storeId: 'STR002' })));
check('STORE001 user CANNOT move a STORE001 bill to STR002', denied(await patch(A, store001Bill, { storeId: 'STR002' })));
check('normal user CANNOT change their own storeId', denied(await patch(A, `staff/${aUid}`, { storeId: 'STR002' })));
check('normal user CANNOT make themselves admin', denied(await patch(A, `staff/${aUid}`, { role: 'admin' })));
check('STR002 admin CANNOT create a super admin',
  denied(await create(B, 'staff', 'zz_evil', { name: 'x', role: 'super_admin', storeId: 'STR002', active: true })));

// STR002's own data — the test store.
const tag = Date.now();
r = await create(B, 'products', `test_p_${tag}`, { name: 'TEST Feed', nameMr: 'चाचणी', brandId: '', bagWeightKg: 50, fullBagPrice: 1000, perKgPrice: 25, storeId: 'STR002' });
check('STR002 admin creates a product in STR002', okStatus(r), `${r.status}`);
r = await create(B, 'customers', `test_c_${tag}`, { name: 'TEST Customer', mobile: '', outstandingBalance: 0, storeId: 'STR002' });
check('STR002 admin creates a customer in STR002', okStatus(r), `${r.status}`);
check('STR002 admin CANNOT move its customer to STORE001', denied(await patch(B, `customers/test_c_${tag}`, { storeId: 'STORE001' })));
check('STR002 admin CANNOT move its product to STORE001', denied(await patch(B, `products/test_p_${tag}`, { storeId: 'STORE001' })));

// A full sale in STR002, written exactly like the app's one transaction.
// (Firestore's REST beginTransaction is not available to end-user tokens,
// so the same documents go in ONE atomic commit — rules evaluate them
// together exactly as for the app's SDK transaction.)
const counters = await call(B, 'GET', `${FS}/stores/STR002/meta/counters`);
const next = (dec(counters.body?.fields?.bill) ?? 1000) + 1;
const billId = `STR002_BILL${next}`;
const nowIso = new Date().toISOString();
const doc = (path, data) => ({ update: { name: `projects/${PROJECT}/databases/(default)/documents/${path}`, fields: fields(data) } });
const commit = await call(B, 'POST', `${FS}:commit`, {
  writes: [
    { update: { name: `projects/${PROJECT}/databases/(default)/documents/stores/STR002/meta/counters`, fields: fields({ bill: next }) }, updateMask: { fieldPaths: ['bill'] } },
    doc(`batches/test_b_${tag}`, { branchId: 'test', productId: `test_p_${tag}`, batchNo: 'T1', bagsReceived: 10, bagsAvailable: 9, looseKgAvailable: 0, bagsSold: 1, status: 'active', storeId: 'STR002', createdAt: nowIso, updatedAt: nowIso }),
    doc(`stock/test_p_${tag}`, { productId: `test_p_${tag}`, bagsRemaining: 9, looseKgRemaining: 0, storeId: 'STR002' }),
    doc(`stockLogs/test_l_${tag}`, { productId: `test_p_${tag}`, type: 'sale', bagsDelta: -1, looseKgDelta: 0, billId, createdAt: nowIso, storeId: 'STR002' }),
    doc(`bills/${billId}`, { billNumber: next, customerId: `test_c_${tag}`, customerName: 'TEST Customer', subtotal: 1000, discountTotal: 0, totalAmount: 1000, payments: [{ mode: 'cash', amount: 1000 }], status: 'final', createdAt: nowIso, createdBy: bUid, revision: 0, storeId: 'STR002' }),
    doc(`bills/${billId}/billItems/0`, { productId: `test_p_${tag}`, saleType: 'bag', quantityOrWeight: 1, rate: 1000, catalogRateAtSale: 1000, lineTotal: 1000, storeId: 'STR002' }),
    doc(`auditLogs/test_a_${tag}`, { storeId: 'STR002', userId: bUid, role: 'admin', action: 'BILL_FINALIZED', entityType: 'BILL', entityId: billId, timestamp: nowIso }),
  ],
});
check('STR002 sale = counter + bill + item + batch + stock + log + audit, one atomic commit', okStatus(commit), `${commit.status} ${commit.body?.error?.message ?? ''}`);
check('STR002 bill number is its own sequence (STR002_BILL…, from 1001)', billId.startsWith('STR002_BILL') && next >= 1001, billId);
r = await get(A, 'stores/STORE001/meta/counters');
check('STORE001 counter unchanged by STR002 sale (continues from 1032)', okStatus(r) && dec(r.body.fields.bill) === 1032, `bill=${dec(r.body?.fields?.bill)}`);
check('STR002 admin CANNOT move its bill to STORE001', denied(await patch(B, `bills/${billId}`, { storeId: 'STORE001' })));
check('STR002 admin CANNOT change bill amounts', denied(await patch(B, `bills/${billId}`, { totalAmount: 1 })));
check('STR002 admin CANNOT oversell (negative batch)', denied(await patch(B, `batches/test_b_${tag}`, { bagsAvailable: -1 })));
r = await patch(B, `bills/${billId}`, { status: 'void', statusChangedAt: new Date().toISOString() });
check('STR002 admin voids its bill (status only)', okStatus(r), `${r.status}`);
check('STORE001 user CANNOT see the STR002 bill', denied(await get(A, `bills/${billId}`)));
r = await query(B, 'auditLogs', 'STR002');
check('STR002 admin reads STR002 audit log', okStatus(r) && rows(r) >= 1, `${rows(r)} entries`);
check('STR002 admin CANNOT read STORE001 audit log', denied(await query(B, 'auditLogs', 'STORE001')));
check('staff CANNOT read their store audit log', denied(await query(A, 'auditLogs', 'STORE001')));
check('STORE001 user CANNOT write an audit entry for STR002',
  denied(await create(A, 'auditLogs', `zz_${tag}`, { storeId: 'STR002', userId: aUid, action: 'X', timestamp: nowIso })));

// ---------------- Storage ----------------
const png = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000' +
  '1f15c4890000000d49444154789c6360000002000100e221bc330000000049454e44ae426082', 'hex');
const up = (t, path) => fetch(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?name=${encodeURIComponent(path)}`,
  { method: 'POST', headers: { Authorization: `Firebase ${t}`, 'Content-Type': 'image/png' }, body: png });
const del = (t, path) => fetch(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(path)}`,
  { method: 'DELETE', headers: { Authorization: `Firebase ${t}` } });
const dl = (t, path) => fetch(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(path)}?alt=media`,
  { headers: t ? { Authorization: `Firebase ${t}` } : {} });
const own = `stores/STR002/products/test_p_${tag}/product_image.png`;
let s = await up(B, own);
check('Storage: STR002 admin uploads an image to STR002', s.status === 200, `${s.status}`);
check('Storage: STORE001 user CANNOT read the STR002 image', (await dl(A, own)).status === 403);
check('Storage: STORE001 user CANNOT upload into STR002', (await up(A, `stores/STR002/products/x/y.png`)).status === 403);
check('Storage: STR002 admin CANNOT upload into STORE001', (await up(B, `stores/STORE001/products/x/y.png`)).status === 403);
check('Storage: STR002 admin CANNOT upload a non-image', (await fetch(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?name=${encodeURIComponent(`stores/STR002/products/x/a.txt`)}`,
  { method: 'POST', headers: { Authorization: `Firebase ${B}`, 'Content-Type': 'text/plain' }, body: 'x' })).status === 403);
check('Storage: STR002 admin CANNOT upload into the legacy path', (await up(B, `products/x/y.png`)).status === 403);
s = await del(B, own);
check('Storage: STR002 admin deletes its test image', s.status === 204 || s.status === 200, `${s.status}`);

fs.writeFileSync('live-security-results.json', JSON.stringify({ at: new Date().toISOString(), pass, fail, results, testIds: { tag, billId } }, null, 2));
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exitCode = 1;
