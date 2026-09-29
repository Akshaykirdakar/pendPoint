// WhatsApp bill message + number handling, the bag-only stock report, and
// product / brand search.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/services/whatsapp_service.dart';
import 'package:pend_point/state/bag_stock.dart';
import 'package:pend_point/state/catalog_search.dart';

import 'test_support.dart';

Bill _bill({int revision = 0, List<Payment>? payments}) => Bill(
      id: 'BILL1234',
      billNumber: 1234,
      customerName: 'रमेश पाटील',
      items: const [
        // One line FEFO split across two batches, plus a loose-kg line.
        BillItem(
            productId: 'p1',
            saleType: SaleType.bag,
            qty: 2,
            catalogRate: 1450,
            rate: 1400,
            lineTotal: 2800,
            batchId: 'b1'),
        BillItem(
            productId: 'p1',
            saleType: SaleType.bag,
            qty: 1,
            catalogRate: 1450,
            rate: 1400,
            lineTotal: 1400,
            batchId: 'b2'),
        BillItem(
            productId: 'p2',
            saleType: SaleType.kg,
            qty: 12.5,
            catalogRate: 30,
            rate: 30,
            lineTotal: 375),
      ],
      subtotal: 4575,
      discountTotal: 150,
      total: 4575,
      payments: payments ?? const [Payment(PayMode.cash, 4575)],
      at: DateTime(2026, 9, 28, 10, 15),
      revision: revision,
    );

String _label(String id) => id == 'p1' ? 'दूध बूस्टर (Godrej)' : 'सरकी पेंड';

