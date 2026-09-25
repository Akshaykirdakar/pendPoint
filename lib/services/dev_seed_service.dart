// Development-only demo data seeder — NOT wired to run automatically.
//
// Deliberately does NOT use the Admin SDK or invent a parallel schema: every
// write here goes through the exact same [AppState] methods (and therefore
// the exact same Firestore collections/fields and the exact same signed-in
// user + security rules) that the real app uses for Stock In / POS / Master
// screens. That is the whole point — if a write or read fails here, it fails
// for the same reason it would fail in the app, which is what makes this
// seeding useful for diagnosing a "some collections load, others
// permission-denied" report (see the Settings → Prototype → "Seed Demo Data"
// button, gated to debug builds).
//
// Idempotent: re-running it after data already exists is a safe no-op (it
// checks by name for each master entity before creating another one) rather
// than piling up duplicates.
import '../models/enums.dart';
import '../state/app_state.dart';

class DevSeedResult {
  final bool alreadySeeded;
  final Map<String, int> created;
  final List<String> notes;
  const DevSeedResult(
      {required this.alreadySeeded, required this.created, required this.notes});
}

class DevSeedService {
  const DevSeedService._();

  static Future<DevSeedResult> seed(AppState app) async {
    final created = <String, int>{
      'branches': 0,
      'brands': 0,
      'suppliers': 0,
      'products': 0,
      'customers': 0,
      'batches (via Stock In)': 0,
      'bills': 0,
    };
    final notes = <String>[];

    // ---- idempotency: don't duplicate on a second run ----
    if (app.brands.any((b) => b.name == 'Samruddhi') &&
        app.products.any((p) => p.name == 'Samruddhi 25kg')) {
      return DevSeedResult(
          alreadySeeded: true,
          created: created,
          notes: ['Demo data already present — nothing created. '
              'Delete the "Samruddhi" brand/products in More → Catalogue '
              'first if you want a completely fresh reseed.']);
    }

    // ---- 1. Shop name (there is no separate "business" collection in this
    // app's schema — the shop name lives on the single meta/settings doc) ----
    if (app.settings.shop != 'Demo Shop') {
      await app.updateSettings((s) => s.shop = 'Demo Shop');
    }

    // ---- 2. Staff / user membership ----
    // There is no membership join to create: every signed-in user IS staff
    // (`isStaff()` in firestore.rules is just `isSignedIn()`), and the
    // staff/{uid} doc that grants admin rights can only be created by an
    // existing admin (or via the Firebase Console/Admin SDK) — never by the
    // client itself. We only verify + report the current user here.
    final uid = app.repo.currentUserId;
    final me = uid == null ? null : app.staff.where((s) => s.id == uid).firstOrNull;
    if (uid == null) {
      notes.add('No authenticated user (repo.currentUserId is null) — '
          'this repository is not Firestore-backed, or no one is signed in.');
    } else if (me == null) {
      notes.add('⚠️ No staff/$uid document exists for the signed-in user. '
          'Every subsequent write below requires isAdmin() and will fail '
          'with permission-denied until an existing admin (or the Firebase '
          'Console / Admin SDK) creates staff/$uid with role: "admin".');
    } else {
      notes.add('Signed in as staff/$uid (${me.name}, role=${me.role}, '
          'active=${me.active}).');
    }

    // ---- 3. Branches ----
    if (app.branches.isEmpty) {
      await app.saveBranch(name: 'Pune Main', nameMr: 'पुणे मुख्य', address: 'Pune');
      created['branches'] = created['branches']! + 1;
    }
    final pune = app.activeBranchId ?? app.branches.first.id;
    app.setActiveBranch(pune);

    // ---- 4. Brands ----
    String brandId(String name) => app.brands.firstWhere((b) => b.name == name).id;
    for (final b in const [
      ('Samruddhi', 'समृद्धी'),
      ('Demo Brand', 'डेमो ब्रँड'),
      ('Test Brand', 'टेस्ट ब्रँड'),
    ]) {
      if (!app.brands.any((x) => x.name == b.$1)) {
        await app.saveBrand(name: b.$1, nameMr: b.$2);
        created['brands'] = created['brands']! + 1;
      }
    }
    final samruddhi = brandId('Samruddhi');
    final demoBrand = brandId('Demo Brand');

    // ---- 5. Suppliers ----
    String supplierId(String name) => app.suppliers.firstWhere((s) => s.name == name).id;
    for (final s in const ['ABC Traders', 'XYZ Suppliers', 'Demo Supplier']) {
      if (!app.suppliers.any((x) => x.name == s)) {
        await app.saveSupplier(name: s, mobile: '98765 00000', active: true);
        created['suppliers'] = created['suppliers']! + 1;
      }
    }
    final abcTraders = supplierId('ABC Traders');
    final xyzSuppliers = supplierId('XYZ Suppliers');

    // ---- 6. Products ----
    Future<String> ensureProduct(String name, String nameMr, String brand,
        {required int bagWeightKg, required double bagPrice, required double kgPrice}) async {
      final existing = app.products.where((p) => p.name == name).firstOrNull;
      if (existing != null) return existing.id;
      final p = await app.saveProduct(
          brandId: brand,
          name: name,
          nameMr: nameMr,
          bagWeightKg: bagWeightKg,
          fullBagPrice: bagPrice,
          perKgPrice: kgPrice,
          costPrice: bagPrice * 0.8,
          minPriceFloor: bagPrice * 0.85);
      final idx = app.products.indexWhere((x) => x.id == p.id);
      app.products[idx] = app.products[idx].copyWith(branchIds: [pune]);
      await app.repo.upsertProduct(app.products[idx]);
      created['products'] = created['products']! + 1;
      return p.id;
    }

    final sam25 = await ensureProduct('Samruddhi 25kg', 'समृद्धी २५किलो', samruddhi,
        bagWeightKg: 25, bagPrice: 950, kgPrice: 42);
    final sam50 = await ensureProduct('Samruddhi 50kg', 'समृद्धी ५०किलो', samruddhi,
        bagWeightKg: 50, bagPrice: 1800, kgPrice: 40);
    await ensureProduct('Demo Product A', 'डेमो उत्पादन अ', demoBrand,
        bagWeightKg: 50, bagPrice: 1000, kgPrice: 25);
    await ensureProduct('Demo Product B', 'डेमो उत्पादन ब', demoBrand,
        bagWeightKg: 50, bagPrice: 1100, kgPrice: 27);

    // ---- 7. Customer (needed for a credit sale) ----
    if (!app.customers.any((c) => c.name == 'Demo Customer')) {
      await app.saveCustomer(name: 'Demo Customer', mobile: '90000 00000');
      created['customers'] = created['customers']! + 1;
    }
    final demoCustomer = app.customers.firstWhere((c) => c.name == 'Demo Customer').id;

    // ---- 8/9/10. Batches + purchases (Stock In) — multiple batches of the
    // SAME product, plus one near-expiry, one critical/expired, and one
    // zero-stock-expired batch for alert testing ----
    final now = DateTime.now();
    Future<void> stockIn(String productId, String batchNo, String supplier,
        {required int bags, required DateTime? expiry, required double cost}) async {
      await app.stockIn(
          branchId: pune,
          productId: productId,
          supplierId: supplier,
          batchNo: batchNo,
          expiry: expiry,
          bags: bags,
          cost: cost);
      created['batches (via Stock In)'] = created['batches (via Stock In)']! + 1;
    }

    await stockIn(sam25, 'SAM-25-001', abcTraders,
        bags: 100, expiry: DateTime(2027, 6, 30), cost: 900);
    await stockIn(sam25, 'SAM-25-002', xyzSuppliers,
        bags: 75, expiry: DateTime(2027, 12, 31), cost: 920);
    await stockIn(sam25, 'SAM-25-003', abcTraders,
        bags: 20, expiry: now.add(const Duration(days: 20)), cost: 900); // near expiry
    await stockIn(sam25, 'SAM-25-004', xyzSuppliers,
        bags: 10, expiry: now.subtract(const Duration(days: 5)), cost: 900); // expired, still in stock
    await stockIn(sam50, 'SAM-50-001', abcTraders,
        bags: 50, expiry: now.add(const Duration(days: 300)), cost: 1700);

    // Zero-stock expired batch: must exist (for inventory history) but
    // produce NO active expiry alert, since it has nothing left to sell —
    // spec "do not generate useless expiry alerts for batches with zero
    // stock". A batch that's already expired can never be sold down via the
    // real POS/FEFO path (by design), so this one is created then zeroed out
    // directly — the one deliberate exception to "every write goes through
    // AppState", because there is no write-off/adjustment screen yet to do
    // this the normal way (see the reviewed plan's Phase-3 follow-ups).
    await stockIn(sam25, 'SAM-25-005', abcTraders,
        bags: 5, expiry: now.subtract(const Duration(days: 15)), cost: 900);
    final zeroBatch = app.batches.firstWhere((b) => b.batchNo == 'SAM-25-005');
    zeroBatch.bagsAvailable = 0;
    zeroBatch.bagsSold = 5;
    zeroBatch.updatedAt = DateTime.now();
    await app.repo.upsertBatch(zeroBatch);
    app.recomputeStockFor(sam25);
    notes.add('SAM-25-005 is expired AND zero-stock — should show NO active '
        'expiry alert anywhere (dashboard/Alerts/Reports).');

    // ---- 11/12/13/14/15. Sales — Cash/UPI/Credit, Bags + Loose, allocated
    // by the real FEFO logic (nearest-expiry-first), so which batch(es) a
    // bill actually draws from depends on the expiries seeded above, not a
    // hand-picked batch number. ----
    Future<void> sell(String productId, SaleType type, double qty, PayMode mode,
        {String? customerId}) async {
      app.addToCart(productId, type, qty);
      app.ensurePayments();
      if (customerId != null) app.setCartCustomer(customerId);
      app.setPayment(0, mode: mode, amount: app.cartTotal);
      final res = await app.finalizeSale();
      if (res.ok) {
        created['bills'] = created['bills']! + 1;
      } else {
        notes.add('Seed sale failed for $productId: ${res.error}');
        app.cart.clear();
        app.resetPayments();
      }
    }

    await sell(sam25, SaleType.bag, 2, PayMode.cash);
    await sell(sam25, SaleType.bag, 3, PayMode.upi);
    await sell(sam50, SaleType.bag, 1, PayMode.credit, customerId: demoCustomer);
    await sell(sam25, SaleType.kg, 25, PayMode.upi); // loose sale

    notes.add('All batches and products were assigned to the shop.');

    return DevSeedResult(alreadySeeded: false, created: created, notes: notes);
  }
}
