// Optional supplier-bill photo on a purchase: stored in (Storage via) the
// repository, referenced from the purchase — never inside it — and shown
// on Purchase Detail only when there is one.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/data/memory_repository.dart';
import 'package:pend_point/data/stock_commit.dart';
import 'package:pend_point/models/purchase.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/ui/screens/purchase_detail_screen.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

// A real 1×1 PNG, so Image.memory can decode it.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
final _png2 = Uint8List.fromList([..._png]);

/// Rejects every stock commit — the purchase is never saved.
class _Rejecting extends InMemoryRepository {
  @override
  Future<void> commitStock(StockCommit commit) async =>
      throw const StockCommitException('conflict');
}

Future<PurchaseResult> _buy(AppState app, String pid,
        {BillPhotoChange photo = const BillPhotoChange.keep(),
        String? editing}) =>
    app.savePurchase(
        supplierId: app.suppliers.first.id,
        editingPurchaseId: editing,
        lines: [
          PurchaseLineInput(
              productId: pid,
              bags: 4,
              rate: 900,
              batchNo: 'PH',
              expiry: inDays(90))
        ],
        photo: photo);

void main() {
  test('17: a purchase saves exactly as before without a photo', () async {
    final app = await bootedApp();
    final pid = await freshProduct(app);
    final res = await _buy(app, pid);
    expect(res.ok, isTrue, reason: res.error);
    expect(res.purchase!.hasBillPhoto, isFalse);
    expect(res.purchase!.billPhotoUrl, isNull);
    expect(res.purchase!.toMap()['billPhotoPath'], isNull);
    expect(app.stockOf(pid).bags, 4);
  });

  test(
      '18: with a photo — uploaded under purchase-bills/{id}/, only a ref stored',
      () async {
    final repo = InMemoryRepository();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final res =
        await _buy(app, pid, photo: BillPhotoChange.replace(_png, 'png'));
    expect(res.ok, isTrue, reason: res.error);
    final p = res.purchase!;
    expect(p.hasBillPhoto, isTrue);
    expect(p.billPhotoPath, startsWith('purchase-bills/${p.id}/'));
    expect(p.billPhotoPath, endsWith('.png'));
    // The document holds the reference, not the image bytes.
    final doc = p.toMap();
    expect(doc['billPhotoPath'], p.billPhotoPath);
    expect(doc.values.whereType<Uint8List>(), isEmpty);
    expect(await app.purchaseBillPhoto(p), _png);
    // Round-trips through the stored map.
    final back = Purchase.fromMap(p.id, doc, p.items);
    expect(back.billPhotoPath, p.billPhotoPath);
    expect(back.billPhotoUrl, p.billPhotoUrl);
  });

  test(
      '19+20: edit keeps, replaces or removes the photo; history keeps its own',
      () async {
    final repo = InMemoryRepository();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final first =
        (await _buy(app, pid, photo: BillPhotoChange.replace(_png, 'jpg')))
            .purchase!;

    // Edit without touching the photo → carried forward.
    final kept = (await _buy(app, pid, editing: first.id)).purchase!;
    expect(kept.billPhotoPath, first.billPhotoPath);

    // Replace → a NEW file; the older revision still points at its own.
    final replaced = (await _buy(app, pid,
            editing: kept.id, photo: BillPhotoChange.replace(_png2, 'jpg')))
        .purchase!;
    expect(replaced.billPhotoPath, isNot(first.billPhotoPath));
    expect(
        replaced.billPhotoPath, startsWith('purchase-bills/${replaced.id}/'));
    expect(app.purchaseOf(first.id)!.billPhotoPath, first.billPhotoPath);
    expect(repo.photos.containsKey(first.billPhotoPath), isTrue);

    // Remove → the new revision has none; stock is unaffected throughout.
    final removed = (await _buy(app, pid,
            editing: replaced.id, photo: const BillPhotoChange.remove()))
        .purchase!;
    expect(removed.hasBillPhoto, isFalse);
    expect(await app.purchaseBillPhoto(removed), isNull);
    expect(app.stockOf(pid).bags, 4);
  });

  test('a failed save removes the photo it just uploaded', () async {
    final repo = _Rejecting();
    final app = await bootedApp(repo);
    final pid = await freshProduct(app);
    final res =
        await _buy(app, pid, photo: BillPhotoChange.replace(_png, 'png'));
    expect(res.ok, isFalse);
    expect(repo.photos, isEmpty);
  });

  group('screens', () {
    Future<AppState> pump(
        WidgetTester tester, Widget home, AppState app) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: home)));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('21: detail shows "View Bill Photo" only when there is one',
        (tester) async {
      final app = (await tester.runAsync(bootedApp))!;
      final pid = (await tester.runAsync(() => freshProduct(app)))!;
      final plain = (await tester.runAsync(() => _buy(app, pid)))!.purchase!;
      final withPhoto = (await tester.runAsync(() =>
              _buy(app, pid, photo: BillPhotoChange.replace(_png, 'png'))))!
          .purchase!;

      await pump(tester, PurchaseDetailScreen(purchaseId: plain.id), app);
      expect(find.byKey(const ValueKey('purchase-view-photo')), findsNothing);
      expect(find.byType(Image), findsNothing); // no broken placeholder

      await pump(tester, PurchaseDetailScreen(purchaseId: withPhoto.id), app);
      await tester.tap(find.byKey(const ValueKey('purchase-view-photo')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('purchase-photo-image')), findsOneWidget);
      // The storage path is never shown to the user.
      expect(find.textContaining('purchase-bills/'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'entry: pick → preview → replace → remove, saved with the purchase',
        (tester) async {
      final app = (await tester.runAsync(bootedApp))!;
      final picks = <ImageSource>[];
      PurchaseEntryScreen.debugPickPhoto = (src) async {
        picks.add(src);
        return (bytes: picks.length == 1 ? _png : _png2, name: 'bill.png');
      };
      addTearDown(() => PurchaseEntryScreen.debugPickPhoto = null);
      await pump(tester, const PurchaseEntryScreen(productId: 'p1'), app);

      expect(
          find.byKey(const ValueKey('purchase-photo-preview')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('purchase-photo-camera')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('purchase-photo-preview')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('purchase-photo-gallery')));
      await tester.pumpAndSettle();
      expect(picks, [ImageSource.camera, ImageSource.gallery]);

      await tester.tap(find.byKey(const ValueKey('purchase-photo-remove')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('purchase-photo-preview')), findsNothing);

      // Pick again, fill the purchase and save: the photo goes with it.
      await tester.tap(find.byKey(const ValueKey('purchase-photo-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-party')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-option-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('purchase-row-0-bags')), '2');
      await tester.enterText(
          find.byKey(const ValueKey('purchase-row-0-rate')), '900');
      await tester.enterText(
          find.byKey(const ValueKey('purchase-row-0-batch')), 'PH-1');
      await tester.tap(find.text('निवडा · Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-save')));
      await tester.pumpAndSettle();
      expect(app.purchases, hasLength(1));
      expect(app.purchases.single.hasBillPhoto, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
