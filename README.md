# पेंड Point — Flutter + Firebase

Billing & stock management for a cattle-feed (पेंड) shop. Built from the reviewed
Software Requirements Specification. Bilingual (Marathi + English), modern & bold,
light & dark.

This is a **buildable, breadth-first production foundation**: the data layer,
state, and every screen in the spec are implemented and wired. It runs
**immediately on an in-memory sample shop** (no Firebase needed), and the
Firestore backend is written behind the same interface — flip one line to go live.

---

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.3+).

```bash
cd pend_point
flutter create .        # generates android/ ios/ web/ platform folders
flutter pub get
flutter run             # on an emulator, device, or `-d chrome`
```

It boots straight into the sample shop. **Demo PINs:** Owner `1234`, Staff `1111`.

> `flutter create .` only adds the missing platform folders; it does not touch
> anything under `lib/`.

---

## Go live on Firebase (persist data)

1. In `pubspec.yaml`, uncomment `firebase_core`, `cloud_firestore` (and
   `firebase_auth`, `firebase_storage`) → `flutter pub get`.
2. `dart pub global activate flutterfire_cli && flutterfire configure`
   (generates `lib/firebase_options.dart`).
3. Uncomment the body of `lib/data/firestore_repository.dart`.
4. In `lib/main.dart`, follow the header comment: initialise Firebase, enable
   offline persistence, and build `FirestoreRepository()` instead of
   `InMemoryRepository()`.
5. Deploy the rules: `firebase deploy --only firestore:rules` (see `firestore.rules`).

Nothing else changes — the app talks only to the `Repository` interface.

---

## What's complete vs. stubbed

**Complete & wired**
- Full data model, in-memory repository + seed, and a complete `FirestoreRepository`.
- `AppState` business logic: cart, price override with **floor + PIN gate**,
  split-payment checkout, **atomic stock deduction** (auto-opens bags for
  by-weight sales), **credit/khata ledger**, void/return that restores stock,
  stock-in with batch/expiry/cost, adjustments, low-stock (on **total kg**),
  near-expiry, reports incl. the **discount/override report**.
- All 21 screens, bottom-tab navigation, bilingual UI, light/dark theme.

**Stubbed (clearly marked `TODO` in code) — the device/hardware bits**
- **QR scanning** (`scan_screen.dart`): simulated by tapping a code. Production
  drop-in is `mobile_scanner` (ML Kit) — the exact wiring is in the file header.
- **Thermal printing** (`bill_screen.dart` / `qr_sheet_screen.dart`): shows the
  flow and the *render-as-image* note (so Marathi/Devanagari prints correctly).
  Add `blue_thermal_printer` + a bitmap render of the receipt.
- **Auth**: production authorization is Firebase Auth plus the protected
  `staff/{uid}.role` record enforced by Firestore and Storage rules.

---

## How the code maps to the spec

| Spec area | Where |
|---|---|
| Data entities (Part D) | `lib/models/*` |
| Firestore layout & offline | `lib/data/firestore_repository.dart`, `firestore.rules` |
| Dual-unit stock (bags + loose kg), effective-kg low-stock | `models/stock.dart`, `AppState.levelOf` / `effKg` |
| Open-a-bag conversion | `AppState.openBag` + auto in `finalizeSale` |
| Price override stores catalogue rate; discount report | `models/bill.dart` (`catalogRate`), `reports_screen.dart` |
| Override PIN gate + price floor (findings 1 & 11) | `AppState.checkRate`, `cart_screen.dart` |
| Credit / khata ledger (finding 2) | `models/customer.dart`, `khata_screen.dart`, `customer_screen.dart` |
| Manual product search (finding 3) | `sell_screen.dart` |
| Devanagari thermal printing (finding 4) | `bill_screen.dart` (note + image-render TODO) |
| Void / returns (finding 5) | `AppState.voidBill`, `returns_screen.dart` |
| Batch / expiry on stock-in (finding 7) | `stock_in_screen.dart`, `models/stock_log.dart` |
| Split payments (finding 12) | `models/bill.dart` (`payments[]`), `checkout_screen.dart` |
| Bilingual UI (NFR5) | Baloo 2 + Mukta fonts, `ProductName`, language setting |

---

## Project structure

```
lib/
  main.dart                 app bootstrap, theme mode, Firebase switch
  models/                   Brand, Product, Stock, StockLog, Bill+BillItem+Payment,
                            Customer+LedgerEntry, Staff, AppSettings, enums
  data/
    repository.dart         Repository interface + Snapshot
    seed_data.dart          the sample shop
    memory_repository.dart  default (in-memory) backend
    firestore_repository.dart  production backend (enable Firebase to use)
  state/
    app_state.dart          all business logic (ChangeNotifier + Provider)
    cart_line.dart
  utils/                    theme (tokens, fonts), formatters, 
  ui/
    root_shell.dart         bottom-tab shell
    widgets/                PendScaffold, shared widgets
    screens/                21 screens
firestore.rules             security rules
```

Built with Flutter, Provider, google_fonts, qr_flutter, intl.

---

## Build the APK on GitHub

The GitHub Actions workflow at `.github/workflows/android-apk.yml` runs on every
pull request, every push to `main`, and manually from **Actions → Android APK →
Run workflow**. It fetches packages, runs analysis and widget tests, then uploads
`pend-point-release-apk` as a workflow artifact. Open the completed workflow and
download that artifact to get `app-release.apk`.

Before pushing this project, keep `android/`, `lib/firebase_options.dart`,
`android/app/google-services.json`, and `pubspec.lock` tracked; they are needed
for a reproducible Firebase Android build. The artifact is signed with the
Android debug key at present, so it is suitable for device testing only. Configure
a dedicated upload/release keystore via GitHub Actions secrets before Play Store
distribution.
