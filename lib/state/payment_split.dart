import '../models/bill.dart';
import '../models/enums.dart';

/// Split-payment arithmetic for Checkout — the shopkeeper types one amount
/// and the rest is worked out, so the rows always add up to the bill.
///
/// All sums are done in whole paise (int) and converted back to rupees at
/// the end, so ₹1,800 stays exactly ₹1,800 (never ₹1,799.999). Nothing here
/// touches khata/credit rules — it only decides the amounts on the rows.
///
/// The "absorber" row takes whatever is left over: the first row, or — when
/// the first row is the one being typed in — the last row. The row the user
/// is typing in keeps exactly what they typed (capped at the bill total).
class PaymentSplit {
  PaymentSplit._();

  static int paise(double rupees) => (rupees * 100).round();
  static double rupees(int paise) => paise / 100;

  static int _sum(Iterable<Payment> ps) =>
      ps.fold(0, (s, p) => s + paise(p.amount));

  /// Total entered across all rows (rupees, exact to the paisa).
  static double entered(List<Payment> ps) => rupees(_sum(ps));

  /// Amount still to allocate (0 when complete or over).
  static double remaining(List<Payment> ps, double due) {
    final r = paise(due) - _sum(ps);
    return r > 0 ? rupees(r) : 0;
  }

  /// Amount over the bill total (0 when not over).
  static double excess(List<Payment> ps, double due) {
    final r = _sum(ps) - paise(due);
    return r > 0 ? rupees(r) : 0;
  }

  static bool isComplete(List<Payment> ps, double due) =>
      _sum(ps) == paise(due);

  /// Modes not used by any row except [exceptIndex] — the choices offered
  /// in a row's dropdown, so the same mode never appears twice.
  static List<PayMode> freeModes(List<Payment> ps, {int? exceptIndex}) => [
        for (final m in PayMode.values)
          if (!ps.indexed.any((e) => e.$1 != exceptIndex && e.$2.mode == m)) m
      ];

  /// Row [edited] was set to [amount]; returns the rebalanced rows. The
  /// edited row keeps its value (capped to 0…due); the absorber row takes
  /// what is left; if the other rows alone would push the total over the
  /// bill, they are reduced from the last one up, so the total never
  /// exceeds [due].
  static List<Payment> setAmount(
      List<Payment> ps, double due, int edited, double amount) {
    final d = paise(due);
    final rows = [for (final p in ps) paise(p.amount)];
    rows[edited] = paise(amount).clamp(0, d < 0 ? 0 : d);
    if (ps.length > 1) {
      final absorber = edited == 0 ? ps.length - 1 : 0;
      var left = d - rows[edited];
      // Fixed rows (neither edited nor absorber) keep their value while it
      // fits, trimmed from the last one when it doesn't.
      final fixed = [
        for (var i = 0; i < rows.length; i++)
          if (i != edited && i != absorber) i
      ];
      var fixedSum = fixed.fold(0, (s, i) => s + rows[i]);
      for (final i in fixed.reversed) {
        if (fixedSum <= left) break;
        final cut = (fixedSum - left).clamp(0, rows[i]);
        rows[i] -= cut;
        fixedSum -= cut;
      }
      left -= fixedSum;
      rows[absorber] = left < 0 ? 0 : left;
    }
    return [
      for (var i = 0; i < ps.length; i++) Payment(ps[i].mode, rupees(rows[i]))
    ];
  }

  /// Adds a row with the next unused mode, pre-filled with whatever is still
  /// unallocated (often ₹0 — then typing into it rebalances the first row).
  /// Returns [ps] unchanged when every mode is already in use.
  static List<Payment> addRow(List<Payment> ps, double due) {
    final free = freeModes(ps);
    if (free.isEmpty) return ps;
    // Prefer credit/UPI for the split — the first row is usually cash.
    final mode = free.contains(PayMode.credit)
        ? PayMode.credit
        : free.contains(PayMode.upi)
            ? PayMode.upi
            : free.first;
    final left = paise(due) - _sum(ps);
    return [...ps, Payment(mode, rupees(left > 0 ? left : 0))];
  }

  /// Removes row [i]; the freed amount goes back to the absorber (first)
  /// row, so e.g. Cash ₹1,300 + Credit ₹500 → remove Credit → Cash ₹1,800.
  static List<Payment> removeRow(List<Payment> ps, double due, int i) {
    if (ps.length <= 1) return ps;
    final rest = [...ps]..removeAt(i);
    return fit(rest, due);
  }

  /// Changes row [i]'s mode. Picking a mode another row already has merges
  /// the two rows into one (Cash ₹500 + Cash ₹300 → Cash ₹800).
  static List<Payment> setMode(
      List<Payment> ps, double due, int i, PayMode mode) {
    final rows = [...ps];
    rows[i] = Payment(mode, rows[i].amount);
    return fit(normalize(rows), due);
  }

  /// Merges rows that share a mode, keeping the first row's position.
  static List<Payment> normalize(List<Payment> ps) {
    final order = <PayMode>[];
    final sums = <PayMode, int>{};
    for (final p in ps) {
      if (!sums.containsKey(p.mode)) order.add(p.mode);
      sums[p.mode] = (sums[p.mode] ?? 0) + paise(p.amount);
    }
    return [for (final m in order) Payment(m, rupees(sums[m]!))];
  }

  /// Makes existing rows add up to [due] (e.g. an edited bill whose total
  /// changed): every row but the first keeps its amount while it fits, and
  /// the first row takes the rest.
  static List<Payment> fit(List<Payment> ps, double due) {
    if (ps.isEmpty) return [Payment(PayMode.cash, rupees(paise(due)))];
    final rows = normalize(ps);
    if (rows.length == 1) return [Payment(rows.first.mode, rupees(paise(due)))];
    // Re-use setAmount with the LAST row as the "edited" one so the first
    // row absorbs; clamp the last row first if it alone exceeds the total.
    final last = rows.length - 1;
    return setAmount(rows, due, last, rows[last].amount);
  }
}
