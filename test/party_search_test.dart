// Party Master: search by code / name / mobile, sales vs purchase parties,
// and "both" parties sharing one id across customers + suppliers.
import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/models/customer.dart';
import 'package:pend_point/models/party.dart';
import 'package:pend_point/models/supplier.dart';

import 'test_support.dart';

List<Party> _parties() => Party.combine([
      Customer(
          id: 'c1', code: '1', name: 'Ramesh Patil', mobile: '98220 11223'),
      Customer(
          id: 'c2', code: '12', name: 'Sunil Jadhav', mobile: '90280 44556'),
      Customer(
          id: 'x1', code: '7', name: 'Ganesh Traders', mobile: '77001 12000'),
    ], [
      Supplier(
          id: 's1',
          code: '21',
          name: 'ABC Traders',
          mobile: '+91 98765-43210',
          createdAt: DateTime(2024)),
      Supplier(
          id: 'x1',
          code: '7',
          name: 'Ganesh Traders',
          mobile: '77001 12000',
          createdAt: DateTime(2024)),
    ]);

void main() {
  test('Party search by code — exact code ranks first', () {
    final r = searchParties(_parties(), '12');
    expect(r.first.name, 'Sunil Jadhav'); // code 12, not a mobile containing 12
    expect(searchParties(_parties(), '21').first.name, 'ABC Traders');
  });

  test('Party search by name (case-insensitive, partial)', () {
    final r = searchParties(_parties(), 'patil');
    expect(r.map((p) => p.name), ['Ramesh Patil']);
    expect(searchParties(_parties(), 'trad').map((p) => p.name),
        containsAll(['ABC Traders', 'Ganesh Traders']));
  });

  test('Party search by mobile ignores spaces, dashes and +91', () {
    expect(searchParties(_parties(), '9822011').single.name, 'Ramesh Patil');
    expect(searchParties(_parties(), '98765 432').single.name, 'ABC Traders');
    expect(searchParties(_parties(), '44556').single.name, 'Sunil Jadhav');
  });

  test('Empty search lists every party (shown before typing)', () {
    expect(searchParties(_parties(), '').length, 4);
  });

  test('Same id in customers and suppliers is one "both" party', () {
    final both = _parties().firstWhere((p) => p.id == 'x1');
    expect(both.type, PartyType.both);
    expect(_parties().firstWhere((p) => p.id == 'c1').type, PartyType.sales);
    expect(_parties().firstWhere((p) => p.id == 's1').type, PartyType.purchase);
  });

  test('AppState: sales vs purchase party lists, codes, saveParty(both)',
      () async {
    final app = await bootedApp();
    final sales = app.salesParties.length;
    final purchase = app.purchaseParties.length;

    final code = app.nextPartyCode();
    final p = await app.saveParty(
        name: 'Shinde Agro',
        code: code,
        mobile: '99999 88888',
        type: PartyType.both);
    expect(p.type, PartyType.both);
    expect(app.customers.any((c) => c.id == p.id), isTrue);
    expect(app.suppliers.any((s) => s.id == p.id), isTrue);
    expect(app.salesParties.length, sales + 1);
    expect(app.purchaseParties.length, purchase + 1);
    expect(app.partyCodeTaken(code), isTrue);
    expect(app.partyCodeTaken(code, exceptId: p.id), isFalse);
    expect(int.parse(app.nextPartyCode()), int.parse(code) + 1);

    // Found in both pickers by code / name / mobile.
    expect(searchParties(app.salesParties, code).first.id, p.id);
    expect(searchParties(app.purchaseParties, 'shinde').first.id, p.id);
    expect(searchParties(app.purchaseParties, '9999988').first.id, p.id);

    // Customers created through khata get the next code automatically.
    final c = await app.saveCustomer(name: 'Walk In Farmer');
    expect(c.code, isNotEmpty);
  });
}
