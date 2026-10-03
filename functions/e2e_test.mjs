// End to end in the emulators (Auth + Firestore + Functions, demo project —
// nothing real is touched): real sign-ins call setUserPassword, and the
// result is checked by signing in with the old / new password.
//
//   cd functions && npm run test:e2e
const PROJECT = process.env.GCLOUD_PROJECT ?? 'demo-pend-fn';
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const FS = `http://127.0.0.1:8086/v1/projects/${PROJECT}/databases/(default)/documents`;
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1/setUserPassword`;

let failed = 0;
const ok = (cond, what) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${what}`);
  if (!cond) failed++;
};

async function post(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

async function signUp(email, password) {
  const r = await post(`${AUTH}/accounts:signUp?key=fake`, { email, password, returnSecureToken: true });
  if (r.status !== 200) throw new Error(`signUp ${email}: ${JSON.stringify(r.json)}`);
  return { uid: r.json.localId, token: r.json.idToken };
}
async function signIn(email, password) {
  const r = await post(`${AUTH}/accounts:signInWithPassword?key=fake`, { email, password, returnSecureToken: true });
  return r.status === 200 ? r.json.idToken : null;
}

const value = (v) => v === null ? { nullValue: null }
  : typeof v === 'boolean' ? { booleanValue: v } : { stringValue: String(v) };
async function setDoc(path, data) {
  const fields = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)]));
  const res = await fetch(`${FS}/${path}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) throw new Error(`setDoc ${path}: ${res.status}`);
}
async function audits() {
  const res = await fetch(`${FS}/auditLogs?pageSize=100`, { headers: { Authorization: 'Bearer owner' } });
  const json = await res.json();
  return (json.documents ?? []).map((d) => Object.fromEntries(
    Object.entries(d.fields).map(([k, v]) => [k, v.stringValue ?? v.nullValue ?? v.booleanValue])));
}

async function setPassword(token, uid, password) {
  const r = await post(FN, { data: { uid, password } }, token ? { Authorization: `Bearer ${token}` } : {});
  if (r.json.error) return r.json.error.status;
  return r.status === 200 && r.json.result?.ok === true ? 'OK' : `HTTP ${r.status}`;
}

// ---- people ----
const pw = 'start-123';
const users = {};
for (const name of ['boss', 'adminA', 'staffA', 'staffA2', 'adminA2', 'staffB', 'adminOff', 'staffOff']) {
  users[name] = { email: `${name.toLowerCase()}@test.local`, ...(await signUp(`${name.toLowerCase()}@test.local`, pw)) };
}
await setDoc('stores/STR-A', { status: 'ACTIVE' });
await setDoc('stores/STR-B', { status: 'ACTIVE' });
await setDoc('stores/STR-OFF', { status: 'INACTIVE' });
const staff = {
  boss: { role: 'super_admin', storeId: null },
  adminA: { role: 'admin', storeId: 'STR-A' },
  staffA: { role: 'staff', storeId: 'STR-A' },
  staffA2: { role: 'staff', storeId: 'STR-A' },
  adminA2: { role: 'admin', storeId: 'STR-A' },
  staffB: { role: 'staff', storeId: 'STR-B' },
  adminOff: { role: 'admin', storeId: 'STR-OFF' },
  staffOff: { role: 'staff', storeId: 'STR-OFF' },
};
for (const [k, v] of Object.entries(staff)) {
  await setDoc(`staff/${users[k].uid}`, { name: k, active: true, ...v });
}
const t = (k) => users[k].token;
const u = (k) => users[k].uid;

// ---- allowed ----
ok(await setPassword(t('adminA'), u('staffA'), 'staffA-new1') === 'OK', 'store admin sets own-store staff password');
ok(await signIn(users.staffA.email, 'staffA-new1') !== null, '  staff signs in with the new password');
ok(await signIn(users.staffA.email, pw) === null, '  old password no longer works');
ok(await setPassword(t('boss'), u('adminA2'), 'adminA2-new') === 'OK', 'super admin sets a store admin password');
ok(await signIn(users.adminA2.email, 'adminA2-new') !== null, '  admin signs in with the new password');
ok(await setPassword(t('boss'), u('staffB'), 'staffB-new1') === 'OK', 'super admin sets another store\'s staff password');

// ---- refused (and nothing changed) ----
ok(await setPassword(t('adminA'), u('staffB'), 'hack-1234') === 'PERMISSION_DENIED', 'store admin → other store\'s staff refused');
ok(await signIn(users.staffB.email, 'hack-1234') === null, '  that password was not set');
ok(await setPassword(t('adminA'), u('adminA2'), 'hack-1234') === 'PERMISSION_DENIED', 'store admin → another admin refused');
ok(await setPassword(t('adminA'), u('boss'), 'hack-1234') === 'PERMISSION_DENIED', 'store admin → super admin refused');
ok(await setPassword(t('staffA2'), u('staffA'), 'hack-1234') === 'PERMISSION_DENIED', 'staff → staff refused');
ok(await setPassword(t('adminOff'), u('staffOff'), 'hack-1234') === 'PERMISSION_DENIED', 'admin of an inactive store refused');
ok(await setPassword(null, u('staffA'), 'hack-1234') === 'UNAUTHENTICATED', 'signed out refused');
ok(await setPassword(t('boss'), u('boss'), 'hack-1234') === 'FAILED_PRECONDITION', 'own password not via this function');
ok(await setPassword(t('adminA'), u('staffA2'), '123') === 'INVALID_ARGUMENT', 'too-short password refused');
ok(await signIn(users.staffA.email, 'hack-1234') === null && await signIn(users.boss.email, pw) !== null,
  '  refused calls changed nothing');

// disabled admin
await setDoc(`staff/${u('adminA')}`, { name: 'adminA', active: false, role: 'admin', storeId: 'STR-A' });
ok(await setPassword(t('adminA'), u('staffA2'), 'hack-1234') === 'PERMISSION_DENIED', 'disabled admin refused');

// ---- audit ----
const log = (await audits()).filter((a) => a.action === 'PASSWORD_RESET');
ok(log.length === 3, `3 PASSWORD_RESET audit entries (got ${log.length})`);
const first = log.find((a) => a.entityId === u('staffA'));
ok(first?.storeId === 'STR-A' && first?.userId === u('adminA') && first?.role === 'admin' && !!first?.timestamp,
  '  entry has store, user, role, record and time');
ok(!JSON.stringify(log).includes('staffA-new1'), '  no password stored in the audit log');

console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED');
process.exit(failed ? 1 : 0);
