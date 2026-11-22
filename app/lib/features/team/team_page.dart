import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_controller.dart';
import '../../domain/models.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';
import '../../ui/record_image.dart';
import '../../ui/photo_viewer.dart';
import '../../ui/tuantuan.dart';
import '../reports/shared_report_card.dart';

class TeamPage extends ConsumerStatefulWidget {
  const TeamPage({super.key});
  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> {
  String? next;
  bool busy = false;
  String? issue;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => load());
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final page = await ref
          .read(appControllerProvider.notifier)
          .loadPage('checkins', cursor: more ? next : null, append: more);
      if (!more) {
        await Future.wait([
          ref.read(appControllerProvider.notifier).loadPage('overdue'),
          ref.read(appControllerProvider.notifier).loadPage('reports'),
        ]);
      }
      if (mounted) {
        setState(() {
          next = nullableString(page['next_cursor']);
          issue = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => issue = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) => Scaffold(
      appBar: AppBar(
        title: Text(s.team?.name ?? '一起更容易'),
        actions: [
          IconButton(
            tooltip: '小队管理与邀请',
            onPressed: () => context.push('/invite'),
            icon: const Icon(CupertinoIcons.person_add),
          ),
        ],
      ),
      body: PageBody(
        onRefresh: () async {
          await ref.read(appControllerProvider.notifier).refresh();
          await load();
        },
        children: [
          if (s.team == null && isTuanTuan(context)) ...[
            const TuanTuanHero(title: '找个搭子，一起出发。', body: '团团陪你把小目标，变成每天的小进步。'),
            const SizedBox(height: 20),
          ],
          if (s.team == null)
            EmptyMessage(
              title: '目标不同，也能一起坚持。',
              body: '邀请 1–4 位朋友。你读书，他跑步，互相看见每天的进展。',
              action: FilledButton(
                onPressed: () => context.push('/invite'),
                child: const Text('创建或加入小队'),
              ),
            ),
          if (s.team != null) ...[
            if (isTuanTuan(context)) ...[
              TuanTuanHero(
                title: '一起坚持，\n多点勇气。',
                body: '${s.team!.members.length} 位同行者，互相看见每一点进步。',
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.flame_fill,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '共同坚持 ${s.team!.streak} 天',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '全员完成当天计划才增加 · ${s.timezone}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                '有人同行，每一步都算数。',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text('${s.team!.members.length} 位同行者 · ${s.timezone}'),
              const SizedBox(height: 8),
              Text('共同坚持 ${s.team!.streak} 天 · 全员完成当天计划才增加'),
            ],
            if (s.team!.weeklyStreak > 0)
              Text('每周目标共同连续达标 ${s.team!.weeklyStreak} 周'),
            const SizedBox(height: 22),
            Wrap(
              spacing: isTuanTuan(context) ? 14 : 20,
              runSpacing: 16,
              children: s.team!.members
                  .map(
                    (m) => SizedBox(
                      width: isTuanTuan(context)
                          ? MediaQuery.textScalerOf(context).scale(58)
                          : 65,
                      child: Column(
                        children: [
                          PersonAvatar(
                            m.nickname,
                            url: m.avatarUrl,
                            userId: m.id,
                            size: isTuanTuan(context) ? 58 : 50,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            m.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isTuanTuan(context)) const SizedBox(height: 4),
                          Text(
                            switch (m.status) {
                              'completed' => '已完成',
                              'in_progress' => '进行中',
                              'makeup' => '已补卡',
                              _ => '未开始',
                            },
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SectionTitle('小队动态'),
          ],
          ...s.overdue.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Paper(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF332B12)
                    : const Color(0xFFFFF6D6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.clock),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${o.nickname} · ${o.status == 'resolved' ? '已补上' : '还差一张记录'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(o.title),
                    const SizedBox(height: 4),
                    Text(
                      '${o.pokeCount} 位队友提醒过',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (o.userId != s.profile.id && o.status != 'resolved')
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          onPressed: o.poked
                              ? null
                              : () => runAction(context, ref, 'poke', {
                                  'overdue_id': o.id,
                                }),
                          child: Text(o.poked ? '已戳过' : '戳一下'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ...s.reports
              .where((r) => r.kind == 'personal' && r.shared)
              .map(
                (r) => SharedReportCard(
                  report: r,
                  author:
                      s.team?.members
                          .where((m) => m.id == r.userId)
                          .firstOrNull
                          ?.nickname ??
                      s.profile.nickname,
                ),
              ),
          ...s.checkins
              .where((c) => s.feedIds == null || s.feedIds!.contains(c.id))
              .map((c) => CheckinCard(checkin: c)),
          if (issue != null)
            TextButton(onPressed: () => load(), child: Text('$issue · 重试')),
          if (busy) const Center(child: CircularProgressIndicator.adaptive()),
          if (next != null && !busy)
            TextButton(
              onPressed: () => load(more: true),
              child: const Text('加载更多动态'),
            ),
          if (s.team != null && s.checkins.isEmpty)
            const EmptyMessage(
              title: '把第一份坚持留在这里',
              body: '每次盖章都会成为一条记录，队友可以点赞和留言。',
            ),
        ],
      ),
    ),
  );
}

class CheckinCard extends ConsumerWidget {
  const CheckinCard({super.key, required this.checkin});
  final Checkin checkin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = checkin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PersonAvatar(c.nickname, url: c.avatarUrl, userId: c.userId),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.nickname,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${CategoryMark.label(c.category)} · ${c.localDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StampLabel(text: checkinStatusLabel(c.status), compact: true),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              c.summary.isEmpty ? '记录已收好，纪要正在生成。' : c.summary,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (c.photos.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: c.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: c.photos[i].cleanupStatus == 'pending'
                        ? const SizedBox(
                            width: 140,
                            child: Center(child: Text('原图清理中')),
                          )
                        : InkWell(
                            onTap: () => showPhotoViewer(context, c.photos, i),
                            child: RecordImage(
                              c.photos[i].url,
                              width: 140,
                              height: 120,
                            ),
                          ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: c.isCompleted
                      ? () => runAction(context, ref, 'interact', {
                          'checkin_id': c.id,
                          'kind': 'like',
                        })
                      : null,
                  icon: Icon(
                    c.liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    size: 20,
                  ),
                  label: Text('${c.likes}'),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/memo/${c.id}'),
                  icon: const Icon(CupertinoIcons.chat_bubble, size: 20),
                  label: Text('${c.comments.length}'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/memo/${c.id}'),
                  child: const Text('看纪要'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
