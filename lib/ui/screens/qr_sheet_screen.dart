import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/product.dart';
import '../../services/report_export_service.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

enum _PrintMode { complete, specific }

/// Printable QR grid — paste one code under each product on the shelf.
class QrSheetScreen extends StatefulWidget {
  const QrSheetScreen({super.key});
  @override
  State<QrSheetScreen> createState() => _QrSheetScreenState();
}

class _QrSheetScreenState extends State<QrSheetScreen> {
  String? _brandId;
  _PrintMode _mode = _PrintMode.complete;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final products = _brandId == null
        ? app.products
        : app.products.where((p) => p.brandId == _brandId).toList();

    return PendScaffold(
      titleMr: 'QR शीट',
      titleEn: 'QR sheet',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'छापण्यायोग्य QR कॅटलॉग · Scanning a code opens that product at the counter.',
            style: TextStyle(color: context.c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        _brandDropdown(context, app),
        const SizedBox(height: 12),
        SegmentedButton<_PrintMode>(
          segments: const [
            ButtonSegment(
                value: _PrintMode.complete,
                label: Text('संपूर्ण कॅटलॉग · Complete catalogue')),
            ButtonSegment(
                value: _PrintMode.specific,
                label: Text('निवडक · Select specific')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        if (_mode == _PrintMode.specific) ...[
          const SizedBox(height: 10),
          Text('${_selected.length} निवडले · ${_selected.length} selected',
              style: TextStyle(fontSize: 12, color: c.ink2)),
          const SizedBox(height: 2),
          Wrap(spacing: 4, children: [
            TextButton(
              onPressed: () => setState(
                  () => _selected.addAll(products.map((p) => p.id))),
              child: const Text('सर्व निवडा · Select all'),
            ),
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('साफ करा · Clear'),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        if (products.isEmpty)
          const EmptyState(
              '📭', 'या ब्रँडसाठी कोणतीही उत्पादने नाहीत · No products for this brand')
        else
          LayoutBuilder(builder: (context, constraints) {
            const spacing = 11.0;
            const cardPadding = 20.0; // Container's EdgeInsets.all(10) * 2
            final cardWidth = (constraints.maxWidth - spacing) / 2;
            // Photo and QR sit side by side inside the card — size them to
            // the card's actual width so they never overflow on narrow
            // phones instead of assuming a fixed size fits every screen.
            final iconSize =
                ((cardWidth - cardPadding - 8) / 2).clamp(40.0, 74.0);
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final p in products)
                  SizedBox(
                      width: cardWidth,
                      child: _qrCard(context, app, p, iconSize)),
              ],
            );
          }),
        const SizedBox(height: 16),
        BigButton.brand(
            _busy
                ? 'तयार करत आहे... · Preparing...'
                : _mode == _PrintMode.specific
                    ? '🖨️ निवडक छापा · Print selected (${_selected.length})'
                    : '🖨️ शीट छापा · Export sheet',
            onTap: !_busy && _canExport(products)
                ? () => _export(app, products)
                : null),
      ]),
    );
  }

  bool _canExport(List<Product> products) {
    if (products.isEmpty) return false;
    if (_mode == _PrintMode.specific) return _selected.isNotEmpty;
    return true;
  }

  Future<void> _export(AppState app, List<Product> products) async {
    final exportList = _mode == _PrintMode.specific
        ? products.where((p) => _selected.contains(p.id)).toList()
        : products;
    setState(() => _busy = true);
    final result = await ReportExportService.shareQrSheetPdf(app, exportList,
        brand: _brandId == null ? null : app.brandOf(_brandId!));
    if (mounted) {
      setState(() => _busy = false);
      showExportOutcome(context, result);
    }
  }

  Widget _brandDropdown(BuildContext context, AppState app) {
    return DropdownButtonFormField<String?>(
      initialValue: _brandId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'ब्रँड · Brand'),
      items: [
        const DropdownMenuItem(value: null, child: Text('सर्व ब्रँड · All Brands')),
        for (final b in app.brands)
          DropdownMenuItem(value: b.id, child: Text('${b.nameMr} · ${b.name}')),
      ],
      onChanged: (v) => setState(() => _brandId = v),
    );
  }

  Widget _qrCard(BuildContext context, AppState app, Product p, double iconSize) {
    final c = context.c;
    final selected = _selected.contains(p.id);
    final brand = app.brandOf(p.brandId);
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _mode == _PrintMode.specific && selected
                  ? c.brand
                  : context.c.line,
              width: _mode == _PrintMode.specific && selected ? 2 : 1)),
      padding: const EdgeInsets.all(10),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: PhotoSwatch(p, size: iconSize),
            ),
            QrImageView(data: p.qr, size: iconSize, padding: EdgeInsets.zero),
          ]),
          const SizedBox(height: 8),
          Text(p.nameMr.isEmpty ? p.name : p.nameMr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: baloo(size: 14.5, weight: FontWeight.w800, color: c.critical)),
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c.ink)),
          if (brand != null)
            Text(brand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.muted)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
                color: c.surface2, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(
                  child: _infoChip(context, Icons.inventory_2_outlined,
                      'पॅक · Pack', '${p.bagWeightKg} kg')),
              Container(width: 1, height: 26, color: c.line),
              Expanded(
                  child: _infoChip(context, Icons.sell_outlined,
                      'प्रकार · Category', p.category ?? 'सर्वसाधारण · General')),
            ]),
          ),
        ]),
        if (_mode == _PrintMode.specific)
          Positioned(
            top: -4,
            right: -4,
            child: Checkbox(
              value: selected,
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(p.id);
                } else {
                  _selected.remove(p.id);
                }
              }),
            ),
          ),
      ]),
    );
  }

  Widget _infoChip(
          BuildContext context, IconData icon, String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: context.c.muted),
          const SizedBox(width: 3),
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: context.c.muted))),
        ]),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.c.ink)),
      ]);
}
