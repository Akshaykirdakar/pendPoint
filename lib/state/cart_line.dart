import '../models/enums.dart';

/// A working line in the current (not-yet-finalized) bill.
class CartLine {
  final String productId;
  final SaleType saleType;
  double qty; // bags (int-valued) or kg
  final double catalogRate; // catalogue price captured when the line was added
  double rate; // current charged price (may be overridden)

  CartLine({
    required this.productId,
    required this.saleType,
    required this.qty,
    required this.catalogRate,
    required this.rate,
  });

  bool get isBag => saleType == SaleType.bag;
  bool get isOverridden => rate != catalogRate;
  double get lineTotal => rate * qty;
  double get step => isBag ? 1 : 0.5;
}
