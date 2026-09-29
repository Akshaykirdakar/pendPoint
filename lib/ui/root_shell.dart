import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../utils/lang.dart';
import '../utils/theme.dart';
import 'screens/home_screen.dart';
import 'screens/khata_screen.dart';
import 'screens/more_screen.dart';
import 'screens/sell_screen.dart';
import 'screens/stock_screen.dart';

/// Bottom-tab shell: मुख्य / विक्री / साठा / खाते / अधिक.
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  static const _pages = [
    HomeScreen(),
    SellScreen(),
    StockScreen(),
    KhataScreen(),
    MoreScreen()
  ];

  static const _tabs = [
    (icon: Icons.home_rounded, mr: 'मुख्य', en: 'Home'),
    (icon: Icons.point_of_sale_rounded, mr: 'विक्री', en: 'Sell'),
    (icon: Icons.inventory_2_rounded, mr: 'साठा', en: 'Stock'),
    (icon: Icons.menu_book_rounded, mr: 'खाते', en: 'Credit'),
    (icon: Icons.apps_rounded, mr: 'अधिक', en: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            color: c.surface, border: Border(top: BorderSide(color: c.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final on = i == _tab;
                final t = _tabs[i];
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _tab = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // Selected tab: filled pill behind a big icon.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                              color: on
                                  ? c.brand.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999)),
                          child: Icon(t.icon,
                              size: 27, color: on ? c.brand : c.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(appLang == AppLang.en ? t.en : t.mr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    on ? FontWeight.w800 : FontWeight.w600,
                                color: on ? c.brand : c.muted)),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
