import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/party.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'party_edit_screen.dart';
import '../../utils/lang.dart';

/// Party Master — every sales party (customer) and purchase party
/// (supplier) in one searchable list: by code, name or mobile.
class PartyMasterScreen extends StatefulWidget {
  const PartyMasterScreen({super.key});
  @override
  State<PartyMasterScreen> createState() => _PartyMasterScreenState();
}

enum _TypeFilter { all, sales, purchase, both }

class _PartyMasterScreenState extends State<PartyMasterScreen> {
  final _search = TextEditingController();
  _TypeFilter _filter = _TypeFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final list = searchParties(
        app.parties.where((p) => switch (_filter) {
              _TypeFilter.all => true,
              _TypeFilter.sales => p.type.isSales,
              _TypeFilter.purchase => p.type.isPurchase,
              _TypeFilter.both => p.type == PartyType.both,
            }),
        _search.text);

    return PendScaffold(
      titleMr: 'पार्टी मास्टर',
      titleEn: 'Party Master',
      actions: [
        BarAction(tr('＋ पार्टी · Add'),
            icon: Icons.person_add_alt_1_rounded,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PartyEditScreen()))),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const ValueKey('party-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            hintText: tr('कोड, नाव किंवा मोबाइल · Code, name or mobile'),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final f in _TypeFilter.values)
            ChoiceChip(
              label: Text(switch (f) {
                _TypeFilter.all => tr('सर्व · All'),
                _TypeFilter.sales => tr('विक्री · Sales'),
                _TypeFilter.purchase => tr('खरेदी · Purchase'),
                _TypeFilter.both => tr('दोन्ही · Both'),
              }),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
        ]),
        const SizedBox(height: 12),
        if (app.historyLoading && app.customers.isEmpty)
          const HistoryLoadingNote()
        else if (list.isEmpty)
          EmptyState('👥', tr('पार्टी सापडली नाही · No party found'))
        else
          CardList([
            for (final p in list)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PartyEditScreen(partyId: p.id))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: c.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(p.code.isEmpty ? '—' : p.code,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: c.brand)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(p.name,
                              style: baloo(
                                  size: 14.5,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          Text(
                              [
                                if (p.mobile.isNotEmpty) p.mobile,
                                if (!p.active) tr('निष्क्रिय · Inactive'),
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: c.ink2)),
                        ])),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _TypePill(p.type),
                          if ((p.customer?.outstanding ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                  '${L('बाकी', 'Due')} ${money(p.customer!.outstanding)}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: c.serious)),
                            ),
                        ]),
                  ]),
                ),
              ),
          ]),
      ]),
    );
  }
}

class _TypePill extends StatelessWidget {
  final PartyType type;
  const _TypePill(this.type);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (type) {
      PartyType.sales => c.good,
      PartyType.purchase => c.s1,
      PartyType.both => c.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(tr(type.label),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
