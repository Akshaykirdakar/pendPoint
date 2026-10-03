// Passwords: super admin / store admin change their own; super admin sets
// any store user's; a store admin sets their own store's staff's — nobody
// else's. (The server function checks the same: functions/access.js.)
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/firestore_repository.dart';
import 'package:pend_point/models/staff.dart';
import 'package:pend_point/models/store.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/ui/screens/staff_screen.dart';
import 'package:pend_point/ui/screens/super_admin_screens.dart';
import 'package:pend_point/ui/screens/super_admin_shell.dart';
import 'package:pend_point/utils/theme.dart';

import 'multistore_support.dart';

/// Records the password calls instead of reaching Firebase Auth / Functions.
class _PwRepo extends FirestoreRepository {
  _PwRepo(FakeFirebaseFirestore db)
      : super(firestore: db, currentUid: () => signedInUid);
  String currentPassword = 'old-pass';
  final List<(String, String)> setCalls = [];

  @override
  Future<void> changeOwnPassword(String current, String next) async {
    if (current != currentPassword) {
      throw StateError('[firebase_auth/invalid-credential] bad');
    }
    currentPassword = next;
  }

  @override
  Future<void> setUserPassword(String uid, String password) async =>
      setCalls.add((uid, password));
}

Future<(AppState, _PwRepo, FakeFirebaseFirestore)> _login(String uid) async {
  final db = await twoStores();
  signedInUid = uid;
  final repo = _PwRepo(db);
  final app = AppState(repo);
  await app.startSession();
  while (app.historyLoading) {
    await Future<void>.delayed(Duration.zero);
  }
  return (app, repo, db);
}

Staff _u(String id, String role, String? store) =>
    Staff(id: id, name: id, role: role, storeId: store);

void main() {
  final staffA = _u('staffA', Roles.staff, storeA);
  final adminA = _u('adminA', Roles.storeAdmin, storeA);
  final staffB = _u('staffB', Roles.staff, storeB);
  final adminB = _u('adminB', Roles.storeAdmin, storeB);
  final boss = _u('super1', Roles.superAdmin, null);

  test('who may set whose password', () async {
    final (sa, _, _) = await _login('super1');
    expect(sa.canChangeOwnPassword, isTrue);
    expect(sa.canSetPasswordFor(staffA), isTrue);
    expect(sa.canSetPasswordFor(adminB), isTrue);
    expect(sa.canSetPasswordFor(boss), isFalse, reason: 'own / super admin');

    final (a, _, _) = await _login('adminA');
    expect(a.canChangeOwnPassword, isTrue);
    expect(a.canSetPasswordFor(staffA), isTrue);
    expect(a.canSetPasswordFor(staffB), isFalse, reason: 'other store');
    expect(a.canSetPasswordFor(adminA), isFalse, reason: 'own');
    expect(a.canSetPasswordFor(_u('admin2', Roles.storeAdmin, storeA)),
        isFalse, reason: 'another admin');
    expect(a.canSetPasswordFor(boss), isFalse);

    final (s, _, _) = await _login('staffA');
    expect(s.canChangeOwnPassword, isFalse);
    expect(s.canSetPasswordFor(_u('staff2', Roles.staff, storeA)), isFalse);
  });

  test('store admin sets own staff password; refused elsewhere', () async {
    final (a, repo, _) = await _login('adminA');
    expect(await a.setPasswordFor(staffA, next: 'new-123', confirm: 'new-12'),
        contains('match'));
    expect(await a.setPasswordFor(staffA, next: '123', confirm: '123'),
        contains('6'));
    expect(repo.setCalls, isEmpty);
    expect(await a.setPasswordFor(staffA, next: 'new-123', confirm: 'new-123'),
        isNull);
    expect(repo.setCalls, [('staffA', 'new-123')]);
    expect(await a.setPasswordFor(staffB, next: 'new-123', confirm: 'new-123'),
        isNotNull);
    expect(repo.setCalls, hasLength(1), reason: 'never sent');
  });

  test('change own password: checks, wrong current, audit', () async {
    final (a, repo, db) = await _login('adminA');
    Future<String?> change(String c, String n, [String? k]) =>
        a.changeMyPassword(current: c, next: n, confirm: k ?? n);
    expect(await change('', 'new-pass'), contains('current'));
    expect(await change('old-pass', 'abc'), contains('6'));
    expect(await change('old-pass', 'new-pass', 'other'), contains('match'));
    expect(await change('old-pass', 'old-pass'), contains('differ'));
    expect(await change('nope-pass', 'new-pass'), contains('wrong'));
    expect(repo.currentPassword, 'old-pass');

    expect(await change('old-pass', 'new-pass'), isNull);
    expect(repo.currentPassword, 'new-pass');
    await Future<void>.delayed(Duration.zero);
    final audits = (await db.collection('auditLogs').get()).docs;
    final e = audits.singleWhere((d) => d.get('action') == 'PASSWORD_CHANGED');
    expect(e.get('storeId'), storeA);
    expect(e.get('userId'), 'adminA');
    expect(e.data().toString(), isNot(contains('new-pass')));
  });

  test('staff cannot change passwords here', () async {
    final (s, repo, _) = await _login('staffA');
    expect(
        await s.changeMyPassword(
            current: 'old-pass', next: 'new-pass', confirm: 'new-pass'),
        isNotNull);
    expect(repo.currentPassword, 'old-pass');
  });

  group('screens', () {
    Future<(AppState, _PwRepo)> pump(
        WidgetTester tester, String uid, Widget screen) async {
      tester.view.physicalSize = const Size(720, 2400); // 360 wide
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (app, repo, _) = (await tester.runAsync(() => _login(uid)))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: screen)));
      await tester.pumpAndSettle();
      return (app, repo);
    }

    testWidgets('store admin: key on staff only; set a password',
        (tester) async {
      final (_, repo) = await pump(tester, 'adminA', const StaffScreen());
      expect(find.byKey(const ValueKey('staff-password-staffA')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('staff-password-adminA')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('staff-password-staffA')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'abc-123');
      await tester.enterText(
          find.byKey(const ValueKey('pw-confirm')), 'abc-124');
      await tester.tap(find.byKey(const ValueKey('pw-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pw-error')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('pw-confirm')), 'abc-123');
      await tester.tap(find.byKey(const ValueKey('pw-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pw-save')), findsNothing);
      expect(repo.setCalls, [('staffA', 'abc-123')]);
    });

    testWidgets('super admin: own password and store users\' passwords',
        (tester) async {
      final (app, repo) = await pump(tester, 'super1', const SuperAdminSettingsTab());
      await tester.tap(find.byKey(const ValueKey('sa-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pw-current')), 'old-pass');
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'boss-pass');
      await tester.enterText(
          find.byKey(const ValueKey('pw-confirm')), 'boss-pass');
      await tester.tap(find.byKey(const ValueKey('pw-save')));
      await tester.pumpAndSettle();
      expect(repo.currentPassword, 'boss-pass');

      final st = (await app.repo.loadStore(storeA))!;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: StoreUsersScreen(store: st))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sa-user-password-adminA')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sa-user-password-adminA')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'admin-new');
      await tester.enterText(
          find.byKey(const ValueKey('pw-confirm')), 'admin-new');
      await tester.tap(find.byKey(const ValueKey('pw-save')));
      await tester.pumpAndSettle();
      expect(repo.setCalls, [('adminA', 'admin-new')]);
    });
  });
}
