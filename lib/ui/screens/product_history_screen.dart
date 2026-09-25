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
import 'bill_screen.dart';

/// Product drill-down (reviewed spec §8–§11): every sale of one product
/// within the Reports screen's currently selected date range, each row
/// traceable to its actual bill via [BillScreen] — never a second,
/// competing bill-detail view.
class ProductHistoryScreen extends StatelessWidget {
  final String productId;
  final ReportFilter filter;
  const ProductHistoryScreen(
      {required this.productId, required this.filter, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final product = app.productOf(productId);
    if (product == null) {
      return const PendScaffold(
          titleMr: 'उत्पादन इतिहास',
          titleEn: 'Product History',
          body: EmptyState('❓', 'Product not found'));
    }
    final brand = app.brandOf(product.brandId);
    final history = buildProductHistory(
        bills: app.finalBills, productId: productId, filter: filter);

    return PendScaffold(
      titleMr: 'उत्पादन इतिहास',
      titleEn: 'Product History',
      actions: [
        const InfoTooltip('Download or share this product\'s sales history.\n'
            'या उत्पादनाचा विक्री इतिहास डाउनलोड किंवा शेअर करा.'),
        BarAction('एक्सपोर्ट', icon: Icons.ios_share_rounded,
            onTap: () => showExportSheet(
                  context,
                  onDownloadPdf: () =>
                      ReportExportService.downloadProductHistoryPdf(
                          app, product, history),
                  onDownloadExcel: () =>
                      ReportExportService.downloadProductHistoryExcel(
                          app, product, history),
                  onSharePdf: () =>
                      ReportExportService.shareProductHistoryPdfFile(
                          app, product, history),
                  onShareExcel: () =>
                      ReportExportService.shareProductHistoryExcelFile(
                          app, product, history),
                )),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            PhotoSwatch(product, size: 56),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  ProductName(product, size: 16.5),
                  if (brand != null)
                    Text('${brand.nameMr} · ${brand.name}',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                  if (product.category != null && product.category!.isNotEmpty)
                    Text(product.category!,
                        style: TextStyle(fontSize: 11.5, color: c.muted)),
                ])),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
            '${dayFull(filter.start)} → ${dayFull(filter.end)}',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink2)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: 'विक्री · Revenue',
                  value: money(history.totalRevenue),
                  sub: '${history.totalBills} bills')),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(label: 'गोणी · Bags', value: '${history.totalBags}')),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: 'सुटे · Loose', value: kg(history.totalLooseKg))),
        ]),
        SectionHeader('विक्री नोंदी · Sales'),
        if (history.isEmpty)
          Container(
            decoration: cardDecoration(context),
            child: const EmptyState('📭',
                'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही.\nNo sales found for the selected filters.'),
          )
        else
          CardList([
            for (final row in history.rows)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BillScreen(billId: row.bill.id))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text('बिल #${row.bill.billNumber}',
                              style: baloo(
                                  size: 13.5,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          Text(dateTimeShort(row.bill.at),
                              style: TextStyle(fontSize: 11.5, color: c.ink2)),
                          if (row.bill.customerName.isNotEmpty)
                            Text(row.bill.customerName,
                                style:
                                    TextStyle(fontSize: 11.5, color: c.ink2)),
                          Text(
                              row.item.saleType == SaleType.bag
                                  ? '${row.item.qty.round()} × गोणी bag'
                                  : '${kg(row.item.qty)} सुटे loose',
                              style: TextStyle(fontSize: 11.5, color: c.muted)),
                        ])),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money(row.amount),
                              style: baloo(
                                  size: 14,
                                  weight: FontWeight.w800,
                                  color: c.ink)),
                          const SizedBox(height: 3),
                          Text(
                              row.bill.payments
                                  .map((p) => p.mode.name)
                                  .join('+'),
                              style: TextStyle(fontSize: 11, color: c.muted)),
                        ]),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: c.muted),
                  ]),
                ),
              ),
          ]),
      ]),
    );
  }
}
