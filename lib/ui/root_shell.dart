import 'package:flutter/material.dart';

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
    (icon: Icons.home_rounded, mr: 'मुख्य'),
    (icon: Icons.receipt_long_rounded, mr: 'विक्री'),
    (icon: Icons.inventory_2_rounded, mr: 'साठा'),
    (icon: Icons.menu_book_rounded, mr: 'खाते'),
    (icon: Icons.more_horiz_rounded, mr: 'अधिक'),
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
                        Icon(t.icon, size: 22, color: on ? c.brand : c.muted),
                        const SizedBox(height: 2),
                        Text(t.mr,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
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
