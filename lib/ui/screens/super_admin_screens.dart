import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../models/staff.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
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
import '../widgets/tiles.dart';

/// 👑 Super Admin — stores and their users. A super admin is the only role
/// that works across stores; opening a store keeps their identity and only
/// changes which store the app shows.
class SuperAdminHome extends StatefulWidget {
  const SuperAdminHome({super.key});
  @override
  State<SuperAdminHome> createState() => _SuperAdminHomeState();
}

class _SuperAdminHomeState extends State<SuperAdminHome> {
  /// Live store documents: a rename, (de)activation, plan or payment change
  /// shows at once — never a stale cached copy.
  late final Stream<List<Store>> _stores =
      context.read<AppState>().repo.platform.watchStores();
  late Future<(List<Staff>, List<AuditEntry>, List<Announcement>, GlobalSettings)>
      _extras;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Users, recent audit events and announcements (fresh from Firestore
  /// whenever the dashboard is shown again).
  void _reload() {
    final app = context.read<AppState>();
    final next = () async {
      Future<T> safe<T>(Future<T> f, T fallback) =>
          f.catchError((Object _) => fallback);
      final users = await app.repo.listUsers();
      final audit = await safe(app.repo.loadAudit(limit: 6), <AuditEntry>[]);
      final ann = await app.platform.announcements(limit: 3);
      final g = await app.platform.settings(refresh: true);
      return (users, audit, ann, g);
    }();
    setState(() {
      _extras = next;
    });
  }

  Future<void> _push(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'सुपर ॲडमिन',
      titleEn: 'Super Admin',
      actions: [
        const NotificationBell(),
        BarAction('🔑',
            key: const ValueKey('sa-password'),
            onTap: () => showChangeMyPassword(context)),
        BarAction('लॉगआउट · Sign out',
            key: const ValueKey('sa-signout'), onTap: () => app.signOut()),
      ],
      body: StreamBuilder<List<Store>>(
        stream: _stores,
        builder: (context, storeSnap) {
          if (storeSnap.hasError) {
            return EmptyState('⚠️', '${storeSnap.error}');
          }
          final stores = storeSnap.data;
          return FutureBuilder(
            future: _extras,
            builder: (context, snap) {
              if (snap.hasError) {
                return EmptyState('⚠️', '${snap.error}');
              }
              if (!snap.hasData || stores == null) {
                return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()));
              }
              final (users, audit, announcements, g) = snap.data!;
              final storeUsers = users.where((u) => !u.isSuperAdmin).toList();
              final now = DateTime.now();
              final within = g.remindBeforeDays.fold(7, (a, b) => a > b ? a : b);
              String status(Store s) => s.planStatusAt(now, expiringWithinDays: within);
              final expiring = stores.where((s) => status(s) == PlanStatus.expiring).length;
              final expired = stores.where((s) => status(s) == PlanStatus.expired).length;
              final pending = stores
                  .where((s) =>
                      s.paymentStatus == PaymentStatus.pending ||
                      s.paymentStatus == PaymentStatus.failed)
                  .length;
              const storeTypes = {
                NoticeType.storeCreated,
                NoticeType.storeUpdated,
                NoticeType.storeActivated,
                NoticeType.storeDeactivated,
                NoticeType.storePlanChanged,
              };
              final changes = app.notifications
                  .where((n) => storeTypes.contains(n.type))
                  .take(4)
                  .toList();
              Widget nav(String label, String key, Widget screen) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: BigButton.ghost(label,
                        key: ValueKey(key), onTap: () => _push(screen)),
                  );
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileGrid(columns: 2, gap: 10, [
                      StatTile(
                          key: const ValueKey('sa-total-stores'),
                          label: tr('एकूण दुकाने · Total stores'),
                          value: '${stores.length}',
                          sub:
                              '✅ ${stores.where((s) => s.isActive).length}   ⛔ ${stores.where((s) => !s.isActive).length}'),
                      StatTile(
                          key: const ValueKey('sa-total-users'),
                          label: tr('एकूण वापरकर्ते · Total users'),
                          value: '${storeUsers.length}',
                          sub:
                              '✅ ${storeUsers.where((u) => u.active).length} ${L('सक्रिय', 'active')}'),
                      StatTile(
                          key: const ValueKey('sa-expiring'),
                          label: tr('मुदत संपत आलेली · Expiring soon'),
                          value: '$expiring',
                          sub: '⛔ ${L('संपलेली', 'expired')} $expired'),
                      StatTile(
                          key: const ValueKey('sa-pending'),
                          label: tr('बाकी पेमेंट · Pending payments'),
                          value: '$pending',
                          sub: '📨 ${L('न वाचलेल्या', 'unread')} ${app.unreadNotifications}'),
                    ]),
                    const SizedBox(height: 14),
                    BigButton.primary(tr('＋ नवीन दुकान · Create store'),
                        key: const ValueKey('sa-create-store'),
                        onTap: () => _push(const StoreFormScreen())),
                    const SizedBox(height: 8),
                    nav(tr('📤 सूचना पाठवा · Send notification'), 'sa-send',
                        const SendNotificationScreen()),
                    nav(tr('📢 घोषणा · Announcements'), 'sa-announcements',
                        const AnnouncementsScreen()),
                    nav(tr('📋 प्लॅन · Plans'), 'sa-plans', const PlansScreen()),
                    nav(tr('⚙️ सामान्य सेटिंग्ज · General settings'), 'sa-settings',
                        const GeneralSettingsScreen()),
                    nav(tr('📜 ऑडिट लॉग · Audit logs'), 'sa-audit',
                        const AuditLogScreen()),
                    BigButton.ghost(
                        _running
                            ? tr('⏳ चालू आहे… · Running…')
                            : tr('⏰ आठवणी आत्ता पाठवा · Run plan reminders now'),
                        key: const ValueKey('sa-run-reminders'),
                        onTap: _running ? null : () => _runReminders(stores)),
                    if (changes.isNotEmpty) ...[
                      SectionHeader(tr('अलीकडील बदल · Recent store changes')),
                      for (final n in changes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${NoticeType.icon(n.type)} ${n.message}',
                              key: ValueKey('sa-change-${n.id}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: c.ink2)),
                        ),
                    ],
                    SectionHeader(tr('दुकाने · Stores')),
                    if (stores.isEmpty)
                      EmptyState('🏪', tr('अजून दुकान नाही · No stores yet'))
                    else
                      for (final st in stores) ...[
                        _storeCard(context, app, st,
                            storeUsers.where((u) => u.storeId == st.id).length,
                            status(st)),
                        const SizedBox(height: 10),
                      ],
                    if (announcements.isNotEmpty) ...[
                      SectionHeader(tr('अलीकडील घोषणा · Recent announcements')),
                      for (final a in announcements)
                        Text('📢 ${a.title} · ${dateTimeShort(a.createdAt)}',
                            style: TextStyle(fontSize: 12.5, color: c.ink2)),
                    ],
                    if (audit.isNotEmpty) ...[
                      SectionHeader(tr('अलीकडील नोंदी · Recent audit events')),
                      for (final a in audit)
                        Text(
                            '${a.action} · ${a.storeId}${a.field == null ? '' : ' · ${a.field}'} · ${dateTimeShort(a.at)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.ink2)),
                    ],
                    const SizedBox(height: 10),
                    Text(
                        tr('दुकान उघडल्यावर तुम्ही त्या दुकानाचा डेटा पाहता — इतर दुकानांचा नाही. · Opening a store shows that store\'s data only.'),
                        style: TextStyle(fontSize: 11.5, color: c.muted)),
                  ]);
            },
          );
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
        showToast(context,
            L('$n आठवणी तयार झाल्या', '$n reminder(s) generated'));
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Widget _storeCard(
      BuildContext context, AppState app, Store st, int users, String plan) {
    final c = context.c;
    Widget action(String label, Color color, VoidCallback onTap, String key) =>
        Expanded(
          child: Material(
            key: ValueKey(key),
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(4),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        );
    final planColor = switch (plan) {
      PlanStatus.expired || PlanStatus.suspended => c.critical,
      PlanStatus.expiring => c.serious,
      _ => c.ink2,
    };
    return Container(
      key: ValueKey('sa-store-${st.id}'),
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.storeName,
                  key: ValueKey('sa-store-name-${st.id}'),
                  style:
                      baloo(size: 16, weight: FontWeight.w800, color: c.ink)),
              Text(
                  '${st.id} · 👥 $users${st.city.isEmpty ? '' : ' · ${st.city}'}',
                  style: TextStyle(fontSize: 12.5, color: c.ink2)),
              if (plan != PlanStatus.none)
                Text(
                    '💳 ${st.planName ?? ''} · ${planStatusLabel(plan)} · ${daysLeftText(st, DateTime.now())}',
                    key: ValueKey('sa-plan-${st.id}'),
                    style: TextStyle(fontSize: 12, color: planColor)),
              if (st.ownerName.isNotEmpty)
                Text('👤 ${st.ownerName}',
                    style: TextStyle(fontSize: 12, color: c.ink2)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color:
                    (st.isActive ? c.good : c.critical).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999)),
            child: Text(
                st.isActive
                    ? '✅ ${L('सुरू', 'Active')}'
                    : '⛔ ${L('बंद', 'Inactive')}',
                key: ValueKey('sa-status-${st.id}'),
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: c.ink, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          action(tr('▶ उघडा · Open'), c.brand, () => app.openStore(st),
              'sa-open-${st.id}'),
          const SizedBox(width: 6),
          action(tr('👥 वापरकर्ते · Users'), c.s1,
              () => _push(StoreUsersScreen(store: st)), 'sa-users-${st.id}'),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          action(tr('✏️ बदला · Edit'), c.ink2,
              () => _push(StoreFormScreen(store: st)), 'sa-edit-${st.id}'),
          const SizedBox(width: 6),
          action(tr('💳 प्लॅन · Plan'), c.brand,
              () => _push(StorePlanScreen(storeId: st.id)), 'sa-plan-open-${st.id}'),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          action(
              st.isActive
                  ? tr('⛔ बंद करा · Deactivate')
                  : tr('✅ सुरू करा · Activate'),
              st.isActive ? c.critical : c.good,
              () => _toggle(app, st),
              'sa-toggle-${st.id}'),
        ]),
      ]),
    );
  }

  Future<void> _toggle(AppState app, Store st) async {
    final off = st.isActive;
    if (off) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
              L('${st.storeName} बंद करायचे?', 'Deactivate ${st.storeName}?')),
          content: Text(tr(
              'या दुकानाचे वापरकर्ते काम करू शकणार नाहीत. डेटा हटवला जाणार नाही. · Its users can no longer work in it. No data is deleted.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(L('नाही', 'No'))),
            FilledButton(
                key: const ValueKey('sa-toggle-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(L('बंद करा', 'Deactivate'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final error = await app.updateStore(
        st.copyWith(status: off ? StoreStatus.inactive : StoreStatus.active));
    if (!mounted) return;
    showToast(
        context,
        error ??
            (off
                ? L('दुकान बंद केले', 'Store deactivated')
                : L('दुकान सुरू केले', 'Store activated')));
    _reload();
  }
}

/// Create (with an optional first store admin) or edit a store.
class StoreFormScreen extends StatefulWidget {
  final Store? store;

  /// A store admin editing their own store: name and contact/owner details
  /// only (plan, payment and status stay with the super admin).
  final bool ownStore;
  const StoreFormScreen({this.store, this.ownStore = false, super.key});
  @override
  State<StoreFormScreen> createState() => _StoreFormScreenState();
}

class _StoreFormScreenState extends State<StoreFormScreen> {
  late final Map<String, TextEditingController> f;
  final adminName = TextEditingController();
  final adminEmail = TextEditingController();
  final adminPassword = TextEditingController();
  bool _busy = false;
  String? _error;
  String _channel = 'whatsApp';

  @override
  void initState() {
    super.initState();
    final s = widget.store;
    f = {
      'code': TextEditingController(text: s?.id ?? ''),
      'name': TextEditingController(text: s?.storeName ?? ''),
      'legal': TextEditingController(text: s?.legalName ?? ''),
      'address': TextEditingController(text: s?.address ?? ''),
      'city': TextEditingController(text: s?.city ?? ''),
      'state': TextEditingController(text: s?.state ?? ''),
      'pincode': TextEditingController(text: s?.pincode ?? ''),
      'phone': TextEditingController(text: s?.phone ?? ''),
      'email': TextEditingController(text: s?.email ?? ''),
      'gst': TextEditingController(text: s?.gstNumber ?? ''),
      'ownerName': TextEditingController(text: s?.ownerName ?? ''),
      'ownerEmail': TextEditingController(text: s?.ownerEmail ?? ''),
      'ownerPhone': TextEditingController(text: s?.ownerPhone ?? ''),
      'ownerWhatsApp': TextEditingController(text: s?.ownerWhatsApp ?? ''),
    };
    _channel = s?.notifyChannel ?? 'whatsApp';
    if (s == null) _fillCode();
  }

  /// A new store's code is given automatically (next number after the
  /// stores so far); it can't be typed.
  Future<void> _fillCode() async {
    try {
      final code = await context.read<AppState>().nextStoreCode();
      if (mounted) setState(() => f['code']!.text = code);
    } catch (_) {
      // Left empty: "Create store" works the code out again when saving.
    }
  }

  @override
  void dispose() {
    for (final c in [...f.values, adminName, adminEmail, adminPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String mr, String en,
          {TextInputType? type, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey('store-form-$key'),
          controller: f[key],
          enabled: enabled,
          keyboardType: type,
          textCapitalization: key == 'code'
              ? TextCapitalization.characters
              : TextCapitalization.none,
          decoration: InputDecoration(labelText: L(mr, en)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.store != null;
    return PendScaffold(
      titleMr: widget.ownStore ? 'दुकानाची माहिती' : editing ? 'दुकान बदला' : 'नवीन दुकान',
      titleEn: widget.ownStore ? 'Store details' : editing ? 'Edit store' : 'Create store',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field('code', 'दुकान कोड', 'Store code', enabled: false),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
              editing
                  ? tr('दुकान कोड बदलता येत नाही · The store code cannot change')
                  : tr('दुकान कोड आपोआप दिला जातो · The store code is given automatically'),
              style: TextStyle(fontSize: 12, color: context.c.muted)),
        ),
        _field('name', 'दुकानाचे नाव', 'Store name'),
        _field('legal', 'कायदेशीर नाव', 'Legal name'),
        _field('address', 'पत्ता', 'Address'),
        _field('city', 'शहर', 'City'),
        _field('state', 'राज्य', 'State'),
        _field('pincode', 'पिनकोड', 'Pincode', type: TextInputType.number),
        _field('phone', 'फोन', 'Phone', type: TextInputType.phone),
        _field('email', 'ईमेल', 'Email', type: TextInputType.emailAddress),
        _field('gst', 'GST क्रमांक', 'GST number'),
        SectionHeader(tr('मालक / संपर्क · Owner / contact')),
        _field('ownerName', 'मालकाचे नाव', 'Owner name'),
        _field('ownerEmail', 'मालकाचा ईमेल', 'Owner email',
            type: TextInputType.emailAddress),
        _field('ownerPhone', 'मालकाचा फोन', 'Owner phone',
            type: TextInputType.phone),
        _field('ownerWhatsApp', 'मालकाचा WhatsApp', 'Owner WhatsApp',
            type: TextInputType.phone),
        DropdownButtonFormField<String>(
          key: const ValueKey('store-form-channel'),
          isExpanded: true,
          initialValue: _channel,
          decoration: InputDecoration(
              labelText: L('सूचना कशी पाठवायची', 'Preferred notification channel')),
          items: [
            const DropdownMenuItem(value: 'whatsApp', child: Text('WhatsApp')),
            const DropdownMenuItem(value: 'sms', child: Text('SMS')),
            DropdownMenuItem(value: 'both', child: Text(tr('दोन्ही · Both'))),
            DropdownMenuItem(value: 'none', child: Text(tr('काहीही नाही · None'))),
          ],
          onChanged: (v) => setState(() => _channel = v ?? _channel),
        ),
        const SizedBox(height: 10),
        if (!editing) ...[
          SectionHeader(
              tr('पहिला दुकान मालक (ऐच्छिक) · First store admin (optional)')),
          TextField(
              key: const ValueKey('store-form-admin-name'),
              controller: adminName,
              decoration: InputDecoration(labelText: tr('नाव · Name'))),
          const SizedBox(height: 10),
          TextField(
              key: const ValueKey('store-form-admin-email'),
              controller: adminEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('ईमेल · Email'))),
          const SizedBox(height: 10),
          TextField(
              key: const ValueKey('store-form-admin-password'),
              controller: adminPassword,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: tr('तात्पुरता पासवर्ड · Temporary password'))),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!,
                key: const ValueKey('store-form-error'),
                style: TextStyle(
                    color: context.c.critical, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 16),
        BigButton.primary(
            editing
                ? tr('जतन करा · Save')
                : tr('दुकान तयार करा · Create store'),
            key: const ValueKey('store-form-save'),
            onTap: _busy ? null : _save),
      ]),
    );
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    final s = widget.store;
    if (s != null && widget.ownStore) {
      error = await app.updateMyStore(s.copyWith(
          storeName: f['name']!.text.trim(),
          legalName: f['legal']!.text.trim(),
          address: f['address']!.text.trim(),
          city: f['city']!.text.trim(),
          state: f['state']!.text.trim(),
          pincode: f['pincode']!.text.trim(),
          phone: f['phone']!.text.trim(),
          email: f['email']!.text.trim(),
          gstNumber: f['gst']!.text.trim(),
          ownerName: f['ownerName']!.text.trim(),
          ownerEmail: f['ownerEmail']!.text.trim(),
          ownerPhone: f['ownerPhone']!.text.trim(),
          ownerWhatsApp: f['ownerWhatsApp']!.text.trim(),
          notifyChannel: _channel));
    } else if (s != null) {
      error = await app.updateStore(s.copyWith(
          storeName: f['name']!.text.trim(),
          legalName: f['legal']!.text.trim(),
          address: f['address']!.text.trim(),
          city: f['city']!.text.trim(),
          state: f['state']!.text.trim(),
          pincode: f['pincode']!.text.trim(),
          phone: f['phone']!.text.trim(),
          email: f['email']!.text.trim(),
          gstNumber: f['gst']!.text.trim(),
          ownerName: f['ownerName']!.text.trim(),
          ownerEmail: f['ownerEmail']!.text.trim(),
          ownerPhone: f['ownerPhone']!.text.trim(),
          ownerWhatsApp: f['ownerWhatsApp']!.text.trim(),
          notifyChannel: _channel));
    } else {
      var code = f['code']!.text.trim();
      if (code.isEmpty) code = await app.nextStoreCode();
      Future<String?> create() => app.createStore(
          code: code,
          name: f['name']!.text,
          legalName: f['legal']!.text,
          address: f['address']!.text,
          city: f['city']!.text,
          state: f['state']!.text,
          pincode: f['pincode']!.text,
          phone: f['phone']!.text,
          email: f['email']!.text,
          gstNumber: f['gst']!.text,
          ownerName: f['ownerName']!.text,
          ownerEmail: f['ownerEmail']!.text,
          ownerPhone: f['ownerPhone']!.text,
          ownerWhatsApp: f['ownerWhatsApp']!.text,
          notifyChannel: _channel);
      error = await create();
      if (error != null && error.contains('already used')) {
        // Another store took this code meanwhile — take the next one.
        code = await app.nextStoreCode();
        if (mounted) f['code']!.text = code;
        error = await create();
      }
      if (error == null && adminEmail.text.trim().isNotEmpty) {
        error = await app.createStoreUser(
            storeId: code,
            name: adminName.text,
            email: adminEmail.text,
            password: adminPassword.text);
        if (error != null) {
          error = L('दुकान तयार झाले, पण मालक खाते नाही: $error',
              'Store created, but not the admin account: $error');
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      showToast(context, tr('✅ जतन झाले · Saved'));
      Navigator.of(context).pop();
    }
  }
}

/// Users (store admins and staff) of one store.
class StoreUsersScreen extends StatefulWidget {
  final Store store;
  const StoreUsersScreen({required this.store, super.key});
  @override
  State<StoreUsersScreen> createState() => _StoreUsersScreenState();
}

class _StoreUsersScreenState extends State<StoreUsersScreen> {
  late Future<List<Staff>> _users;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final next =
        context.read<AppState>().repo.listUsers(storeId: widget.store.id);
    setState(() {
      _users = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'वापरकर्ते',
      titleEn: 'Store users',
      actions: [
        BarAction('＋ वापरकर्ता · User',
            key: const ValueKey('sa-add-user'), onTap: () => _addUser(context)),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${widget.store.storeName} · ${widget.store.id}',
            style: baloo(size: 16, weight: FontWeight.w800, color: c.ink)),
        const SizedBox(height: 10),
        FutureBuilder<List<Staff>>(
          future: _users,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final users = snap.data!;
            if (users.isEmpty) {
              return EmptyState('👥', tr('अजून वापरकर्ता नाही · No users yet'));
            }
            return CardList([
              for (final u in users)
                Material(
                  color: c.surface,
                  child: ListTile(
                    key: ValueKey('sa-user-${u.id}'),
                    title: Text(u.name),
                    subtitle: Text(
                        '${u.email ?? u.id}\n${u.isAdmin ? L('दुकान मालक', 'Store admin') : L('कर्मचारी', 'Staff')} · ${u.active ? L('सक्रिय', 'Active') : L('निष्क्रिय', 'Inactive')}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          key: ValueKey('sa-user-password-${u.id}'),
                          tooltip: tr('पासवर्ड बदला · Set password'),
                          icon: const Icon(Icons.key_outlined),
                          onPressed: () => showSetPassword(context, u)),
                      IconButton(
                          key: ValueKey('sa-user-edit-${u.id}'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editUser(context, u)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }

  Future<void> _addUser(BuildContext context) async {
    final app = context.read<AppState>();
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    var role = Roles.storeAdmin;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(tr('नवीन वापरकर्ता · New user')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  key: const ValueKey('user-name'),
                  controller: name,
                  decoration: InputDecoration(labelText: tr('नाव · Name'))),
              TextField(
                  key: const ValueKey('user-email'),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: tr('ईमेल · Email'))),
              TextField(
                  key: const ValueKey('user-phone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: tr('फोन · Phone'))),
              TextField(
                  key: const ValueKey('user-password'),
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: tr('तात्पुरता पासवर्ड · Temporary password'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('user-role'),
                isExpanded: true,
                initialValue: role,
                items: [
                  DropdownMenuItem(
                      value: Roles.storeAdmin,
                      child: Text(tr('दुकान मालक · Store admin'))),
                  DropdownMenuItem(
                      value: Roles.staff, child: Text(tr('कर्मचारी · Staff'))),
                ],
                onChanged: (v) => setSt(() => role = v ?? role),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: ctx.c.critical)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                key: const ValueKey('user-save'),
                onPressed: () async {
                  final e = await app.createStoreUser(
                      storeId: widget.store.id,
                      name: name.text,
                      email: email.text,
                      password: password.text,
                      phone: phone.text,
                      role: role);
                  if (e != null) {
                    setSt(() => error = e);
                  } else if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
                child: Text(L('तयार करा', 'Create'))),
          ],
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _editUser(BuildContext context, Staff u) async {
    final app = context.read<AppState>();
    var role = u.role;
    var active = u.active;
    final name = TextEditingController(text: u.name);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(u.email ?? u.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: InputDecoration(labelText: tr('नाव · Name'))),
            DropdownButtonFormField<String>(
              key: const ValueKey('user-edit-role'),
              isExpanded: true,
              initialValue: role == Roles.storeAdmin ? role : Roles.staff,
              items: [
                DropdownMenuItem(
                    value: Roles.storeAdmin,
                    child: Text(tr('दुकान मालक · Store admin'))),
                DropdownMenuItem(
                    value: Roles.staff, child: Text(tr('कर्मचारी · Staff'))),
              ],
              onChanged: (v) => setSt(() => role = v ?? role),
            ),
            SwitchListTile(
              key: const ValueKey('user-edit-active'),
              value: active,
              title: Text(tr('सक्रिय · Active')),
              onChanged: (v) => setSt(() => active = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L('रद्द', 'Cancel'))),
            FilledButton(
                key: const ValueKey('user-edit-save'),
                onPressed: () async {
                  final e = await app.updateStoreUser(u.copyWith(
                      name: name.text.trim(), role: role, active: active));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (e != null && context.mounted) showToast(context, e);
                },
                child: Text(L('जतन', 'Save'))),
          ],
        ),
      ),
    );
    if (mounted) _reload();
  }
}

/// 📜 Audit trail — one store's (store admin) or every store's (super admin).
class AuditLogScreen extends StatelessWidget {
  final String? storeId;
  const AuditLogScreen({this.storeId, super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'ऑडिट लॉग',
      titleEn: 'Audit logs',
      body: FutureBuilder(
        future: app.repo.loadAudit(storeId: storeId),
        builder: (context, snap) {
          if (snap.hasError) return EmptyState('⚠️', '${snap.error}');
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return EmptyState('📜', tr('अजून नोंद नाही · Nothing logged yet'));
          }
          return CardList([
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a.action} · ${a.entityType} ${a.entityId}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: c.ink)),
                      Text(
                          '${a.storeId} · ${a.role} · ${a.userId} · ${dateTimeShort(a.at)}${a.note == null ? '' : '\n${a.note}'}',
                          style: TextStyle(fontSize: 12, color: c.ink2)),
                    ]),
              ),
          ]);
        },
      ),
    );
  }
}

/// "🏪 Pune Main · STR002" — which store the app is working in. For a
/// super admin inside a store it also offers the way back to all stores.
class StoreBadge extends StatelessWidget {
  const StoreBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.store;
    if (st == null) return const SizedBox.shrink();
    final c = context.c;
    return Container(
      key: const ValueKey('store-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: c.brand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12)),
      // Wraps, so a long name or the super-admin button fits any width.
      child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text('🏪 ${st.storeName} · ${st.id}',
                key: const ValueKey('store-badge-name'),
                style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
            if (app.isSuperAdmin)
              TextButton(
                  key: const ValueKey('store-badge-back'),
                  onPressed: app.closeStore,
                  child: Text(tr('👑 सर्व दुकाने · All stores'))),
          ]),
    );
  }
}
