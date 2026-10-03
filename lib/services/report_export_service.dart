// PDF + Excel export for the Reports module — respects whatever ReportFilter
// produced the ReportResult/ProductHistoryResult it's given (reviewed spec
// §12–§15).
//
// Report generation here only ever produces bytes — identical on every
// platform. Getting those bytes onto the user's device is [ExportFileService]'s
// job, not this file's: "Download" goes through its `saveFile` (Android
// Storage Access Framework / Windows save dialog / Web download, uniformly —
// see that file's header for why this replaced share_plus for that action),
// "Share" goes through its `shareFile` (the OS share sheet, with the Android
// filename bug worked around). Every public export method here returns an
// [ExportResult] so the caller can tell a cancelled save dialog apart from an
// actual failure apart from success, and never show a fake success message.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../models/bill.dart';
import '../models/brand.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../state/report_query.dart';
import 'export_file_service.dart';
import 'xlsx_writer.dart';

const _pdfMime = 'application/pdf';
const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

final _dateFmt = DateFormat('dd MMM yyyy');
final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

/// Bundled Noto Sans Devanagari (Regular + Bold) so PDF exports can render
/// Marathi (and mixed Marathi+English) text correctly — the base14 Helvetica
/// fonts `pdf`/`dart_pdf` fall back to have no Devanagari glyphs at all.
/// Loaded once via `rootBundle` (works identically on Android/Web/Windows —
/// no platform-specific filesystem path) and cached for the app's lifetime.
class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  const _PdfFonts(this.regular, this.bold);

  static Future<_PdfFonts>? _loading;

  static Future<_PdfFonts> load() {
    return _loading ??= () async {
      final regularData =
          await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf');
      return _PdfFonts(pw.Font.ttf(regularData), pw.Font.ttf(boldData));
    }();
  }
}

/// PDF text uses the base14 Helvetica font, which has no glyph for ₹ — so
/// money in PDF exports is still spelled "Rs." (mirrors why the printed bill
/// receipt is rendered as an image instead of ESC/POS text — see
/// [BillScreen]'s header comment). Marathi text, however, now renders
/// correctly via the bundled Noto Sans Devanagari font (see [_PdfFonts]).
String _moneyPdf(num n) =>
    'Rs. ${NumberFormat('#,##0', 'en_IN').format(n.round())}';
String _kgPdf(num n) {
  final r = (n * 10).round() / 10;
  final s =
      r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return '$s kg';
}

/// Bilingual (Marathi + English) payment-method label — renders correctly in
/// PDF now that the document's default font is Devanagari-capable.
String _payModeLabel(PayMode m) => switch (m) {
      PayMode.cash => 'रोख Cash',
      PayMode.upi => 'UPI',
      PayMode.credit => 'उधार Credit',
    };

String _filterDateLabel(ReportFilter f) =>
    '${_dateFmt.format(f.start)} - ${_dateFmt.format(f.end)}';

/// Resolves the active Product filter to a display name — never the raw id,
/// and never a product-type/category (that filter no longer exists; see the
/// reviewed data-model correction).
String _productLabel(AppState app, String? productId) {
  if (productId == null) return 'All';
  final p = app.productOf(productId);
  return p == null ? productId : (p.nameMr.isNotEmpty ? '${p.nameMr} / ${p.name}' : p.name);
}

String _saleTypeLabel(SaleTypeFilter f) => switch (f) {
      SaleTypeFilter.all => 'All',
      SaleTypeFilter.bags => 'Bags',
      SaleTypeFilter.loose => 'Loose',
    };

String _branchLabel(AppState app, String? branchId) {
  if (branchId == null) return 'All';
  final b = app.branchOf(branchId);
  return b == null ? branchId : '${b.nameMr} / ${b.name}';
}

/// A safe, meaningful file-name stem from the shop name (from Settings —
/// never hard-coded) plus today's date, e.g. `pendpoint_sales_report`.
String _fileStem(String shopName, String reportKind) {
  final slug = shopName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .trim();
  final prefix = slug.isEmpty ? 'pendpoint' : slug;
  final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return '${prefix}_${reportKind}_$date';
}

class ReportExportService {
  const ReportExportService._();

