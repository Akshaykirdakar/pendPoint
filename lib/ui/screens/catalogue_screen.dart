import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'product_edit_screen.dart';

class CatalogueScreen extends StatelessWidget {
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'कॅटलॉग',
      titleEn: 'Catalogue',
      actions: [
        BarAction('＋ नवीन',
            onTap: () => _push(context, const ProductEditScreen()))
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final b in app.brands) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 20, 2, 9),
            child: Row(children: [
              Expanded(
                  child: Text('${b.name}  ',
                      style: baloo(
                          size: 15.5, weight: FontWeight.w700, color: c.ink))),
              TextButton(
                  onPressed: () =>
                      _push(context, ProductEditScreen(brandId: b.id)),
                  child: const Text('＋ उत्पादन')),
            ]),
          ),
          CardList([
            for (final p in app.products.where((p) => p.brandId == b.id))
              InkWell(
                onTap: () => _push(context, ProductEditScreen(productId: p.id)),
                child: Padding(
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
                              '${p.bagWeightKg}kg · ${money(p.fullBagPrice)} · ${money(p.perKgPrice)}/kg · min ${money(p.minPriceFloor)}',
                              style: TextStyle(fontSize: 11.5, color: c.ink2)),
                        ])),
                    Icon(Icons.chevron_right, color: c.muted),
                  ]),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        BigButton.ghost('＋ नवीन ब्रँड · Add brand',
            onTap: () => _addBrand(context, app)),
      ]),
    );
  }

  void _addBrand(BuildContext context, AppState app) {
    final mr = TextEditingController();
    final en = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.c.surface,
        title: Text('नवीन ब्रँड · New brand',
            style:
                baloo(size: 17, weight: FontWeight.w700, color: context.c.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: mr,
              decoration: const InputDecoration(labelText: 'नाव (मराठी)')),
          const SizedBox(height: 10),
          TextField(
              controller: en,
              decoration: const InputDecoration(labelText: 'Name (English)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          FilledButton(
              onPressed: () async {
                if (mr.text.trim().isEmpty && en.text.trim().isEmpty) return;
                await app.saveBrand(
                    name: en.text.trim().isEmpty
                        ? mr.text.trim()
                        : en.text.trim(),
                    nameMr: mr.text.trim().isEmpty
                        ? en.text.trim()
                        : mr.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('जतन')),
        ],
      ),
    );
  }

  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
