# PendPoint — pre-existing production data issues

Project `senior-citizen-app-2454f` · read-only check on 2026-10-03, after the
multi-store migration. **Nothing listed here was changed, deleted or
reconstructed.** Every record already had these problems before the migration;
the migration only added `storeId: STORE001` to them.

Decide each item with the shop owner before anyone changes anything. Fixing
any of them changes bills, stock or reports, so it needs a backup first and an
audit entry.

## 1. Bill lines whose product was deleted (23 lines, 19 bills)

The product records these bill lines point to were deleted earlier. The
bills themselves are intact: totals, payments and khata are correct, and the
lines keep their quantity, rate and amount. The effect is that the app
cannot show a product name for these lines, and product- or brand-wise
breakdowns cannot attribute them. Bill totals and revenue still count them.

| Deleted product id | Bill lines |
|---|---|
| `p1` | BILL1001/0, BILL1002/1, BILL1004/0, BILL1005/0, BILL1007/0, BILL1010/0, BILL1011/1 |
| `p5` | BILL1002/0, BILL1006/0 |
| `p6` | BILL1003/0, BILL1003/1 |
| `p17891969451095695` | BILL1007/1, BILL1009/0, BILL1009/1, BILL1010/1, BILL1013/0, BILL1014/0 |
| `p17891937823725474` | BILL1012/0 |
| `p17906993380840006` | BILL1021/0, BILL1022/0, BILL1024/0 |
| `p17906993394120007` | BILL1023/0, BILL1023-R1/0 |

Recommended: leave the bills as they are; they are financial history. If
names matter, a product with the same id could be re-created as
**inactive**, which brings the names back without changing any bill.

## 2. Stock batches of deleted products (12 batches)

| Batch | Deleted product | Bags | Loose kg |
|---|---|---:|---:|
| batch17893282106070001 | p17891969451095695 | 17 | 30 |
| batch17893282113650003 | p2 | 4 | 22 |
| batch17893282117310004 | p3 | 21 | 0 |
| batch17893282120940005 | p4 | 2 | 8 |
| batch17893282124670006 | p5 | **−7** | 17 |
| batch17893282128270007 | p6 | 13 | 33 |
| batch179069934366600011 | p17906993380840006 | 100 | 0 |
| batch179069934627800013 | p17906993380840006 | 75 | 0 |
| batch179069934719500015 | p17906993380840006 | 14 | 0 |
| batch179069934833300017 | p17906993380840006 | 10 | 0 |
| batch179069934915100019 | p17906993394120007 | 49 | 0 |
| batch179069935048500021 | p17906993380840006 | 0 | 0 |

These can never be sold, because there's no product to pick. They still sit
in the database as "active" stock, and one has a **negative** quantity (−7
bags of `p5`). Any report that adds up all batches includes these quantities.

Recommended: the owner checks whether the goods physically exist. If not,
mark the batches finished or zero them with a recorded stock adjustment,
keeping the history. Do not delete them.

## 3. BILL1008 — total ₹6,100, no item lines

| Field | Value |
|---|---|
| Bill number | 1008 |
| Status | final |
| Total | ₹6,100 |
| Subtotal | 0 |
| Payments | none recorded |
| Customer | none (walk-in) |
| Created | 2026-09-13 07:34 |
| Item lines | 0 |

The total doesn't match its (empty) lines and no payment is recorded. It looks
like a test or partly-saved bill from an older app version. It is counted in
revenue reports (₹6,100).

Recommended: the owner confirms whether this sale happened. If not, **void**
it from the app's Bills screen. Voiding keeps the record and writes an audit
entry. Do not delete it or edit its amount.

## 4. Another application's collections in the same database

The project's Firestore also holds collections that do not belong to PendPoint
and look like a Senior Citizen app (the project's name):

| Collection | Documents (2026-10-03) |
|---|---:|
| `announcements` | 6 |
| `emergency_logs` | 1 |
| `members` | 4 |
| `settings` | 1 |
| `sms_logs` | 1 |
| `users` | 4 |

PendPoint never reads or writes them, and the migration did not touch them.
PendPoint's rules deny all access to them. So did the rules that were live
before the multi-store deployment (verified from the saved copy), so this
didn't change. If that app is still in use, it is a separate concern: either
it gets its own rules block (written and reviewed for that app), or it moves
to its own Firebase project. Do not loosen the PendPoint rules for it.
