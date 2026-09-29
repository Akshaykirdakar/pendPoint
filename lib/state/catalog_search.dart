import '../models/brand.dart';
import '../models/product.dart';

/// Brand search: English or Marathi name. (Brands have no separate code in
/// this catalogue — the id is internal and never shown.)
bool brandMatches(Brand b, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return b.name.toLowerCase().contains(q) || b.nameMr.toLowerCase().contains(q);
}

/// Product search: English/Marathi name, product code (the catalogue QR
/// code, e.g. "PEND-P1" — typing "p1" finds it), category, or the brand's
/// name.
bool productMatches(Product p, Brand? brand, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return p.name.toLowerCase().contains(q) ||
      p.nameMr.toLowerCase().contains(q) ||
      p.qr.toLowerCase().contains(q) ||
      (p.category?.toLowerCase().contains(q) ?? false) ||
      (brand != null && brandMatches(brand, q));
}

List<Brand> searchBrands(Iterable<Brand> brands, String query) {
  final list = brands.where((b) => brandMatches(b, query)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Products matching [query], optionally only [brandId]'s, sorted by brand
/// then name. An empty query returns the whole (brand-filtered) list so it
/// can be shown before the user types.
List<Product> searchProducts(
  Iterable<Product> products,
  Brand? Function(String brandId) brandOf,
  String query, {
  String? brandId,
}) {
  final list = products
      .where((p) => brandId == null || p.brandId == brandId)
      .where((p) => productMatches(p, brandOf(p.brandId), query))
      .toList()
    ..sort((a, b) {
      final ba = brandOf(a.brandId)?.name ?? '';
      final bb = brandOf(b.brandId)?.name ?? '';
      final byBrand = ba.toLowerCase().compareTo(bb.toLowerCase());
      if (byBrand != 0) return byBrand;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return list;
}
