import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'supplier_edit_screen.dart';
import '../../utils/lang.dart';

/// Supplier Master list (spec §2 READ: list, search, active/inactive filter).
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

enum _ActiveFilter { all, active, inactive }

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _search = TextEditingController();
  _ActiveFilter _filter = _ActiveFilter.active;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final q = _search.text.trim().toLowerCase();
    final list = app.suppliers.where((s) {
      if (_filter == _ActiveFilter.active && !s.active) return false;
      if (_filter == _ActiveFilter.inactive && s.active) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || s.mobile.contains(q);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return PendScaffold(
      titleMr: 'पुरवठादार',
      titleEn: 'Suppliers',
      actions: [
        BarAction(tr('＋ पुरवठादार · Add'), icon: Icons.add_rounded,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SupplierEditScreen()))),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            hintText: tr('शोधा · Search name or mobile'),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final f in _ActiveFilter.values) ...[
            ChoiceChip(
              label: Text(switch (f) {
                _ActiveFilter.all => tr('सर्व · All'),
                _ActiveFilter.active => tr('सक्रिय · Active'),
                _ActiveFilter.inactive => tr('निष्क्रिय · Inactive'),
              }),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState('🚚', tr('कोणतेही पुरवठादार सापडले नाहीत · No suppliers found'))
        else
          CardList([
            for (final s in list)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SupplierEditScreen(supplierId: s.id))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(s.name,
                              style: baloo(
                                  size: 14.5,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          if (s.mobile.isNotEmpty)
                            Text(s.mobile,
                                style: TextStyle(fontSize: 12, color: c.ink2)),
                        ])),
                    if (!s.active)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: c.muted.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(tr('निष्क्रिय · Inactive'),
                              style: TextStyle(fontSize: 10.5, color: c.muted)),
                        ),
                      ),
                    Icon(Icons.chevron_right, color: c.muted),
                  ]),
                ),
              ),
          ]),
      ]),
    );
  }
}
