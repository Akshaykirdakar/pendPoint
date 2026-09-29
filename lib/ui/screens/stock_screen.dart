import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/pickers.dart';
import '../widgets/tiles.dart';
import 'bag_stock_screen.dart';
import 'catalogue_screen.dart';
import 'history_screen.dart';
import 'purchase_entry_screen.dart';
import 'purchases_screen.dart';
import 'stock_in_screen.dart';
import '../../utils/lang.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _lowOnly = false;
  String? _brandId; // null = All Brands

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PendScaffold(
      titleMr: 'साठा',
      titleEn: 'Inventory',
      actions: [
        BarAction('＋ खरेदी · Purchase',
            onTap: () => _push(context, const PurchaseEntryScreen()))
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TileGrid(columns: 3, gap: 8, [
          BigTile(
              icon: Icons.local_shipping_rounded,
              mr: 'खरेदी',
              en: 'Purchase',
              color: context.c.brand,
              onTap: () => _push(context, const PurchaseEntryScreen())),
          BigTile(
              key: const ValueKey('stock-bag-report'),
              icon: Icons.inventory_rounded,
              mr: 'गोणी साठा',
              en: 'Bag stock',
              color: context.c.s1,
              onTap: () => _push(context, const BagStockScreen())),
          BigTile(
              key: const ValueKey('stock-purchases'),
              icon: Icons.list_alt_rounded,
              mr: 'खरेदी यादी',
              en: 'Purchases',
              color: context.c.s2,
              onTap: () => _push(context, const PurchasesScreen())),
          BigTile(
              icon: Icons.history_rounded,
              mr: 'इतिहास',
              en: 'History',
              color: context.c.ink2,
              onTap: () => _push(context, const HistoryScreen())),
          // The existing Catalogue (More → Catalogue), one tap from Stock.
          // Owner-only, like there — brands/products/prices are owner data.
          if (app.hasOwnerRights)
            BigTile(
                key: const ValueKey('stock-catalogue'),
                icon: Icons.menu_book_rounded,
                mr: 'कॅटलॉग',
                en: 'Catalogue',
                color: context.c.s3,
                onTap: () => _push(context, const CatalogueScreen())),
        ]),
        const SizedBox(height: 12),
        BrandField(
          key: const ValueKey('stock-brand-filter'),
          app: app,
          includeInactive: true, // stock view shows every brand
          brandId: _brandId,
          onChanged: (id) => setState(() => _brandId = id),
        ),
        const SizedBox(height: 10),
        _seg(context),
        const SizedBox(height: 4),
        for (final b in app.brands)
          if (_brandId == null || b.id == _brandId)
            ..._brandBlock(context, app, b.id),
      ]),
    );
  }

  Widget _seg(BuildContext context) {
    final c = context.c;
    Widget b(String label, bool on, VoidCallback t) => Expanded(
          child: GestureDetector(
            onTap: t,
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: on ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: on
                      ? [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6)
                        ]
                      : null),
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: on ? c.brand : c.ink2)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: Row(children: [
        b(tr('सर्व · All'), !_lowOnly, () => setState(() => _lowOnly = false)),
        b(tr('कमी · Low'), _lowOnly, () => setState(() => _lowOnly = true)),
      ]),
    );
  }

  List<Widget> _brandBlock(BuildContext context, AppState app, String brandId) {
    var ps = app.products.where((p) => p.brandId == brandId).toList();
    if (_lowOnly) {
      ps = ps.where((p) => app.levelOf(p.id) != StockLevel.ok).toList();
    }
    if (ps.isEmpty) return [];
    final b = app.brandOf(brandId)!;
    return [
      SectionHeader(b.name),
      CardList([for (final p in ps) _row(context, app, p)]),
    ];
  }

  Widget _row(BuildContext context, AppState app, Product p) {
    final c = context.c;
    final s = app.stockOf(p.id);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        PhotoSwatch(p, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ProductName(p),
                const SizedBox(height: 2),
                Text(
                    '🛍️ ${s.bags} ${tr('गोणी · bags')}    ⚖️ ${kg(s.looseKg)} ${tr('सुटे · loose')}',
                    style: TextStyle(fontSize: 12, color: c.ink2)),
              ]),
        ),
        // Status + Actions stay narrow (they shrink to fit) so the product
        // name keeps its room on a 360px phone in every language.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FittedBox(
                fit: BoxFit.scaleDown, child: StatusPill(app.levelOf(p.id))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _actions(context, app, p),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.line)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(L('क्रिया ▾', 'Actions ▾'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _actions(BuildContext context, AppState app, Product p) {
    final s = app.stockOf(p.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: context.c.line,
                          borderRadius: BorderRadius.circular(9)))),
              Text(p.nameMr,
                  style: baloo(
                      size: 18, weight: FontWeight.w700, color: context.c.ink)),
              const SizedBox(height: 12),
              BigButton.brand(tr('📦 खरेदी नोंद · Purchase entry'), onTap: () {
                Navigator.pop(ctx);
                _push(context, PurchaseEntryScreen(productId: p.id));
              }),
              const SizedBox(height: 10),
              BigButton.ghost(
                  tr('➕ एकल / सुटे साठा · Single or loose stock-in'),
                  onTap: () {
                Navigator.pop(ctx);
                _push(context, StockInScreen(productId: p.id));
              }),
              const SizedBox(height: 10),
              BigButton.ghost(
                  tr('🔓 गोणी उघडा · Open a bag (+${p.bagWeightKg}kg loose)'),
                  onTap: s.bags < 1
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await app.openBag(p.id);
                          if (context.mounted) {
                            showToast(context, tr('गोणी उघडली · Opened'));
                          }
                        }),
              const SizedBox(height: 10),
              BigButton.ghost(tr('✏️ समायोजन · Adjust / write-off'), onTap: () {
                Navigator.pop(ctx);
                _adjust(context, app, p);
              }),
            ]),
      ),
    );
  }

  void _adjust(BuildContext context, AppState app, Product p) {
    final bagsCtrl = TextEditingController(text: '0');
    final kgCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text(tr('साठा समायोजन · Adjust'),
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              L('खराब / घट / दुरुस्ती. कमी करण्यासाठी वजा (−) टाका.',
                  'Damage / loss / correction. Use minus to write off.'),
              style: TextStyle(fontSize: 12, color: context.c.ink2)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: bagsCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: '${L('गोणी', 'Bags')} ±'))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: kgCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: '${L('किलो', 'Kg')} ±'))),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: noteCtrl,
              decoration: InputDecoration(labelText: tr('कारण · Reason'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L('रद्द', 'Cancel'))),
          FilledButton(
              onPressed: () async {
                final b = int.tryParse(bagsCtrl.text) ?? 0;
                final k = double.tryParse(kgCtrl.text) ?? 0;
                if (b == 0 && k == 0) {
                  Navigator.pop(ctx);
                  return;
                }
                await app.adjustStock(p.id, b, k,
                    noteCtrl.text.isEmpty ? 'adjustment' : noteCtrl.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  showToast(context, tr('साठा अद्ययावत · Stock adjusted'));
                }
              },
              child: Text(L('जतन', 'Save'))),
        ],
      ),
    );
  }

  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
