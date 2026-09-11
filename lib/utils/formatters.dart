import 'package:intl/intl.dart';

final _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dayFmt = DateFormat('dd MMM');
final _timeFmt = DateFormat('hh:mm a');

/// ₹1,450 (Indian grouping).
String money(num n) => _money.format(n.round());

/// "12 kg" / "12.5 kg" (drops trailing .0).
String kg(num n) {
  final r = (n * 10).round() / 10;
  final s =
      r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return '$s kg';
}

String qtyLabel(bool isBag, double qty) => isBag ? '${qty.round()}' : kg(qty);

String dateTimeShort(DateTime d) =>
    '${_dayFmt.format(d)} ${_timeFmt.format(d)}';
String dayShort(DateTime d) => _dayFmt.format(d);
String weekdayShort(DateTime d) => DateFormat('EEE').format(d).substring(0, 2);