void main() {
  group('WhatsApp', () {
    test(
        'bill message has shop, bill no, date, party, products, qty, amounts, total',
        () {
      final m = WhatsAppService.billMessage(
          shopName: 'जय किसान पेंड भांडार',
          bill: _bill(),
          productLabel: _label);
      expect(m, contains('जय किसान पेंड भांडार'));
      expect(m, contains('#1234'));
      expect(m, contains('28 Sep 2026'));
      expect(m, contains('रमेश पाटील'));
      expect(m, contains('दूध बूस्टर (Godrej)'));
      expect(m, contains('सरकी पेंड'));
      // FEFO-split lines merged back: 2 + 1 bags at the same rate.
      expect(m, contains('3 गोणी bags × ₹1,400 = ₹4,200'));
      expect(m, contains('12.5 kg × ₹30 = ₹375'));
      // Subtotal (catalogue) − discount = grand total.
      expect(m, contains('Subtotal: ₹4,725'));
      expect(m, contains('Discount: -₹150'));
      expect(m, contains('Grand total: ₹4,575'));
      expect(m, isNot(contains('Due')));
    });

    test('credit and revision are called out', () {
      final m = WhatsAppService.billMessage(
          shopName: 'Shop',
          bill: _bill(revision: 1, payments: const [
            Payment(PayMode.cash, 1000),
            Payment(PayMode.credit, 3575),
          ]),
          productLabel: _label);
      expect(m, contains('Revised 1'));
      expect(m, contains('Paid: ₹1,000'));
      expect(m, contains('Due: ₹3,575'));
    });

    test('Indian mobile numbers are normalised for wa.me', () {
      expect(WhatsAppService.phoneForWhatsApp('98220 11223'), '919822011223');
      expect(WhatsAppService.phoneForWhatsApp('098220-11223'), '919822011223');
      expect(
          WhatsAppService.phoneForWhatsApp('+91 98220 11223'), '919822011223');
      expect(WhatsAppService.phoneForWhatsApp('12345'), isNull);
      expect(WhatsAppService.phoneForWhatsApp(''), isNull);
    });

    test('wa.me link carries the number and the encoded message', () {
      final uri = WhatsAppService.whatsAppUri('98220 11223', 'बिल #1 ₹100');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919822011223');
      expect(uri.queryParameters['text'], 'बिल #1 ₹100');
      // No usable number → WhatsApp lets the user choose the chat.
      expect(WhatsAppService.whatsAppUri(null, 'x').path, '/');
    });
  });

  group('Bag stock report', () {
    test('rows are Product / Brand / Bags — bags only, loose kg not counted',
        () async {
      final app = await bootedApp();
      final rows = bagStockReport(
          products: app.products, brandOf: app.brandOf, stockOf: app.stockOf);
      expect(rows, hasLength(app.products.length));
      for (final r in rows) {
        expect(r.brand?.id, r.product.brandId);
        expect(r.bags, app.stockOf(r.product.id).bags);
      }
      // A product holding only loose kg shows 0 bags in this report.
      final loose = app.products.firstWhere(
          (p) => app.stockOf(p.id).looseKg > 0,
          orElse: () => app.products.first);
      app.stock[loose.id]!.looseKg = 37.5;
      final again = bagStockReport(
          products: app.products, brandOf: app.brandOf, stockOf: app.stockOf);
      expect(again.firstWhere((r) => r.product.id == loose.id).bags,
          app.stockOf(loose.id).bags);
      expect(
          totalBags(again),
          app.products.fold<int>(
              0, (s, p) => s + app.stockOf(p.id).bags.clamp(0, 1 << 30)));
    });

    test('grouped by brand, filterable by brand, search and in-stock only',
        () async {
      final app = await bootedApp();
      final brand = app.brands.first;
      final byBrand = bagStockReport(
          products: app.products,
          brandOf: app.brandOf,
          stockOf: app.stockOf,
          brandId: brand.id);
      expect(byBrand, isNotEmpty);
      expect(byBrand.every((r) => r.product.brandId == brand.id), isTrue);

      final pid = await freshProduct(app, name: 'Zero Stock Feed');
      final all = bagStockReport(
          products: app.products, brandOf: app.brandOf, stockOf: app.stockOf);
      expect(all.any((r) => r.product.id == pid), isTrue);
      final inStock = bagStockReport(
          products: app.products,
          brandOf: app.brandOf,
          stockOf: app.stockOf,
          inStockOnly: true);
      expect(inStock.any((r) => r.product.id == pid), isFalse);

      final found = bagStockReport(
          products: app.products,
          brandOf: app.brandOf,
          stockOf: app.stockOf,
          query: 'zero stock');
      expect(found.single.product.id, pid);

      // Brand order: rows of one brand are contiguous.
      final brandsInOrder = [for (final r in all) r.product.brandId];
      final seen = <String>{};
      String? last;
      for (final id in brandsInOrder) {
        if (id != last) {
          expect(seen.contains(id), isFalse, reason: 'brand $id split up');
          seen.add(id);
          last = id;
        }
      }
    });
  });

  group('Product / brand search', () {
    test('product by English name, Marathi name, code and brand', () async {
      final app = await bootedApp();
      final p1 = app.productOf('p1')!; // Milk Booster · Godrej · PEND-P1
      List<String> ids(String q, {String? brandId}) => [
            for (final p in searchProducts(app.products, app.brandOf, q,
                brandId: brandId))
              p.id
          ];
      expect(ids('milk'), contains('p1'));
      expect(ids(p1.nameMr.substring(0, 3)), contains('p1'));
      expect(ids('pend-p1'), contains('p1'));
      expect(
          ids('godrej'),
          everyElement(
              predicate<String>((id) => app.productOf(id)!.brandId == 'b1')));
      expect(
          ids('', brandId: 'b2'),
          everyElement(
              predicate<String>((id) => app.productOf(id)!.brandId == 'b2')));
      expect(ids('no-such-product-xyz'), isEmpty);
      expect(ids('').length, app.products.length);
    });

    test('brand by English or Marathi name', () async {
      final app = await bootedApp();
      expect(searchBrands(app.brands, 'karg').single.id, 'b2');
      expect(searchBrands(app.brands, 'गोदरेज').single.id, 'b1');
      expect(searchBrands(app.brands, '').length, app.brands.length);
    });
  });
}
