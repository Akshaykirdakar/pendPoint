import '../models/brand.dart';
import '../models/product.dart';
import '../models/stock.dart';
import 'catalog_search.dart';

/// One row of the daily bag stock view: product, its brand, full bags on
/// hand. Deliberately bag-only — loose kg from opened bags is not part of
/// this report (it is still tracked, sold and shown everywhere else).
class BagStockRow {
  final Product product;
  final Brand? brand;
  final int bags;
  const BagStockRow(this.product, this.brand, this.bags);
}

/// Builds the bag stock report, grouped Brand → Product, from the per-
/// product stock rollup (which is itself the sum of every batch's bags).
List<BagStockRow> bagStockReport({
  required List<Product> products,
  required Brand? Function(String brandId) brandOf,
  required Stock Function(String productId) stockOf,
  String query = '',
  String? brandId,
  bool inStockOnly = false,
}) {
  final rows = <BagStockRow>[];
  for (final p in searchProducts(products, brandOf, query, brandId: brandId)) {
    final bags = stockOf(p.id).bags;
    if (inStockOnly && bags <= 0) continue;
    rows.add(BagStockRow(p, brandOf(p.brandId), bags));
  }
  return rows;
}

int totalBags(Iterable<BagStockRow> rows) =>
    rows.fold(0, (s, r) => s + (r.bags > 0 ? r.bags : 0));
