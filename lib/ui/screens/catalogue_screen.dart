import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'brand_edit_screen.dart';
import 'product_edit_screen.dart';
import '../../utils/lang.dart';

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
        BarAction('＋ नवीन · New',
            onTap: () => _push(context, const ProductEditScreen()))
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final b in app.brands) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 20, 2, 9),
            child: Row(children: [
              // Tap the brand to edit it: names, photo, active, delete.
              Expanded(
                child: InkWell(
                  key: ValueKey('catalogue-brand-${b.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _push(context, BrandEditScreen(brandId: b.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      BrandLogo(b, size: 36),
                      const SizedBox(width: 10),
                      // Name, with the Inactive tag under it (not beside
                      // it) so a 360px phone never runs out of width.
                      Flexible(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: baloo(
                                      size: 15.5,
                                      weight: FontWeight.w700,
                                      color: b.active ? c.ink : c.muted)),
                              if (!b.active)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: c.muted.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999)),
                                  child: Text(L('निष्क्रिय', 'Inactive'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: c.ink2)),
                                ),
                            ]),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined, size: 16, color: c.muted),
                    ]),
                  ),
                ),
              ),
              IconButton.filledTonal(
                  key: ValueKey('catalogue-add-product-${b.id}'),
                  tooltip: L('या ब्रँडमध्ये उत्पादन जोडा', 'Add product to this brand'),
                  onPressed: () =>
                      _push(context, ProductEditScreen(brandId: b.id)),
                  icon: const Icon(Icons.add_rounded)),
            ]),
          ),
          if (!app.products.any((p) => p.brandId == b.id))
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(L('अजून उत्पादन नाही', 'No products yet'),
                  style: TextStyle(color: c.muted, fontSize: 12.5)),
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
                              '${p.bagWeightKg}kg · ${money(p.fullBagPrice)} · ${money(p.perKgPrice)}/kg · ${L('किमान', 'min')} ${money(p.minPriceFloor)}',
                              style: TextStyle(fontSize: 11.5, color: c.ink2)),
                        ])),
                    Icon(Icons.chevron_right, color: c.muted),
                  ]),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        BigButton.ghost(tr('＋ नवीन ब्रँड · Add brand'),
            key: const ValueKey('catalogue-add-brand'),
            // Full brand form: names, optional photo, active.
            onTap: () => _push(context, const BrandEditScreen())),
      ]),
    );
  }

  static void _push(BuildContext ctx, Widget w) =>
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
}
