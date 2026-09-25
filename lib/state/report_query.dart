/// Reports filtering & aggregation — the single source of truth used by the
/// Reports screen (summary / payment mix / top products), Product History,
/// and both exports (PDF/Excel). Every one of those reads from [buildReport]
/// or [buildProductHistory] below rather than re-filtering bills itself, so
/// they can never drift apart (see reviewed spec §20).
library;

import '../models/bill.dart';
import '../models/enums.dart';
import '../models/product.dart';

/// Which date-range preset produced [ReportFilter.start]/[end] — kept only so
/// the UI can highlight the active chip; all filtering uses start/end.
enum DateRangePresetKind {
  today,
  yesterday,
  last7,
  last30,
  last90,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  custom,
}

/// Which quantity/form of sale to include — a separate axis from
/// brand/product (a bag sale and a loose sale of the very same product are
/// still distinguished here).
enum SaleTypeFilter { all, bags, loose }

/// A day-inclusive, timezone-safe date range plus optional brand/product and
/// sale-type filters. [start] is always midnight of the first day; [end] is
/// the last instant (23:59:59.999) of the last day, so a bill timestamped any
/// time on the end date is included — see reviewed spec §2.
class ReportFilter {
  final DateTime start;
  final DateTime end;
  final DateRangePresetKind preset;
  final String? brandId; // null = all brands
  final String? productId; // null = all products
  final SaleTypeFilter saleType; // default: all (bags + loose)
  final String? branchId; // null = all branches

  const ReportFilter({
    required this.start,
    required this.end,
    required this.preset,
    this.brandId,
    this.productId,
    this.saleType = SaleTypeFilter.all,
    this.branchId,
  });

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  factory ReportFilter.preset(DateRangePresetKind kind,
      {String? brandId,
      String? productId,
      SaleTypeFilter saleType = SaleTypeFilter.all,
      String? branchId,
      DateTime? now}) {
    final today = _midnight(now ?? DateTime.now());
    late DateTime start, end;
    switch (kind) {
      case DateRangePresetKind.today:
        start = today;
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.yesterday:
        final y = today.subtract(const Duration(days: 1));
        start = y;
        end = _endOfDay(y);
        break;
      case DateRangePresetKind.last7:
        start = today.subtract(const Duration(days: 6));
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.last30:
        start = today.subtract(const Duration(days: 29));
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.last90:
        start = today.subtract(const Duration(days: 89));
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.thisWeek:
        // Week starts Monday.
        start = today.subtract(Duration(days: today.weekday - 1));
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.lastWeek:
        final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
        start = thisWeekStart.subtract(const Duration(days: 7));
        end = _endOfDay(thisWeekStart.subtract(const Duration(days: 1)));
        break;
      case DateRangePresetKind.thisMonth:
        start = DateTime(today.year, today.month, 1);
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.lastMonth:
        final firstOfThis = DateTime(today.year, today.month, 1);
        final lastOfPrev = firstOfThis.subtract(const Duration(days: 1));
        start = DateTime(lastOfPrev.year, lastOfPrev.month, 1);
        end = _endOfDay(lastOfPrev);
        break;
      case DateRangePresetKind.thisYear:
        start = DateTime(today.year, 1, 1);
        end = _endOfDay(today);
        break;
      case DateRangePresetKind.lastYear:
        start = DateTime(today.year - 1, 1, 1);
        end = _endOfDay(DateTime(today.year - 1, 12, 31));
        break;
      case DateRangePresetKind.custom:
        start = today;
        end = _endOfDay(today);
        break;
    }
    return ReportFilter(
        start: start,
        end: end,
        preset: kind,
        brandId: brandId,
        productId: productId,
        saleType: saleType,
        branchId: branchId);
  }

  factory ReportFilter.range(DateTime start, DateTime end,
          {String? brandId,
          String? productId,
          SaleTypeFilter saleType = SaleTypeFilter.all,
          String? branchId}) =>
      ReportFilter(
        start: _midnight(start),
        end: _endOfDay(end),
        preset: DateRangePresetKind.custom,
        brandId: brandId,
        productId: productId,
        saleType: saleType,
        branchId: branchId,
      );

