import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/platform.dart';
import '../models/store.dart';

/// Which notifications a feed shows. Built by the app from the signed-in
/// user's StoreContext — never from user input:
///  - super admin:   audiences [super_admin]                (no storeId)
///  - store admin:   storeId = own store, audiences [all, admin]
///  - staff:         storeId = own store, audiences [all]
///  - super admin "sent": audiences [admin, all]            (no storeId)
class NotificationQuery {
  final String? storeId;
  final List<String> audiences;
  final int limit;
  const NotificationQuery(
      {this.storeId, required this.audiences, this.limit = 100});
}

/// Super Admin platform data: live store documents, global settings,
/// plans, store payments, notifications, announcements and the reminder
/// log. Separate from [Repository] (the store's own business data) so the
/// POS code is untouched. Firestore rules decide who may do what.
abstract class PlatformRepository {
  Stream<List<Store>> watchStores();
  Stream<Store?> watchStore(String storeId);

  /// Changes only [fields] of stores/{storeId} (a store admin may change
  /// only name/contact fields — see [Store.ownerEditable]).
  Future<void> updateStoreFields(String storeId, Map<String, dynamic> fields);

  /// The general part for everyone; with [admin] also the super admin part.
  Future<GlobalSettings> loadSettings({required bool admin});
  Future<void> saveSettings(GlobalSettings settings);

  Future<List<Plan>> listPlans();
  Future<void> savePlan(Plan plan);

  Future<void> addPayment(String storeId, StorePayment payment);
  Future<List<StorePayment>> listPayments(String storeId);

  Future<void> addNotifications(List<AppNotification> notifications);
  Stream<List<AppNotification>> watchNotifications(NotificationQuery q);
  Future<void> markRead(List<String> ids, String uid);

  Future<void> saveAnnouncement(Announcement a);
  Future<List<Announcement>> listAnnouncements({int limit = 50});

  /// Records reminder [key] of [storeId] as sent. False if it already was
  /// (so the same reminder is never generated twice, on any device).
  Future<bool> claimReminder(
      String storeId, String key, Map<String, dynamic> info);

  /// A new unique document id.
  String newId();
}

class FirestorePlatformRepository implements PlatformRepository {
  final FirebaseFirestore db;
  FirestorePlatformRepository(this.db);

  CollectionReference<Map<String, dynamic>> get _notes =>
      db.collection('notifications');

  @override
  String newId() => db.collection('notifications').doc().id;

  @override
  Stream<List<Store>> watchStores() => db.collection('stores').snapshots().map(
      (s) => [for (final d in s.docs) Store.fromMap(d.id, d.data())]
        ..sort((a, b) => a.id.compareTo(b.id)));

  @override
  Stream<Store?> watchStore(String storeId) =>
      db.collection('stores').doc(storeId).snapshots().map(
          (d) => d.exists ? Store.fromMap(d.id, d.data()!) : null);

  @override
  Future<void> updateStoreFields(String storeId, Map<String, dynamic> fields) =>
      db.collection('stores').doc(storeId).update(fields);

  @override
  Future<GlobalSettings> loadSettings({required bool admin}) async {
    final g = await db.doc('global_settings/general').get();
    final a = admin ? await db.doc('global_settings/admin').get() : null;
    return GlobalSettings.fromMaps(g.data(), a?.data());
  }

  @override
  Future<void> saveSettings(GlobalSettings s) async {
    final b = db.batch();
    b.set(db.doc('global_settings/general'), s.generalMap());
    b.set(db.doc('global_settings/admin'), s.adminMap());
    await b.commit();
  }

  @override
  Future<List<Plan>> listPlans() async {
    final snap = await db.collection('plans').get();
    return [for (final d in snap.docs) Plan.fromMap(d.id, d.data())]
      ..sort((a, b) => a.price.compareTo(b.price));
  }

  @override
  Future<void> savePlan(Plan plan) =>
      db.collection('plans').doc(plan.id).set(plan.toMap());

  @override
  Future<void> addPayment(String storeId, StorePayment p) => db
      .collection('stores')
      .doc(storeId)
      .collection('payments')
      .doc(p.id)
      .set(p.toMap());

  @override
  Future<List<StorePayment>> listPayments(String storeId) async {
    final snap = await db
        .collection('stores')
        .doc(storeId)
        .collection('payments')
        .orderBy('paymentDate', descending: true)
        .get();
    return [for (final d in snap.docs) StorePayment.fromMap(d.id, d.data())];
  }

  @override
  Future<void> addNotifications(List<AppNotification> list) async {
    for (var i = 0; i < list.length; i += 400) {
      final b = db.batch();
      for (final n in list.skip(i).take(400)) {
        b.set(_notes.doc(n.id), n.toMap());
      }
      await b.commit();
    }
  }

