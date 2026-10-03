import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../state/platform_service.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

String noticeTypeLabel(String type) => switch (type) {
      NoticeType.paymentReminder => L('पेमेंट आठवण', 'Payment reminder'),
      NoticeType.renewalReminder => L('नूतनीकरण आठवण', 'Renewal reminder'),
      NoticeType.planExpiry => L('मुदत संपत आहे', 'Plan expiry'),
      NoticeType.paymentConfirmation => L('पेमेंट मिळाले', 'Payment confirmation'),
      NoticeType.offer => L('ऑफर', 'Offer'),
      NoticeType.announcement => L('घोषणा', 'Announcement'),
      NoticeType.maintenance => L('देखभाल', 'Maintenance'),
      _ => L('इतर', 'Custom'),
    };

String _defaultSubject(String type) => switch (type) {
      NoticeType.paymentReminder => 'Payment due',
      NoticeType.renewalReminder => 'Plan renewal reminder',
      NoticeType.planExpiry => 'Your plan is expiring',
      NoticeType.paymentConfirmation => 'Payment received',
      NoticeType.offer => 'New offer',
      NoticeType.announcement => 'Announcement',
      NoticeType.maintenance => 'Scheduled maintenance',
      _ => '',
    };

/// 📤 Super Admin → Notifications → Send.
class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});
  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  late final Stream<List<Store>> _stores =
      context.read<AppState>().repo.platform.watchStores();
  GlobalSettings _g = GlobalSettings();
  String _type = NoticeType.paymentReminder;
  String _group = RecipientGroup.active;
  final Set<String> _picked = {};
  final Set<String> _channels = {Channels.inApp};
  final _subject = TextEditingController();
  final _message = TextEditingController();
  DateTime? _when;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().platform.settings(refresh: true).then((g) {
      if (!mounted) return;
      setState(() => _g = g);
      _fill(_type);
    });
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _fill(String type) {
    _subject.text = _defaultSubject(type);
    _message.text = _g.templates[type] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'सूचना पाठवा',
      titleEn: 'Send notification',
      actions: [
        BarAction('📜 पाठवलेले · Sent',
            key: const ValueKey('send-history'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SentNotificationsScreen()))),
      ],
      body: StreamBuilder<List<Store>>(
        stream: _stores,
        builder: (context, snap) {
          final stores = snap.data ?? const <Store>[];
          final now = DateTime.now();
          final targets = PlatformService.resolve(stores, _group,
              selected: _picked,
              now: now,
              expiringWithinDays: _g.remindBeforeDays.fold(7, (a, b) => a > b ? a : b));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('send-type'),
              isExpanded: true,
              initialValue: _type,
              decoration: InputDecoration(labelText: L('प्रकार', 'Notification type')),
              items: [
                for (final t in NoticeType.sendable)
                  DropdownMenuItem(value: t, child: Text('${NoticeType.icon(t)} ${noticeTypeLabel(t)}')),
              ],
              onChanged: (v) => setState(() {
                _type = v ?? _type;
                _fill(_type);
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('send-group'),
              isExpanded: true,
              initialValue: _group,
              decoration: InputDecoration(labelText: L('कोणाला', 'Recipients')),
              items: [
                DropdownMenuItem(value: RecipientGroup.all, child: Text(tr('सर्व दुकाने · All stores'))),
                DropdownMenuItem(value: RecipientGroup.active, child: Text(tr('सुरू दुकाने · Active stores'))),
                DropdownMenuItem(value: RecipientGroup.expiring, child: Text(tr('मुदत संपत आलेली · Expiring stores'))),
                DropdownMenuItem(value: RecipientGroup.expired, child: Text(tr('मुदत संपलेली · Expired stores'))),
                DropdownMenuItem(value: RecipientGroup.selected, child: Text(tr('निवडलेली दुकाने · Selected stores'))),
                DropdownMenuItem(value: RecipientGroup.owner, child: Text(tr('एका दुकानाचा मालक · One store owner'))),
              ],
              onChanged: (v) => setState(() {
                _group = v ?? _group;
                _picked.clear();
              }),
            ),
            if (_group == RecipientGroup.selected || _group == RecipientGroup.owner)
              for (final s in stores)
                CheckboxListTile(
                  key: ValueKey('send-store-${s.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _picked.contains(s.id),
                  title: Text('${s.storeName} · ${s.id}'),
                  subtitle: s.ownerName.isEmpty ? null : Text(s.ownerName),
                  onChanged: (v) => setState(() {
                    if (_group == RecipientGroup.owner) _picked.clear();
                    if (v == true) {
                      _picked.add(s.id);
                    } else {
                      _picked.remove(s.id);
                    }
                  }),
                ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(L('${targets.length} दुकाने', '${targets.length} store(s)'),
                  key: const ValueKey('send-count'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
            ),
            SectionHeader(tr('माध्यम · Channels')),
            for (final ch in Channels.all)
              CheckboxListTile(
                key: ValueKey('send-ch-$ch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _channels.contains(ch),
                title: Text(switch (ch) {
                  Channels.inApp => tr('ॲपमध्ये · In-app'),
                  Channels.whatsApp => 'WhatsApp',
                  _ => 'SMS',
                }),
                subtitle: ch == Channels.inApp
                    ? null
                    : Text(
                        tr('प्रोव्हायडर जोडलेला नाही — पाठवले जाणार नाही · No provider connected — will not be sent'),
                        style: TextStyle(fontSize: 11.5, color: c.critical)),
                onChanged: (v) => setState(() =>
                    v == true ? _channels.add(ch) : _channels.remove(ch)),
              ),
            const SizedBox(height: 6),
            TextField(
                key: const ValueKey('send-subject'),
                controller: _subject,
                decoration: InputDecoration(labelText: L('विषय', 'Subject'))),
            const SizedBox(height: 10),
            TextField(
                key: const ValueKey('send-message'),
                controller: _message,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: L('संदेश', 'Message'))),
            Text('{storeName} {amount} {dueDate} {expiryDate} {days}',
                style: TextStyle(fontSize: 11.5, color: c.muted)),
            SectionHeader(tr('कधी · When')),
            Row(children: [
              Expanded(
                child: ChoiceChip(
                  key: const ValueKey('send-now'),
                  label: Text(L('आत्ता', 'Send now')),
                  selected: _when == null,
                  onSelected: (_) => setState(() => _when = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  key: const ValueKey('send-later'),
                  label: Text(_when == null
                      ? L('नंतर', 'Schedule later')
                      : dateTimeShort(_when!)),
                  selected: _when != null,
                  onSelected: (_) => _pickWhen(),
                ),
              ),
            ]),
            if (_when != null)
              Text(
                  tr('ॲपमधील सूचना त्या वेळेपासून दिसेल. WhatsApp/SMS ठरवलेल्या वेळी पाठवण्याची सर्व्हर व्यवस्था नाही. · The in-app notice shows from that time. There is no server scheduler for WhatsApp/SMS.'),
                  style: TextStyle(fontSize: 11.5, color: c.ink2)),
            const SizedBox(height: 14),
            BigButton.primary(tr('📤 पाठवा · Send'),
                key: const ValueKey('send-go'),
                onTap: _busy || targets.isEmpty || _channels.isEmpty
                    ? null
                    : () => _send(targets)),
          ]);
        },
      ),
    );
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
        initialDate: now.add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (!mounted) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  Future<void> _send(List<Store> targets) async {
    if (_message.text.trim().isEmpty || _subject.text.trim().isEmpty) {
      showToast(context, tr('विषय आणि संदेश लिहा · Enter a subject and message'));
      return;
    }
    setState(() => _busy = true);
    final app = context.read<AppState>();
    try {
      final r = await app.platform.send(
          stores: targets,
          type: _type,
          subject: _subject.text.trim(),
          message: _message.text.trim(),
          channels: _channels,
          audience: _group == RecipientGroup.owner ? Audience.storeAdmin : null,
          scheduledFor: _when);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(tr('पाठवले · Sent')),
                content: Text(
                    key: const ValueKey('send-report'),
                    [
                      L('${r.stores} दुकाने', '${r.stores} store(s)'),
                      if (_channels.contains(Channels.inApp))
                        '${L('ॲपमध्ये', 'In-app')}: ${r.count(Channels.inApp, ChannelStatus.delivered) + r.count(Channels.inApp, ChannelStatus.scheduled)}',
                      for (final ch in [Channels.whatsApp, Channels.sms])
                        if (_channels.contains(ch))
                          '${ch == Channels.sms ? 'SMS' : 'WhatsApp'}: ${L('पाठवले नाही — प्रोव्हायडर नाही', 'NOT sent — provider required')} (${r.count(ch, ChannelStatus.providerRequired)}), ${L('बंद', 'off')} ${r.count(ch, ChannelStatus.disabled)}, ${L('नंबर नाही', 'no number')} ${r.count(ch, ChannelStatus.noContact)}',
                    ].join('\n')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(L('ठीक', 'OK')))
                ],
              ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// What the super admin sent to stores, newest first, with read counts.
class SentNotificationsScreen extends StatelessWidget {
  const SentNotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'पाठवलेल्या सूचना',
      titleEn: 'Sent notifications',
      body: StreamBuilder<List<AppNotification>>(
        stream: app.platform.watchSent(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyState('⚠️', '${snap.error}');
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) return EmptyState('📤', tr('अजून काही पाठवले नाही · Nothing sent yet'));
          return CardList([
            for (final n in list)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${NoticeType.icon(n.type)} ${n.title}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
                  Text(n.message, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.ink2)),
                  Text(
                      '${n.storeId ?? ''} · ${dateTimeShort(n.createdAt)} · ${n.status} · ${L('वाचले', 'read')} ${n.readBy.length}'
                      '${[for (final e in n.channelStatus.entries) if (e.key != Channels.inApp) ' · ${e.key}: ${e.value}'].join()}',
                      style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
