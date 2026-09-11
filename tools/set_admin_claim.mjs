// One-off: grants an existing Firebase Auth user the `role: admin` custom
// claim that firestore.rules checks (request.auth.token.role). This is the
// ONE step that cannot be done by hand in the Firestore console — everything
// else (catalogue, stock, customers, staff doc, meta) can be typed in there
// directly. Run this after creating the owner's account in
// Console -> Authentication -> Users.
//
//   cd tools
//   npm install
//   cd ..
//   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\pend-point-service-account.json'
//   $env:PEND_OWNER_EMAIL = 'owner@example.com'
//   node tools/set_admin_claim.mjs
//
// Prints the owner's UID — use that exact string as the document ID when you
// create staff/{uid} by hand in the console.

import admin from 'firebase-admin';

const ownerEmail = process.env.PEND_OWNER_EMAIL?.trim();

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account JSON file.');
}
if (!ownerEmail) {
  throw new Error('Set PEND_OWNER_EMAIL to the existing Firebase Auth owner email.');
}

admin.initializeApp({credential: admin.credential.applicationDefault()});

const owner = await admin.auth().getUserByEmail(ownerEmail);
await admin.auth().setCustomUserClaims(owner.uid, {
  ...owner.customClaims,
  role: 'admin',
});

console.log(`Admin claim set for ${owner.email}.`);
console.log(`UID: ${owner.uid}`);
console.log('Use this UID as the document ID for staff/{uid} in the Firestore console.');
console.log('Sign out and back in on the app afterward so it picks up the new claim.');
