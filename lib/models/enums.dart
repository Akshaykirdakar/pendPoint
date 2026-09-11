/// Shared enums for पेंड Point.
library;

/// How a line is sold: a full sealed bag, or loose by weight (kg).
enum SaleType { bag, kg }

extension SaleTypeX on SaleType {
  String get id => this == SaleType.bag ? 'bag' : 'kg';
  static SaleType fromId(String? v) => v == 'kg' ? SaleType.kg : SaleType.bag;
}

/// How a bill was paid. Credit == उधार / khata.
enum PayMode { cash, upi, credit }

extension PayModeX on PayMode {
  String get id => name;
  static PayMode fromId(String? v) =>
      PayMode.values.firstWhere((m) => m.name == v, orElse: () => PayMode.cash);
}

/// A stock movement's reason.
enum StockLogType { purchase, sale, adjustment, bagOpened, saleVoid, returned }

extension StockLogTypeX on StockLogType {
  String get id {
    switch (this) {
      case StockLogType.bagOpened:
        return 'bag-opened';
      case StockLogType.saleVoid:
        return 'sale-void';
      case StockLogType.returned:
        return 'return';
      default:
        return name;
    }
  }

  static StockLogType fromId(String? v) {
    switch (v) {
      case 'bag-opened':
        return StockLogType.bagOpened;
      case 'sale-void':
        return StockLogType.saleVoid;
      case 'return':
        return StockLogType.returned;
      case 'purchase':
        return StockLogType.purchase;
      case 'adjustment':
        return StockLogType.adjustment;
      default:
        return StockLogType.sale;
    }
  }
}

enum BillStatus { finalized, voided }

extension BillStatusX on BillStatus {
  String get id => this == BillStatus.voided ? 'void' : 'final';
  static BillStatus fromId(String? v) =>
      v == 'void' ? BillStatus.voided : BillStatus.finalized;
}

/// Stock health used for pills and alerts (measured on TOTAL kg, not bags alone).
enum StockLevel { ok, low, out }