  ReportFilter copyWith(
          {String? brandId,
          String? productId,
          SaleTypeFilter? saleType,
          String? branchId,
          bool clearBrand = false,
          bool clearProduct = false,
          bool clearBranch = false}) =>
      ReportFilter(
        start: start,
        end: end,
        preset: preset,
        brandId: clearBrand ? null : (brandId ?? this.brandId),
        productId: clearProduct ? null : (productId ?? this.productId),
        saleType: saleType ?? this.saleType,
        branchId: clearBranch ? null : (branchId ?? this.branchId),
      );

  bool includes(DateTime at) => !at.isBefore(start) && !at.isAfter(end);
}

/// Aggregated numbers for one product within the filtered range.
class ProductStat {
  final String productId;
  int bags = 0;
  double looseKg = 0;
  double revenue = 0;
  double qty = 0; // bags + kg combined, for a simple "total quantity" figure

  ProductStat(this.productId);
}

/// The complete, filtered report — every number here corresponds to the
/// active [ReportFilter] (reviewed spec §5): nothing here is a global total.
class ReportResult {
  final ReportFilter filter;
  final int billCount;
  final double revenue;
  final int bags;
  final double looseKg;
  final double bagsRevenue;
  final double looseRevenue;
  final Map<PayMode, double> paymentTotals;
  final Map<PayMode, int> paymentCounts; // bills using each payment method
  final List<ProductStat> products; // sorted by revenue, descending

  const ReportResult({
    required this.filter,
    required this.billCount,
    required this.revenue,
    required this.bags,
    required this.looseKg,
    required this.bagsRevenue,
    required this.looseRevenue,
    required this.paymentTotals,
    required this.paymentCounts,
    required this.products,
  });

  bool get isEmpty => billCount == 0;
}

/// Does [item]'s product pass the brand/product filter? A product that has
/// gone missing (deleted) is excluded once a brand/product filter is active
/// (nothing to match against) but still counts under "All" — see §22.
///
/// Exposed (not just used internally by [buildReport]) so every other place
/// that needs "does this line match the active filter" — e.g. the
/// discount/override audit on the Reports screen — asks this one function
/// instead of re-implementing the match (reviewed spec §20).
bool productMatchesFilter(
    BillItem item, Map<String, Product> productsById, ReportFilter f) {
  if (f.brandId == null && f.productId == null) return true;
  final p = productsById[item.productId];
  if (p == null) return false;
  if (f.brandId != null && p.brandId != f.brandId) return false;
  if (f.productId != null && item.productId != f.productId) return false;
  return true;
}

/// Does [item] pass the active [ReportFilter.saleType] (All / Bags / Loose)?
bool saleTypeMatchesFilter(BillItem item, ReportFilter f) {
  switch (f.saleType) {
    case SaleTypeFilter.all:
      return true;
    case SaleTypeFilter.bags:
      return item.saleType == SaleType.bag;
    case SaleTypeFilter.loose:
      return item.saleType == SaleType.kg;
  }
}

/// Does [item] pass every axis of [f] — brand, product and sale type? The one
/// check every report/drill-down screen uses, so they can never disagree.
bool itemMatchesFilter(
        BillItem item, Map<String, Product> productsById, ReportFilter f) =>
    productMatchesFilter(item, productsById, f) &&
    saleTypeMatchesFilter(item, f);

/// Does [bill] pass the active Branch filter? A bill created before branches
/// existed (`branchId == null`) is excluded once a branch filter is active —
/// nothing to match against — but still counts under "All Branches".
bool billMatchesFilter(Bill bill, ReportFilter f) =>
    f.branchId == null || bill.branchId == f.branchId;

