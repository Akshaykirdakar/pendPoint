# PendPoint — Multi-Store Architecture

One Firebase project, one Firestore database, many stores. Every
store-owned record carries `storeId`; a user's role and store come only from
their protected `staff/{uid}` record. Isolation is enforced twice:

1. **App** — `FirestoreRepository` filters every read and stamps every write
   with the current store (screens never pass a store id). With no store
   context it throws `StoreContextException` instead of reading anything.
2. **Firestore / Storage rules** — the server enforces the same boundary,
   independent of the app.

---

## 1. Roles

| Role | Stored `staff.role` | Store | Can |
|---|---|---|---|
| SUPER_ADMIN | `super_admin` (new) | `storeId: null` | create/edit/activate/deactivate stores, create/manage store users, open any store, read all audit logs |
| STORE_ADMIN | `admin` (unchanged) | one store | everything the owner could do before, in their store only |
| STAFF | `staff` (unchanged) | one store | everything staff could do before, in their store only |

Existing role values were kept so live staff records keep working. A user
belongs to exactly one store (`storeId`); the model can later grow a
`storeIds` list without changing the rules' shape.

## 2. Collection-scope matrix

| Collection | Scope | Isolation |
|---|---|---|
| `stores/{storeId}` | GLOBAL | super admin writes; a store user reads only their own store doc |
| `stores/{storeId}/meta/settings` | STORE | path = store; owner writes |
| `stores/{storeId}/meta/counters` | STORE | path = store; bill/purchase/draft numbers per store |
| `staff/{uid}` | GLOBAL + store assignment | `storeId` field; store admin manages own store only |
| `brands`, `branches`, `suppliers`, `products` | STORE | `storeId`; owner writes |
| `stock`, `batches`, `stockLogs` | STORE | `storeId`; staff write via the stock transaction |
| `bills` (+ `billItems`) | STORE | `storeId`; items inherit the parent bill's store |
| `purchases` (+ `purchaseItems`) | STORE | `storeId`; items inherit the parent |
| `customers` (+ `ledgerEntries`) | STORE | `storeId`; khata entries inherit the customer |
| `draftBills` | STORE | `storeId`; version check unchanged |
| `auditLogs` | STORE | `storeId`; append-only |
| `meta/settings`, `meta/counters` | legacy | copied to STORE001 by the migration; read-only for super admin |
| Storage `stores/{storeId}/…` | STORE | product photos, brand logos, purchase-bill photos |
| Storage `products/…`, `brands/…`, `purchase-bills/…` | legacy | STORE001 + super admin only; no new uploads |

Returns and reports are not collections: returns are `stockLogs` (type
`return`) and reports are computed from the store's loaded bills — both are
therefore store-scoped automatically.

## 3. Key design decisions

- **Store code = document id** (`stores/STR002`): unique by construction and
  immutable. Codes: 3–20 of `A–Z 0–9 -`.
- **Original store = `STORE001`**: all pre-existing data is migrated there.
- **Bill / purchase / draft numbering is per store**, continuing STORE001's
  existing sequence unchanged. Document ids get the store prefix for new
  stores (`STR002_BILL1001`) so two stores' `BILL1001` never collide;
  STORE001 keeps its existing id format.
- **`storeId` is stamped by the repository**, not carried by UI models, so no
  screen can supply another store's id. Nested documents also get `storeId`.
- **Super admin "Open store"** changes only the app's administrative store
  context (`StoreContext.openStore`); the Firebase identity stays super
  admin, and rules recognise it as such.
- **Inactive store / disabled user**: no data loads (app) and no reads/writes
  are allowed (rules); the user sees why.
- **Audit trail** (`auditLogs`): bill finalized/voided/corrected, price
  override, return, purchase created/corrected/voided, stock in/adjust/
  transfer, product price change, staff created/updated/disabled, store
  created/updated/disabled/enabled. Stock-affecting entries are written in the
  same transaction as the change.

## 4. Login flow

```
Firebase Auth → staff/{uid}
   none        → "No staff profile"
   inactive    → "Account disabled"
   super_admin → Super Admin dashboard (no store data loaded)
   store user  → stores/{storeId}
                   missing  → "No store assigned"
                   INACTIVE → "This store is currently inactive…"
                   ACTIVE   → StoreContext set → store data loads
```