  /// Runs [build] (which may itself throw — font loading, malformed data)
  /// and saves the resulting bytes, collapsing any failure from either step
  /// into a single [ExportResult.failed] instead of letting it propagate as
  /// an uncaught exception into the UI.
  static Future<ExportResult> _download(
      Future<Uint8List> Function() build, String fileName, String mimeType) async {
    try {
      final bytes = await build();
      return await ExportFileService.saveFile(
          bytes: bytes, fileName: fileName, mimeType: mimeType);
    } catch (e) {
      return ExportResult(ExportOutcome.failed, error: e);
    }
  }

  /// Same as [_download], for the "Share" action.
  static Future<ExportResult> _share(Future<Uint8List> Function() build,
      String fileName, String mimeType, String subject) async {
    try {
      final bytes = await build();
      return await ExportFileService.shareFile(
          bytes: bytes, fileName: fileName, mimeType: mimeType, subject: subject);
    } catch (e) {
      return ExportResult(ExportOutcome.failed, error: e);
    }
  }

  // ---------------- Test hooks ----------------

  /// Exposes the PDF byte-builders for tests (see test/pdf_marathi_font_test.dart)
  /// without going through `share_plus`, which needs a platform channel that
  /// isn't available in a plain widget/unit test.
  @visibleForTesting
  static Future<Uint8List> buildReportPdfBytes(AppState app, ReportResult r) =>
      _buildReportPdf(app, r);

  @visibleForTesting
  static Future<Uint8List> buildPaymentMixPdfBytes(
          AppState app, ReportResult r) =>
      _buildPaymentMixPdf(app, r);

  @visibleForTesting
  static Future<Uint8List> buildProductHistoryPdfBytes(
          AppState app, Product product, ProductHistoryResult h) =>
      _buildProductHistoryPdf(app, product, h);

  @visibleForTesting
  static Future<Uint8List> buildQrSheetPdfBytes(
          AppState app, List<Product> products, {Brand? brand}) =>
      _buildQrSheetPdf(app, products, brand);

  // ---------------- Plain-text share (spec §5 "Share") ----------------

  /// Shares a short plain-text summary — a genuine, working "Share" option
  /// distinct from the PDF/Excel downloads, using the same `share_plus`
  /// mechanism already used for files.
  static Future<void> shareReportSummaryText(
      AppState app, ReportResult r) async {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final text = StringBuffer()
      ..writeln(app.shopName)
      ..writeln('विक्री अहवाल · Sales Report')
      ..writeln(_filterDateLabel(r.filter))
      ..writeln('शाखा · Branch: ${_branchLabel(app, r.filter.branchId)}')
      ..writeln('ब्रँड · Brand: ${brand == null ? 'सर्व · All' : brand.name}')
      ..writeln('उत्पाद · Product: ${_productLabel(app, r.filter.productId)}')
      ..writeln('विक्री प्रकार · Sale Type: ${_saleTypeLabel(r.filter.saleType)}')
      ..writeln()
      ..writeln('एकूण विक्री · Total Revenue: ${_moneyPdf(r.revenue)}')
      ..writeln('बिले · Bills: ${r.billCount}')
      ..writeln('गोणी · Bags: ${r.bags}')
      ..writeln('सुटे · Loose: ${_kgPdf(r.looseKg)}');
    await SharePlus.instance.share(ShareParams(text: text.toString()));
  }

  static Future<void> sharePaymentMixSummaryText(
      AppState app, ReportResult r) async {
    final text = StringBuffer()
      ..writeln(app.shopName)
      ..writeln('पेमेंट विभागणी · Payment Mix')
      ..writeln(_filterDateLabel(r.filter))
      ..writeln()
      ..writeln('एकूण बिले · Total Bills: ${r.billCount}')
      ..writeln('एकूण रक्कम · Total Amount: ${_moneyPdf(r.revenue)}');
    for (final mode in PayMode.values) {
      final amt = r.paymentTotals[mode] ?? 0;
      final pct = r.revenue == 0 ? 0.0 : (amt / r.revenue) * 100;
      text.writeln(
          '${_payModeLabel(mode)}: ${_moneyPdf(amt)} (${pct.toStringAsFixed(1)}%)');
    }
    await SharePlus.instance.share(ShareParams(text: text.toString()));
  }

  // ---------------- Full report ----------------

