import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'branch_edit_screen.dart';

/// Branch Master list — "More" → Branch Master (spec §22). Each row opens
/// [BranchEditScreen]; "+ Add" creates a new one.
class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'शाखा',
      titleEn: 'Branches',
      actions: [
        BarAction('＋ शाखा · Add', icon: Icons.add_rounded,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BranchEditScreen()))),
      ],
      body: app.branches.isEmpty
          ? const EmptyState(
              '🏬', 'अजून कोणतीही शाखा नाही · No branches yet')
          : CardList([
              for (final b in app.branches)
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BranchEditScreen(branchId: b.id))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text('${b.nameMr} · ${b.name}',
                                style: baloo(
                                    size: 14.5,
                                    weight: FontWeight.w700,
                                    color: c.ink)),
                            if (b.address.isNotEmpty)
                              Text(b.address,
                                  style:
                                      TextStyle(fontSize: 12, color: c.ink2)),
                          ])),
                      if (b.id == app.activeBranchId)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: StatusPill(StockLevel.ok, label: 'सक्रिय · Active'),
                        )
                      else if (!b.active)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child:
                              StatusPill(StockLevel.out, label: 'निष्क्रिय · Inactive'),
                        ),
                      Icon(Icons.chevron_right, color: c.muted),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
