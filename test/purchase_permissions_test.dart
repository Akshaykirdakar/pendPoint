// Purchase save vs Firestore security rules (app side). The rules
// themselves are exercised against the Firestore emulator by
// tools/rules_test (see README there); these tests pin down what the app
// SENDS and what it does when Firestore says no:
//  - the purchase commit only writes what firestore.rules allows staff to
//    write, in the shapes the rules check (status 'final', batches never
//    below zero, items under purchases/{id}/purchaseItems);
//  - purchase history loads back through the repository;
//  - a permission-denied on the number counter or on the commit leaves no
//    partial stock / batch / purchase / log in the app, and a retry works.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/data/repository.dart';
import 'package:pend_point/data/stock_commit.dart';
import 'package:pend_point/models/purchase.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';

import 'test_support.dart';

/// Looks like cloud_firestore's error for a rules rejection.
class _PermissionDenied implements Exception {
  @override
  String toString() =>
      '[cloud_firestore/permission-denied] Missing or insufficient permissions.';
}

/// Firestore refusing the stock transaction (rules not deployed / wrong role).
class _DeniedCommit extends RecordingRepository {
  bool deny = true;
  @override
  Future<void> commitStock(StockCommit commit) async {
    if (deny) throw _PermissionDenied();
    return super.commitStock(commit);
  }
}

/// Firestore refusing the meta/counters transaction (nextPurchaseNumber).
class _DeniedCounter extends RecordingRepository {
  @override
  Future<int> nextPurchaseNumber() async => throw _PermissionDenied();
}

/// Serves back what was committed, as Firestore's loadHistory would.
class _Persisting extends RecordingRepository {
  final saved = <Purchase>[];
  @override
  Future<void> commitStock(StockCommit commit) async {
    await super.commitStock(commit);
    saved.addAll(commit.newPurchases);
  }

  @override
  Future<HistorySnapshot> loadHistory() async {
    final h = await super.loadHistory();
    return HistorySnapshot(
        logs: h.logs,
        bills: h.bills,
        customers: h.customers,
        batches: h.batches,
        purchases: List.of(saved));
  }
}

List<PurchaseLineInput> _lines(String pid, {int bags = 10}) => [
      PurchaseLineInput(
          productId: pid,
          bags: bags,
          rate: 1200,
          batchNo: 'W-1',
          expiry: inDays(120))
    ];

/// Snapshot of everything a purchase touches in the app's working copy.
String _state(AppState app, String pid) => [
      app.stockOf(pid).bags,
      app.batches.where((b) => b.productId == pid).length,
      app.batches
          .where((b) => b.productId == pid)
          .fold(0, (s, b) => s + b.bagsAvailable),
      app.purchases.length,
      app.logs.where((l) => l.productId == pid).length,
    ].join('/');

void main() {
  test('purchase commit writes only rule-compatible documents', () async {
    final repo = RecordingRepository();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: _lines(pid));
    expect(res.ok, isTrue, reason: res.error);

    final c = repo.commits.single;
    // purchases/{id}: created as 'final' (the rule for create).
    final p = c.newPurchases.single;
    expect(p.toMap()['status'], 'final');
    expect(p.items, hasLength(1));
    // purchaseItems are written under the purchase (subcollection rule).
    expect(p.items.single.toMap()['bags'], 10);
    // batches/{id}: validBatch() — int bags, never below zero.
    expect(c.batches, hasLength(1));
    // (The document written is the batch after the delta is applied.)
    final batchMap = app.batchOf(c.batches.values.single.batchId)!.toMap();
    expect(batchMap['bagsAvailable'], isA<int>());
    expect(batchMap['bagsAvailable'], 10);
    expect(batchMap['looseKgAvailable'], isA<num>());
    // stock/{productId} rollup + one stockLogs entry; nothing else.
    expect(c.rollupDeltas.keys, [pid]);
    expect(c.rollupDeltas[pid]!.$1, 10);
    expect(c.logs, hasLength(1));
    expect(c.newBills, isEmpty);
    expect(c.billPatches, isEmpty);
    expect(c.purchasePatches, isEmpty);
    expect(c.ledger, isEmpty); // no khata writes from a purchase
  });

  test('purchase history loads back (purchases + their items)', () async {
    final repo = _Persisting();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: _lines(pid, bags: 7));
    expect(res.ok, isTrue, reason: res.error);

    // A fresh start (e.g. another device) reads the same history.
    await app.bootstrap();
    while (app.historyLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(app.historyError, isNull);
    expect(app.purchases.map((p) => p.id), [res.purchase!.id]);
    expect(app.purchases.single.items.single.bags, 7);
  });

  test(
      'permission-denied on the stock transaction: nothing partial, retry works',
      () async {
    final repo = _DeniedCommit();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final before = _state(app, pid);

    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: _lines(pid));
    expect(res.ok, isFalse);
    expect(res.error, contains('Permission denied'));
    expect(res.error, contains('nothing was saved'));
    expect(_state(app, pid), before, reason: 'no stock/batch/purchase/log');

    // Once Firestore accepts, one save adds the bags exactly once.
    repo.deny = false;
    final ok = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: _lines(pid));
    expect(ok.ok, isTrue, reason: ok.error);
    expect(app.stockOf(pid).bags, 10);
    expect(app.purchases, hasLength(1));
    expect(repo.commits, hasLength(1));
  });

  test('permission-denied on the purchase number: clean failure, no commit',
      () async {
    final repo = _DeniedCounter();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final before = _state(app, pid);
    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id, lines: _lines(pid));
    expect(res.ok, isFalse);
    expect(res.error, contains('Permission denied'));
    expect(repo.commits, isEmpty);
    expect(_state(app, pid), before);
  });

  test('photo uploaded before a denied commit is removed again', () async {
    final repo = _DeniedCommit();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final res = await app.savePurchase(
        supplierId: app.suppliers.first.id,
        lines: _lines(pid),
        photo: BillPhotoChange.replace(
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]), 'jpg'));
    expect(res.ok, isFalse);
    expect(repo.photos, isEmpty);
  });
}
