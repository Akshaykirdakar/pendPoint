// PDF + Excel export for the Reports module — respects whatever ReportFilter
// produced the ReportResult/ProductHistoryResult it's given (reviewed spec
// §12–§15). Shares the generated file via `share_plus`, which on the Web
// triggers a browser download and on Android opens the native share sheet —
// the same call works on both platforms, so there's no platform-specific
// branch to keep in sync (reviewed spec §15).
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/bill.dart';
import '../models/brand.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../state/report_query.dart';
import 'xlsx_writer.dart';

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

  // ---------------- Plain-text share (spec §5 "Share") ----------------

  /// Shares a short plain-text summary — a genuine, working "Share" option
  /// distinct from the PDF/Excel downloads, using the same `share_plus`
  /// mechanism already used for files.
  static Future<void> shareReportSummaryText(
      AppState app, ReportResult r) async {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final text = StringBuffer()
      ..writeln(app.settings.shop)
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
      ..writeln(app.settings.shop)
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

  static Future<void> shareReportPdf(AppState app, ReportResult r) async {
    final bytes = await _buildReportPdf(app, r);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'sales_report')}.pdf',
            mimeType: 'application/pdf')
      ],
      subject: 'Sales Report · विक्री अहवाल',
    ));
  }

  static Future<void> shareReportExcel(AppState app, ReportResult r) async {
    final bytes = _buildReportXlsx(app, r);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'sales_report')}.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: 'Sales Report · विक्री अहवाल',
    ));
  }

  static Future<Uint8List> _buildReportPdf(AppState app, ReportResult r) async {
    final brand =
        r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final fonts = await _PdfFonts.load();
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(app.settings.shop,
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
      ['Shop', app.settings.shop],
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

  static Future<void> shareProductHistoryPdf(
      AppState app, Product product, ProductHistoryResult h) async {
    final bytes = await _buildProductHistoryPdf(app, product, h);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'product_history')}.pdf',
            mimeType: 'application/pdf')
      ],
      subject: 'Product Sales History — ${product.name}',
    ));
  }

  static Future<void> shareProductHistoryExcel(
      AppState app, Product product, ProductHistoryResult h) async {
    final bytes = _buildProductHistoryXlsx(app, product, h);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'product_history')}.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: 'Product Sales History — ${product.name}',
    ));
  }

  // ---------------- Payment mix ----------------

  static Future<void> sharePaymentMixPdf(AppState app, ReportResult r) async {
    final bytes = await _buildPaymentMixPdf(app, r);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'payment_mix')}.pdf',
            mimeType: 'application/pdf')
      ],
      subject: 'Payment Mix · पेमेंट विभागणी',
    ));
  }

  static Future<void> sharePaymentMixExcel(AppState app, ReportResult r) async {
    final bytes = _buildPaymentMixXlsx(app, r);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            name: '${_fileStem(app.settings.shop, 'payment_mix')}.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: 'Payment Mix · पेमेंट विभागणी',
    ));
  }

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
        pw.Text(app.settings.shop,
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
      ['Shop', app.settings.shop],
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
        pw.Text(app.settings.shop,
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
}
