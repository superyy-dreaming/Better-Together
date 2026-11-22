import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/design.dart';

class BatchDraftCard extends ConsumerStatefulWidget {
  const BatchDraftCard({
    super.key,
    required this.original,
    required this.snapshot,
  });
  final Checkin original;
  final AppSnapshot snapshot;

  @override
  ConsumerState<BatchDraftCard> createState() => _BatchDraftCardState();
}

class _BatchDraftCardState extends ConsumerState<BatchDraftCard> {
  String? selectedId, error;
  bool submitting = false, saved = false;

  Future<void> assign(Checkin target) async {
    if (submitting || saved) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(appControllerProvider.notifier)
          .act(
            'assign_batch_fields',
            args: {
              'checkin_id': widget.original.id,
              'target_checkin_id': target.id,
            },
          );
      if (mounted) {
        setState(() {
          saved = true;
        });
      }
    } catch (issue) {
      if (mounted) {
        setState(() {
          error = issue.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.original;
    final snapshot = widget.snapshot;
    if (original.userId != snapshot.profile.id ||
        (original.unassignedFields.isEmpty &&
            original.unassignedSummary.isEmpty)) {
      return const SizedBox.shrink();
    }
    final plans = {for (final p in snapshot.plans) p.id: p};
    final targets = snapshot.checkins
        .where(
          (candidate) =>
              candidate.userId == snapshot.profile.id &&
              original.batchId.isNotEmpty &&
              candidate.batchId == original.batchId &&
              candidate.isCompleted &&
              !candidate.classificationPending &&
              plans.containsKey(candidate.planId),
        )
        .toList();
    final chosen = targets.where((item) => item.id == selectedId).firstOrNull;
    final publicTarget =
        chosen != null && plans[chosen.planId]!.visibility == 'team';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('仅你可见的待归属内容'),
        Paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saved)
                Semantics(
                  liveRegion: true,
                  child: const Text('内容已归入所选记录。正在同步最新纪要。'),
                )
              else ...[
                const Text('这份手填内容暂未计入周报。请选择本次打卡中的一条记录，只归入一次。'),
                if (original.unassignedSummary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    original.unassignedSummary,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                ...original.unassignedFields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.label,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${field.displayValue} · ${sourceLabel(field.source)}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('归入哪条记录', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (targets.isEmpty)
                  Text(
                    original.classificationPending
                        ? '照片归类完成后，可在这里选择所属记录。'
                        : '本次打卡还没有可归属的计划记录。请先将照片归类到计划，再回来选择。',
                  ),
                ...targets.map((target) {
                  final plan = plans[target.planId]!;
                  final selected = chosen?.id == target.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      selected: selected,
                      child: OutlinedButton(
                        key: ValueKey('draft-target-${target.id}'),
                        onPressed: submitting
                            ? null
                            : () => setState(() {
                                selectedId = target.id;
                                error = null;
                              }),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          minimumSize: const Size.fromHeight(56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan.title),
                                  Text(
                                    '${plan.visibility == 'team' ? '小队可见' : '仅自己可见'} · ${target.localDate}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (chosen != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      publicTarget
                          ? '确认后，这份摘要和手填字段会写入「${plans[chosen.planId]!.title}」，小队成员可以看到。'
                          : '这份内容将归入仅自己可见的记录。',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '将更新目标记录的摘要和同名字段。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '尚未归入，草稿仍保留。$error',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('confirm-draft-assignment'),
                      onPressed: submitting ? null : () => assign(chosen),
                      child: Text(
                        submitting
                            ? '正在归入'
                            : publicTarget
                            ? '确认发布到小队记录'
                            : '确认归入私人记录',
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