/// Builds the filtered report from already-loaded bills (see reviewed spec
/// §16 — no Firestore query here; [bills] is `AppState.finalBills`, and
/// voided bills are excluded by the caller before this runs).
ReportResult buildReport({
  required List<Bill> bills,
  required List<Product> products,
  required ReportFilter filter,
}) {
  final productsById = {for (final p in products) p.id: p};
  var billCount = 0;
  var revenue = 0.0;
  var bags = 0;
  var looseKg = 0.0;
  var bagsRevenue = 0.0;
  var looseRevenue = 0.0;
  final pay = <PayMode, double>{
    PayMode.cash: 0,
    PayMode.upi: 0,
    PayMode.credit: 0,
  };
  final payCounts = <PayMode, int>{
    PayMode.cash: 0,
    PayMode.upi: 0,
    PayMode.credit: 0,
  };
  final byProduct = <String, ProductStat>{};

  for (final b in bills) {
    if (!filter.includes(b.at) || !billMatchesFilter(b, filter)) continue;
    final matchingItems = b.items
        .where((it) => itemMatchesFilter(it, productsById, filter))
        .toList();
    if (matchingItems.isEmpty) continue;
    billCount++;

    var billMatchedTotal = 0.0;
    for (final it in matchingItems) {
      revenue += it.lineTotal;
      billMatchedTotal += it.lineTotal;
      if (it.saleType == SaleType.bag) {
        bags += it.qty.round();
        bagsRevenue += it.lineTotal;
      } else {
        looseKg += it.qty;
        looseRevenue += it.lineTotal;
      }
      final stat = byProduct.putIfAbsent(it.productId, () => ProductStat(it.productId));
      stat.revenue += it.lineTotal;
      stat.qty += it.qty;
      if (it.saleType == SaleType.bag) {
        stat.bags += it.qty.round();
      } else {
        stat.looseKg += it.qty;
      }
    }

    // Payments aren't itemized per product, so when a brand/product/sale-type
    // filter narrows the bill to only some of its lines, attribute payments in the
    // same proportion as the matched revenue. With no filter active,
    // billMatchedTotal == bill.total and this is exactly the full payment.
    final ratio = b.total == 0 ? 0.0 : (billMatchedTotal / b.total).clamp(0.0, 1.0);
    for (final p in b.payments) {
      pay[p.mode] = (pay[p.mode] ?? 0) + p.amount * ratio;
      payCounts[p.mode] = (payCounts[p.mode] ?? 0) + 1;
    }
  }

  final productList = byProduct.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  return ReportResult(
    filter: filter,
    billCount: billCount,
    revenue: revenue,
    bags: bags,
    looseKg: looseKg,
    bagsRevenue: bagsRevenue,
    looseRevenue: looseRevenue,
    paymentTotals: pay,
    paymentCounts: payCounts,
    products: productList,
  );
}

/// One sale of the selected product, traceable back to its bill and the
/// exact bill item — never fabricated (reviewed spec §9).
class ProductSaleRow {
  final Bill bill;
  final BillItem item;
  const ProductSaleRow(this.bill, this.item);

  double get amount => item.lineTotal;
}

class ProductHistoryResult {
  final String productId;
  final ReportFilter filter;
  final int totalBills;
  final int totalBags;
  final double totalLooseKg;
  final double totalRevenue;
  final List<ProductSaleRow> rows; // newest first

  const ProductHistoryResult({
    required this.productId,
    required this.filter,
    required this.totalBills,
    required this.totalBags,
    required this.totalLooseKg,
    required this.totalRevenue,
    required this.rows,
  });

  bool get isEmpty => rows.isEmpty;
}

/// All sales of [productId] within [filter]'s date range (brand/product on
/// the filter are ignored here — a single product already has a fixed brand,
/// so they're implied — but [ReportFilter.saleType] still applies, so
/// drilling into a product respects a Bags/Loose choice made upstream). See
/// reviewed spec §8–§10.
ProductHistoryResult buildProductHistory({
  required List<Bill> bills,
  required String productId,
  required ReportFilter filter,
}) {
  final rows = <ProductSaleRow>[];
  var bags = 0;
  var looseKg = 0.0;
  var revenue = 0.0;

  final inRange = bills
      .where((b) => filter.includes(b.at) && billMatchesFilter(b, filter))
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  for (final b in inRange) {
    for (final it in b.items) {
      if (it.productId != productId) continue;
      if (!saleTypeMatchesFilter(it, filter)) continue;
      rows.add(ProductSaleRow(b, it));
      revenue += it.lineTotal;
      if (it.saleType == SaleType.bag) {
        bags += it.qty.round();
      } else {
        looseKg += it.qty;
      }
    }
  }

  return ProductHistoryResult(
    productId: productId,
    filter: filter,
    totalBills: rows.map((r) => r.bill.id).toSet().length,
    totalBags: bags,
    totalLooseKg: looseKg,
    totalRevenue: revenue,
    rows: rows,
  );
}

