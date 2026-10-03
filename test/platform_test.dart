// Super Admin platform layer through AppState + FirestoreRepository (fake
// Firestore): global settings, live store refresh, automatic store/staff
// notifications with field-level audit, plans/payments/renewals, sending,
// reminders, announcements, read/unread, and store isolation of it all.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/platform.dart';
import 'package:pend_point/models/staff.dart';
import 'package:pend_point/models/store.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/platform_service.dart';
import 'package:pend_point/state/reminder_engine.dart';
import 'package:pend_point/ui/screens/announcements_screen.dart';
import 'package:pend_point/ui/screens/notification_screens.dart';
import 'package:pend_point/ui/screens/platform_settings_screen.dart';
import 'package:pend_point/ui/screens/send_notification_screen.dart';
import 'package:pend_point/ui/screens/store_plan_screen.dart';
import 'package:pend_point/ui/screens/super_admin_screens.dart';
import 'package:pend_point/utils/theme.dart';

import 'multistore_support.dart';

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<AppState> _login(String uid, FakeFirebaseFirestore db) async {
  signedInUid = uid;
  final app = AppState(repoFor(db));
  await app.startSession();
  while (app.historyLoading) {
    await Future<void>.delayed(Duration.zero);
  }
  await _settle();
  return app;
}

Future<List<Map<String, dynamic>>> _notes(FakeFirebaseFirestore db,
        {String? audience, String? storeId}) async =>
    [
      for (final d in (await db.collection('notifications').get()).docs)
        if ((audience == null || d.get('recipientRole') == audience) &&
            (storeId == null || d.get('storeId') == storeId))
          d.data()
    ];

