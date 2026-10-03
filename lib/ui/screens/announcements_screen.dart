import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../state/platform_service.dart' show ddmmyyyy;
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// 📢 Super Admin → Announcements: list + create. Publishing delivers it to
/// the targeted stores as in-app notifications (every user of the store),
/// shown from the start date until the expiry date.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<List<Announcement>> _list;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final next = context.read<AppState>().platform.announcements();
    setState(() {
      _list = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'घोषणा',
      titleEn: 'Announcements',
      actions: [
        BarAction('＋ नवीन · New',
            key: const ValueKey('ann-new'),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AnnouncementFormScreen()));
              if (mounted) _reload();
            }),
      ],
      body: FutureBuilder<List<Announcement>>(
        future: _list,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return EmptyState('📢', tr('अजून घोषणा नाही · No announcements yet'));
          return CardList([
            for (final a in list)
              Padding(
                key: ValueKey('ann-${a.id}'),
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('📢 ${a.title}', style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
                  Text(a.message, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.ink2)),
                  Text(
                      '${a.target} · ${L('${a.deliveredTo} दुकाने', '${a.deliveredTo} store(s)')} · ${ddmmyyyy(a.startAt)}${a.expiresAt == null ? '' : ' → ${ddmmyyyy(a.expiresAt!)}'}',
                      style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class AnnouncementFormScreen extends StatefulWidget {
  const AnnouncementFormScreen({super.key});
  @override
  State<AnnouncementFormScreen> createState() => _AnnouncementFormScreenState();
}

class _AnnouncementFormScreenState extends State<AnnouncementFormScreen> {
  late final Stream<List<Store>> _stores =
      context.read<AppState>().repo.platform.watchStores();
  late final Future<List<Plan>> _plans = context.read<AppState>().platform.plans();
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _image = TextEditingController();
  final _link = TextEditingController();
  String _priority = 'normal';
  String _target = 'all';
  String? _planId;
  final Set<String> _picked = {};
  final Set<String> _channels = {Channels.inApp};
  DateTime _start = DateTime.now();
  DateTime? _expires;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _message, _image, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _date(DateTime initial) => showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: initial);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PendScaffold(
      titleMr: 'नवीन घोषणा',
      titleEn: 'New announcement',
      body: StreamBuilder<List<Store>>(
        stream: _stores,
        builder: (context, snap) {
          final stores = snap.data ?? const <Store>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(key: const ValueKey('ann-title'), controller: _title,
                decoration: InputDecoration(labelText: L('शीर्षक', 'Title'))),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('ann-message'), controller: _message,
                minLines: 3, maxLines: 8,
                decoration: InputDecoration(labelText: L('संदेश', 'Message'))),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('ann-image'), controller: _image,
                decoration: InputDecoration(labelText: L('फोटो लिंक (ऐच्छिक)', 'Image URL (optional)'))),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('ann-link'), controller: _link,
                decoration: InputDecoration(labelText: L('लिंक (ऐच्छिक)', 'Link (optional)'))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('ann-priority'),
              isExpanded: true,
              initialValue: _priority,
              decoration: InputDecoration(labelText: L('महत्त्व', 'Priority')),
              items: [
                for (final p in const ['low', 'normal', 'high', 'urgent'])
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _priority = v ?? _priority),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('ann-target'),
              isExpanded: true,
              initialValue: _target,
              decoration: InputDecoration(labelText: L('कोणाला', 'Target')),
              items: [
                DropdownMenuItem(value: 'all', child: Text(tr('सर्व दुकाने · All stores'))),
                DropdownMenuItem(value: 'active', child: Text(tr('सुरू दुकाने · Active stores'))),
                DropdownMenuItem(value: 'selected', child: Text(tr('निवडलेली दुकाने · Selected stores'))),
                DropdownMenuItem(value: 'plan', child: Text(tr('एका प्लॅनची दुकाने · Stores on a plan'))),
              ],
              onChanged: (v) => setState(() => _target = v ?? _target),
            ),
            if (_target == 'selected')
              for (final s in stores)
                CheckboxListTile(
                  key: ValueKey('ann-store-${s.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _picked.contains(s.id),
                  title: Text('${s.storeName} · ${s.id}'),
                  onChanged: (v) => setState(() =>
                      v == true ? _picked.add(s.id) : _picked.remove(s.id)),
                ),
            if (_target == 'plan')
              FutureBuilder<List<Plan>>(
                future: _plans,
                builder: (context, ps) => DropdownButtonFormField<String>(
                  key: const ValueKey('ann-plan'),
                  isExpanded: true,
                  initialValue: _planId,
                  decoration: InputDecoration(labelText: L('प्लॅन', 'Plan')),
                  items: [
                    for (final p in ps.data ?? const <Plan>[])
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _planId = v),
                ),
              ),
            SectionHeader(tr('माध्यम · Channels')),
            for (final ch in Channels.all)
              CheckboxListTile(
                key: ValueKey('ann-ch-$ch'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _channels.contains(ch),
                title: Text(ch == Channels.inApp ? tr('ॲपमध्ये · In-app') : ch == Channels.sms ? 'SMS' : 'WhatsApp'),
                subtitle: ch == Channels.inApp
                    ? null
                    : Text(tr('प्रोव्हायडर जोडलेला नाही — पाठवले जाणार नाही · No provider connected — will not be sent'),
                        style: TextStyle(fontSize: 11.5, color: c.critical)),
                onChanged: (v) => setState(() =>
                    v == true ? _channels.add(ch) : _channels.remove(ch)),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ann-start'),
                  onPressed: () async {
                    final d = await _date(_start);
                    if (d != null) setState(() => _start = d);
                  },
                  child: Text('${L('पासून', 'From')} ${dayShort(_start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ann-expiry'),
                  onPressed: () async {
                    final d = await _date(_expires ?? _start.add(const Duration(days: 30)));
                    if (d != null) setState(() => _expires = DateTime(d.year, d.month, d.day, 23, 59));
                  },
                  child: Text(_expires == null ? L('मुदत नाही', 'No expiry') : '${L('पर्यंत', 'Until')} ${dayShort(_expires!)}'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            BigButton.primary(tr('📢 प्रकाशित करा · Publish'),
                key: const ValueKey('ann-publish'),
                onTap: _busy ? null : () => _publish(stores)),
          ]);
        },
      ),
    );
  }

  Future<void> _publish(List<Store> stores) async {
    if (_title.text.trim().isEmpty || _message.text.trim().isEmpty) {
      showToast(context, tr('शीर्षक आणि संदेश लिहा · Enter a title and message'));
      return;
    }
    if (_target == 'selected' && _picked.isEmpty) {
      showToast(context, tr('दुकान निवडा · Pick at least one store'));
      return;
    }
    final app = context.read<AppState>();
    setState(() => _busy = true);
    final now = DateTime.now();
    final start = _start.isBefore(now) ? now : _start;
    try {
      final n = await app.platform.publishAnnouncement(
          Announcement(
            id: app.platform.newId(),
            title: _title.text.trim(),
            message: _message.text.trim(),
            imageUrl: _image.text.trim().isEmpty ? null : _image.text.trim(),
            link: _link.text.trim().isEmpty ? null : _link.text.trim(),
            priority: _priority,
            target: _target,
            storeIds: _picked.toList(),
            planId: _planId,
            channels: _channels.toList(),
            startAt: start,
            expiresAt: _expires,
            createdBy: app.repo.currentUserId ?? '',
            createdAt: now,
          ),
          stores);
      if (!mounted) return;
      showToast(context, L('$n दुकानांना पाठवले', 'Published to $n store(s)'));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
