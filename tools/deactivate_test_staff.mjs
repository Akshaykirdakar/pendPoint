// Deactivates the STORE001 verification login (staff record + Auth account).
import fs from 'node:fs';
import { initAdmin, PROJECT_ID } from './admin_init.mjs';
const secrets = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const { uid } = secrets.store001Staff;
const { db } = initAdmin();
await db.doc(`staff/${uid}`).set({ active: false }, { merge: true });
const res = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:update`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${process.env.PEND_ACCESS_TOKEN}`, 'x-goog-user-project': PROJECT_ID, 'Content-Type': 'application/json' },
  body: JSON.stringify({ localId: uid, disableUser: true }),
});
console.log('staff active=false; auth disabled:', res.status, (await res.json()).localId === uid);
