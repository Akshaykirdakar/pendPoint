import 'dart:typed_data';

/// One row typed into Purchase Entry. Blank rows (the always-present "next
/// empty row" at the bottom of the grid) are ignored when saving.
class PurchaseLineInput {
  final String? productId;
  final int bags;
  final double rate; // PURCHASE rate per bag (not the selling price)
  final String batchNo;
  final DateTime? expiry;
  final DateTime? manufactureDate;

  const PurchaseLineInput({
    this.productId,
    this.bags = 0,
    this.rate = 0,
    this.batchNo = '',
    this.expiry,
    this.manufactureDate,
  });

  bool get isBlank =>
      productId == null && bags == 0 && rate == 0 && batchNo.trim().isEmpty;

  double get amount => bags * rate;
}

/// What saving a purchase does with its supplier-bill photo: keep what the
/// purchase already has (nothing, for a new one), use a new photo, or drop
/// it. The photo is optional — a purchase saves the same without one.
class BillPhotoChange {
  final Uint8List? bytes;
  final String extension;
  final bool remove;
  const BillPhotoChange.keep()
      : bytes = null,
        extension = '',
        remove = false;
  const BillPhotoChange.replace(this.bytes, this.extension)
      : remove = false;
  const BillPhotoChange.remove()
      : bytes = null,
        extension = '',
        remove = true;
}

/// Subtotal / other charges / grand total for a purchase, shared by the
/// entry screen's running total and [AppState.savePurchase] so the two can
/// never disagree.
class PurchaseTotals {
  final double subtotal;
  final double otherCharges;
  final int bags;
  const PurchaseTotals(this.subtotal, this.otherCharges, this.bags);

  double get grandTotal => subtotal + otherCharges;

  factory PurchaseTotals.of(Iterable<PurchaseLineInput> lines,
      {double otherCharges = 0}) {
    var subtotal = 0.0;
    var bags = 0;
    for (final l in lines) {
      if (l.isBlank) continue;
      subtotal += l.amount;
      bags += l.bags;
    }
    return PurchaseTotals(subtotal, otherCharges, bags);
  }
}
