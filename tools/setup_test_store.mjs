// Production verification setup: creates the test store STR002 ("Test
// Store") exactly as the Super Admin screen does (store + settings +
// counters), plus two clearly-labelled TEST logins:
//   - a Store Admin of STR002
//   - a staff user of STORE001 (only to prove STORE001 cannot reach STR002)
// Idempotent: existing store/accounts are reused. Passwords are written to
// the git-ignored file given by --secrets (never printed).
//
//   $env:PEND_ACCESS_TOKEN = (gcloud auth print-access-token)
//   node tools/setup_test_store.mjs --secrets deploy-backups/<ts>/test-accounts.json
import fs from 'node:fs';
import crypto from 'node:crypto';
import { initAdmin, PROJECT_ID } from './admin_init.mjs';

const API_KEY = process.env.PEND_WEB_API_KEY; // public web API key (firebase_options.dart)
const secretsFile = process.argv[process.argv.indexOf('--secrets') + 1];
if (!API_KEY || !secretsFile) throw new Error('Set PEND_WEB_API_KEY and pass --secrets <file>');

const { db } = initAdmin();
const now = new Date().toISOString();
const secrets = fs.existsSync(secretsFile) ? JSON.parse(fs.readFileSync(secretsFile, 'utf8')) : {};

// ---- STR002 ----
const store = db.doc('stores/STR002');
if (!(await store.get()).exists) {
  await db.runTransaction(async (tx) => {
    tx.set(store, {
      storeCode: 'STR002', storeName: 'Test Store', legalName: '', address: '', city: '',
      state: '', pincode: '', phone: '', email: '', gstNumber: '', status: 'ACTIVE',
      currency: 'INR', timezone: 'Asia/Kolkata', createdAt: now, updatedAt: now,
      createdBy: 'MozrUAEe7jfdKSiLVAA9QJ3vvLl1',
    });
    tx.set(db.doc('stores/STR002/meta/settings'), { shop: 'Test Store' });
    tx.set(db.doc('stores/STR002/meta/counters'), { bill: 1000, purchase: 0, draft: 1000 });
  });
  await db.collection('auditLogs').add({
    storeId: 'STR002', userId: 'MozrUAEe7jfdKSiLVAA9QJ3vvLl1', role: 'super_admin',
    action: 'STORE_CREATED', entityType: 'STORE', entityId: 'STR002', timestamp: now,
    note: 'production verification',
  });
  console.log('created stores/STR002');
} else {
  console.log('stores/STR002 already exists');
}

// ---- test logins (Firebase Auth sign-up, as the app's createLoginAccount) ----
async function account(key, email, staff) {
  let entry = secrets[key];
  if (!entry) {
    const password = crypto.randomBytes(12).toString('base64url');
    const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: false }),
    });
    const json = await res.json();
    if (!res.ok) throw new Error(`sign-up ${email}: ${json?.error?.message}`);
    entry = { email, password, uid: json.localId };
    secrets[key] = entry;
    fs.writeFileSync(secretsFile, JSON.stringify(secrets, null, 2));
  }
  await db.doc(`staff/${entry.uid}`).set({ ...staff, email, active: true }, { merge: true });
  console.log(`${key}: ${email} uid ${entry.uid}`);
}
await account('str002Admin', 'pendpoint.test.str002.admin@example.com',
  { name: 'TEST Admin STR002', role: 'admin', storeId: 'STR002', phone: '' });
await account('store001Staff', 'pendpoint.test.store001.staff@example.com',
  { name: 'TEST verification staff (deactivate after tests)', role: 'staff', storeId: 'STORE001', phone: '' });
console.log(`project ${PROJECT_ID}: done (passwords in ${secretsFile})`);
