import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/design.dart';
import '../../data/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/state_view.dart';
import '../../domain/notification_route.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  String? next, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final page = await ref
          .read(appControllerProvider.notifier)
          .loadPage('notifications', cursor: more ? next : null, append: more);
      if (mounted) {
        setState(() {
          next = nullableString(page['next_cursor']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) => Scaffold(
      appBar: AppBar(
        title: const Text('有人在意你的坚持'),
        actions: [
          TextButton(
            onPressed: s.unreadCount == 0
                ? null
                : () => runAction(context, ref, 'mark_notifications', {
                    'all': true,
                    'ids': s.notifications.map((n) => n.id).toList(),
                  }),
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: PageBody(
        onRefresh: load,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: load, child: Text('$error，点击重试')),
          if (next != null)
            TextButton(
              onPressed: busy ? null : () => load(more: true),
              child: const Text('加载更早的通知'),
            ),
          if (s.notifications.isEmpty)
            const EmptyMessage(
              title: '新的回应会出现在这里',
              body: '盖章、队友留言和周报消息，都留在这里等你查看。',
            ),
          ...s.notifications.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Paper(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (n.kind) {
                      'poke' => CupertinoIcons.hand_point_right,
                      'report' => CupertinoIcons.chart_bar,
                      'stamp' => CupertinoIcons.check_mark_circled,
                      'interaction' => CupertinoIcons.chat_bubble,
                      'challenge' => CupertinoIcons.question_circle,
                      'overdue' => CupertinoIcons.clock,
                      _ => CupertinoIcons.bell,
                    },
                    color: n.read
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.read ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(n.body),
                  onTap: () async {
                    await runAction(context, ref, 'mark_notifications', {
                      'ids': [n.id],
                    });
                    if (!context.mounted) return;
                    final destination = notificationRoute(
                      n.kind,
                      n.targetId,
                      s,
                    );
                    if (destination != '/notifications') {
                      context.push(destination);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