/// One bill within a drill-down transaction list — the whole bill, plus which
/// of its lines actually matched the active filter (a multi-product bill may
/// only partially match a brand/product/sale-type filter). Never fabricated:
/// every field traces back to the real [Bill]/[BillItem] data.
class TransactionRow {
  final Bill bill;
  final List<BillItem> matchedItems;
  final double matchedRevenue;
  final int matchedBags;
  final double matchedLooseKg;

  const TransactionRow({
    required this.bill,
    required this.matchedItems,
    required this.matchedRevenue,
    required this.matchedBags,
    required this.matchedLooseKg,
  });
}

/// The one transaction/bill list every drill-down screen (Revenue Analytics,
/// Cash/UPI/Credit transactions, Bags/Loose transactions) reads from — so
/// none of them can compute a different set of bills than [buildReport] did
/// for the very same [filter] (reviewed spec §20). Bill-granularity, newest
/// first. When [payMode] is given, only bills carrying at least one payment
/// of that mode are included (payments aren't itemized per line, so this
/// mirrors the same bill-level attribution [buildReport] already uses for
/// payment totals).
List<TransactionRow> buildTransactions({
  required List<Bill> bills,
  required List<Product> products,
  required ReportFilter filter,
  PayMode? payMode,
}) {
  final productsById = {for (final p in products) p.id: p};
  final rows = <TransactionRow>[];

  for (final b in bills) {
    if (!filter.includes(b.at) || !billMatchesFilter(b, filter)) continue;
    if (payMode != null && !b.payments.any((p) => p.mode == payMode)) continue;
    final matchedItems =
        b.items.where((it) => itemMatchesFilter(it, productsById, filter)).toList();
    if (matchedItems.isEmpty) continue;

    var revenue = 0.0;
    var bags = 0;
    var looseKg = 0.0;
    for (final it in matchedItems) {
      revenue += it.lineTotal;
      if (it.saleType == SaleType.bag) {
        bags += it.qty.round();
      } else {
        looseKg += it.qty;
      }
    }
    rows.add(TransactionRow(
      bill: b,
      matchedItems: matchedItems,
      matchedRevenue: revenue,
      matchedBags: bags,
      matchedLooseKg: looseKg,
    ));
  }

  rows.sort((a, b) => b.bill.at.compareTo(a.bill.at));
  return rows;
}

/// Aggregated numbers for one brand within the filtered range — grouped from
/// the already-computed per-product stats, so it never re-scans the bills.
class BrandStat {
  final String brandId;
  double revenue = 0;
  int bags = 0;
  double looseKg = 0;

  BrandStat(this.brandId);
}

/// Groups [productStats] (as produced by [ReportResult.products]) by brand.
/// Sorted by revenue, descending. A product missing from the catalogue (and
/// so with no known brand) is skipped — it already can't have passed a
/// brand/product filter to get into [productStats] in the first place.
List<BrandStat> brandStatsFrom(
    List<ProductStat> productStats, Map<String, Product> productsById) {
  final byBrand = <String, BrandStat>{};
  for (final stat in productStats) {
    final p = productsById[stat.productId];
    if (p == null) continue;
    final b = byBrand.putIfAbsent(p.brandId, () => BrandStat(p.brandId));
    b.revenue += stat.revenue;
    b.bags += stat.bags;
    b.looseKg += stat.looseKg;
  }
  final list = byBrand.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));
  return list;
}

/// One day's totals within a revenue trend / daily breakdown.
class DailyPoint {
  final DateTime day;
  final double revenue;
  final int billCount;
  const DailyPoint(this.day, this.revenue, this.billCount);
}

/// Buckets [rows] (from [buildTransactions]) by calendar day, ascending —
/// used for the revenue trend chart and the daily breakdown list.
List<DailyPoint> dailySeries(List<TransactionRow> rows) {
  final byDay = <DateTime, ({double revenue, int bills})>{};
  for (final r in rows) {
    final d = DateTime(r.bill.at.year, r.bill.at.month, r.bill.at.day);
    final prev = byDay[d] ?? (revenue: 0.0, bills: 0);
    byDay[d] = (revenue: prev.revenue + r.matchedRevenue, bills: prev.bills + 1);
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) DailyPoint(d, byDay[d]!.revenue, byDay[d]!.bills)];
}
