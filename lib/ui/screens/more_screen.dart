import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/tiles.dart';
import 'alerts_screen.dart';
import 'bag_stock_screen.dart';
import 'batch_report_screen.dart';
import 'catalogue_screen.dart';
import 'party_master_screen.dart';
import 'purchases_screen.dart';
import 'qr_sheet_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'settings_screen.dart';
import 'staff_screen.dart';
import 'suppliers_screen.dart';
import '../../utils/lang.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isAdmin = app.staff.any((s) =>
        s.id == app.repo.currentUserId &&
        s.isAdmin &&
        s.active);
    final rows = <(IconData, String, String, Widget)>[
      (
        Icons.groups_rounded,
        tr('पार्टी मास्टर · Party Master'),
        'Sales & purchase parties — code, name, mobile',
        const PartyMasterScreen()
      ),
      (
        Icons.receipt_long_rounded,
        tr('बिले · Bills'),
        'Edit, return or void a saved bill',
        const ReturnsScreen()
      ),
      (
        Icons.local_shipping_rounded,
        tr('खरेदी · Purchases'),
        'Purchase bills — new, edit, void',
        const PurchasesScreen()
      ),
      (
        Icons.inventory_rounded,
        tr('गोणी साठा · Bag stock'),
        'Daily stock by product & brand (bags)',
        const BagStockScreen()
      ),
      if (isAdmin)
        (
          Icons.sell_rounded,
          tr('कॅटलॉग · Catalogue'),
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
        tr('अहवाल · Reports'),
        'Sales, discounts, top items',
        const ReportsScreen()
      ),
      if (isAdmin)
        (
          Icons.local_shipping_rounded,
          tr('पुरवठादार · Suppliers'),
          'Supplier master & purchase history',
          const SuppliersScreen()
        ),
      (
        Icons.notifications_rounded,
        tr('सूचना · Alerts'),
        'Low stock & expiry',
        const AlertsScreen()
      ),
      (
        Icons.inventory_2_rounded,
        tr('बॅच व एक्सपायरी · Batch & Expiry'),
        'Batch-wise stock, expiry report',
        const BatchReportScreen()
      ),
      (
        Icons.group_rounded,
        tr('कर्मचारी · Staff & PIN'),
        'Roles & override rights',
        const StaffScreen()
      ),
      (
        Icons.settings_rounded,
        tr('सेटिंग्ज · Settings'),
        'Language, backup, more',
        const SettingsScreen()
      ),
    ];
    final c = context.c;
    final palette = [c.brand, c.accent, c.s1, c.s2, c.s3, c.serious, c.ink2];
    return PendScaffold(
      titleMr: 'अधिक',
      titleEn: 'More',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // One big picture per feature — title words only, no small print.
        TileGrid([
          for (var i = 0; i < rows.length; i++)
            BigTile(
              icon: rows[i].$1,
              mr: rows[i].$2.split(' · ').first,
              en: rows[i].$2.split(' · ').last,
              color: palette[i % palette.length],
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => rows[i].$4)),
            ),
        ]),
      ]),
    );
  }
}
