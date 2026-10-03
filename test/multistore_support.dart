// Two stores' worth of data in a fake Firestore, shaped exactly like what
// FirestoreRepository reads and writes — for the multi-store tests.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:pend_point/data/firestore_repository.dart';
import 'package:pend_point/models/store.dart';

const storeA = 'STR-A';
const storeB = 'STR-B';
const storeOff = 'STR-OFF';

/// The signed-in Firebase uid the repository sees (tests change it to
/// "log in" as another user).
String? signedInUid;

FirestoreRepository repoFor(FakeFirebaseFirestore db) =>
    FirestoreRepository(firestore: db, currentUid: () => signedInUid);

StoreContext ctxFor(String storeId,
        {String uid = 'staffA', String role = Roles.staff}) =>
    StoreContext(uid: uid, role: role, storeId: storeId);

Future<FakeFirebaseFirestore> twoStores() async {
  final db = FakeFirebaseFirestore();
  final now = DateTime.now().toIso8601String();
  Future<void> set(String path, Map<String, dynamic> data) =>
      db.doc(path).set(data);

  for (final (id, status) in [
    (storeA, 'ACTIVE'),
    (storeB, 'ACTIVE'),
    (storeOff, 'INACTIVE')
  ]) {
    await set('stores/$id', {
      'storeCode': id,
      'storeName': 'Store $id',
      'status': status,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': 'super1',
    });
    await set('stores/$id/meta/counters',
        {'bill': 1000, 'purchase': 0, 'draft': 1000});
    await set('stores/$id/meta/settings', {'shop': 'Shop $id', 'lang': 'both'});
  }
  await set('staff/adminA',
      {'name': 'Admin A', 'role': 'admin', 'storeId': storeA, 'active': true});
  await set('staff/staffA',
      {'name': 'Staff A', 'role': 'staff', 'storeId': storeA, 'active': true});
  await set('staff/adminB',
      {'name': 'Admin B', 'role': 'admin', 'storeId': storeB, 'active': true});
  await set('staff/staffB',
      {'name': 'Staff B', 'role': 'staff', 'storeId': storeB, 'active': true});
  await set('staff/super1',
      {'name': 'Boss', 'role': 'super_admin', 'storeId': null, 'active': true});
  await set('staff/disabledA',
      {'name': 'Gone', 'role': 'staff', 'storeId': storeA, 'active': false});
  await set('staff/offStaff',
      {'name': 'Off', 'role': 'staff', 'storeId': storeOff, 'active': true});
  await set('staff/noStore', {'name': 'Lost', 'role': 'staff', 'active': true});

  for (final s in [storeA, storeB]) {
    final x = s == storeA ? 'A' : 'B';
    await set(
        'branches/br$x', {'name': 'Branch $x', 'active': true, 'storeId': s});
    await set('brands/b$x', {'name': 'Brand $x', 'storeId': s});
    await set('suppliers/sup$x', {'name': 'Supplier $x', 'storeId': s});
    await set('products/p$x', {
      'name': 'Feed $x',
      'nameMr': 'पेंड $x',
      'brandId': 'b$x',
      'bagWeightKg': 50,
      'fullBagPrice': s == storeA ? 1000 : 2000,
      'perKgPrice': 25,
      'branchIds': ['br$x'],
      'qrCode': 'PEND-$x',
      'storeId': s,
    });
    await set('stock/p$x', {
      'productId': 'p$x',
      'bagsRemaining': 10,
      'looseKgRemaining': 0,
      'storeId': s
    });
    await set('batches/bt$x', {
      'branchId': 'br$x',
      'productId': 'p$x',
      'supplierId': 'sup$x',
      'batchNo': 'L-$x',
      'expiry': DateTime.now().add(const Duration(days: 90)).toIso8601String(),
      'unitCost': 800,
      'bagsReceived': 10,
      'bagsAvailable': 10,
      'looseKgAvailable': 0,
      'status': 'active',
      'createdAt': now,
      'updatedAt': now,
      'storeId': s,
    });
    await set('stockLogs/log$x', {
      'productId': 'p$x',
      'type': 'purchase',
      'bagsDelta': 10,
      'looseKgDelta': 0,
      'createdAt': now,
      'storeId': s
    });
    await set('bills/BILL$x', {
      'billNumber': 1000,
      'customerId': 'c$x',
      'customerName': 'Ramesh $x',
      'subtotal': 500,
      'discountTotal': 0,
      'totalAmount': 500,
      'payments': [
        {'mode': 'cash', 'amount': 500}
      ],
      'status': 'final',
      'createdAt': now,
      'storeId': s,
    });
    await set('bills/BILL$x/billItems/0', {
      'productId': 'p$x',
      'saleType': 'bag',
      'quantityOrWeight': 1,
      'rate': 500,
      'lineTotal': 500,
      'storeId': s
    });
    await set('customers/c$x', {
      'name': 'Ramesh $x',
      'mobile': '9822011223',
      'outstandingBalance': s == storeA ? 100 : 900,
      'code': '1',
      'storeId': s
    });
    await set('customers/c$x/ledgerEntries/e1',
        {'type': 'credit-sale', 'amount': 100, 'createdAt': now, 'storeId': s});
    await set('purchases/PUR$x', {
      'purchaseNumber': 1,
      'supplierId': 'sup$x',
      'totalAmount': 8000,
      'status': 'final',
      'createdAt': now,
      'storeId': s
    });
    await set('purchases/PUR$x/purchaseItems/000',
        {'productId': 'p$x', 'bags': 10, 'storeId': s});
    await set('draftBills/DRAFT$x', {
      'status': 'draft',
      'number': 1001,
      'version': 1,
      'lines': [],
      'payments': [],
      'createdAt': now,
      'updatedAt': now,
      'storeId': s
    });
  }
  return db;
}
