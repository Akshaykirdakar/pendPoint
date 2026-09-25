import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/enums.dart';
import '../../services/report_export_service.dart';
import '../../state/app_state.dart';
import '../../state/report_query.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'payment_mix_screen.dart';
import 'payment_method_transactions_screen.dart';
import 'product_history_screen.dart';
import 'quantity_analytics_screen.dart';
import 'revenue_analytics_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

const _presets = [
  (DateRangePresetKind.today, 'आज', 'Today'),
  (DateRangePresetKind.yesterday, 'काल', 'Yesterday'),
  (DateRangePresetKind.last7, 'मागील 7 दिवस', 'Last 7 Days'),
  (DateRangePresetKind.last30, 'मागील 30 दिवस', 'Last 30 Days'),
  (DateRangePresetKind.last90, 'मागील 90 दिवस', 'Last 90 Days'),
  (DateRangePresetKind.thisWeek, 'या आठवड्यात', 'This Week'),
  (DateRangePresetKind.lastWeek, 'मागील आठवडा', 'Last Week'),
  (DateRangePresetKind.thisMonth, 'या महिन्यात', 'This Month'),
  (DateRangePresetKind.lastMonth, 'मागील महिना', 'Last Month'),
  (DateRangePresetKind.thisYear, 'या वर्षी', 'This Year'),
  (DateRangePresetKind.lastYear, 'मागील वर्ष', 'Last Year'),
];

class _ReportsScreenState extends State<ReportsScreen> {
  ReportFilter _filter = ReportFilter.preset(DateRangePresetKind.last7);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;

    // Single source of truth (reviewed spec §20) — every number below, the
    // payment mix, the product ranking, and both exports all read from this
    // one filtered result.
    final result = buildReport(
        bills: app.finalBills, products: app.products, filter: _filter);
    final overrides = _overriddenLines(app);

