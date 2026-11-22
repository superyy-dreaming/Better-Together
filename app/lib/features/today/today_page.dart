import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_controller.dart';
import '../../domain/rules.dart';
import '../../ui/design.dart';
import '../../ui/tuantuan.dart';
import '../../ui/state_view.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SnapshotView(
    builder: (s) {
      final date = localDate(DateTime.now(), s.timezone);
      final plans = s.plans
          .where((p) => planIsDue(p, DateTime.now(), s.timezone))
          .toList();
      final records = s.checkins
          .where(
            (c) =>
                c.userId == s.profile.id &&
                c.localDate == date &&
                c.isCompleted,
          )
          .toList();
      final done = plans
          .where(
            (p) =>
                (p.todayRecordCount > 0 ||
                records.any((c) => c.planId == p.id)),
          )
          .length;
      return Scaffold(
        appBar: AppBar(
          leadingWidth: 70,
          leading: Padding(
            padding: const EdgeInsets.only(left: 18),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: '我的与设置',
              onPressed: () => context.push('/settings'),
              icon: PersonAvatar(s.profile.nickname, url: s.profile.avatarUrl),
            ),
          ),
          title: const Text(
            'Better Together',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: '通知',
              onPressed: () => context.push('/notifications'),
              icon: Badge(
                isLabelVisible: s.unreadCount > 0,
                label: Text('${s.unreadCount}'),
                child: const Icon(CupertinoIcons.bell),
              ),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: () => context.push('/settings'),
              icon: const Icon(CupertinoIcons.gear),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: PageBody(
          onRefresh: () => ref.read(appControllerProvider.notifier).refresh(),
          children: [
            const SizedBox(height: 18),
            Text(
              '${date.substring(5).replaceAll('-', '月')}日 · ${s.timezone}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isTuanTuan(context)) ...[
              TuanTuanHero(
                title: plans.isNotEmpty && done == plans.length
                    ? '今天的你，真棒！'
                    : '今天也一起加油。',
                body:
                    '${s.profile.nickname}，${plans.isEmpty
                        ? '从一件想坚持的小事开始，团团陪你。'
                        : done == plans.length
                        ? '计划都完成啦，给队友也送一点鼓励吧。'
                        : '不用一下子很厉害。完成一件小事，就很棒。'}',
                pose: plans.isNotEmpty && done == plans.length
                    ? TuanTuanPose.celebrate
                    : TuanTuanPose.wave,
              ),
              const SizedBox(height: 16),
              TuanTuanProgress(
                done: done,
                total: plans.length,
                teamLabel: s.team == null
                    ? '一个人开始，也是一种勇气。'
                    : '${s.team!.name} · 共同坚持 ${s.team!.streak} 天',
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text('今天，也一起。', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                '${s.profile.nickname}，${plans.isEmpty
                    ? '给今天留下一点值得记录的事。'
                    : done == plans.length
                    ? '今天的计划已完成，去看看队友吧。'
                    : '先完成一件小事，再盖一个章。'}',
              ),
              const SizedBox(height: 24),
              Paper(
                color: Palette.forest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '今日的坚持',
                            style: TextStyle(
                              color: Color(0xFFDDEBE1),
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          '$done / ${plans.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: plans.isEmpty ? 0 : done / plans.length,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        color: Palette.sun,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.person_2,
                          color: Color(0xFFC4DECA),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.team == null
                                ? '一个人开始，也是一种勇气。'
                                : '${s.team!.name} · 共同坚持 ${s.team!.streak} 天',
                            style: const TextStyle(
                              color: Color(0xFFE2EEE6),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            SectionTitle(
              '今天到期',
              action: TextButton(
                onPressed: () => context.go('/plans'),
                child: const Text('全部计划'),
              ),
            ),
            if (plans.isEmpty)
              EmptyMessage(
                title: '从一个小目标开始',
                body: '学习、运动或好好吃饭。先选一件你想坚持的事。',
                action: FilledButton.icon(
                  onPressed: () => context.push('/plan/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('创建第一个计划'),
                ),
              ),
            ...plans.map((p) {
              final completed =
                  (p.todayRecordCount > 0 ||
                  records.any((c) => c.planId == p.id));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Paper(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CategoryMark(p.category),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  completed
                                      ? '已记录今天的坚持'
                                      : '${p.deadline} 前 · ${CategoryMark.label(p.category)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (completed)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: StampLabel(compact: true),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '连续完成 ${p.streak ?? streakForPlan(p, s.checkins, s.profile.id, DateTime.now(), s.timezone)} 次',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (completed)
                            TextButton(
                              onPressed: () =>
                                  context.push('/checkin?plan=${p.id}'),
                              child: const Text('再记一次'),
                            ),
                          TextButton(
                            onPressed: () => completed
                                ? context.push(
                                    '/memo/${p.todayCheckinId ?? records.firstWhere((c) => c.planId == p.id).id}',
                                  )
                                : context.push('/checkin?plan=${p.id}'),
                            child: Text(completed ? '查看纪要' : '去打卡'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (s.plans.any(
              (p) =>
                  p.scheduleKind == 'weekly_target' ||
                  p.scheduleKind == 'period_target',
            ))
              const SectionTitle('周期目标'),
            ...s.plans
                .where(
                  (p) =>
                      (p.scheduleKind == 'weekly_target' ||
                          p.scheduleKind == 'period_target') &&
                      p.isActive,
                )
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Paper(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.scheduleKind == 'period_target'
                                ? '本周期（${p.periodStart ?? '起始日'} 至 ${p.periodEnd ?? '周期末'}）完成 ${p.periodCompleted} / ${p.periodTarget} 天'
                                : '本周完成 ${p.weeklyCompleted} / ${p.weeklyTarget} 天 · 完整周目标 ${p.weeklyTargetDays} 天',
                          ),
                          if (p.scheduleKind == 'period_target' &&
                              p.periodExtraDays > 0)
                            Text('本周期比目标多 ${p.periodExtraDays} 天，继续保持自己的节奏'),
                          if (p.scheduleKind == 'weekly_target' &&
                              p.extraDays > 0)
                            Text('比目标多 ${p.extraDays} 天，继续保持自己的节奏'),
                          Text(
                            p.scheduleKind == 'period_target'
                                ? '连续达标 ${p.periodStreak} 期'
                                : '连续达标 ${p.weeklyStreak} 周',
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  context.push('/checkin?plan=${p.id}'),
                              child: const Text('记录今天'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            SectionTitle(
              '彼此看见',
              action: TextButton(
                onPressed: () => context.go('/team'),
                child: Text(s.team == null ? '邀请朋友' : '小队动态'),
              ),
            ),
            if (s.team == null) const Text('每个人定自己的目标，一起分享每天的进展。'),
            ...s.checkins
                .where((c) => c.userId != s.profile.id)
                .take(2)
                .map(
                  (c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PersonAvatar(
                      c.nickname,
                      url: c.avatarUrl,
                      userId: c.userId,
                    ),
                    title: Text(c.nickname),
                    subtitle: Text(
                      c.summary.isEmpty ? '记录已盖章，纪要生成中' : c.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                    ),
                    onTap: () => context.push('/memo/${c.id}'),
                  ),
                ),
          ],
        ),
      );
    },
  );
}
