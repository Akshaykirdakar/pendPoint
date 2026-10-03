// READ-ONLY: the super admin's Firebase Auth user and staff record.
import { initAdmin } from './admin_init.mjs';
const UID = 'MozrUAEe7jfdKSiLVAA9QJ3vvLl1', EMAIL = 'superadmin@gmail.com';
const { db, auth } = initAdmin();
const u = await auth.getUser(UID);
console.log(JSON.stringify({
  uid: u.uid, email: u.email, emailMatches: u.email === EMAIL, disabled: u.disabled,
  providers: u.providerData.map((p) => p.providerId),
}));
const byEmail = await auth.getUserByEmail(EMAIL);
console.log('getUserByEmail uid matches:', byEmail.uid === UID);
const s = await db.doc(`staff/${UID}`).get();
console.log('staff doc:', s.exists ? JSON.stringify(s.data()) : '(none)');
