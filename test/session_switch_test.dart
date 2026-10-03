// One AppState lives for the whole app (sign-out → sign-in reuses it), so a
// store's data must never land in the next session: a slow store load that
// finishes after sign-out / "All stores" / opening another store is
// dropped, and a brand-new store still gets its own Main Branch. Also: the
// draft audit trail.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/firestore_repository.dart';
import 'package:pend_point/data/repository.dart' show CoreSnapshot;
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';

import 'multistore_support.dart';

/// Answers a store load only on [release] — like a slow phone connection:
/// the query runs for the store open at the time, the answer comes late.
class _SlowRepo extends FirestoreRepository {
  _SlowRepo(FakeFirebaseFirestore db)
      : super(firestore: db, currentUid: () => signedInUid);
  Completer<void>? gate;
  void hold() => gate = Completer<void>();

  @override
  Future<CoreSnapshot> loadCore() async {
    final g = gate;
    final answer = await super.loadCore();
    if (g != null) await g.future;
    return answer;
  }
}

Future<void> _settle(AppState app) async {
  for (var i = 0; i < 50 && (app.historyLoading || app.loading); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a slow store load finishing after sign-out is dropped', () async {
    final db = await twoStores();
    final repo = _SlowRepo(db)..hold();
    signedInUid = 'staffA';
    final app = AppState(repo);
    final session = app.startSession();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20 && app.storeId == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(app.storeId, storeA);

    app.clearSession(); // signed out while Store A was still loading
    repo.gate!.complete();
    await session;
    expect(app.session, SessionState.none);
    expect(app.products, isEmpty);
    expect(app.stock, isEmpty);
    expect(app.settings.shop, isNot('Shop $storeA'));
  });

  test('super admin: Store A still loading, Store B opened → only B shows',
      () async {
    final db = await twoStores();
    final repo = _SlowRepo(db);
    signedInUid = 'super1';
    final app = AppState(repo);
    await app.startSession();
    expect(app.session, SessionState.superAdmin);

    repo.hold();
    final gateA = repo.gate!;
    final openA = app.openStore((await repo.loadStore(storeA))!);
    await Future<void>.delayed(Duration.zero);
    repo.gate = null; // Store B answers at once
    await app.openStore((await repo.loadStore(storeB))!);
    await _settle(app);
    expect(app.products.map((p) => p.id), ['pB']);

    // Store A's late answer arrives now — and must not replace B's data.
    gateA.complete();
    await openA;
    await _settle(app);
    expect(app.storeId, storeB);
    expect(app.products.map((p) => p.id), ['pB']);
    expect(app.settings.shop, 'Shop $storeB');

    // "All stores" while a store is still loading: nothing of it shows.
    repo.hold();
    final gateB = repo.gate!;
    final reopen = app.openStore((await repo.loadStore(storeB))!);
    await Future<void>.delayed(Duration.zero);
    app.closeStore();
    gateB.complete();
    await reopen;
    expect(app.session, SessionState.superAdmin);
    expect(app.products, isEmpty);
    expect(app.storeId, isNull);
  });

  test('a new store gets its Main Branch even after another store was open',
      () async {
    final db = await twoStores();
    final now = DateTime.now().toIso8601String();
    await db.doc('stores/STR-C').set({
      'storeCode': 'STR-C',
      'storeName': 'Store C',
      'status': 'ACTIVE',
      'createdAt': now,
      'updatedAt': now,
    });
    await db.doc('stores/STR-C/meta/counters')
        .set({'bill': 1000, 'purchase': 0, 'draft': 1000});
    await db.doc('stores/STR-C/meta/settings').set({'shop': 'Shop C'});
    await db.doc('staff/adminC').set(
        {'name': 'Admin C', 'role': 'admin', 'storeId': 'STR-C', 'active': true});

    final app = AppState(repoFor(db));
    signedInUid = 'staffA';
    await app.startSession();
    await _settle(app);
    expect(app.branches.map((b) => b.id), ['brA']);

    // Same app, next person: a brand-new store with no branch yet.
    app.clearSession(); // what the auth gate does on sign-out
    signedInUid = 'adminC';
    await app.startSession();
    await _settle(app);
    expect(app.storeId, 'STR-C');
    expect(app.branches, hasLength(1));
    expect(app.activeBranchId, app.branches.single.id);
    final saved = await db.doc('branches/${app.branches.single.id}').get();
    expect(saved.get('storeId'), 'STR-C');
  });

  test('drafts are audited once when created and when deleted', () async {
    final db = await twoStores();
    signedInUid = 'staffA';
    final app = AppState(repoFor(db));
    await app.startSession();
    await _settle(app);

    app.addToCart('pA', SaleType.bag, 1);
    final d = (await app.saveDraft()).draft!;
    app.addToCart('pA', SaleType.bag, 1);
    expect((await app.saveDraft()).ok, isTrue); // an update: not audited
    expect(await app.deleteDraft(d.id), isNull);
    await Future<void>.delayed(Duration.zero);

    final audits = (await db.collection('auditLogs').get()).docs;
    final draftAudits = audits.where((a) => a.get('entityType') == 'DRAFT');
    expect(draftAudits.map((a) => a.get('action')),
        unorderedEquals(['DRAFT_CREATED', 'DRAFT_DELETED']));
    for (final a in draftAudits) {
      expect(a.get('storeId'), storeA);
      expect(a.get('userId'), 'staffA');
      expect(a.get('entityId'), d.id);
    }
  });
}
