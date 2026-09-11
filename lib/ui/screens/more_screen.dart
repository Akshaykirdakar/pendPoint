import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../utils/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'alerts_screen.dart';
import 'catalogue_screen.dart';
import 'qr_sheet_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'settings_screen.dart';
import 'staff_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isAdmin = app.staff.any((s) =>
        s.id == FirebaseAuth.instance.currentUser?.uid &&
        s.isAdmin &&
        s.active);
    final rows = <(IconData, String, String, Widget)>[
      if (isAdmin)
        (
          Icons.sell_rounded,
          'कॅटलॉग · Catalogue',
          'Brands, products, prices',
          const CatalogueScreen()
        ),
      (
        Icons.qr_code_2_rounded,
        'QR शीट · QR sheet',
        'Print QR codes',
        const QrSheetScreen()
      ),
      (
        Icons.bar_chart_rounded,
        'अहवाल · Reports',
        'Sales, discounts, top items',
        const ReportsScreen()
      ),
      (
        Icons.notifications_rounded,
        'सूचना · Alerts',
        'Low stock & expiry',
        const AlertsScreen()
      ),
      (
        Icons.undo_rounded,
        'परतावा / रद्द · Returns & void',
        'Reverse a sale',
        const ReturnsScreen()
      ),
      (
        Icons.group_rounded,
        'कर्मचारी · Staff & PIN',
        'Roles & override rights',
        const StaffScreen()
      ),
      (
        Icons.settings_rounded,
        'सेटिंग्ज · Settings',
        'Language, backup, more',
        const SettingsScreen()
      ),
    ];
    final c = context.c;
    return PendScaffold(
      titleMr: 'अधिक',
      titleEn: 'More',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              InkWell(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => rows[i].$4)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(11)),
                        child: Icon(rows[i].$1, size: 19, color: c.brand)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(rows[i].$2,
                              style: baloo(
                                  size: 14.5,
                                  weight: FontWeight.w700,
                                  color: c.ink)),
                          Text(rows[i].$3,
                              style: TextStyle(fontSize: 12, color: c.muted)),
                        ])),
                    Icon(Icons.chevron_right, color: c.muted),
                  ]),
                ),
              ),
              if (i != rows.length - 1) Divider(height: 1, color: c.line),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        Center(
            child: Text(
                'पेंड Point · prototype v1\nData is in-memory (swap to Firebase to persist).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: c.muted))),
      ]),
    );
  }
}
