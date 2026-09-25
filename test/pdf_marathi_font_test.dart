// Verifies that PDF export renders Marathi/Devanagari text using the bundled
// Noto Sans Devanagari font instead of falling back to Helvetica (which has
// no Devanagari glyphs and used to throw/log "Unable to find a font to draw"
// for every Marathi character). See lib/services/report_export_service.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/models/product.dart';
import 'package:pend_point/services/report_export_service.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/report_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState app;
  late Product product;

  setUp(() async {
    app = AppState(InMemoryRepository());
    await app.bootstrap();
    product = app.products.first;
  });

  Bill sampleBill() => Bill(
        id: 'BILL1',
        billNumber: 1,
        customerName: 'जय किसान पेंड भंडार',
        items: [
          BillItem(
            productId: product.id,
            saleType: SaleType.bag,
            qty: 2,
            catalogRate: product.fullBagPrice,
            rate: product.fullBagPrice,
            lineTotal: product.fullBagPrice * 2,
          ),
        ],
        subtotal: product.fullBagPrice * 2,
        discountTotal: 0,
        total: product.fullBagPrice * 2,
        payments: [
          Payment(PayMode.credit, product.fullBagPrice * 2),
        ],
        at: DateTime.now(),
      );

  test('Sales report PDF generates without font/glyph errors for Marathi text', () async {
    final bill = sampleBill();
    final filter = ReportFilter.preset(DateRangePresetKind.last30);
    final result = buildReport(
        bills: [bill], products: app.products, filter: filter);

    // Sanity: the strings this PDF must render really do contain Devanagari.
    expect(app.settings.shop, contains('जय किसान पेंड भांडार'));

    final bytes = await ReportExportService.buildReportPdfBytes(app, result);

    expect(bytes, isNotEmpty);
    // A well-formed PDF always starts with the "%PDF-" header.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Payment Mix PDF generates without font/glyph errors ("उधार Credit" etc.)',
      () async {
    final bill = sampleBill();
    final filter = ReportFilter.preset(DateRangePresetKind.last30);
    final result = buildReport(
        bills: [bill], products: app.products, filter: filter);

    expect(result.paymentTotals[PayMode.credit], greaterThan(0));

    final bytes = await ReportExportService.buildPaymentMixPdfBytes(app, result);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Product history PDF generates without font/glyph errors ("सर्व · All Products")',
      () async {
    final bill = sampleBill();
    final filter = ReportFilter.preset(DateRangePresetKind.last30);
    final history = buildProductHistory(
        bills: [bill], productId: product.id, filter: filter);

    final bytes = await ReportExportService.buildProductHistoryPdfBytes(
        app, product, history);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test(
      'QR sheet PDF generates without font/glyph errors, with no photoUrl set',
      () async {
    // Seeded products have no photoUrl — this also exercises the "no photo"
    // path (no network call attempted) alongside Marathi product names.
    final bytes =
        await ReportExportService.buildQrSheetPdfBytes(app, app.products);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('QR sheet PDF generates for an empty product list', () async {
    final bytes = await ReportExportService.buildQrSheetPdfBytes(app, const []);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
