import 'customer.dart';
import 'supplier.dart';

/// What a party is used for. Sales parties are [Customer]s (khata), purchase
/// parties are [Supplier]s; a party that is both has one record in each
/// collection sharing the same document id.
enum PartyType { sales, purchase, both }

extension PartyTypeX on PartyType {
  bool get isSales => this != PartyType.purchase;
  bool get isPurchase => this != PartyType.sales;

  String get label => switch (this) {
        PartyType.sales => 'विक्री · Sales',
        PartyType.purchase => 'खरेदी · Purchase',
        PartyType.both => 'दोन्ही · Both',
      };
}

/// The Party Master's unified, read-only view over [Customer] (sales) and
/// [Supplier] (purchase) records. It is not stored on its own — customers
/// keep their khata ledger and suppliers keep their batch history exactly
/// where they were; this just lets the counter find either kind by code,
/// name or mobile number in one place.
class Party {
  final String id;
  final Customer? customer;
  final Supplier? supplier;

  const Party({required this.id, this.customer, this.supplier})
      : assert(customer != null || supplier != null);

  PartyType get type => customer != null && supplier != null
      ? PartyType.both
      : (customer != null ? PartyType.sales : PartyType.purchase);

  String get code => _firstNonEmpty(customer?.code, supplier?.code);
  String get name => _firstNonEmpty(customer?.name, supplier?.name);
  String get mobile => _firstNonEmpty(customer?.mobile, supplier?.mobile);
  String get address => _firstNonEmpty(customer?.address, supplier?.address);

  /// Inactive only when it is purely a supplier that was deactivated.
  bool get active => customer != null || (supplier?.active ?? true);

  static String _firstNonEmpty(String? a, String? b) =>
      (a != null && a.isNotEmpty) ? a : (b ?? '');

  /// Combines customers and suppliers into parties — records that share an
  /// id are the same party ([PartyType.both]).
  static List<Party> combine(
      List<Customer> customers, List<Supplier> suppliers) {
    final byId = {for (final s in suppliers) s.id: s};
    final out = <Party>[];
    for (final c in customers) {
      out.add(Party(id: c.id, customer: c, supplier: byId.remove(c.id)));
    }
    for (final s in byId.values) {
      out.add(Party(id: s.id, supplier: s));
    }
    return out;
  }
}

/// Digits only — "98220 11223" and "+91-9822011223" both search as digits.
String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// How well [party] matches the search text [query]; null when it doesn't
/// match at all. Lower is better: exact code, code prefix, mobile, name
/// prefix, then name/address substring — so typing "12" puts party code 12
/// above a party whose mobile happens to contain 12.
int? partyMatchRank(Party party, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 5;
  final code = party.code.toLowerCase();
  if (code.isNotEmpty && code == q) return 0;
  if (code.isNotEmpty && code.startsWith(q)) return 1;
  final qDigits = digitsOnly(q);
  // Only treat the query as a phone search when it is mostly digits, so a
  // code like "A1" doesn't match every mobile containing a 1.
  if (qDigits.length >= 3 && qDigits.length == q.replaceAll(' ', '').length) {
    if (digitsOnly(party.mobile).contains(qDigits)) return 2;
  }
  final name = party.name.toLowerCase();
  if (name.startsWith(q)) return 3;
  if (name.contains(q)) return 4;
  if (code.contains(q)) return 4;
  return null;
}

/// Parties matching [query] (code / name / mobile), best matches first and
/// then alphabetically. An empty query returns every party — the list is
/// shown before the user types anything.
List<Party> searchParties(Iterable<Party> parties, String query) {
  final ranked = <(Party, int)>[];
  for (final p in parties) {
    final r = partyMatchRank(p, query);
    if (r != null) ranked.add((p, r));
  }
  ranked.sort((a, b) {
    final byRank = a.$2.compareTo(b.$2);
    if (byRank != 0) return byRank;
    return a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
  });
  return [for (final r in ranked) r.$1];
}
