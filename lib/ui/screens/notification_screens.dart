import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// "📨 3" — opens this user's notifications (super admin: platform events;
/// store users: their own store's notices and announcements only).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    final n = context.watch<AppState>().unreadNotifications;
    return BarAction(n > 0 ? '📨 $n' : '📨',
        key: const ValueKey('notification-bell'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const NotificationCenterScreen())));
  }
}

class NotificationCenterScreen extends StatelessWidget {
  /// Buttons shown above the list (the Super Admin tab: send / sent /
  /// announcements).
  final List<({String label, String key, Widget screen})> header;
  const NotificationCenterScreen({this.header = const [], super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.notifications;
    final uid = app.repo.currentUserId ?? app.storeContext?.uid ?? '';
    final unread = app.unreadNotifications;
    return PendScaffold(
      titleMr: 'सूचना',
      titleEn: 'Notifications',
      actions: [
        if (unread > 0)
          BarAction('✓ सर्व वाचले · All read',
              key: const ValueKey('notifications-all-read'),
              onTap: () => app.platform.markRead(list)),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final h in header)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BigButton.ghost(tr(h.label),
                key: ValueKey(h.key),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => h.screen))),
          ),
        if (header.isNotEmpty)
          SectionHeader(L('माझ्या सूचना ($unread न वाचलेल्या)', 'Inbox ($unread unread)')),
        if (list.isEmpty)
          EmptyState('📨', tr('अजून सूचना नाहीत · No notifications yet'))
        else
          CardList([
            for (final n in list) _NoticeTile(n: n, unread: !n.isReadBy(uid)),
          ]),
      ]),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final AppNotification n;
  final bool unread;
  const _NoticeTile({required this.n, required this.unread});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      key: ValueKey('notification-${n.id}'),
      color: unread ? c.brand.withValues(alpha: 0.07) : c.surface,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(NoticeType.icon(n.type), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w900 : FontWeight.w600,
                            color: c.ink)),
                    const SizedBox(height: 2),
                    Text(n.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.ink2)),
                    const SizedBox(height: 4),
                    Text(
                        '${dateTimeShort(n.createdAt)}${n.storeId == null ? '' : ' · ${n.storeId}'}',
                        style: TextStyle(fontSize: 11, color: c.muted)),
                  ]),
            ),
            if (unread)
              Container(
                  key: ValueKey('unread-${n.id}'),
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 6, left: 6),
                  decoration:
                      BoxDecoration(color: c.brand, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final app = context.read<AppState>();
    if (unread) await app.platform.markRead([n]);
    if (!context.mounted) return;
    final c = context.c;
    String status(String v) => switch (v) {
          ChannelStatus.delivered => L('पोहोचले', 'delivered'),
          ChannelStatus.scheduled => L('ठरवलेले', 'scheduled'),
          ChannelStatus.providerRequired =>
            L('प्रोव्हायडर नाही — पाठवले नाही', 'provider required — not sent'),
          ChannelStatus.disabled => L('बंद', 'switched off'),
          ChannelStatus.noContact => L('नंबर नाही', 'no number'),
          _ => v,
        };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${NoticeType.icon(n.type)} ${n.title}'),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(n.message, key: const ValueKey('notification-detail')),
                if (n.link != null && n.link!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(n.link!, style: TextStyle(color: c.brand)),
                ],
                const SizedBox(height: 12),
                Text(dateTimeShort(n.createdAt),
                    style: TextStyle(fontSize: 12, color: c.muted)),
                if (n.channelStatus.length > 1)
                  for (final e in n.channelStatus.entries)
                    Text('${e.key}: ${status(e.value)}',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L('ठीक', 'OK'))),
        ],
      ),
    );
  }
}
