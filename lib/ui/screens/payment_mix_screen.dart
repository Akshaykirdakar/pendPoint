import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/report_export_service.dart';
import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'payment_method_transactions_screen.dart';

/// Payment Mix detail (spec §3) — the same [ReportResult] the Reports
/// dashboard computed for the active [ReportFilter], just presented with the
/// extra detail (transaction counts, averages, filters applied) that doesn't
/// fit the dashboard's summary card. Never recomputes the numbers itself.
class PaymentMixScreen extends StatelessWidget {
  final ReportResult result;
  const PaymentMixScreen({required this.result, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final r = result;
    final brand = r.filter.brandId == null ? null : app.brandOf(r.filter.brandId!);
    final modeColor = {
      PayMode.cash: c.s1,
      PayMode.upi: c.s3,
      PayMode.credit: c.s2,
    };

    return PendScaffold(
      titleMr: 'पेमेंट विभागणी',
      titleEn: 'Payment Mix',
      actions: [
        InfoTooltip('Download or share this payment breakdown.\n'
            'हे पेमेंट विभाजन डाउनलोड किंवा शेअर करा.'),
        BarAction('एक्सपोर्ट', icon: Icons.ios_share_rounded,
            onTap: r.isEmpty
                ? () => showToast(context,
                    'निर्यात करण्यासाठी विक्री नाही · Nothing to export')
                : () => showExportSheet(
                      context,
                      onDownloadPdf: () =>
                          ReportExportService.downloadPaymentMixPdf(app, r),
                      onDownloadExcel: () =>
                          ReportExportService.downloadPaymentMixExcel(app, r),
                      onSharePdf: () =>
                          ReportExportService.sharePaymentMixPdfFile(app, r),
                      onShareExcel: () =>
                          ReportExportService.sharePaymentMixExcelFile(app, r),
                      onShareSummary: () => _export(context, () =>
                          ReportExportService.sharePaymentMixSummaryText(app, r)),
                    )),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Filters applied — so this screen is legible on its own.
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('लागू फिल्टर · Filters applied',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
            const SizedBox(height: 6),
            Text('${dayFull(r.filter.start)} → ${dayFull(r.filter.end)}',
                style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 3),
            if (app.branches.length > 1)
              Text(
                  'शाखा · Branch: ${r.filter.branchId == null ? 'सर्व · All' : (app.branchOf(r.filter.branchId!) == null ? r.filter.branchId! : '${app.branchOf(r.filter.branchId!)!.nameMr} · ${app.branchOf(r.filter.branchId!)!.name}')}',
                  style: TextStyle(fontSize: 12, color: c.ink2)),
            Text(
                'ब्रँड · Brand: ${brand == null ? 'सर्व · All' : '${brand.nameMr} · ${brand.name}'}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
            Text(
                'उत्पाद · Product: ${_productLabel(app, r.filter.productId)}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
            Text('विक्री प्रकार · Sale Type: ${_saleTypeLabel(r.filter.saleType)}',
                style: TextStyle(fontSize: 12, color: c.ink2)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: 'एकूण रक्कम · Total Amount',
                  value: money(r.revenue),
                  sub: '${r.billCount} bills')),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'एकूण बिले · Total Bills', value: '${r.billCount}')),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: 'सरासरी बिल · Avg Bill',
                  value: r.billCount == 0
                      ? money(0)
                      : money(r.revenue / r.billCount))),
        ]),
        if (r.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: cardDecoration(context),
            child: const EmptyState('📭',
                'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही.\nNo sales found for the selected filters.'),
          ),
        ] else ...[
          SectionHeader('तपशीलवार विभागणी · Detailed breakdown',
              action: const InfoTooltip(
                  'Tap a payment method to see its transactions.\n'
                  'व्यवहार पाहण्यासाठी पेमेंट पद्धतीवर टॅप करा.')),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final mode in PayMode.values)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PaymentMethodTransactionsScreen(
                          filter: r.filter, mode: mode))),
                  child: PaymentMixBar(
                      label: _label(mode),
                      value: r.paymentTotals[mode] ?? 0,
                      total: r.revenue,
                      color: modeColor[mode]!),
                ),
            ]),
          ),
          SectionHeader('दैनंदिन कल · Daily trend'),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            child: RevenueTrendChart(dailySeries(buildTransactions(
                bills: app.finalBills, products: app.products, filter: r.filter))),
          ),
          SectionHeader('व्यवहार · Transactions per method'),
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final mode in PayMode.values) _txnRow(context, mode, r),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _txnRow(BuildContext context, PayMode mode, ReportResult r) {
    final c = context.c;
    final n = r.paymentCounts[mode] ?? 0;
    final amt = r.paymentTotals[mode] ?? 0;
    final avg = n == 0 ? 0.0 : amt / n;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              PaymentMethodTransactionsScreen(filter: r.filter, mode: mode))),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Expanded(
              child: Text(_label(mode),
                  style: baloo(size: 13.5, weight: FontWeight.w700, color: c.ink))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$n व्यवहार · txns',
                style: TextStyle(fontSize: 11.5, color: c.ink2)),
            if (n > 0)
              Text('सरासरी · avg ${money(avg)}',
                  style: TextStyle(fontSize: 11, color: c.muted)),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }

  String _label(PayMode m) => switch (m) {
        PayMode.cash => 'रोख Cash',
        PayMode.upi => 'UPI',
        PayMode.credit => 'उधार Credit',
      };

  String _productLabel(AppState app, String? productId) {
    if (productId == null) return 'सर्व · All';
    final p = app.productOf(productId);
    return p == null ? productId : (p.nameMr.isNotEmpty ? p.nameMr : p.name);
  }

  String _saleTypeLabel(SaleTypeFilter f) => switch (f) {
        SaleTypeFilter.all => 'सर्व · All',
        SaleTypeFilter.bags => 'बॅग · Bags',
        SaleTypeFilter.loose => 'सुटे · Loose',
      };

  Future<void> _export(BuildContext context, Future<void> Function() run) async {
    try {
      await run();
    } catch (_) {
      if (context.mounted) {
        showToast(context, 'एक्सपोर्ट अयशस्वी · Export failed');
      }
    }
  }
}
