// Unit tests for the dev-only demo data seeder — verifies it creates the
// expected masters/batches/bills and, critically, that re-running it is a
// safe no-op (idempotent) rather than duplicating records.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/services/dev_seed_service.dart';
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

void main() {
  test('Seeding creates the expected shop data',
      () async {
    final app = await _bootedApp();
    final result = await DevSeedService.seed(app);

    expect(result.alreadySeeded, isFalse);
    expect(app.branches, hasLength(1));
    expect(app.brands.any((b) => b.name == 'Samruddhi'), isTrue);
    expect(app.suppliers.any((s) => s.name == 'ABC Traders'), isTrue);
    expect(app.products.any((p) => p.name == 'Samruddhi 25kg'), isTrue);

    final sam25 = app.products.firstWhere((p) => p.name == 'Samruddhi 25kg');
    final batchesForSam25 = app.batches.where((b) => b.productId == sam25.id).toList();
    // 5 seeded batches for Samruddhi 25kg (001-005), spanning normal/near/expired/zero-stock.
    expect(batchesForSam25.length, 5);
    expect(batchesForSam25.map((b) => b.batchNo),
        containsAll(['SAM-25-001', 'SAM-25-002', 'SAM-25-003', 'SAM-25-004', 'SAM-25-005']));

    // The zero-stock expired batch must not produce an active expiry alert.
    final alerts = BatchAlertService.expiryAlerts(app);
    expect(alerts.where((a) => a.batch.batchNo == 'SAM-25-005'), isEmpty);
    // But the already-expired, still-in-stock batch (004) must show up.
    expect(alerts.any((a) => a.batch.batchNo == 'SAM-25-004' && a.isExpired), isTrue);

    expect(result.created['bills'], greaterThan(0));
  });

  test('Re-seeding is idempotent — no duplicate branches/products/batches', () async {
    final app = await _bootedApp();
    await DevSeedService.seed(app);
    final branchesBefore = app.branches.length;
    final productsBefore = app.products.length;
    final batchesBefore = app.batches.length;

    final second = await DevSeedService.seed(app);

    expect(second.alreadySeeded, isTrue);
    expect(app.branches.length, branchesBefore);
    expect(app.products.length, productsBefore);
    expect(app.batches.length, batchesBefore);
  });
}