    return PendScaffold(
      titleMr: 'अहवाल',
      titleEn: 'Reports',
      actions: [
        const InfoTooltip('Download or share this report.\n'
            'हा अहवाल डाउनलोड किंवा शेअर करा.'),
        BarAction('एक्सपोर्ट', icon: Icons.ios_share_rounded,
            onTap: result.isEmpty
                ? () => showToast(context,
                    'निर्यात करण्यासाठी विक्री नाही · Nothing to export')
                : () => showExportSheet(
                      context,
                      onPdf: () => _export(() =>
                          ReportExportService.shareReportPdf(app, result)),
                      onExcel: () => _export(() =>
                          ReportExportService.shareReportExcel(app, result)),
                      onShare: () => _export(() =>
                          ReportExportService.shareReportSummaryText(app, result)),
                    )),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _filterCard(context, app),
        if (app.historyLoading && app.bills.isEmpty) ...[
          const SizedBox(height: 4),
          const HistoryLoadingNote(),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: StatTile(
                  hero: true,
                  label: 'विक्री · Revenue',
                  value: money(result.revenue),
                  sub: '${result.billCount} bills',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RevenueAnalyticsScreen(filter: _filter)))),
          ),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'गोणी · Bags',
                  value: '${result.bags}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuantityAnalyticsScreen(
                          filter: _filter, kind: SaleTypeFilter.bags))))),
          const SizedBox(width: 11),
          Expanded(
              child: StatTile(
                  label: 'सुटे · Loose',
                  value: kg(result.looseKg),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuantityAnalyticsScreen(
                          filter: _filter, kind: SaleTypeFilter.loose))))),
        ]),
        if (result.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: cardDecoration(context),
            child: const EmptyState('📭',
                'निवडलेल्या फिल्टरसाठी विक्री सापडली नाही.\nNo sales found for the selected filters.'),
          ),
        ] else ...[
          SectionHeader('पेमेंट विभागणी · Payment mix',
              action: const InfoTooltip(
                  'Tap to see the full payment breakdown — amounts, '
                  'transaction counts and averages per method.\n'
                  'पूर्ण पेमेंट तपशील पाहण्यासाठी टॅप करा.')),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _payModeRow(context, result, PayMode.cash, 'रोख Cash', c.s1),
              _payModeRow(context, result, PayMode.upi, 'UPI', c.s3),
              _payModeRow(context, result, PayMode.credit, 'उधार Credit', c.s2),
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PaymentMixScreen(result: result))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text('संपूर्ण तपशील पहा · View full breakdown',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: c.muted))),
                    Icon(Icons.chevron_right, size: 18, color: c.muted),
                  ]),
                ),
              ),
            ]),
          ),
          SectionHeader('टॉप उत्पादने · Top products'),
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final stat in result.products)
                _productRow(context, app, stat, result.revenue),
            ]),
          ),
          SectionHeader('💸 भाव-बदल अहवाल · Discount / override'),
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                color: c.surface2,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text('एकूण सूट दिली · Total discount',
                            style: baloo(
                                size: 13,
                                weight: FontWeight.w700,
                                color: c.ink)),
                        Text('${overrides.length} line items had edited price',
                            style: TextStyle(fontSize: 11.5, color: c.ink2)),
                      ])),
                  Text(
                      money(overrides.fold(
                          0.0, (s, o) => s + o.item.discountAmount)),
                      style: baloo(
                          size: 15, weight: FontWeight.w800, color: c.serious)),
                ]),
              ),
              if (overrides.isEmpty)
                const EmptyState('👍', 'कोणतीही किंमत बदलली नाही · No overrides')
              else
                for (final o in overrides.take(10))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(
                                '${app.productOf(o.item.productId)?.nameMr ?? ''}  #${o.bill.billNumber}',
                                style: baloo(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: c.ink)),
                            Text(
                                'कॅटलॉग ${money(o.item.catalogRate)} → भाव ${money(o.item.rate)}',
                                style:
                                    TextStyle(fontSize: 11.5, color: c.ink2)),
                          ])),
                      Text('–${money(o.item.discountAmount)}',
                          style: baloo(
                              size: 13.5,
                              weight: FontWeight.w800,
                              color: c.serious)),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
              'Every edited price stores the original catalogue rate — so this report shows exactly how much was discounted.',
              style: TextStyle(fontSize: 11.5, color: c.muted)),
        ],
      ]),
    );
  }

  /// Overridden (discounted) lines within the active filter — reuses the
  /// exact same brand/category match as [buildReport] (reviewed spec §20).
  List<({Bill bill, BillItem item})> _overriddenLines(AppState app) {
    final productsById = {for (final p in app.products) p.id: p};
    final out = <({Bill bill, BillItem item})>[];
    for (final b in app.finalBills) {
      if (!_filter.includes(b.at)) continue;
      for (final it in b.items) {
        if (!it.isPriceOverridden) continue;
        if (!productMatchesFilter(it, productsById, _filter)) continue;
        out.add((bill: b, item: it));
      }
    }
    return out;
  }

  Widget _productRow(BuildContext context, AppState app, ProductStat stat,
      double totalRevenue) {
    final c = context.c;
    final p = app.productOf(stat.productId);
    final brand = p == null ? null : app.brandOf(p.brandId);
    final pct = totalRevenue == 0 ? 0.0 : stat.revenue / totalRevenue;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              ProductHistoryScreen(productId: stat.productId, filter: _filter))),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(p?.nameMr.isNotEmpty == true ? p!.nameMr : (p?.name ?? stat.productId),
                    style:
                        baloo(size: 14, weight: FontWeight.w700, color: c.ink)),
                if (brand != null)
                  Text('${brand.nameMr} · ${brand.name}',
                      style: TextStyle(fontSize: 11.5, color: c.ink2)),
                const SizedBox(height: 3),
                Text(
                    '${stat.bags} गोणी bags · ${kg(stat.looseKg)} सुटे loose · ${pct.isNaN ? 0 : (pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11.5, color: c.muted)),
              ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(stat.revenue),
                style: baloo(size: 14.5, weight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 3),
            Icon(Icons.chevron_right, size: 18, color: c.muted),
          ]),
        ]),
      ),
    );
  }

  /// One payment-method row on the dashboard's Payment Mix card — tappable on
  /// its own, taking the user straight to that method's filtered transaction
  /// list (spec: "Payment Mix — make it fully interactive").
  Widget _payModeRow(BuildContext context, ReportResult result, PayMode mode,
      String label, Color color) {
    final c = context.c;
    final value = result.paymentTotals[mode] ?? 0;
    final pct = result.revenue == 0 ? 0.0 : value / result.revenue;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              PaymentMethodTransactionsScreen(filter: _filter, mode: mode))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${money(value)} · ${(pct * 100).toStringAsFixed(0)}%',
                style: baloo(size: 13, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: c.muted),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                  value: pct.clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: c.surface2,
                  color: color)),
        ]),
      ),
    );
  }

  Widget _filterCard(BuildContext context, AppState app) {
    final c = context.c;
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LabelWithHelp('दिनांक श्रेणी · Date Range',
            'Select the period used to calculate this report.\n'
                'या अहवालासाठी वापरला जाणारा कालावधी निवडा.'),
        const SizedBox(height: 8),
        _dateRangeDropdown(context),
        const SizedBox(height: 6),
        Text('${dayFull(_filter.start)} → ${dayFull(_filter.end)}',
            style: baloo(size: 13, weight: FontWeight.w700, color: c.ink)),
        if (app.branches.length > 1) ...[
          const SizedBox(height: 14),
          _branchDropdown(context, app),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _brandDropdown(context, app)),
          const SizedBox(width: 10),
          Expanded(child: _productDropdown(context, app)),
        ]),
        const SizedBox(height: 14),
        _saleTypeDropdown(context),
      ]),
    );
  }

  /// शाखा · Branch — only shown once there's more than one branch to filter
  /// by (spec §16). Combines (ANDs) with every other filter, same as Brand.
  Widget _branchDropdown(BuildContext context, AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LabelWithHelp('शाखा · Branch',
          'Show results for a specific branch or all branches.\n'
              'विशिष्ट शाखा किंवा सर्व शाखांचे परिणाम पहा.'),
      const SizedBox(height: 4),
      DropdownButtonFormField<String?>(
        initialValue: _filter.branchId,
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('सर्व · All Branches')),
          for (final b in app.branches)
            DropdownMenuItem(value: b.id, child: Text('${b.nameMr} · ${b.name}')),
        ],
        onChanged: (v) => setState(() =>
            _filter = _filter.copyWith(branchId: v, clearBranch: v == null)),
      ),
    ]);
  }

  /// Compact single-field dropdown replacing the old horizontally-scrolling
  /// preset chips (spec §1) — no horizontal scrolling anywhere on this
  /// screen anymore. "सानुकूल · Custom" opens the date-range picker.
  Widget _dateRangeDropdown(BuildContext context) {
    return DropdownButtonFormField<DateRangePresetKind>(
      initialValue: _filter.preset,
      isExpanded: true,
      decoration: const InputDecoration(
          prefixIcon: Icon(Icons.date_range_rounded, size: 20)),
      items: [
        for (final p in _presets)
          DropdownMenuItem(value: p.$1, child: Text('${p.$2} · ${p.$3}')),
        const DropdownMenuItem(
            value: DateRangePresetKind.custom, child: Text('सानुकूल · Custom')),
      ],
      onChanged: (kind) {
        if (kind == null) return;
        if (kind == DateRangePresetKind.custom) {
          _pickCustomRange(context);
        } else {
          setState(() => _filter = ReportFilter.preset(kind,
              brandId: _filter.brandId,
              productId: _filter.productId,
              saleType: _filter.saleType,
              branchId: _filter.branchId));
        }
      },
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _filter.start, end: _filter.end),
    );
    if (picked == null) return;
    setState(() => _filter = ReportFilter.range(picked.start, picked.end,
        brandId: _filter.brandId,
        productId: _filter.productId,
        saleType: _filter.saleType,
        branchId: _filter.branchId));
  }

  Widget _brandDropdown(BuildContext context, AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LabelWithHelp('ब्रँड · Brand',
          'Show results for a specific brand or all brands.\n'
              'विशिष्ट ब्रँड किंवा सर्व ब्रँडचे परिणाम पहा.'),
      const SizedBox(height: 4),
      DropdownButtonFormField<String?>(
        initialValue: _filter.brandId,
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('सर्व · All Brands')),
          for (final b in app.brands)
            DropdownMenuItem(value: b.id, child: Text('${b.nameMr} · ${b.name}')),
        ],
        onChanged: (v) => setState(() {
          // The selected product may not belong to the newly-picked brand —
          // reset it rather than silently keep filtering by a product the
          // user can no longer see in the Product dropdown.
          final keepProduct = v == null ||
              app.products.any((p) => p.id == _filter.productId && p.brandId == v);
          _filter = _filter.copyWith(
              brandId: v,
              clearBrand: v == null,
              clearProduct: !keepProduct);
        }),
      ),
    ]);
  }

  /// The real Product filter (not a product-type/category — see the reviewed
  /// data-model correction): populated dynamically from [AppState.products],
  /// scoped to the selected brand when one is chosen. While the catalogue is
  /// still loading this shows a disabled placeholder instead of a misleading
  /// empty "All Products" state; once loaded with genuinely zero products for
  /// the current brand it says so plainly rather than looking broken.
  Widget _productDropdown(BuildContext context, AppState app) {
    final loading = app.loading;
    final products = _filter.brandId == null
        ? app.products
        : app.products.where((p) => p.brandId == _filter.brandId).toList();
    final sorted = [...products]
      ..sort((a, b) => (a.nameMr.isNotEmpty ? a.nameMr : a.name)
          .compareTo(b.nameMr.isNotEmpty ? b.nameMr : b.name));
    final selected =
        sorted.any((p) => p.id == _filter.productId) ? _filter.productId : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LabelWithHelp('उत्पाद · Product',
          'Filter the report by a specific product.\n'
              'विशिष्ट उत्पादनानुसार अहवाल फिल्टर करा.'),
      const SizedBox(height: 4),
      DropdownButtonFormField<String?>(
        initialValue: selected,
        isExpanded: true,
        items: [
          DropdownMenuItem(
              value: null,
              child: Text(loading
                  ? 'लोड होत आहे... · Loading...'
                  : 'सर्व · All Products')),
          for (final p in sorted)
            DropdownMenuItem(
                value: p.id,
                child: Text(p.nameMr.isNotEmpty ? p.nameMr : p.name,
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: loading
            ? null
            : (v) => setState(() => _filter =
                _filter.copyWith(productId: v, clearProduct: v == null)),
      ),
      if (!loading && sorted.isEmpty) ...[
        const SizedBox(height: 4),
        Text(
            _filter.brandId == null
                ? 'कोणतीही उत्पादने सापडली नाहीत · No products found'
                : 'या ब्रँडसाठी कोणतीही उत्पादने नाहीत · No products for this brand',
            style: TextStyle(fontSize: 10.5, color: context.c.muted)),
      ],
    ]);
  }

  /// विक्री प्रकार · Sale Type — All / Bags / Loose. A separate axis from
  /// Brand/Product: affects every downstream calculation (Revenue, Bills,
  /// Bags, Loose, Payment Mix, product analytics).
  Widget _saleTypeDropdown(BuildContext context) {
    const options = [
      (SaleTypeFilter.all, 'सर्व', 'All'),
      (SaleTypeFilter.bags, 'बॅग', 'Bags'),
      (SaleTypeFilter.loose, 'सुटे', 'Loose'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LabelWithHelp('विक्री प्रकार · Sale Type',
          'Show only bag sales, only loose (by-weight) sales, or both.\n'
              'फक्त गोणी विक्री, फक्त सुटी विक्री किंवा दोन्ही दाखवा.'),
      const SizedBox(height: 4),
      DropdownButtonFormField<SaleTypeFilter>(
        initialValue: _filter.saleType,
        isExpanded: true,
        items: [
          for (final o in options)
            DropdownMenuItem(value: o.$1, child: Text('${o.$2} · ${o.$3}')),
        ],
        onChanged: (v) =>
            setState(() => _filter = _filter.copyWith(saleType: v)),
      ),
    ]);
  }

  Future<void> _export(Future<void> Function() run) async {
    try {
      await run();
    } catch (_) {
      if (mounted) {
        showToast(context, 'एक्सपोर्ट अयशस्वी · Export failed');
      }
    }
  }
}
