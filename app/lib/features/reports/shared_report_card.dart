import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';

class SharedReportCard extends ConsumerStatefulWidget {
  const SharedReportCard({
    super.key,
    required this.report,
    required this.author,
  });
  final WeeklyReport report;
  final String author;
  @override
  ConsumerState<SharedReportCard> createState() => _SharedReportCardState();
}

class _SharedReportCardState extends ConsumerState<SharedReportCard> {
  bool busy = false;
  Future<void> comment() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('回应这份周报'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '说一句鼓励的话'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (text != null && mounted) {
      await runAction(context, ref, 'interact_report', {
        'report_id': widget.report.id,
        'kind': 'comment',
        'content': text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.author}的周报',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(r.weekStart, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(r.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(r.summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await runAction(context, ref, 'interact_report', {
                            'report_id': r.id,
                            'kind': 'like',
                          });
                          if (mounted) setState(() => busy = false);
                        },
                  icon: Icon(r.liked ? Icons.favorite : Icons.favorite_border),
                  label: Text('${r.likes}'),
                ),
                TextButton.icon(
                  onPressed: comment,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text('回应 ${r.comments.length}'),
                ),
              ],
            ),
            ...r.comments
                .take(3)
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PersonAvatar(
                          c.nickname,
                          url: c.avatarUrl,
                          userId: c.userId,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${c.nickname}：${c.content}')),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
