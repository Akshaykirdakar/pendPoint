import '../models/platform.dart';
import '../models/store.dart';

/// A plan reminder that is due for one store.
class DueReminder {
  final Store store;

  /// Unique per store, threshold and expiry date — e.g.
  /// `before-7@2026-11-01`. Recorded in stores/{id}/reminders/{key} when
  /// sent, so it is never generated twice; a renewal (new expiry date)
  /// starts a fresh set.
  final String key;
  final String type; // renewalReminder | planExpiry | planExpired
  final int daysToExpiry;
  final bool urgent;
  const DueReminder(
      {required this.store,
      required this.key,
      required this.type,
      required this.daysToExpiry,
      this.urgent = false});
}

/// The plan reminders due on [now] (pure — no I/O; the caller claims each
/// key before sending, which makes repeats impossible).
///
///  - before expiry: the nearest configured threshold reached (7, 3, 1 days
///    by default) → renewal reminder (urgent at 1 day). If a day was missed
///    only the most urgent one is due, not every older one.
///  - on the expiry day → plan expiry notice.
///  - after expiry: the furthest threshold passed (1, 7 days by default) →
///    expired-plan notice.
///
/// Stores without an expiry date (no plan recorded), inactive or suspended
/// stores get nothing; switched-off reminder types are skipped.
List<DueReminder> dueReminders(
    Iterable<Store> stores, GlobalSettings g, DateTime now) {
  final out = <DueReminder>[];
  final before = [...g.remindBeforeDays.where((d) => d > 0)]..sort();
  final after = [...g.remindAfterDays.where((d) => d > 0)]..sort();
  for (final st in stores) {
    final days = st.daysToExpiry(now);
    if (days == null || !st.isActive || st.planStatus == PlanStatus.suspended) {
      continue;
    }
    final exp = st.planExpiryDate!;
    final stamp =
        '${exp.year}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')}';
    if (days > 0) {
      if (!g.renewalReminders) continue;
      final t = before.where((t) => days <= t).firstOrNull;
      if (t == null) continue;
      out.add(DueReminder(
          store: st,
          key: 'before-$t@$stamp',
          type: NoticeType.renewalReminder,
          daysToExpiry: days,
          urgent: t <= 1));
    } else if (days == 0) {
      if (!g.expiryReminders) continue;
      out.add(DueReminder(
          store: st,
          key: 'day0@$stamp',
          type: NoticeType.planExpiry,
          daysToExpiry: 0,
          urgent: true));
    } else {
      if (!g.expiryReminders) continue;
      final t = after.lastWhere((t) => -days >= t, orElse: () => -1);
      if (t < 0) continue;
      out.add(DueReminder(
          store: st,
          key: 'after-$t@$stamp',
          type: NoticeType.planExpired,
          daysToExpiry: days,
          urgent: true));
    }
  }
  return out;
}