Sign-out (`AppState.signOut`) clears every list, the cart, drafts, settings
and the store context before Firebase sign-out. Firestore's offline cache is
not wiped, but every query is filtered by `storeId` (and checked by rules),
so cached documents of one store never appear in another store's queries.

## 5. Code map

| Piece | Where |
|---|---|
| Store, roles, StoreContext, AuditEntry, StoreContextException | `lib/models/store.dart` |
| Staff with `storeId`, `phone` | `lib/models/staff.dart` |
| Repository API (context, stores, users, audit) | `lib/data/repository.dart` |
| Store-scoped Firestore implementation | `lib/data/firestore_repository.dart` |
| Session, open/close store, super-admin ops, audit, per-store ids | `lib/state/app_state.dart` |
| Login routing (`SessionScreen`) | `lib/main.dart` |
| Super admin dashboard, store form, store users, audit log, store badge | `lib/ui/screens/super_admin_screens.dart` |
| Rules | `firestore.rules`, `storage.rules` |
| Indexes | `firestore.indexes.json` |
| Migration (+ emulator test) | `tools/migrate_multistore.mjs`, `tools/migration_test.mjs` |

## 6. Tests

| Suite | What it proves | Result |
|---|---|---|
| `tools/rules_test/multistore_rules.test.mjs` | Store A ↛ Store B for every collection (get by id, query, create, update, delete, storeId change), nested items/khata, staff management limits, counters/settings, super admin, disabled/inactive/no-profile/signed-out, audit logs | 37/37 |
| `tools/rules_test/purchase_rules.test.mjs`, `draft_rules.test.mjs` | existing purchase/sale/void/draft behaviour under the new rules | 15/15, 8/8 |
| `tools/migration_test.mjs` | dry run writes nothing; apply keeps counts and totals; idempotent; other stores untouched; super admin set up | 5/5 |
| `test/multistore_repository_test.dart` | repository reads/writes scoped and stamped; no context = exception; per-store counters; cross-store commit and delete refused | 8/8 |
| `test/multistore_app_test.dart` | login routing; A ⇄ B isolation through the app; per-store bill ids; audit; sign-out clearing; super admin flows; screens at 360px | 14/14 |
| `test/session_switch_test.dart`, `test/photo_check_test.dart` | late store loads dropped on sign-out / store switch; new store gets its branch; draft audit; photo type/size and replace-without-self-delete | 7/7 |
| whole Flutter suite (incl. language/360px audit) | nothing else broke | 433/433 |

Run: `flutter test`; `cd tools/rules_test && npm test`;
`cd tools && npm run test:migration` (both need Java 21 for the emulator).

## 7. Production deployment checklist

Do these in order. Steps 1–4 are safe while the current app keeps running —
the migration only adds a field the current app ignores.

1. **Back up Firestore** — Console → Firestore → Import/Export (or
   `gcloud firestore export gs://<bucket>/pre-multistore`). Note the date.
2. **Service account** — Console → Project settings → Service accounts →
   generate a key; keep it outside the repo.
   `$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\key.json'`
3. **Dry run** — `cd tools; npm install; cd ..;`
   `node tools/migrate_multistore.mjs` → read the report (counts per
   collection).
4. **Migrate** —
   `node tools/migrate_multistore.mjs --apply --super-admin-email <your login email>`
   The report must end with `VALIDATION PASSED`.
5. **Deploy indexes, then wait until they are built** (Console → Firestore →
   Indexes):
   `firebase deploy --only firestore:indexes --project senior-citizen-app-2454f`
6. **Deploy rules and the new app together** (the old app does not stamp
   `storeId`, so it cannot write under the new rules):
   `firebase deploy --only firestore:rules,storage --project senior-citizen-app-2454f`
   then publish the new web build / APK.
7. **Run the migration once more with `--apply`** — catches anything the old
   app wrote between steps 4 and 6 (idempotent; normally "0 migrated").
8. **Verify on a real device**: store owner and staff log in to STORE001 and
   see their data; create STR002 as super admin with an admin user; log in
   as that user and confirm STORE001 data is not visible; a sale, a purchase,
   a draft, a void, printing, WhatsApp and SMS work.
9. Firebase Auth → Sign-in method → **Email/Password must be enabled** for
   the super admin to create store users.

Rollback: restore the step-1 export and redeploy the previous rules/app.

## 8. Final matrix

