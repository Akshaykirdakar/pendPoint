import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'कर्मचारी',
      titleEn: 'Staff & PIN',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'कर्मचारी व भाव-बदल अधिकार · Staff logins and who may discount below catalogue price.',
            style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        CardList([
          for (final s in app.staff)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: s.isAdmin
                            ? c.brand.withValues(alpha: 0.16)
                            : c.surface2,
                        borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: Text(s.isAdmin ? '👑' : '🧑‍💼',
                        style: const TextStyle(fontSize: 20))),
                const SizedBox(width: 12),
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
                      Text(
                          s.isAdmin
                              ? 'मालक · Admin — full rights'
                              : 'स्टाफ · Staff — max ${s.maxDiscountPct.round()}% discount',
                          style: TextStyle(fontSize: 12, color: c.ink2)),
                    ])),
              ]),
            ),
        ]),
        SectionHeader('भाव-बदल संरक्षण · Override guard'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(
                'Staff need Owner PIN to discount beyond their limit, and no price can go below the product\'s floor.',
                style: TextStyle(fontSize: 12.5, color: c.ink2)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PIN मागा · Require PIN for large discounts',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              value: app.settings.gateOverride,
              activeThumbColor: c.brand,
              onChanged: (v) => app.updateSettings((s) => s.gateOverride = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('किमान भाव लागू · Enforce price floor',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              value: app.settings.floorOn,
              activeThumbColor: c.brand,
              onChanged: (v) => app.updateSettings((s) => s.floorOn = v),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
            'Demo PINs — Owner 1234, Staff 1111. In production: Firebase Auth + hashed PINs, never stored in plaintext.',
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }
}
