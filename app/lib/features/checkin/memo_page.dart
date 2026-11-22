import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';
import '../../ui/tuantuan.dart';
import '../../ui/record_image.dart';
import '../../ui/photo_viewer.dart';
import 'memo_editor.dart';
import 'batch_draft_card.dart';

class MemoPage extends ConsumerStatefulWidget {
  const MemoPage({super.key, required this.id, this.sealed = false});
  final String id;
  final bool sealed;
  @override
  ConsumerState<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends ConsumerState<MemoPage> {
  final comment = TextEditingController();
  bool challenge = false, busy = false;
  Timer? poll;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(appControllerProvider.notifier).ensureCheckin(widget.id);
      } catch (_) {
        /* Existing records remain visible; missing ones show retry. */
      }
    });
    poll = Timer.periodic(const Duration(seconds: 8), (_) {
      final s = ref.read(appControllerProvider).asData?.value;
      final matches = s?.checkins.where((c) => c.id == widget.id);
      if (matches == null) return;
      if (matches.isNotEmpty &&
          (matches.first.memoStatus == 'pending' ||
              matches.first.classificationPending ||
              matches.first.photos.any((p) => p.cleanupStatus == 'pending'))) {
        ref
            .read(appControllerProvider.notifier)
            .ensureCheckin(widget.id)
            .catchError((Object _) {});
      } else {
        poll?.cancel();
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    comment.dispose();
    super.dispose();
  }

  Future<void> edit(Checkin c) async {
    final value = await showModalBottomSheet<JsonMap>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MemoEditor(checkin: c),
    );
    if (value != null && mounted) {
      await runAction(context, ref, 'edit_memo', {
        'checkin_id': c.id,
        ...value,
      });
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) {
      final matches = s.checkins.where((c) => c.id == widget.id);
      if (matches.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('打卡纪要')),
          body: Center(
            child: TextButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(appControllerProvider.notifier)
                      .ensureCheckin(widget.id);
                } catch (e) {
                  if (context.mounted) feedback(context, e.toString());
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('读取这条记录'),
            ),
          ),
        );
      }
      final c = matches.first;
      final mine = c.userId == s.profile.id;
      return Scaffold(
        appBar: AppBar(
          title: const Text('打卡纪要'),
          actions: [
            if (mine)
              IconButton(
                tooltip: '编辑纪要',
                onPressed: () => edit(c),
                icon: const Icon(CupertinoIcons.pencil),
              ),
          ],
        ),
        body: PageBody(
          children: [
            if (widget.sealed && c.isCompleted) ...[
              if (isTuanTuan(context))
                TuanTuanHero(
                  title: c.isMakeup ? '补上这一步，\n也值得记录。' : '好耶，\n又完成一件！',
                  body: c.memoStatus == 'pending' || c.classificationPending
                      ? '打卡已完成，纪要正在整理。'
                      : '小小的一步，也值得庆祝。',
                  pose: TuanTuanPose.celebrate,
                )
              else ...[
                const SizedBox(height: 14),
                const Center(child: StampLabel(text: '今天的坚持，已盖章')),
              ],
              if (s.checkins
                      .where(
                        (entry) =>
                            entry.planId == c.planId &&
                            entry.userId == c.userId &&
                            entry.localDate == c.localDate &&
                            entry.isCompleted,
                      )
                      .length >
                  1)
                const Text('又记录了一次坚持'),
              if (s.plans.where((p) => p.id == c.planId).firstOrNull
                  case final plan?)
                if (plan.extraDays > 0)
                  Text(
                    '本周完成 ${plan.weeklyCompleted} 天，比目标多 ${plan.extraDays} 天',
                  ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                CategoryMark(c.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CategoryMark.label(c.category),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${c.nickname} · ${c.localDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StampLabel(text: checkinStatusLabel(c.status), compact: true),
              ],
            ),
            const SizedBox(height: 20),
            if (c.isLate) const Text('迟到完成：计入完成，不增加连续记录。'),
            if (c.isMakeup) const Text('已补卡：保留完成率，连续记录冻结一天。'),
            if (s.checkins.any(
              (other) =>
                  other.batchId == c.batchId &&
                  other.userId == c.userId &&
                  other.id != c.id,
            )) ...[
              const SectionTitle('这次一起提交的记录'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final other in s.checkins.where(
                    (other) =>
                        other.batchId == c.batchId && other.userId == c.userId,
                  ))
                    OutlinedButton(
                      onPressed: other.id == c.id
                          ? null
                          : () => context.push('/memo/${other.id}'),
                      child: Text(
                        s.plans
                                .where((p) => p.id == other.planId)
                                .firstOrNull
                                ?.title ??
                            'ALL，暂不归类',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (c.photos.isNotEmpty) ...[
              SizedBox(
                height: 250,
                child: PageView(
                  children: c.photos
                      .map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: p.cleanupStatus == 'pending'
                                ? const Center(child: Text('原图清理中，完成后会自动移除。'))
                                : InkWell(
                                    onTap: () => showPhotoViewer(
                                      context,
                                      c.photos,
                                      c.photos.indexOf(p),
                                    ),
                                    child: RecordImage(p.url),
                                  ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              ...c.photos.map(
                (p) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '照片 ${c.photos.indexOf(p) + 1} · ${sourceLabel(p.source)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (p.recognition != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              p.recognition!.summary.isNotEmpty
                                  ? p.recognition!.summary
                                  : '摘要待补生成',
                            ),
                            for (final field in p.recognition!.fields)
                              Text(
                                '${field.label}：${field.displayValue} · ${sourceLabel(field.source)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (mine &&
                                p.recognition!.isPending &&
                                p.cleanupStatus != 'pending')
                              TextButton(
                                onPressed: () => runAction(
                                  context,
                                  ref,
                                  'retry_photo_ai',
                                  {'media_id': p.id},
                                ),
                                child: const Text('补生成这张照片摘要'),
                              ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    if (mine && p.cleanupStatus != 'pending')
                      IconButton(
                        tooltip: '删除这张原图',
                        onPressed: () async {
                          if (await confirmAction(
                                context,
                                '删除这张原图？',
                                '删除后无法恢复。纪要和统计仍会保留。',
                                accept: '删除原图',
                              ) &&
                              context.mounted) {
                            await runAction(context, ref, 'delete_photo', {
                              'photo_id': p.id,
                            });
                          }
                        },
                        icon: const Icon(CupertinoIcons.trash, size: 18),
                      ),
                  ],
                ),
              ),
            ],
            const SectionTitle('今天留下了什么'),
            Paper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.memoStatus == 'pending' || c.classificationPending)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.memoStatus == 'pending'
                              ? '纪要待补，盖章已生效。已启用 AI 时会在 App 活跃期间继续整理。'
                              : '记录保留在 ALL，可手动选择归属计划。',
                        ),
                        if (mine && c.memoStatus == 'pending')
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    setState(() => busy = true);
                                    try {
                                      for (final photo in c.photos.where(
                                        (p) => p.cleanupStatus != 'pending',
                                      )) {
                                        await ref
                                            .read(repositoryProvider)
                                            .action(
                                              'retry_photo_ai',
                                              args: {'media_id': photo.id},
                                            );
                                      }
                                      if (context.mounted) {
                                        feedback(
                                          context,
                                          '已加入本机补生成任务，可离开当前页面。',
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        feedback(context, e.toString());
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                            child: Text(busy ? '正在加入任务' : '补生成纪要'),
                          ),
                      ],
                    )
                  else if (c.memoStatus == 'unavailable')
                    Text(
                      c.summary.isEmpty
                          ? '纪要暂未生成。你可以先写下自己的记录。'
                          : '自动整理暂不可用，你的纪要已保留。',
                    ),
                  if (c.summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      c.summary,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  ...c.fields.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(f.label)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  f.displayValue,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  sourceLabel(f.source),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (mine &&
                (c.unassignedFields.isNotEmpty ||
                    c.unassignedSummary.isNotEmpty))
              BatchDraftCard(
                key: ValueKey('batch-draft-${c.id}'),
                original: c,
                snapshot: s,
              ),
            if (mine) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => edit(c),
                icon: const Icon(CupertinoIcons.pencil),
                label: const Text('编辑纪要'),
              ),
              const SectionTitle('归类到计划'),
              DropdownButtonFormField<String>(
                initialValue: s.plans.any((p) => p.id == c.planId)
                    ? c.planId
                    : null,
                decoration: const InputDecoration(labelText: '盖章后 24 小时内可以改标签'),
                items: s.plans
                    .map(
                      (p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.title)),
                    )
                    .toList(),
                onChanged: (id) async {
                  if (id != null) {
                    await runAction(context, ref, 'reclassify', {
                      'checkin_id': c.id,
                      'plan_id': id,
                    });
                  }
                },
              ),
            ],
            if (c.status == 'redo_required') ...[
              const SizedBox(height: 18),
              Paper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '需要一份新记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('质疑已过半，连续记录暂时冻结。请在次日 12:00 前重新打卡。'),
                    if (mine)
                      FilledButton(
                        onPressed: () => context.push(
                          '/checkin?plan=${c.planId ?? ''}&redo=${c.id}&date=${c.localDate}',
                        ),
                        child: const Text('重新打卡'),
                      ),
                  ],
                ),
              ),
            ],
            const SectionTitle('队友的回应'),
            if (c.challengeCount > 0)
              Text(
                '${c.challengeCount}/${c.challengeThreshold} 位队友提出质疑。未过半不影响盖章。',
              ),
            ...c.comments.map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PersonAvatar(
                  m.nickname,
                  url: m.avatarUrl,
                  userId: m.userId,
                ),
                title: Text('${m.nickname}${m.isChallenge ? ' · 质疑' : ''}'),
                subtitle: Text(m.content),
              ),
            ),
            if (s.team != null && c.isCompleted) ...[
              TextField(
                controller: comment,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(labelText: '写一句回应'),
              ),
              if (!mine)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('质疑这张卡'),
                  subtitle: const Text('请写明理由，每天最多 2 次。'),
                  value: challenge,
                  onChanged: (v) => setState(() => challenge = v ?? false),
                ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (comment.text.trim().isEmpty) {
                          feedback(context, challenge ? '写一句质疑理由' : '先写一句回应');
                          return;
                        }
                        setState(() => busy = true);
                        final r = await runAction(context, ref, 'interact', {
                          'checkin_id': c.id,
                          'kind': challenge ? 'challenge' : 'comment',
                          'content': comment.text.trim(),
                        });
                        if (mounted) {
                          setState(() => busy = false);
                          if (r != null) comment.clear();
                        }
                      },
                child: Text(busy ? '正在发送' : '发送回应'),
              ),
            ],
          ],
        ),
      );
    },
  );
}
