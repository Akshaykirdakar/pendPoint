// Shared helpers for the purchase / sales / party tests.
import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/data/stock_commit.dart';
import 'package:pend_point/state/app_state.dart';

/// Records every commit that reaches the repository layer.
class RecordingRepository extends InMemoryRepository {
  final List<StockCommit> commits = [];
  @override
  Future<void> commitStock(StockCommit commit) async => commits.add(commit);
}

/// Rejects every commit, as Firestore does when another device sold the
/// stock first.
class RejectingRepository extends InMemoryRepository {
  @override
  Future<void> commitStock(StockCommit commit) async =>
      throw const StockCommitException('conflict: stock changed elsewhere');
}

/// Signed in as the seeded non-admin counter staff member ('s2').
class StaffLoginRepository extends InMemoryRepository {
  @override
  String? get currentUserId => 's2';
}

Future<AppState> bootedApp([InMemoryRepository? repo]) async {
  final app = AppState(repo ?? InMemoryRepository());
  await app.bootstrap();
  while (app.historyLoading) {
    await Future.delayed(Duration.zero);
  }
  return app;
}

/// A brand-new product with no batches, so stock assertions are exact.
Future<String> freshProduct(AppState app,
    {String name = 'Test Feed',
    double sellPrice = 1000,
    bool batchTracking = true,
    bool expiryTracking = true,
    String? brandId}) async {
  final p = await app.saveProduct(
      brandId: brandId ?? app.brands.first.id,
      name: name,
      nameMr: '$name मराठी',
      bagWeightKg: 50,
      fullBagPrice: sellPrice,
      perKgPrice: sellPrice / 40,
      costPrice: sellPrice * 0.8);
  final idx = app.products.indexWhere((x) => x.id == p.id);
  app.products[idx] = app.products[idx].copyWith(
      branchIds: [app.activeBranchId!],
      batchTrackingEnabled: batchTracking,
      expiryTrackingEnabled: expiryTracking);
  return p.id;
}

DateTime inDays(int n) => DateTime.now().add(Duration(days: n));
