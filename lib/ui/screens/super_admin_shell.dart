import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/platform.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../widgets/password_dialogs.dart';
import 'announcements_screen.dart';
import 'notification_screens.dart';
import 'platform_settings_screen.dart';
import 'send_notification_screen.dart';
import 'store_plan_screen.dart';
import 'super_admin_screens.dart';

/// 👑 Super Admin bottom tabs: Dashboard · Stores · Notifications · Plans ·
/// Settings (same look as the store app's tabs).
class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});
  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  int _tab = 0;

  static const _pages = [
    SuperAdminHome(),
    SuperAdminHome(storesTab: true),
    SuperAdminNotificationsTab(),
    SuperAdminPlansTab(),
    SuperAdminSettingsTab(),
  ];

  static const _tabs = [
    (
      icon: Icons.dashboard_rounded,
      mr: 'डॅशबोर्ड',
      en: 'Dashboard',
      key: 'sa-tab-dashboard'
    ),
    (
      icon: Icons.storefront_rounded,
      mr: 'दुकाने',
      en: 'Stores',
      key: 'sa-tab-stores'
    ),
    (
      icon: Icons.notifications_rounded,
      mr: 'सूचना',
      en: 'Alerts',
      key: 'sa-tab-notifications'
    ),
    (
      icon: Icons.workspace_premium_rounded,
      mr: 'प्लॅन',
      en: 'Plans',
      key: 'sa-tab-plans'
    ),
    (
      icon: Icons.settings_rounded,
      mr: 'सेटिंग्ज',
      en: 'Settings',
      key: 'sa-tab-settings'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final unread = context.watch<AppState>().unreadNotifications;
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
                final icon =
                    Icon(t.icon, size: 27, color: on ? c.brand : c.muted);
                return Expanded(
                  child: InkWell(
                    key: ValueKey(t.key),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _tab = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                              color: on
                                  ? c.brand.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999)),
                          child: i == 2 && unread > 0
                              ? Badge(
                                  key: const ValueKey('sa-tab-unread'),
                                  label: Text('$unread'),
                                  child: icon)
                              : icon,
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

Future<void> _push(BuildContext context, Widget w) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

/// 📨 Notifications tab: send / sent / announcements, then the inbox.
class SuperAdminNotificationsTab extends StatelessWidget {
  const SuperAdminNotificationsTab({super.key});
  @override
  Widget build(BuildContext context) => const NotificationCenterScreen(
        header: [
          (
            label: '📤 सूचना पाठवा · Send notification',
            key: 'sa-send',
            screen: SendNotificationScreen()
          ),
          (
            label: '📜 पाठवलेल्या सूचना · Sent notifications',
            key: 'sa-sent',
            screen: SentNotificationsScreen()
          ),
          (
            label: '📢 घोषणा · Announcements',
            key: 'sa-announcements',
            screen: AnnouncementsScreen()
          ),
        ],
      );
}

/// 💳 Plans tab: every store's plan (live), plan list, reminders.
class SuperAdminPlansTab extends StatefulWidget {
  const SuperAdminPlansTab({super.key});
  @override
  State<SuperAdminPlansTab> createState() => _SuperAdminPlansTabState();
}

class _SuperAdminPlansTabState extends State<SuperAdminPlansTab> {
  late final Stream<List<Store>> _stores =
      context.read<AppState>().repo.platform.watchStores();
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'प्लॅन',
      titleEn: 'Plans',
      body: StreamBuilder<List<Store>>(
        stream: _stores,
        builder: (context, snap) {
          final stores = snap.data;
          if (stores == null) {
            return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()));
          }
          final now = DateTime.now();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BigButton.primary(tr('📋 प्लॅन व किंमती · Manage plans'),
                    key: const ValueKey('sa-plans'),
                    onTap: () => _push(context, const PlansScreen())),
                const SizedBox(height: 8),
                BigButton.ghost(
                    _running
                        ? tr('⏳ चालू आहे… · Running…')
                        : tr('⏰ आठवणी आत्ता पाठवा · Run plan reminders now'),
                    key: const ValueKey('sa-run-reminders'),
                    onTap: _running ? null : () => _runReminders(stores)),
                SectionHeader(tr('दुकानांचे प्लॅन · Store plans')),
                if (stores.isEmpty)
                  EmptyState('🏪', tr('अजून दुकान नाही · No stores yet'))
                else
                  CardList([
                    for (final st in stores)
                      Builder(builder: (context) {
                        final status = st.planStatusAt(now);
                        final color = switch (status) {
                          PlanStatus.expired ||
                          PlanStatus.suspended =>
                            c.critical,
                          PlanStatus.expiring => c.serious,
                          _ => c.ink2,
                        };
                        return Material(
                            color: c.surface,
                            child: ListTile(
                              key: ValueKey('sa-planrow-${st.id}'),
                              title: Text('${st.storeName} · ${st.id}'),
                              subtitle: Text(
                                  '${st.planName ?? '—'} · ${planStatusLabel(status)}'
                                  '${st.planExpiryDate == null ? '' : ' · ${daysLeftText(st, now)}'}'
                                  '${st.paymentStatus == null ? '' : ' · 💳 ${st.paymentStatus}'}',
                                  style: TextStyle(color: color)),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _push(
                                  context, StorePlanScreen(storeId: st.id)),
                            ));
                      }),
                  ]),
              ]);
        },
      ),
    );
  }

  Future<void> _runReminders(List<Store> stores) async {
    setState(() => _running = true);
    final app = context.read<AppState>();
    try {
      final n = await app.platform.runReminders(stores);
      if (mounted) {
        showToast(
            context, L('$n आठवणी तयार झाल्या', '$n reminder(s) generated'));
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

/// ⚙️ Settings tab: general settings, audit logs, password, sign out.
class SuperAdminSettingsTab extends StatelessWidget {
  const SuperAdminSettingsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'सेटिंग्ज',
      titleEn: 'Settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BigButton.ghost(tr('⚙️ सामान्य सेटिंग्ज · General settings'),
            key: const ValueKey('sa-settings'),
            onTap: () => _push(context, const GeneralSettingsScreen())),
        const SizedBox(height: 8),
        BigButton.ghost(tr('📜 ऑडिट लॉग · Audit logs'),
            key: const ValueKey('sa-audit'),
            onTap: () => _push(context, const AuditLogScreen())),
        SectionHeader(tr('खाते · Account')),
        Text(L('👑 सुपर ॲडमिन', '👑 Super Admin'),
            style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 10),
        BigButton.ghost(tr('🔑 पासवर्ड बदला · Change password'),
            key: const ValueKey('sa-password'),
            onTap: () => showChangeMyPassword(context)),
        const SizedBox(height: 10),
        BigButton.danger(tr('बाहेर पडा · Sign Out'),
            key: const ValueKey('sa-signout'), onTap: () => app.signOut()),
      ]),
    );
  }
}