| Module | Store scoped | Modified | Tested | Status |
|---|---|---|---|---|
| Products | Yes | repo + rules + photos path | rules, repo, app | Done |
| Brands | Yes | repo + rules + logo path | rules, repo | Done |
| Customers | Yes | repo + rules | rules, repo, app | Done |
| Bills (+ items) | Yes | repo + rules + per-store ids | rules, repo, app | Done |
| Drafts | Yes | repo + rules + per-store ids | rules, repo, app | Done |
| Stock | Yes | repo + rules | rules, repo, app | Done |
| Batches | Yes | repo + rules | rules, repo, app | Done |
| Purchases (+ items, photos) | Yes | repo + rules + photo path | rules, repo, app | Done |
| Returns (stock logs) | Yes | repo + rules + audit | rules, repo | Done |
| Khata (ledger) | Yes | repo + rules | rules, repo, app | Done |
| Reports / dashboard | Yes (from store data) | — | app | Done |
| Settings / counters | Yes (`stores/{id}/meta`) | repo + rules | rules, repo | Done |
| Staff | Global + store | model + repo + rules | rules, app | Done |
| Audit logs | Yes | new | rules, repo, app | Done |
| Stores | Global | new | rules, repo, app | Done |
| Super Admin | Global | new screens | app, widget | Done |

## 9. Not done / to know

- **Deployed and migrated** on 2026-10-03; see §10. Pre-existing data
  issues are in `docs/DATA_ISSUES.md`.
- **Switching user/store in one app session** — a store load that finishes
  after sign-out, "All stores" or opening another store is discarded
  (`_bootstrapSeq`), and each new store gets its own branch set-up
  (`test/session_switch_test.dart`).
- **Global settings screen** — there are no global settings yet, so the
  Super Admin area has Dashboard, Stores, Users and Audit logs only.
- **Firestore offline cache** is partitioned by `storeId` queries rather than
  wiped at sign-out.
- **New store catalogue starts empty** — the store admin adds brands,
  products and stock; nothing is copied from another store.
- `tools/seed_firestore.mjs` seeds a fresh single store without `storeId`;
  run the migration after seeding a new project.

## 9a. Passwords

| Who | Own password | Sets another user's password |
|---|---|---|
| Super admin | 🔑 on the Super Admin bar, or Settings | any store user (Users → 🔑) — never a super admin |
| Store admin | Settings → 🔑 Change password | staff of their own store (Staff → 🔑) |
| Staff | — (ask the store admin) | — |

Own password: Firebase Auth in the app (current password first).
Another user's: the `setUserPassword` Cloud Function (`functions/`), because
only the Admin SDK can set someone else's password. It reads the caller's
`staff/{uid}` (and their store) itself, refuses everything else, signs the
user out of other devices and writes a `PASSWORD_RESET` audit entry (never the
password). Tests: `cd functions && npm test` (access rules) and
`npm run test:e2e` (emulators, needs Java 21).
Deploy: `firebase deploy --only functions --project senior-citizen-app-2454f`.

## 10. Production deployment record — 2026-10-03

Project `senior-citizen-app-2454f` (owner login used for admin tools via
`gcloud auth print-access-token`; no service-account key created).

| Step | Result |
|---|---|
| Backup | managed export `gs://senior-citizen-app-2454f-firestore-backups/pre-multistore-20261003-100050` — SUCCESSFUL, 214 documents (= audit total) |
| Previous rules / indexes | saved locally in `deploy-backups/20261003-100050/` (git-ignored) |
| Indexes | 4 composite indexes deployed, all READY |
| Migration | applied; every PendPoint record → `STORE001`; counts and totals identical; second run migrates 0 |
| Super admin | `staff/MozrUAEe7jfdKSiLVAA9QJ3vvLl1` = super_admin, storeId null, active |
| Rules | Firestore ruleset `7671f320-…`, Storage ruleset `21b53ed0-…` — identical to the repo files |
| IAM | Storage service agent granted `roles/firebaserules.firestoreServiceAgent` (needed for `firestore.get` in Storage rules) |
| Test store | `STR002` "Test Store" + TEST admin login (credentials only in `deploy-backups/…/test-accounts.json`) |
| Live security test | `tools/live_security_test.mjs` — 50/50 as real users |

Pre-existing data notes (unchanged by the migration): 23 bill items and 12
batches reference products deleted earlier; bill `BILL1008` has no item
lines. The database also holds another app's collections (`announcements`,
`emergency_logs`, `members`, `settings`, `sms_logs`, `users`), which the
PendPoint rules deny — exactly as the rules deployed before this did.