  static Future<ExportResult> downloadReportPdf(AppState app, ReportResult r) =>
      _download(() => _buildReportPdf(app, r),
          '${_fileStem(app.shopName, 'sales_report')}.pdf', _pdfMime);

  static Future<ExportResult> shareReportPdfFile(AppState app, ReportResult r) =>
      _share(
          () => _buildReportPdf(app, r),
          '${_fileStem(app.shopName, 'sales_report')}.pdf',
          _pdfMime,
          'Sales Report · विक्री अहवाल');

  static Future<ExportResult> downloadReportExcel(
          AppState app, ReportResult r) =>
      _download(() async => _buildReportXlsx(app, r),
          '${_fileStem(app.shopName, 'sales_report')}.xlsx', _xlsxMime);

  static Future<ExportResult> shareReportExcelFile(
          AppState app, ReportResult r) =>
      _share(
          () async => _buildReportXlsx(app, r),
          '${_fileStem(app.shopName, 'sales_report')}.xlsx',
          _xlsxMime,
          'Sales Report · विक्री अहवाल');

  static Future<Uint8List> _buildReportPdf(AppState app, ReportResult r) async {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final fonts = await _PdfFonts.load();
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(app.shopName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('विक्री अहवाल · Sales Report',
            style: const pw.TextStyle(fontSize: 13)),
        pw.Text('Generated: ${_dateTimeFmt.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        _filterBlock(r.filter, brand, app),
        pw.SizedBox(height: 14),
        pw.Text('सारांश · Summary',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          data: [
            ['एकूण विक्री · Total Revenue', _moneyPdf(r.revenue)],
            ['बिले · Total Bills', '${r.billCount}'],
            ['गोणी · Total Bags', '${r.bags}'],
            ['सुटे · Total Loose Kg', _kgPdf(r.looseKg)],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('पेमेंट विभागणी · Payment Summary',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['पेमेंट पद्धत · Payment Method', 'रक्कम · Amount', '%'],
          data: [
            for (final mode in PayMode.values)
              [
                _payModeLabel(mode),
                _moneyPdf(r.paymentTotals[mode] ?? 0),
                r.revenue == 0
                    ? '0%'
                    : '${(((r.paymentTotals[mode] ?? 0) / r.revenue) * 100).toStringAsFixed(1)}%',
              ],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('उत्पादन सारांश · Product Summary',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (r.products.isEmpty)
          pw.Text(
              'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही · No sales found for the selected filters.')
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'उत्पादन · Product',
              'ब्रँड · Brand',
              'गोणी · Bags',
              'सुटे · Loose Kg',
              'विक्री · Revenue'
            ],
            data: [
              for (final stat in r.products)
                () {
                  final p = app.productOf(stat.productId);
                  final b = p == null ? null : app.brandOf(p.brandId);
                  return [
                    p == null
                        ? stat.productId
                        : (p.nameMr.isEmpty
                            ? p.name
                            : '${p.nameMr} · ${p.name}'),
                    b == null ? '' : '${b.nameMr} · ${b.name}',
                    '${stat.bags}',
                    _kgPdf(stat.looseKg),
                    _moneyPdf(stat.revenue),
                  ];
                }(),
            ],
          ),
      ],
    ));
    return doc.save();
  }

  static Uint8List _buildReportXlsx(AppState app, ReportResult r) {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final summary = XlsxSheet('Summary', [
      ['Shop', app.shopName],
      ['Report Period', _filterDateLabel(r.filter)],
      ['Branch Filter', _branchLabel(app, r.filter.branchId)],
      ['Product Filter', _productLabel(app, r.filter.productId)],
      ['Sale Type Filter', _saleTypeLabel(r.filter.saleType)],
      [
        'Brand Filter',
        brand == null ? 'All' : '${brand.name} / ${brand.nameMr}'
      ],
      ['Revenue', r.revenue],
      ['Bills', r.billCount],
      ['Bags', r.bags],
      ['Loose Kg', r.looseKg],
    ]);
    final products = XlsxSheet('Product Summary', [
      ['Product', 'Marathi Name', 'Brand', 'Bags', 'Loose Kg', 'Revenue'],
      for (final stat in r.products)
        () {
          final p = app.productOf(stat.productId);
          final b = p == null ? null : app.brandOf(p.brandId);
          return [
            p?.name ?? stat.productId,
            p?.nameMr ?? '',
            b?.name ?? '',
            stat.bags,
            stat.looseKg,
            stat.revenue,
          ];
        }(),
    ]);
    final payments = XlsxSheet('Payment Summary', [
      ['Payment Method', 'Amount', 'Percentage'],
      for (final mode in PayMode.values)
        [
          _payModeLabel(mode),
          r.paymentTotals[mode] ?? 0,
          r.revenue == 0 ? 0 : ((r.paymentTotals[mode] ?? 0) / r.revenue) * 100,
        ],
    ]);
    return buildXlsx([summary, products, payments]);
  }

  static pw.Widget _filterBlock(ReportFilter f, Brand? brand, AppState app) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('दिनांक श्रेणी · Date: ${_filterDateLabel(f)}'),
          pw.Text('शाखा · Branch: ${_branchLabel(app, f.branchId)}'),
          pw.Text(
              'ब्रँड · Brand: ${brand == null ? 'सर्व · All' : '${brand.nameMr} · ${brand.name}'}'),
          pw.Text('उत्पाद · Product: ${_productLabel(app, f.productId)}'),
          pw.Text('विक्री प्रकार · Sale Type: ${_saleTypeLabel(f.saleType)}'),
        ],
      );

