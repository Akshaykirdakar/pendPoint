# First-time Firebase seed

This seed is intentionally an Admin SDK script. It does not relax Firestore
rules or expose an in-app administrator bootstrap path.

1. In Firebase Console → Authentication → Users, create the owner's Email/Password account.
2. In Google Cloud Console for `senior-citizen-app-2454f`, create a service-account key with permission to administer Firebase Auth and Firestore. Store its JSON file outside this repository.
3. From the project root, install the seeder dependency and run it in PowerShell:

```powershell
npm install --prefix tools
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\pend-point-service-account.json'
$env:PEND_OWNER_EMAIL = 'owner@example.com'
node tools/seed_firestore.mjs
```

The script refuses to run if products already exist. Use `--force` only to
merge the standard sample data into an existing database. It creates the
owner's protected `staff/{uid}` record with `role: "admin"`, and seeds brands,
products, stock, customers, and `meta` documents. Firestore and Storage rules
use this staff record as their single authorization source of truth.

For an existing project, create/verify this document using the Firebase
Console or a trusted Admin SDK environment only: `staff/{authenticated uid}`
with `role: "admin"`. A normal app user cannot create or promote this record.

Never commit the service-account JSON. `.gitignore` excludes keystores and
local Android settings; keep the service-account key outside the project too.
