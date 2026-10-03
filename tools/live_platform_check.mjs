// LIVE check of the platform rules (global settings, plans, announcements,
// notifications, store payments/reminders) against the deployed rules,
// signed in as the TEST admin of STR002 through the Firestore REST API —
// the server decides. READ-ONLY: every write attempted here must be DENIED,
// so nothing in production changes.
//
//   PEND_WEB_API_KEY=... node tools/live_platform_check.mjs --secrets <test-accounts.json>
import fs from 'node:fs';

const PROJECT = 'senior-citizen-app-2454f';
const KEY = process.env.PEND_WEB_API_KEY;
const secrets = JSON.parse(fs.readFileSync(process.argv[process.argv.indexOf('--secrets') + 1], 'utf8'));
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let pass = 0, fail = 0;
function check(name, ok, detail = '') {
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`);
}
async function signIn({ email, password }) {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`sign-in: ${j?.error?.message}`);
  return j.idToken;
}
async function call(token, method, url, body) {
  const r = await fetch(url, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return r.status;
}
const get = (t, path) => call(t, 'GET', `${FS}/${path}`);
const eq = (f, v) => ({ fieldFilter: { field: { fieldPath: f }, op: 'EQUAL', value: { stringValue: v } } });
const inList = (f, vs) => ({ fieldFilter: { field: { fieldPath: f }, op: 'IN',
  value: { arrayValue: { values: vs.map((v) => ({ stringValue: v })) } } } });
const runQuery = (t, filters, order = true) => call(t, 'POST', `${FS}:runQuery`, {
  structuredQuery: {
    from: [{ collectionId: 'notifications' }],
    where: filters.length === 1 ? filters[0] : { compositeFilter: { op: 'AND', filters } },
    ...(order ? { orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }] } : {}),
    limit: 20,
  },
});
const write = (t, path, data) => call(t, 'PATCH', `${FS}/${path}`, {
  fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, { stringValue: v }])),
});
const allowed = (s) => s === 200 || s === 404; // 404 = allowed, doc not there yet
const denied = (s) => s === 403;

const t = await signIn(secrets.str002Admin);
const S = 'STR002', HOME = 'STORE001';

let s;
s = await get(t, 'global_settings/general'); check('store admin may read global_settings/general', allowed(s), s);
s = await get(t, 'global_settings/admin'); check('store admin may NOT read global_settings/admin', denied(s), s);
s = await write(t, 'global_settings/general', { appName: 'x' }); check('store admin may NOT write global settings', denied(s), s);
s = await get(t, 'plans/any'); check('store admin may NOT read plans', denied(s), s);
s = await write(t, 'plans/x', { name: 'free' }); check('store admin may NOT create plans', denied(s), s);
s = await get(t, 'platformAnnouncements/any'); check('store admin may NOT read platform announcements', denied(s), s);
s = await get(t, 'announcements/any'); check("other application's `announcements` still closed", denied(s), s);

s = await runQuery(t, [eq('storeId', S), inList('recipientRole', ['all', 'admin'])]);
check('own-store notification feed query works (index READY)', s === 200, s);
s = await runQuery(t, [eq('storeId', HOME), inList('recipientRole', ['all', 'admin'])]);
check('STORE001 notifications refused', denied(s), s);
s = await runQuery(t, [eq('recipientRole', 'super_admin')]);
check('super admin notifications refused', denied(s), s);
s = await write(t, `notifications/live-check-${Date.now()}`, { storeId: S, recipientRole: 'all', type: 'announcement' });
check('store admin may NOT broadcast notifications', denied(s), s);

s = await get(t, `stores/${HOME}/payments/any`); check('STORE001 payments refused', denied(s), s);
s = await write(t, `stores/${S}/payments/fake`, { status: 'paid' }); check('store admin may NOT record payments', denied(s), s);
s = await get(t, `stores/${S}/reminders/any`); check('reminder log refused to store admin', denied(s), s);
s = await call(t, 'PATCH', `${FS}/stores/${S}?updateMask.fieldPaths=planExpiryDate`,
  { fields: { planExpiryDate: { stringValue: '2099-01-01' } } });
check('store admin may NOT extend own plan', denied(s), s);
s = await call(t, 'PATCH', `${FS}/stores/${S}?updateMask.fieldPaths=status`,
  { fields: { status: { stringValue: 'INACTIVE' } } });
check('store admin may NOT change own store status', denied(s), s);
s = await call(t, 'PATCH', `${FS}/stores/${HOME}?updateMask.fieldPaths=storeName`,
  { fields: { storeName: { stringValue: 'hijack' } } });
check('store admin may NOT rename another store', denied(s), s);
s = await get(t, `bills/BILL1032`); check('existing isolation: STORE001 bill still refused', denied(s), s);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
