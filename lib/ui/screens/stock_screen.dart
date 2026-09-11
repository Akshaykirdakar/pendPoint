import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'history_screen.dart';
import 'stock_in_screen.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PendScaffold(
      titleMr: 'साठा',
      titleEn: 'Inventory',
      actions: [
        BarAction('＋ भरा', onTap: () => _push(context, const StockInScreen()))
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _seg(context),
        const SizedBox(height: 4),
        for (final b in app.brands) ..._brandBlock(context, app, b.id),
        const SizedBox(height: 16),
        BigButton.ghost('🕓 साठा इतिहास · Stock history log',
            onTap: () => _push(context, const HistoryScreen())),
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
        b('सर्व All', !_lowOnly, () => setState(() => _lowOnly = false)),
        b('कमी Low', _lowOnly, () => setState(() => _lowOnly = true)),
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
                    '${s.bags} bags · ${kg(s.looseKg)} loose · ${kg(app.effKg(p.id))} total',
                    style: TextStyle(fontSize: 12, color: c.ink2)),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StatusPill(app.levelOf(p.id)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _actions(context, app, p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.line)),
              child: Text('क्रिया ▾',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink)),
            ),
          ),
        ]),
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
              BigButton.brand('📦 साठा भरा · Stock in', onTap: () {
                Navigator.pop(ctx);
                _push(context, StockInScreen(productId: p.id));
              }),
              const SizedBox(height: 10),
              BigButton.ghost(
                  '🔓 गोणी उघडा · Open a bag (+${p.bagWeightKg}kg loose)',
                  onTap: s.bags < 1
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await app.openBag(p.id);
                          if (context.mounted) {
                            showToast(context, 'गोणी उघडली · Opened');
                          }
                        }),
              const SizedBox(height: 10),
              BigButton.ghost('✏️ समायोजन · Adjust / write-off', onTap: () {
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
        title: Text('साठा समायोजन · Adjust',
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Damage / loss / correction. Use minus to write off.',
              style: TextStyle(fontSize: 12, color: context.c.ink2)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: bagsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'गोणी ±'))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: kgCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'किलो ±'))),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'कारण · Reason')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
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
                  showToast(context, 'साठा अद्ययावत · Stock adjusted');
                }
              },
              child: const Text('जतन')),
        ],
      ),
    );
  }

  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