  @override
  Stream<List<AppNotification>> watchNotifications(NotificationQuery q) {
    Query<Map<String, dynamic>> query = _notes;
    if (q.storeId != null) query = query.where('storeId', isEqualTo: q.storeId);
    query = q.audiences.length == 1
        ? query.where('recipientRole', isEqualTo: q.audiences.single)
        : query.where('recipientRole', whereIn: q.audiences);
    return query
        .orderBy('createdAt', descending: true)
        .limit(q.limit)
        .snapshots()
        .map((s) => [
              for (final d in s.docs) AppNotification.fromMap(d.id, d.data())
            ]);
  }

  @override
  Future<void> markRead(List<String> ids, String uid) async {
    if (ids.isEmpty) return;
    final at = DateTime.now().toIso8601String();
    for (var i = 0; i < ids.length; i += 400) {
      final b = db.batch();
      for (final id in ids.skip(i).take(400)) {
        b.update(_notes.doc(id), {'readBy.$uid': at});
      }
      await b.commit();
    }
  }

  @override
  Future<void> saveAnnouncement(Announcement a) =>
      db.collection('platformAnnouncements').doc(a.id).set(a.toMap());

  @override
  Future<List<Announcement>> listAnnouncements({int limit = 50}) async {
    final snap = await db
        .collection('platformAnnouncements')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return [for (final d in snap.docs) Announcement.fromMap(d.id, d.data())];
  }

  @override
  Future<bool> claimReminder(
      String storeId, String key, Map<String, dynamic> info) {
    final ref =
        db.collection('stores').doc(storeId).collection('reminders').doc(key);
    return db.runTransaction<bool>((tx) async {
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, info);
      return true;
    });
  }
}

/// The same, kept in memory (demo mode and tests).
class InMemoryPlatformRepository implements PlatformRepository {
  /// The store map shared with the in-memory business repository.
  final Map<String, Store> stores;
  InMemoryPlatformRepository(this.stores);

  Map<String, dynamic>? general;
  Map<String, dynamic>? admin;
  final Map<String, Plan> plans = {};
  final Map<String, List<StorePayment>> payments = {};
  final Map<String, AppNotification> notifications = {};
  final List<Announcement> announcements = [];
  final Map<String, Map<String, dynamic>> reminders = {};
  final _changed = StreamController<void>.broadcast();
  int _ids = 0;

  void _touch() => _changed.add(null);

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changed.stream) {
      yield read();
    }
  }

  @override
  String newId() => 'n${++_ids}';

  @override
  Stream<List<Store>> watchStores() => _live(
      () => stores.values.toList()..sort((a, b) => a.id.compareTo(b.id)));

  @override
  Stream<Store?> watchStore(String storeId) => _live(() => stores[storeId]);

  /// Call after changing [stores] directly so live views update.
  void storesChanged() => _touch();

  @override
  Future<void> updateStoreFields(
      String storeId, Map<String, dynamic> fields) async {
    final st = stores[storeId];
    if (st == null) throw StateError('No store $storeId');
    stores[storeId] = Store.fromMap(storeId, {...st.toMap(), ...fields});
    _touch();
  }

  @override
  Future<GlobalSettings> loadSettings({required bool admin}) async =>
      GlobalSettings.fromMaps(general, admin ? this.admin : null);

  @override
  Future<void> saveSettings(GlobalSettings s) async {
    general = s.generalMap();
    admin = s.adminMap();
  }

  @override
  Future<List<Plan>> listPlans() async =>
      plans.values.toList()..sort((a, b) => a.price.compareTo(b.price));

  @override
  Future<void> savePlan(Plan plan) async => plans[plan.id] = plan;

  @override
  Future<void> addPayment(String storeId, StorePayment p) async =>
      (payments[storeId] ??= []).add(p);

  @override
  Future<List<StorePayment>> listPayments(String storeId) async =>
      [...?payments[storeId]]
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

  @override
  Future<void> addNotifications(List<AppNotification> list) async {
    for (final n in list) {
      notifications[n.id] = n;
    }
    _touch();
  }

  List<AppNotification> _query(NotificationQuery q) => [
        for (final n in notifications.values)
          if (q.audiences.contains(n.audience) &&
              (q.storeId == null || n.storeId == q.storeId))
            n
      ]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<List<AppNotification>> watchNotifications(NotificationQuery q) =>
      _live(() => _query(q).take(q.limit).toList());

  @override
  Future<void> markRead(List<String> ids, String uid) async {
    final at = DateTime.now().toIso8601String();
    for (final id in ids) {
      final n = notifications[id];
      if (n == null) continue;
      notifications[id] = AppNotification.fromMap(id, {
        ...n.toMap(),
        'readBy': {...n.readBy, uid: at},
      });
    }
    _touch();
  }

  @override
  Future<void> saveAnnouncement(Announcement a) async {
    announcements.removeWhere((x) => x.id == a.id);
    announcements.add(a);
  }

  @override
  Future<List<Announcement>> listAnnouncements({int limit = 50}) async =>
      (announcements.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          .take(limit)
          .toList();

  @override
  Future<bool> claimReminder(
      String storeId, String key, Map<String, dynamic> info) async {
    final k = '$storeId/$key';
    if (reminders.containsKey(k)) return false;
    reminders[k] = info;
    return true;
  }
}
