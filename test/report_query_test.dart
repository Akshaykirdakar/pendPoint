import 'package:flutter_test/flutter_test.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/models/product.dart';
import 'package:pend_point/state/report_query.dart';

Product _product(String id, String brandId, {String? category}) => Product(
      id: id,
      brandId: brandId,
      name: 'Product $id',
      nameMr: 'उत्पादन $id',
      bagWeightKg: 50,
      fullBagPrice: 1000,
      perKgPrice: 22,
      qr: 'PEND-$id',
      category: category,
    );

Bill _bill({
  required String id,
  required int number,
  required DateTime at,
  required List<BillItem> items,
  List<Payment>? payments,
  String customerName = '',
  String? customerId,
  BillStatus status = BillStatus.finalized,
}) {
  final total = items.fold(0.0, (s, i) => s + i.lineTotal);
  return Bill(
    id: id,
    billNumber: number,
    customerId: customerId,
    customerName: customerName,
    items: items,
    subtotal: total,
    discountTotal: 0,
    total: total,
    payments: payments ?? [Payment(PayMode.cash, total)],
    status: status,
    at: at,
  );
}

BillItem _bagItem(String productId, double qty, double rate,
        {double? catalogRate}) =>
    BillItem(
      productId: productId,
      saleType: SaleType.bag,
      qty: qty,
      catalogRate: catalogRate ?? rate,
      rate: rate,
      lineTotal: qty * rate,
    );

BillItem _kgItem(String productId, double qty, double rate) => BillItem(
      productId: productId,
      saleType: SaleType.kg,
      qty: qty,
      catalogRate: rate,
      rate: rate,
      lineTotal: qty * rate,
    );

