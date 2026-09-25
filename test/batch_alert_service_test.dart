// Unit tests for the shared expiry/stock alert calculation (spec §27) — the
// one place every screen (dashboard, Alerts, POS, Reports) reads from, so a
// batch never shows a different status in two places.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/batch_alert_service.dart';

Future<AppState> _bootedApp() async {
  final app = AppState(InMemoryRepository());
  await app.bootstrap();
  while (app.historyLoading) {
    await Future.delayed(Duration.zero);
  }
  return app;
}

Future<String> _freshProduct(AppState app, String branchId) async {
  final p = await app.saveProduct(
      brandId: app.brands.first.id,
      name: 'Test Product',
      nameMr: 'चाचणी उत्पादन',
      bagWeightKg: 50,
      fullBagPrice: 1000,
      perKgPrice: 20);
  final idx = app.products.indexWhere((x) => x.id == p.id);
  app.products[idx] = app.products[idx].copyWith(branchIds: [branchId]);
  return p.id;
}

void main() {
  test('Zero-stock batch is excluded from expiry alerts even with a near expiry date',
      () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = await _freshProduct(app, branch);

    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'ZERO',
        expiry: DateTime.now().add(const Duration(days: 1)),
        bags: 5,
        cost: 100);
    app.setActiveBranch(branch);
    app.addToCart(productId, SaleType.bag, 5); // sell out the whole batch
    final res = await app.finalizeSale();
    expect(res.ok, isTrue);

    final alerts = BatchAlertService.expiryAlerts(app, branchId: branch);
    expect(alerts.where((a) => a.batch.batchNo == 'ZERO'), isEmpty);
  });

  test('Severity tiers follow the configured thresholds', () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = await _freshProduct(app, branch);

    // Default thresholds: critical <=7d, near/soon <=30d.
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'CRIT',
        expiry: DateTime.now().add(const Duration(days: 3)),
        bags: 1,
        cost: 100);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'NEAR',
        expiry: DateTime.now().add(const Duration(days: 20)),
        bags: 1,
        cost: 100);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'FAR',
        expiry: DateTime.now().add(const Duration(days: 200)),
        bags: 1,
        cost: 100);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'GONE',
        expiry: DateTime.now().subtract(const Duration(days: 2)),
        bags: 1,
        cost: 100);

    final critical = BatchAlertService.criticalBatches(app, branchId: branch);
    final near = BatchAlertService.nearExpiryBatches(app, branchId: branch);
    final expired = BatchAlertService.expiredBatches(app, branchId: branch);

    expect(critical.map((a) => a.batch.batchNo), contains('CRIT'));
    expect(near.map((a) => a.batch.batchNo), contains('NEAR'));
    expect(expired.map((a) => a.batch.batchNo), contains('GONE'));
    // FAR (200 days out) is beyond every threshold — not in any alert list.
    expect(critical.map((a) => a.batch.batchNo), isNot(contains('FAR')));
    expect(near.map((a) => a.batch.batchNo), isNot(contains('FAR')));
  });

  test('Turning expiry alerts off in Settings suppresses every expiry alert', () async {
    final app = await _bootedApp();
    final branch = app.branches.first.id;
    final supplier = app.suppliers.first.id;
    final productId = await _freshProduct(app, branch);
    await app.stockIn(
        branchId: branch,
        productId: productId,
        supplierId: supplier,
        batchNo: 'OFF-TEST',
        expiry: DateTime.now().subtract(const Duration(days: 1)),
        bags: 1,
        cost: 100);
    expect(BatchAlertService.expiryAlerts(app, branchId: branch), isNotEmpty);

    await app.updateSettings((s) => s.expiryAlertsOn = false);
    expect(BatchAlertService.expiryAlerts(app, branchId: branch), isEmpty);
  });
}
