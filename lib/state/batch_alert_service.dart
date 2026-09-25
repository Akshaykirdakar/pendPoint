/// The one shared expiry/stock-status calculation (spec §27Q: "the same
/// batch must show the same expiry status everywhere — dashboard, inventory,
/// batch management, product details, reports, POS, notifications"). Every
/// screen that needs a batch's severity or a shop-wide alert count reads
/// from here rather than recomputing its own thresholds.
library;

import '../models/app_settings.dart';
import '../models/batch.dart';
import '../models/enums.dart';
import '../models/product.dart';
import 'app_state.dart';

enum AlertSeverity { info, warning, critical }

/// One batch's live expiry alert — only ever produced for a batch that
/// actually has stock (spec §27B: "do not generate useless expiry alerts for
/// batches with zero stock").
class ExpiryAlert {
  final Batch batch;
  final int daysRemaining; // negative once expired
  final AlertSeverity severity;
  const ExpiryAlert(this.batch, this.daysRemaining, this.severity);

  bool get isExpired => daysRemaining < 0;
}

class BatchAlertService {
  const BatchAlertService._();

  /// Every batch with expiry tracking, stock on hand, and a calculable
  /// severity — sorted most-urgent first (expired, then soonest-expiring).
  /// Optionally scoped to one branch.
  static List<ExpiryAlert> expiryAlerts(AppState app, {String? branchId}) {
    final settings = app.settings;
    if (!settings.expiryAlertsOn) return const [];
    final out = <ExpiryAlert>[];
    for (final b in app.batches) {
      if (branchId != null && b.branchId != branchId) continue;
      if (b.expiry == null) continue;
      final product = app.productOf(b.productId);
      final qty = b.availableKg(product?.bagWeightKg ?? 1);
      if (qty <= 0) continue; // spec §27B
      final days = b.daysRemaining()!;
      AlertSeverity? severity;
      if (days < 0) {
        severity = AlertSeverity.critical; // expired
      } else if (days <= settings.criticalExpiryDays) {
        severity = AlertSeverity.critical;
      } else if (days <= settings.expirySoonDays) {
        severity = AlertSeverity.warning;
      } else if (days <= settings.nearExpiryDays) {
        severity = AlertSeverity.warning;
      }
      if (severity != null) out.add(ExpiryAlert(b, days, severity));
    }
    out.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    return out;
  }

  static List<ExpiryAlert> expiredBatches(AppState app, {String? branchId}) =>
      expiryAlerts(app, branchId: branchId).where((a) => a.isExpired).toList();

  static List<ExpiryAlert> criticalBatches(AppState app, {String? branchId}) =>
      expiryAlerts(app, branchId: branchId)
          .where((a) => !a.isExpired && a.daysRemaining <= app.settings.criticalExpiryDays)
          .toList();

  static List<ExpiryAlert> nearExpiryBatches(AppState app, {String? branchId}) =>
      expiryAlerts(app, branchId: branchId)
          .where((a) =>
              !a.isExpired &&
              a.daysRemaining > app.settings.criticalExpiryDays &&
              a.daysRemaining <= app.settings.nearExpiryDays)
          .toList();

  /// Low-stock products (spec §27E) — product-level, per [AppState.lowStock],
  /// gated on the Low Stock Alerts toggle.
  static List<Product> lowStockProducts(AppState app) =>
      app.settings.lowStockAlertsOn
          ? app.lowStock.where((p) => app.levelOf(p.id) == StockLevel.low).toList()
          : const [];

  /// Out-of-stock products (spec §27F) — gated on the Out of Stock Alerts
  /// toggle.
  static List<Product> outOfStockProducts(AppState app) => app.settings.outOfStockAlertsOn
      ? app.products.where((p) => app.levelOf(p.id) == StockLevel.out).toList()
      : const [];
}