void main() {
  final day1 = DateTime(2026, 9, 1, 10, 0);
  final day5 = DateTime(2026, 9, 5, 18, 30);
  final day13 = DateTime(2026, 9, 13, 23, 59);
  final products = [
    _product('p1', 'brandA', category: 'Feed'),
    _product('p2', 'brandB', category: 'Supplement'),
  ];

  test('Today preset includes only bills timestamped today', () {
    final now = DateTime(2026, 9, 13, 15, 0);
    final bills = [
      _bill(id: 'b1', number: 1, at: DateTime(2026, 9, 13, 8, 0), items: [_bagItem('p1', 1, 1000)]),
      _bill(id: 'b2', number: 2, at: DateTime(2026, 9, 12, 23, 59), items: [_bagItem('p1', 1, 1000)]),
    ];
    final filter = ReportFilter.preset(DateRangePresetKind.today, now: now);
    final r = buildReport(bills: bills, products: products, filter: filter);
    expect(r.billCount, 1);
    expect(r.revenue, 1000);
  });

  test('Custom date range is inclusive of both the start and end date', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day1, items: [_bagItem('p1', 1, 1000)]),
      _bill(id: 'b2', number: 2, at: day13, items: [_bagItem('p1', 1, 1000)]), // 23:59 on last day
      _bill(id: 'b3', number: 3, at: DateTime(2026, 9, 14, 0, 1), items: [_bagItem('p1', 1, 1000)]),
    ];
    final filter = ReportFilter.range(DateTime(2026, 9, 1), DateTime(2026, 9, 13));
    final r = buildReport(bills: bills, products: products, filter: filter);
    expect(r.billCount, 2); // b1 and b2 included, b3 (next day) excluded
  });

  test('Brand filter only counts matching products', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 1, 1000), _bagItem('p2', 2, 500)]),
    ];
    final filter = ReportFilter.range(day1, day13, brandId: 'brandA');
    final r = buildReport(bills: bills, products: products, filter: filter);
    expect(r.revenue, 1000); // only p1 (brandA) counted, not p2's 1000
    expect(r.billCount, 1);
    expect(r.products.length, 1);
    expect(r.products.first.productId, 'p1');
  });

  test('Product filter only counts the matching product (not by category)', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 1, 1000), _bagItem('p2', 2, 500)]),
    ];
    final filter = ReportFilter.range(day1, day13, productId: 'p2');
    final r = buildReport(bills: bills, products: products, filter: filter);
    expect(r.revenue, 1000); // p2: 2 * 500
    expect(r.products.first.productId, 'p2');
  });

  test('Date + brand combined filter', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day1, items: [_bagItem('p1', 1, 1000)]),
      _bill(id: 'b2', number: 2, at: day13, items: [_bagItem('p2', 1, 1000)]),
      _bill(id: 'b3', number: 3, at: DateTime(2026, 9, 20), items: [_bagItem('p1', 1, 1000)]),
    ];
    final filter = ReportFilter.range(day1, day13, brandId: 'brandA');
    final r = buildReport(bills: bills, products: products, filter: filter);
    expect(r.billCount, 1); // only b1: in range AND brandA
    expect(r.revenue, 1000);
  });

  test('Date + product + brand combined filter', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [
        _bagItem('p1', 1, 1000), // brandA
        _bagItem('p2', 1, 500), // brandB
      ]),
    ];
    final matching = ReportFilter.range(day1, day13, brandId: 'brandA', productId: 'p1');
    final r1 = buildReport(bills: bills, products: products, filter: matching);
    expect(r1.billCount, 1);
    expect(r1.revenue, 1000);

    // p2 doesn't belong to brandA, so a brandA + p2 filter matches nothing.
    final nonMatching = ReportFilter.range(day1, day13, brandId: 'brandA', productId: 'p2');
    final r2 = buildReport(bills: bills, products: products, filter: nonMatching);
    expect(r2.billCount, 0);
    expect(r2.revenue, 0);
  });

  test('Sale type filter narrows to only bag or only loose lines', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [
        _bagItem('p1', 2, 1000), // 2000, bag
        _kgItem('p1', 10, 22), // 220, loose
      ]),
    ];
    final bagsOnly = buildReport(
        bills: bills,
        products: products,
        filter: ReportFilter.range(day1, day13, saleType: SaleTypeFilter.bags));
    expect(bagsOnly.revenue, 2000);
    expect(bagsOnly.bags, 2);
    expect(bagsOnly.looseKg, 0);
    expect(bagsOnly.bagsRevenue, 2000);
    expect(bagsOnly.looseRevenue, 0);

    final looseOnly = buildReport(
        bills: bills,
        products: products,
        filter: ReportFilter.range(day1, day13, saleType: SaleTypeFilter.loose));
    expect(looseOnly.revenue, 220);
    expect(looseOnly.looseKg, 10);
    expect(looseOnly.bags, 0);

    final all = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(all.revenue, 2220);
  });

  test('buildTransactions returns matching bills newest first, narrowed by payMode', () {
    final older = _bill(
      id: 'b1',
      number: 1,
      at: day1,
      items: [_bagItem('p1', 1, 1000)],
      payments: [Payment(PayMode.cash, 1000)],
    );
    final newer = _bill(
      id: 'b2',
      number: 2,
      at: day13,
      items: [_bagItem('p1', 1, 1000)],
      payments: [Payment(PayMode.upi, 1000)],
    );
    final bills = [older, newer];
    final all = buildTransactions(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(all.length, 2);
    expect(all.first.bill.id, 'b2'); // newest first

    final cashOnly = buildTransactions(
        bills: bills,
        products: products,
        filter: ReportFilter.range(day1, day13),
        payMode: PayMode.cash);
    expect(cashOnly.length, 1);
    expect(cashOnly.first.bill.id, 'b1');
  });

  test('Bags calculation rounds to whole bags and sums across bills', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 2, 1000)]),
      _bill(id: 'b2', number: 2, at: day5, items: [_bagItem('p1', 3, 1000)]),
    ];
    final r = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(r.bags, 5);
  });

  test('Loose kg calculation sums fractional weights', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_kgItem('p1', 12.5, 22)]),
      _bill(id: 'b2', number: 2, at: day5, items: [_kgItem('p1', 7.5, 22)]),
    ];
    final r = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(r.looseKg, 20.0);
  });

  test('Payment totals split correctly, including a prorated partial-match bill', () {
    final bills = [
      _bill(
        id: 'b1',
        number: 1,
        at: day5,
        items: [_bagItem('p1', 1, 1000), _bagItem('p2', 1, 1000)], // total 2000
        payments: [Payment(PayMode.cash, 1200), Payment(PayMode.upi, 800)],
      ),
    ];
    // Filtering to only p1 (half the bill's value) should prorate payments by half.
    final r = buildReport(
        bills: bills,
        products: products,
        filter: ReportFilter.range(day1, day13, brandId: 'brandA'));
    expect(r.paymentTotals[PayMode.cash], 600);
    expect(r.paymentTotals[PayMode.upi], 400);
  });

  test('Product ranking sorts by revenue descending', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 1, 500)]),
      _bill(id: 'b2', number: 2, at: day5, items: [_bagItem('p2', 5, 500)]),
    ];
    final r = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(r.products.first.productId, 'p2');
    expect(r.products.first.revenue, 2500);
    expect(r.products.last.productId, 'p1');
  });

  test('Product history returns only that product\'s lines, using bill-item amount', () {
    final bills = [
      _bill(id: 'b1', number: 101, at: day5, customerName: 'Ramesh Patil', items: [
        _bagItem('p1', 2, 1000), // this product's actual attributable amount
        _bagItem('p2', 1, 500), // a different product on the same (multi-product) bill
      ]),
    ];
    final h = buildProductHistory(
        bills: bills, productId: 'p1', filter: ReportFilter.range(day1, day13));
    expect(h.rows.length, 1);
    expect(h.rows.first.amount, 2000); // not the full bill total of 2500
    expect(h.rows.first.bill.customerName, 'Ramesh Patil');
    expect(h.totalRevenue, 2000);
    expect(h.totalBags, 2);
    expect(h.totalBills, 1);
  });

  test('Multi-product bill: each product\'s history is independent', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 1, 1000), _kgItem('p2', 10, 22)]),
    ];
    final h1 = buildProductHistory(
        bills: bills, productId: 'p1', filter: ReportFilter.range(day1, day13));
    final h2 = buildProductHistory(
        bills: bills, productId: 'p2', filter: ReportFilter.range(day1, day13));
    expect(h1.totalRevenue, 1000);
    expect(h2.totalRevenue, 220);
    expect(h2.totalLooseKg, 10);
  });

  test('Voided/excluded bills passed in are simply not counted by the caller', () {
    // buildReport doesn't itself filter by status — the caller (AppState.finalBills)
    // is expected to exclude voided bills before calling it. Verify a bill list
    // that already excludes a void behaves as expected.
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('p1', 1, 1000)]),
    ];
    final r = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(r.billCount, 1);
  });

  test('Empty result when no bills match the filter', () {
    final bills = [
      _bill(id: 'b1', number: 1, at: DateTime(2026, 1, 1), items: [_bagItem('p1', 1, 1000)]),
    ];
    final r = buildReport(
        bills: bills, products: products, filter: ReportFilter.range(day1, day13));
    expect(r.isEmpty, isTrue);
    expect(r.revenue, 0);
    expect(r.products, isEmpty);
  });

  test('Empty product history when nothing matches', () {
    final h = buildProductHistory(
        bills: const [], productId: 'p1', filter: ReportFilter.range(day1, day13));
    expect(h.isEmpty, isTrue);
    expect(h.totalRevenue, 0);
  });

  test('A product missing from the catalogue is excluded once a brand/category filter is active',
      () {
    final bills = [
      _bill(id: 'b1', number: 1, at: day5, items: [_bagItem('deleted-product', 1, 999)]),
    ];
    final r = buildReport(
        bills: bills,
        products: products,
        filter: ReportFilter.range(day1, day13, brandId: 'brandA'));
    expect(r.billCount, 0); // nothing to match brandA against — excluded, not crashed
  });
}
