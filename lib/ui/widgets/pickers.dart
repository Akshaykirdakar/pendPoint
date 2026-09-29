import 'package:flutter/material.dart';

import '../../models/brand.dart';
import '../../models/party.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/catalog_search.dart';
import '../../utils/formatters.dart';
import '../screens/party_edit_screen.dart';
import 'master_forms.dart';
import 'search_picker.dart';
import '../../utils/lang.dart';

/// Party search (code / name / mobile) for sales ([purchase] false) or
/// purchase ([purchase] true) entry, with "＋ New party" pre-typed with
/// whatever was searched.
Future<Party?> pickParty(BuildContext context, AppState app,
    {required bool purchase}) {
  return showSearchPicker<Party>(
    context,
    title: purchase
        ? tr('खरेदी पार्टी · Purchase party')
        : tr('विक्री पार्टी · Sales party'),
    hint: tr('कोड, नाव किंवा मोबाइल · Code, name or mobile'),
    search: (q) => [
      for (final p in searchParties(
          purchase ? app.purchaseParties : app.salesParties, q))
        PickerOption(p, p.name,
            badge: p.code,
            subtitle: [
              if (p.mobile.isNotEmpty) p.mobile,
              if (p.address.isNotEmpty) p.address,
            ].join(' · '),
            trailing: !purchase && (p.customer?.outstanding ?? 0) > 0
                ? '${L('बाकी', 'Due')} ${money(p.customer!.outstanding)}'
                : null),
    ],
    createLabel: tr('नवीन पार्टी · New'),
    onCreate: (ctx, typed) => Navigator.of(ctx).push<Party>(MaterialPageRoute(
        builder: (_) => PartyEditScreen(
            initialType: purchase ? PartyType.purchase : PartyType.sales,
            initialText: typed))),
  );
}

/// Product search (name, Marathi name, product code, brand), optionally
/// limited to one brand (null = All Brands, searches every product). Shows
/// the SELLING price and bags in stock. With [allowCreate] (and owner
/// rights — the same rule Firestore enforces) a missing product can be
/// added right from the search: "＋ नवीन उत्पादन जोडा". Products of an
/// inactive brand are left out (new sales / purchases) unless
/// [includeInactive].
Future<Product?> pickProduct(BuildContext context, AppState app,
    {String? brandId,
    String? title,
    bool allowCreate = false,
    bool includeInactive = false}) {
  final brand = brandId == null ? null : app.brandOf(brandId);
  return showSearchPicker<Product>(
    context,
    title: title ??
        (brand == null
            ? tr('उत्पादन · Product')
            : '${L('उत्पादन', 'Product')} (${brand.name})'),
    hint: tr('नाव किंवा कोड · Name or code'),
    search: (q) => [
      for (final p
          in searchProducts(app.products, app.brandOf, q, brandId: brandId))
        if (includeInactive || app.isProductSelectable(p))
          PickerOption(p, '${p.nameMr} · ${p.name}',
            subtitle: '${app.brandOf(p.brandId)?.name ?? ''} · ${p.qr} · '
                '${p.bagWeightKg}kg',
            trailing: '🛍️ ${app.stockOf(p.id).bags}'),
    ],
    createLabel: L('नवीन उत्पादन जोडा', 'Add New Product'),
    onCreate: allowCreate && app.hasOwnerRights
        ? (ctx, typed) =>
            showProductForm(ctx, app, brandId: brandId, initialName: typed)
        : null,
  );
}

/// The Brand dropdown used above product pickers — its own field, visibly
/// separate from Product. Empty means "All Brands" (no restriction); the
/// clear (×) button goes back to All Brands.
class BrandField extends StatelessWidget {
  final AppState app;
  final String? brandId;
  final ValueChanged<String?> onChanged;
  final bool allowCreate;

  /// Also offer inactive brands (filters over existing stock/history).
  final bool includeInactive;
  const BrandField(
      {required this.app,
      required this.brandId,
      required this.onChanged,
      this.allowCreate = false,
      this.includeInactive = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    final brand = brandId == null ? null : app.brandOf(brandId!);
    return PickerField(
      label: L('ब्रँड', 'Brand'),
      icon: Icons.sell_rounded,
      value: brand?.name ?? allBrandsLabel(),
      onClear: brand == null ? null : () => onChanged(null),
      onTap: () async {
        final choice = await pickBrand(context, app,
            allowCreate: allowCreate, includeInactive: includeInactive);
        if (choice != null) onChanged(choice.brand?.id);
      },
    );
  }
}

/// What the Brand picker returned: a brand, or "All Brands" ([brand] null).
/// A dismissed picker returns null instead, so callers can tell "closed"
/// from "chose All Brands".
class BrandChoice {
  final Brand? brand;
  const BrandChoice(this.brand);
  bool get isAll => brand == null;
}

/// Brand search. [allowAll] adds "All Brands" at the top (for optional
/// filters); [allowCreate] adds "＋ नवीन ब्रँड जोडा" for owners. Inactive
/// brands are hidden unless [includeInactive] (then marked "Inactive").
Future<BrandChoice?> pickBrand(BuildContext context, AppState app,
    {bool allowAll = true,
    bool allowCreate = false,
    bool includeInactive = false}) {
  int count(String id) => app.products.where((p) => p.brandId == id).length;
  return showSearchPicker<BrandChoice>(
    context,
    title: tr('ब्रँड · Brand'),
    hint: tr('ब्रँड शोधा · Search brand'),
    search: (q) => [
      if (allowAll && q.trim().isEmpty)
        PickerOption(const BrandChoice(null), allBrandsLabel(),
            trailing: L('${app.products.length} उत्पादने',
                '${app.products.length} products')),
      for (final b in searchBrands(
          includeInactive ? app.brands : app.activeBrands, q))
        PickerOption(BrandChoice(b), b.name,
            subtitle: b.active
                ? b.nameMr
                : '${b.nameMr} · ${L('निष्क्रिय', 'Inactive')}',
            trailing: L('${count(b.id)} उत्पादने', '${count(b.id)} products')),
    ],
    createLabel: L('नवीन ब्रँड जोडा', 'Add New Brand'),
    onCreate: allowCreate && app.hasOwnerRights
        ? (ctx, typed) async {
            final b = await showBrandForm(ctx, app, initialName: typed);
            return b == null ? null : BrandChoice(b);
          }
        : null,
  );
}