void main() {
  group('global settings', () {
    test('super admin saves; store users get the general part only', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final g = await sa.platform.settings();
      g
        ..appName = 'PendPoint Pro'
        ..supportPhone = '9800000000'
        ..trialDays = 30
        ..templates[NoticeType.offer] = 'Diwali offer for {storeName}!';
      expect(await sa.platform.saveSettings(g), isNull);
      expect((await db.doc('global_settings/general').get()).get('appName'),
          'PendPoint Pro');
      expect((await db.doc('global_settings/admin').get()).get('trialDays'), 30);

      final a = await _login('adminA', db);
      final seen = await a.platform.settings(refresh: true);
      expect(seen.appName, 'PendPoint Pro');
      expect(seen.supportPhone, '9800000000');
      expect(seen.trialDays, 14, reason: 'admin part not loaded for a store admin');
      expect(seen.template(NoticeType.offer), defaultTemplates[NoticeType.offer]);
      expect(() => a.platform.saveSettings(seen), throwsA(isA<StoreContextException>()));
    });

    test('a new store starts on the configured trial', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final g = await sa.platform.settings()..trialDays = 21;
      await sa.platform.saveSettings(g);
      expect(await sa.createStore(code: 'STR009', name: 'Satara'), isNull);
      final st = (await sa.repo.loadStore('STR009'))!;
      expect(st.planStatus, PlanStatus.trial);
      expect(st.daysToExpiry(DateTime.now()), 21);
    });
  });

  group('store changes', () {
    test('rename: super admin notified with old → new; audit per field', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final st = (await sa.repo.loadStore(storeA))!;
      expect(await sa.updateStore(st.copyWith(storeName: 'Akshay Traders', phone: '9822')), isNull);
      await _settle();
      final n = (await _notes(db, audience: Audience.superAdmin))
          .singleWhere((n) => n['type'] == NoticeType.storeUpdated);
      expect(n['title'], 'Store Updated');
      expect(n['message'],
          '$storeA has been updated. Store name changed from Store $storeA to Akshay Traders; Phone changed from (none) to 9822.');
      expect((n['readBy'] as Map).containsKey('super1'), isTrue,
          reason: 'own action arrives read');
      final audits = (await db.collection('auditLogs').get()).docs
          .where((d) => d.data()['action'] == 'STORE_FIELD_CHANGED')
          .map((d) => d.data())
          .toList();
      final name = audits.singleWhere((a) => a['field'] == 'storeName');
      expect(name['oldValue'], 'Store $storeA');
      expect(name['newValue'], 'Akshay Traders');
      expect(name['userId'], 'super1');
      expect(name['storeId'], storeA);
      expect(audits.any((a) => a['field'] == 'phone'), isTrue);
    });

    test('deactivate / activate: super admin + the store\'s users told', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final st = (await sa.repo.loadStore(storeB))!;
      await sa.updateStore(st.copyWith(status: StoreStatus.inactive));
      await sa.updateStore(st.copyWith(status: StoreStatus.active));
      await _settle();
      final mine = await _notes(db, audience: Audience.superAdmin);
      expect(mine.map((n) => n['message']),
          containsAll(['Store $storeB has been deactivated.', 'Store $storeB has been activated.']));
      final theirs = await _notes(db, audience: Audience.storeAll, storeId: storeB);
      expect(theirs.map((n) => n['type']),
          containsAll([NoticeType.storeDeactivated, NoticeType.storeActivated]));
      expect(await _notes(db, storeId: storeA), isEmpty);
    });

    test('a store admin edits their store: super admin gets an unread notice', () async {
      final db = await twoStores();
      final a = await _login('adminA', db);
      final next = a.store!.copyWith(storeName: 'Akshay Traders', ownerName: 'Akshay');
      expect(await a.updateMyStore(next), isNull);
      expect(a.store!.storeName, 'Akshay Traders');
      expect((await db.doc('stores/$storeA').get()).get('storeName'), 'Akshay Traders');
      await _settle();
      final n = (await _notes(db, audience: Audience.superAdmin)).single;
      expect(n['senderUid'], 'adminA');
      expect(n['readBy'], isEmpty, reason: 'unread for the super admin');
      expect(n['message'], contains('Store name changed from Store $storeA to Akshay Traders'));
      expect(n['message'], contains('Owner name changed from (none) to Akshay'));

      final sa = await _login('super1', db);
      expect(sa.unreadNotifications, 1);
    });

    test('a store user sees their store renamed live, and is stopped when it is switched off',
        () async {
      final db = await twoStores();
      final s = await _login('staffA', db);
      expect(s.store!.storeName, 'Store $storeA');
      await db.doc('stores/$storeA').update({'storeName': 'Akshay Traders'});
      await _settle();
      expect(s.store!.storeName, 'Akshay Traders');
      await db.doc('stores/$storeA').update({'status': 'INACTIVE'});
      await _settle();
      expect(s.session, SessionState.storeInactive);
      expect(s.products, isEmpty);
    });

    test('staff added / disabled / role changed → super admin notified', () async {
      final db = await twoStores();
      final a = await _login('adminA', db);
      await a.saveStaff(const Staff(id: 'new1', name: 'Ravi', role: Roles.staff));
      final ravi = a.staff.firstWhere((s) => s.id == 'new1');
      final off = ravi.copyWith(active: false);
      await a.saveStaff(off);
      final promoted = off.copyWith(role: Roles.storeAdmin);
      await a.saveStaff(promoted);
      await a.saveStaff(promoted.copyWith(name: 'Ravi K')); // name only: no notice
      await a.saveStaff(promoted.copyWith(name: 'Ravi K', active: true));
      await _settle();
      final types = (await _notes(db, audience: Audience.superAdmin))
          .map((n) => n['type'] as String)
          .toList()
        ..sort();
      expect(types, [
        NoticeType.staffActivated,
        NoticeType.staffAdded,
        NoticeType.staffChanged,
        NoticeType.staffDisabled,
      ]);
    });
  });

  group('dashboard', () {
    testWidgets('store name updates on the dashboard without reloading', (tester) async {
      tester.view.physicalSize = const Size(720, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(twoStores))!;
      final app = (await tester.runAsync(() => _login('super1', db)))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: const SuperAdminHome())));
      await tester.pumpAndSettle();
      expect(find.text('Store $storeA'), findsOneWidget);
      await db.doc('stores/$storeA').update({'storeName': 'Akshay Traders'});
      await tester.pumpAndSettle();
      expect(find.text('Akshay Traders'), findsOneWidget);
      expect(find.text('Store $storeA'), findsNothing);
      expect(tester.takeException(), isNull, reason: '360px');
    });
  });

  testWidgets('every platform screen fits 360px and opens without errors',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(twoStores))!;
    final app = (await tester.runAsync(() => _login('super1', db)))!;
    for (final screen in <Widget>[
      const GeneralSettingsScreen(),
      const SendNotificationScreen(),
      const SentNotificationsScreen(),
      const StorePlanScreen(storeId: storeA),
      const PlansScreen(),
      const AnnouncementsScreen(),
      const AnnouncementFormScreen(),
      const NotificationCenterScreen(),
      const StoreFormScreen(),
    ]) {
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: screen)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
    }
    expect(find.byKey(const ValueKey('store-form-channel')), findsOneWidget);
  });

  group('plans and payments', () {
    test('plan change: audit, super admin and owner notified', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      await sa.platform.savePlan(const Plan(id: 'basic', name: 'Basic', durationDays: 365, price: 3000));
      await sa.platform.savePlan(const Plan(id: 'pro', name: 'Pro', durationDays: 365, price: 6000));
      final st = (await sa.repo.loadStore(storeA))!;
      final plans = await sa.platform.plans();
      expect(await sa.platform.changePlan(st, plan: plans.first, planStatus: PlanStatus.active,
          expiry: DateTime.now().add(const Duration(days: 100))), isNull);
      final after = (await sa.repo.loadStore(storeA))!;
      expect(await sa.platform.changePlan(after, plan: plans.last), isNull);
      await _settle();
      final sup = (await _notes(db, audience: Audience.superAdmin))
          .where((n) => n['type'] == NoticeType.storePlanChanged)
          .map((n) => n['message'] as String)
          .toList();
      expect(sup.any((m) => m.contains('upgraded') && m.contains('Basic → Pro')), isTrue);
      final owner = await _notes(db, audience: Audience.storeAdmin, storeId: storeA);
      expect(owner.where((n) => n['type'] == NoticeType.storePlanChanged), hasLength(2));
      final now = (await sa.repo.loadStore(storeA))!;
      expect(now.planName, 'Pro');
      expect(now.renewalAmount, 6000);
    });

    test('paid renewal extends the plan, records payment, notifies both', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final exp = DateTime.now().add(const Duration(days: 5));
      await sa.platform.changePlan((await sa.repo.loadStore(storeA))!,
          planStatus: PlanStatus.active, expiry: exp);
      final st = (await sa.repo.loadStore(storeA))!;
      expect(await sa.platform.recordPayment(st,
          amount: 3000, status: PaymentStatus.paid, method: 'UPI', transactionId: 'T1'), isNull);
      final after = (await sa.repo.loadStore(storeA))!;
      expect(after.paymentStatus, PaymentStatus.paid);
      expect(after.planExpiryDate!.difference(exp).inDays, 365, reason: 'extended from the old expiry');
      final pays = await sa.platform.payments(storeA);
      expect(pays.single.amount, 3000);
      expect(pays.single.transactionId, 'T1');
      expect(pays.single.recordedBy, 'super1');
      await _settle();
      expect((await _notes(db, audience: Audience.superAdmin)).map((n) => n['type']),
          contains(NoticeType.planRenewed));
      final owner = (await _notes(db, audience: Audience.storeAdmin, storeId: storeA))
          .where((n) => n['type'] == NoticeType.paymentConfirmation)
          .single;
      expect(owner['message'], contains('3,000'));
      expect(await _notes(db, storeId: storeB), isEmpty);

      expect(await sa.platform.recordPayment(after, amount: 500, status: PaymentStatus.failed), isNull);
      await _settle();
      expect((await _notes(db, audience: Audience.superAdmin)).map((n) => n['type']),
          contains(NoticeType.paymentFailed));
    });

    test('payment records stay in their store', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      await sa.platform.recordPayment((await sa.repo.loadStore(storeB))!,
          amount: 100, status: PaymentStatus.paid, renew: false);
      final a = await _login('adminA', db);
      expect(await a.platform.payments(storeA), isEmpty);
      expect(() => a.platform.payments(storeB), throwsA(isA<StoreContextException>()));
      final s = await _login('staffA', db);
      expect(() => s.platform.payments(storeA), throwsA(isA<StoreContextException>()));
      expect(() => s.platform.recordPayment(s.store!, amount: 1, status: 'paid'),
          throwsA(isA<StoreContextException>()));
    });
  });

  group('sending and feeds', () {
    test('owner notice: only that store\'s admin sees it; WhatsApp/SMS not pretended', () async {
      final db = await twoStores();
      await db.doc('stores/$storeA').update({'ownerPhone': '9822011223', 'notifyChannel': 'both'});
      final sa = await _login('super1', db);
      final g = await sa.platform.settings()..whatsAppEnabled = true..smsEnabled = true;
      await sa.platform.saveSettings(g);
      final stores = await sa.repo.listStores();
      final r = await sa.platform.send(
          stores: PlatformService.resolve(stores, RecipientGroup.owner,
              selected: {storeA}, now: DateTime.now()),
          type: NoticeType.paymentReminder,
          subject: 'Payment due',
          message: 'Hello {storeName}, please pay {amount}.',
          channels: {Channels.inApp, Channels.whatsApp, Channels.sms},
          audience: Audience.storeAdmin);
      expect(r.stores, 1);
      expect(r.count(Channels.inApp, ChannelStatus.delivered), 1);
      expect(r.count(Channels.whatsApp, ChannelStatus.providerRequired), 1);
      expect(r.count(Channels.sms, ChannelStatus.providerRequired), 1);
      expect(r.count(Channels.whatsApp, ChannelStatus.delivered), 0);

      final a = await _login('adminA', db);
      expect(a.notifications.single.message, 'Hello Store $storeA, please pay ₹0.');
      expect(a.notifications.single.channelStatus[Channels.sms], ChannelStatus.providerRequired);
      final s = await _login('staffA', db);
      expect(s.notifications, isEmpty, reason: 'owner-only notice');
      final b = await _login('adminB', db);
      expect(b.notifications, isEmpty, reason: 'another store');
    });

    test('read / unread and mark all read are per user', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final stores = await sa.repo.listStores();
      await sa.platform.send(
          stores: [stores.firstWhere((s) => s.id == storeA)],
          type: NoticeType.maintenance,
          subject: 'Maintenance',
          message: 'Sunday 2am',
          channels: {Channels.inApp});
      await sa.platform.send(
          stores: [stores.firstWhere((s) => s.id == storeA)],
          type: NoticeType.offer,
          subject: 'Offer',
          message: 'x',
          channels: {Channels.inApp});
      final a = await _login('adminA', db);
      final s = await _login('staffA', db);
      expect(a.unreadNotifications, 2);
      expect(s.unreadNotifications, 1, reason: 'maintenance is store-wide, the offer owner-only');
      signedInUid = 'adminA'; // (the fake login is global: act as adminA)
      await a.platform.markRead([a.notifications.first]);
      await _settle();
      expect(a.unreadNotifications, 1);
      await a.platform.markRead(a.notifications);
      await _settle();
      expect(a.unreadNotifications, 0);
      final s2 = await _login('staffA', db);
      expect(s2.unreadNotifications, 1, reason: 'staff read state is separate');
    });

    test('scheduled notices show only from their time; switched-off types are not sent', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final stores = [(await sa.repo.loadStore(storeA))!];
      final r = await sa.platform.send(
          stores: stores,
          type: NoticeType.announcement,
          subject: 'Later',
          message: 'm',
          channels: {Channels.inApp, Channels.whatsApp},
          scheduledFor: DateTime.now().add(const Duration(days: 1)));
      expect(r.count(Channels.inApp, ChannelStatus.scheduled), 1);
      expect(r.count(Channels.whatsApp, ChannelStatus.disabled), 1,
          reason: 'WhatsApp is off by default in General Settings');
      final a = await _login('adminA', db);
      expect(a.notifications, isEmpty);
    });
  });

  group('reminders', () {
    Store st(String id, int days, {bool active = true, String? status}) => Store(
        id: id,
        storeName: id,
        status: active ? StoreStatus.active : StoreStatus.inactive,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        planStatus: status ?? PlanStatus.active,
        planExpiryDate: DateTime(2026, 10, 3).add(Duration(days: days)));

    test('engine: thresholds, expiry day, after expiry; nothing for no plan / suspended', () {
      final now = DateTime(2026, 10, 3, 10);
      final g = GlobalSettings();
      final due = {
        for (final r in dueReminders([
          st('S10', 10), st('S7', 7), st('S5', 5), st('S1', 1), st('S0', 0),
          st('SM1', -1), st('SM3', -3), st('SM9', -9),
          st('OFF', 1, active: false), st('SUS', 1, status: PlanStatus.suspended),
          Store(id: 'NONE', storeName: 'x', createdAt: now, updatedAt: now),
        ], g, now))
          r.store.id: r
      };
      expect(due.keys, unorderedEquals(['S7', 'S5', 'S1', 'S0', 'SM1', 'SM3', 'SM9']));
      expect(due['S7']!.key, startsWith('before-7@'));
      expect(due['S5']!.key, startsWith('before-7@'));
      expect(due['S1']!.urgent, isTrue);
      expect(due['S0']!.type, NoticeType.planExpiry);
      expect(due['SM3']!.key, startsWith('after-1@'));
      expect(due['SM9']!.key, startsWith('after-7@'));
      expect(dueReminders([st('S1', 1)], GlobalSettings(renewalReminders: false), now), isEmpty);
    });

    test('run twice: each reminder generated once', () async {
      final db = await twoStores();
      final sa = await _login('super1', db);
      final exp = DateTime.now().add(const Duration(days: 3));
      await sa.platform.changePlan((await sa.repo.loadStore(storeA))!,
          planStatus: PlanStatus.active, expiry: exp);
      final stores = await sa.repo.listStores();
      expect(await sa.platform.runReminders(stores), 1);
      expect(await sa.platform.runReminders(await sa.repo.listStores()), 0);
      final owner = (await _notes(db, audience: Audience.storeAdmin, storeId: storeA))
          .where((n) => n['type'] == NoticeType.renewalReminder);
      expect(owner, hasLength(1));
      expect(owner.single['message'], contains('3 days'));
      expect((await db.collection('stores/$storeA/reminders').get()).size, 1);
    });
  });

  test('announcement to selected stores reaches every user there, nobody else', () async {
    final db = await twoStores();
    final sa = await _login('super1', db);
    final stores = await sa.repo.listStores();
    final n = await sa.platform.publishAnnouncement(
        Announcement(
            id: 'a1',
            title: 'New WhatsApp Billing Feature Available',
            message: 'Try it today',
            target: 'selected',
            storeIds: const [storeB],
            startAt: DateTime.now(),
            createdBy: 'super1',
            createdAt: DateTime.now()),
        stores);
    expect(n, 1);
    expect((await sa.platform.announcements()).single.deliveredTo, 1);
    final staffB = await _login('staffB', db);
    expect(staffB.notifications.single.title, 'New WhatsApp Billing Feature Available');
    final staffA = await _login('staffA', db);
    expect(staffA.notifications, isEmpty);
  });
}