  // ---------------- Product history ----------------

  static Future<ExportResult> downloadProductHistoryPdf(
          AppState app, Product product, ProductHistoryResult h) =>
      _download(() => _buildProductHistoryPdf(app, product, h),
          '${_fileStem(app.shopName, 'product_history')}.pdf', _pdfMime);

  static Future<ExportResult> shareProductHistoryPdfFile(
          AppState app, Product product, ProductHistoryResult h) =>
      _share(
          () => _buildProductHistoryPdf(app, product, h),
          '${_fileStem(app.shopName, 'product_history')}.pdf',
          _pdfMime,
          'Product Sales History — ${product.name}');

  static Future<ExportResult> downloadProductHistoryExcel(
          AppState app, Product product, ProductHistoryResult h) =>
      _download(
          () async => _buildProductHistoryXlsx(app, product, h),
          '${_fileStem(app.shopName, 'product_history')}.xlsx',
          _xlsxMime);

  static Future<ExportResult> shareProductHistoryExcelFile(
          AppState app, Product product, ProductHistoryResult h) =>
      _share(
          () async => _buildProductHistoryXlsx(app, product, h),
          '${_fileStem(app.shopName, 'product_history')}.xlsx',
          _xlsxMime,
          'Product Sales History — ${product.name}');

  // ---------------- Payment mix ----------------

  static Future<ExportResult> downloadPaymentMixPdf(
          AppState app, ReportResult r) =>
      _download(() => _buildPaymentMixPdf(app, r),
          '${_fileStem(app.shopName, 'payment_mix')}.pdf', _pdfMime);

  static Future<ExportResult> sharePaymentMixPdfFile(
          AppState app, ReportResult r) =>
      _share(
          () => _buildPaymentMixPdf(app, r),
          '${_fileStem(app.shopName, 'payment_mix')}.pdf',
          _pdfMime,
          'Payment Mix · पेमेंट विभागणी');

  static Future<ExportResult> downloadPaymentMixExcel(
          AppState app, ReportResult r) =>
      _download(() async => _buildPaymentMixXlsx(app, r),
          '${_fileStem(app.shopName, 'payment_mix')}.xlsx', _xlsxMime);

  static Future<ExportResult> sharePaymentMixExcelFile(
          AppState app, ReportResult r) =>
      _share(
          () async => _buildPaymentMixXlsx(app, r),
          '${_fileStem(app.shopName, 'payment_mix')}.xlsx',
          _xlsxMime,
          'Payment Mix · पेमेंट विभागणी');

