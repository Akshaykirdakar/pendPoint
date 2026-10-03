# PendPoint — Super Admin platform layer

This layer adds global settings, store plans and payments, notifications, announcements and plan reminders on top of the multi-store system in `MULTISTORE.md`. Store isolation is unchanged: everything new is either global (super admin only) or tagged with its store and checked by `firestore.rules`.

## Data

| Path | Scope | Who |
|---|---|---|
| `global_settings/general` | app name, logo, version, support contacts, company, address, website, default language | all active users read; super admin writes |
| `global_settings/admin` | notification switches, plan rules (trial / plan / grace days, reminder days), message templates, provider *names* (no secrets) | super admin only |
| `plans/{id}` | name, durationDays, price, active | super admin only |
| `stores/{id}` (new fields) | owner (name / email / phone / WhatsApp / preferred channel); plan (planId, planName, planStatus, start / expiry, renewalAmount, paymentStatus, last / next payment, grace) | super admin all fields; the store's own admin only name and contact/owner fields |
| `stores/{id}/payments/{id}` | amount, currency, paymentDate, paymentMethod, transactionId, planId, periodStart / End, status (pending / paid / failed / refunded), recordedBy, notes, createdAt | super admin writes; that store's admin reads |
| `stores/{id}/reminders/{key}` | one document per reminder sent (`before-7@2026-11-01`) | super admin; create-only, so a reminder can never be sent twice |
| `notifications/{id}` | `recipientRole` `super_admin` / `admin` / `all`, `storeId`, type, title, message, priority, entity, channels + channelStatus, senderUid, status, createdAt, visibleFrom, expiresAt, readBy {uid: time} | see below |
| `platformAnnouncements/{id}` | title, message, image, link, priority, target (all / active / selected / plan), stores, channels, start, expiry | super admin only; delivered as notifications |

**Why `platformAnnouncements` and not `announcements`:** `announcements` in this Firebase project belongs to another application (6 documents). It stays closed.

Existing stores need no migration. Every new field is optional, and a store without a plan shows "No plan" (STORE001 today).

## Notification security (`firestore.rules`)

- `super_admin` notifications: only a super admin reads them.
- `admin` notifications: only the admin of that store.
- `all` notifications: every user of that store, while the store is active.
- Feed queries must name the store and audience. Anything broader is refused.
- **Creating:**
  - the super admin may create any notification;
  - a store admin may only report their own store's changes to the super admin (`store_updated`, `staff_*`), as themselves, and unread;
  - staff create nothing.
- **Reading state:** a user can set only their own `readBy.<uid>` entry; nothing else in the notification can change.

Tests:
- emulator: `tools/rules_test/platform_rules.test.mjs`
- live, read-only: `tools/live_platform_check.mjs`

## Automatic events

All of these come from `PlatformService`.

| Event | Super admin | Store |
|---|---|---|
| store created | Store Created | — |
| name / contact / owner / address changed (super admin or store admin) | Store Updated: "STORE001 has been updated. Store name changed from Demo Shop to Akshay Traders." | — |
| deactivated / activated | "Store STR002 has been deactivated." / "...activated." | every user of the store |
| plan changed (upgrade / downgrade by price) | Store Plan Changed | owner |
| payment recorded: paid / renewal / pending / failed | Payment Received / Renewal Recorded / Payment Pending / Payment Failed | owner gets payment confirmation (paid) |
| staff added / disabled / activated / role or permissions changed | Staff … | — |

- **Duplicates:** the super admin's own actions arrive already marked read. A name-only staff edit creates no notification. One store save produces one notification.
- **Audit:** every store field change is also written to the audit log as `STORE_FIELD_CHANGED` (storeId, user, time, field, oldValue, newValue). Passwords and secrets are never logged.
- **Live refresh:** the super admin dashboard and the open store's badge read Firestore snapshots, so renames, status, plan and payment changes appear without a restart. A store user is stopped as soon as their store is deactivated.
- **Store code:** this is the document id and the security boundary, so it never changes. "Store code changed" therefore cannot happen.

## Channels

`NotificationService` has three channels:

| Channel | Status |
|---|---|
| `InAppNotificationService` | complete |
| `WhatsAppNotificationService` | needs a `MessagingProvider` |
| `SmsNotificationService` | needs a `MessagingProvider` |

**No WhatsApp or SMS provider is configured.** Messages on those channels are recorded per store as `provider_required` and are not sent. The send report and the notification details say so.

To add a provider later:
1. Build a small backend endpoint (Cloud Function) that holds the provider secret.
   - WhatsApp needs a Business Account and an access token, plus approved message templates.
   - SMS needs a DLT-registered gateway: sender ID, template IDs and an API key.
   - Put the secret in Secret Manager. Never in Flutter or Firestore.
2. Implement `MessagingProvider` to call that endpoint.
3. Pass it to the WhatsApp / SMS channel.

Nothing else in the app changes.

## Scheduling and reminders

`dueReminders()` holds the rules:
- before expiry: at the configured days (7, 3, 1 by default);
- on the expiry day;
- after expiry: at the configured days (1, 7 by default).

Each reminder is claimed in `stores/{id}/reminders` before it's sent.

**There is no backend scheduler.** The super admin runs reminders from the dashboard ("Run plan reminders now"). Running them automatically needs a scheduled Cloud Function (Cloud Scheduler) that applies the same rules with the same reminder keys. Not configured.

For "Schedule later" notifications, in-app messages are stored and shown from the chosen time. WhatsApp / SMS have no scheduler, which the app reports.

## Deployment record — 2026-10-03

| Step | Result |
|---|---|
| Emulator rules tests | purchase 15, draft 8, multistore 37, platform 16 groups — all pass |
| Flutter | analyze clean, 459 / 459 tests, web build OK |
| Backup | live indexes and live rules saved in `deploy-backups/20261003-115402-platform/`; live rules verified identical to the last deploy before replacing them |
| Indexes | `notifications` (recipientRole, createdAt) and (storeId, recipientRole, createdAt) — READY, along with the 4 existing |
| Firestore rules | released ruleset `7468cb19-…`, verified identical to the repo file (previous: `7671f320-…`) |
| Live check | 18 / 18 as the STR002 test admin, read-only |
| Not deployed | the app itself (no hosting configured), the `setUserPassword` function, any scheduler |

**Rollback:** redeploy `deploy-backups/20261003-115402-platform/live-firestore.rules-before`. The new rules only add to the old ones, so the current app keeps working with either version.