  static Future<Uint8List> _buildPaymentMixPdf(
      AppState app, ReportResult r) async {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final fonts = await _PdfFonts.load();
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    final counts = r.paymentCounts;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(app.shopName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('पेमेंट विभागणी · Payment Mix',
            style: const pw.TextStyle(fontSize: 13)),
        pw.Text('Generated: ${_dateTimeFmt.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        _filterBlock(r.filter, brand, app),
        pw.SizedBox(height: 14),
        pw.Text('एकूण · Totals',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          data: [
            ['एकूण बिले · Total Bills', '${r.billCount}'],
            ['एकूण रक्कम · Total Amount', _moneyPdf(r.revenue)],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('तपशील · Breakdown',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (r.isEmpty)
          pw.Text(
              'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही · No sales found for the selected filters.')
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'पेमेंट पद्धत · Method',
              'रक्कम · Amount',
              '%',
              'व्यवहार · Txns',
              'सरासरी · Avg',
            ],
            data: [
              for (final mode in PayMode.values)
                () {
                  final amt = r.paymentTotals[mode] ?? 0;
                  final n = counts[mode] ?? 0;
                  return [
                    _payModeLabel(mode),
                    _moneyPdf(amt),
                    r.revenue == 0
                        ? '0%'
                        : '${((amt / r.revenue) * 100).toStringAsFixed(1)}%',
                    '$n',
                    n == 0 ? '-' : _moneyPdf(amt / n),
                  ];
                }(),
            ],
          ),
      ],
    ));
    return doc.save();
  }

  static Uint8List _buildPaymentMixXlsx(AppState app, ReportResult r) {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final counts = r.paymentCounts;
    final summary = XlsxSheet('Payment Mix', [
      ['Shop', app.shopName],
      ['Report Period', _filterDateLabel(r.filter)],
      ['Branch Filter', _branchLabel(app, r.filter.branchId)],
      ['Product Filter', _productLabel(app, r.filter.productId)],
      ['Sale Type Filter', _saleTypeLabel(r.filter.saleType)],
      [
        'Brand Filter',
        brand == null ? 'All' : '${brand.name} / ${brand.nameMr}'
      ],
      ['Total Bills', r.billCount],
      ['Total Amount', r.revenue],
    ]);
    final breakdown = XlsxSheet('Breakdown', [
      [
        'Payment Method',
        'Amount',
        'Percentage',
        'Transactions',
        'Average Amount'
      ],
      for (final mode in PayMode.values)
        () {
          final amt = r.paymentTotals[mode] ?? 0;
          final n = counts[mode] ?? 0;
          return [
            _payModeLabel(mode),
            amt,
            r.revenue == 0 ? 0 : (amt / r.revenue) * 100,
            n,
            n == 0 ? 0 : amt / n,
          ];
        }(),
    ]);
    return buildXlsx([summary, breakdown]);
  }

  static Future<Uint8List> _buildProductHistoryPdf(
      AppState app, Product product, ProductHistoryResult h) async {
    final brand = app.brandOf(product.brandId);
    final fonts = await _PdfFonts.load();
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(app.shopName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('उत्पादन इतिहास · Product Sales History',
            style: const pw.TextStyle(fontSize: 13)),
        pw.Text('Generated: ${_dateTimeFmt.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Text(
            product.nameMr.isEmpty
                ? product.name
                : '${product.nameMr} · ${product.name}',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        if (brand != null)
          pw.Text('ब्रँड · Brand: ${brand.nameMr} · ${brand.name}'),
        pw.Text('दिनांक श्रेणी · Date range: ${_filterDateLabel(h.filter)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          data: [
            ['एकूण बिले · Total Bills', '${h.totalBills}'],
            ['एकूण गोणी · Total Bags', '${h.totalBags}'],
            ['एकूण सुटे · Total Loose Kg', _kgPdf(h.totalLooseKg)],
            ['एकूण विक्री · Total Revenue', _moneyPdf(h.totalRevenue)],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('विक्री नोंदी · Sales',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (h.rows.isEmpty)
          pw.Text(
              'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही · No sales found for the selected filters.')
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'बिल · Bill No',
              'दिनांक · Date',
              'ग्राहक · Customer',
              'प्रमाण · Qty',
              'रक्कम · Amount',
              'पेमेंट · Payment'
            ],
            data: [
              for (final row in h.rows)
                [
                  '#${row.bill.billNumber}',
                  _dateTimeFmt.format(row.bill.at),
                  row.bill.customerName.isEmpty ? '-' : row.bill.customerName,
                  row.item.saleType == SaleType.bag
                      ? '${row.item.qty.round()} bag(s)'
                      : _kgPdf(row.item.qty),
                  _moneyPdf(row.amount),
                  row.bill.payments.map((p) => _payModeLabel(p.mode)).join('+'),
                ],
            ],
          ),
      ],
    ));
    return doc.save();
  }

  static Uint8List _buildProductHistoryXlsx(
      AppState app, Product product, ProductHistoryResult h) {
    final brand = app.brandOf(product.brandId);
    final summary = XlsxSheet('Product Summary', [
      ['Product', product.name],
      ['Marathi Name', product.nameMr],
      ['Brand', brand?.name ?? ''],
      ['Date Range', _filterDateLabel(h.filter)],
      ['Total Bills', h.totalBills],
      ['Total Bags', h.totalBags],
      ['Total Loose Kg', h.totalLooseKg],
      ['Total Revenue', h.totalRevenue],
    ]);
    final history = XlsxSheet('Sales History', [
      [
        'Bill No',
        'Date',
        'Customer',
        'Product',
        'Brand',
        'Bags',
        'Loose Kg',
        'Unit Price',
        'Discount',
        'Amount',
        'Payment Method',
      ],
      for (final row in h.rows)
        [
          row.bill.billNumber,
          _dateTimeFmt.format(row.bill.at),
          row.bill.customerName.isEmpty ? '-' : row.bill.customerName,
          product.name,
          brand?.name ?? '',
          row.item.saleType == SaleType.bag ? row.item.qty.round() : 0,
          row.item.saleType == SaleType.kg ? row.item.qty : 0,
          row.item.rate,
          row.item.discountAmount,
          row.amount,
          row.bill.payments.map((p) => _payModeLabel(p.mode)).join('+'),
        ],
    ]);
    return buildXlsx([summary, history]);
  }

  // ---------------- QR sheet ----------------

  static Future<ExportResult> downloadQrSheetPdf(
          AppState app, List<Product> products, {Brand? brand}) =>
      _download(() => _buildQrSheetPdf(app, products, brand),
          '${_fileStem(app.shopName, 'qr_sheet')}.pdf', _pdfMime);

  static Future<ExportResult> shareQrSheetPdf(
          AppState app, List<Product> products, {Brand? brand}) =>
      _share(
          () => _buildQrSheetPdf(app, products, brand),
          '${_fileStem(app.shopName, 'qr_sheet')}.pdf',
          _pdfMime,
          'QR Sheet · QR शीट');

  /// Best-effort fetch of a product photo for the printed sheet — a slow or
  /// failed network image must never block or break the export, it just
  /// prints without that one photo (mirrors [PhotoSwatch]'s errorBuilder
  /// fallback on-screen).
  static Future<Uint8List?> _fetchPhoto(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {
      // Ignored — see method doc.
    }
    return null;
  }

  static Future<Uint8List> _buildQrSheetPdf(
      AppState app, List<Product> products, Brand? brand) async {
    final fonts = await _PdfFonts.load();
    final photos = <String, Uint8List?>{};
    for (final p in products) {
      photos[p.id] = await _fetchPhoto(p.photoUrl);
    }
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(app.shopName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('QR कॅटलॉग शीट · QR Catalogue Sheet',
            style: const pw.TextStyle(fontSize: 13)),
        pw.Text(
            'ब्रँड · Brand: ${brand == null ? 'सर्व · All' : '${brand.nameMr} · ${brand.name}'}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text('Generated: ${_dateTimeFmt.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),
        if (products.isEmpty)
          pw.Text('कोणतीही उत्पादने नाहीत · No products to print.')
        else
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in products)
                _qrTile(p, photos[p.id], app.brandOf(p.brandId)),
            ],
          ),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _qrTile(Product p, Uint8List? photo, Brand? brand) =>
      pw.Container(
        width: 150,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (photo != null)
                  pw.Container(
                    width: 46,
                    height: 46,
                    child: pw.ClipRRect(
                      horizontalRadius: 6,
                      verticalRadius: 6,
                      child: pw.Image(pw.MemoryImage(photo),
                          fit: pw.BoxFit.cover),
                    ),
                  ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: p.qr,
                  width: 60,
                  height: 60,
                  drawText: false,
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(p.nameMr.isEmpty ? p.name : p.nameMr,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)),
            pw.Text(p.name,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            if (brand != null)
              pw.Text(brand.name,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(
                'पॅक · Pack: ${p.bagWeightKg} kg   •   ${p.category ?? 'सर्वसाधारण · General'}',
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
          ],
        ),
      );
}
