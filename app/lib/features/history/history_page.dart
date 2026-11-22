import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../data/app_controller.dart';
import '../../domain/rules.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String? nextPage, loadIssue;
  bool loadingPage = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(loadPage);
  }

  Future<void> loadPage({bool more = false}) async {
    if (loadingPage) return;
    setState(() => loadingPage = true);
    try {
      final page = await ref
          .read(appControllerProvider.notifier)
          .loadPage('history', cursor: more ? nextPage : null, append: more);
      if (mounted) {
        setState(() {
          nextPage = nullableString(page['next_cursor']);
          calendar = jsonObject(page['calendar']);
          loadIssue = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadIssue = e.toString());
    } finally {
      if (mounted) setState(() => loadingPage = false);
    }
  }

  JsonMap calendar = {};
  String category = 'all';
  String? selectedDay;
  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) {
      final own = s.checkins
          .where(
            (c) =>
                c.userId == s.profile.id &&
                (s.historyIds == null || s.historyIds!.contains(c.id)),
          )
          .toList();
      final entries = own
          .where(
            (c) =>
                (category == 'all' || c.category == category) &&
                (selectedDay == null || c.localDate == selectedDay),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('一路走来的记录')),
        body: PageBody(
          onRefresh: loadPage,
          children: [
            if (loadingPage) const LinearProgressIndicator(),
            if (loadIssue != null)
              TextButton(onPressed: loadPage, child: Text('$loadIssue，点击重试')),
            if (nextPage != null)
              TextButton(
                onPressed: loadingPage ? null : () => loadPage(more: true),
                child: const Text('加载更多'),
              ),
            Text(
              '不必完美，\n每一天都真实。',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            Paper(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
              child: Column(
                children: [
                  const Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [Text('最近 28 天'), Text('点一天，看看那时的自己')],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    mainAxisExtent: 52,
                    children: List.generate(28, (i) {
                      final date = calendarDateOffset(
                        DateTime.now(),
                        s.timezone,
                        i - 27,
                      );
                      final count = calendar.containsKey(date)
                          ? intValue(calendar[date])
                          : own
                                .where(
                                  (c) => c.localDate == date && c.isCompleted,
                                )
                                .length;
                      return Semantics(
                        label: '$date $count 次记录',
                        selected: selectedDay == date,
                        child: InkWell(
                          onTap: () => setState(
                            () =>
                                selectedDay = selectedDay == date ? null : date,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: count > 0
                                  ? Palette.forest
                                  : Theme.of(context).scaffoldBackgroundColor,
                              border: selectedDay == date
                                  ? Border.all(color: Palette.stamp, width: 2)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              date.substring(8),
                              style: TextStyle(
                                color: count > 0 ? Colors.white : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              children:
                  [
                        'all',
                        'study',
                        'exercise',
                        'food',
                        'sleep',
                        'water',
                        'mindfulness',
                        'custom',
                      ]
                      .map(
                        (c) => ChoiceChip(
                          label: Text(categoryLabel(c)),
                          selected: category == c,
                          onSelected: (_) => setState(() => category = c),
                        ),
                      )
                      .toList(),
            ),
            const SectionTitle('纪要档案'),
            if (entries.isEmpty)
              const EmptyMessage(
                title: '这段时间还没有记录',
                body: '换个日期或分类，或从今天开始记下第一件事。',
              ),
            ...entries.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Paper(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CategoryMark(c.category),
                    title: Text(
                      c.summary.isEmpty ? '纪要生成中' : c.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${c.localDate} · ${checkinStatusLabel(c.status)}',
                    ),
                    onTap: () => context.push('/memo/${c.id}'),
                  ),
                ),
              ),
            ),
            const SectionTitle('补上昨天'),
            Text(
              '本月还剩 ${s.profile.makeupRemaining} 张补卡。次日 12:00 前可补，使用今天的照片并写明原因。',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: s.plans
                  .where((p) => p.isActive)
                  .map(
                    (p) => OutlinedButton(
                      onPressed: () => context.push(
                        '/checkin?plan=${p.id}&date=${calendarDateOffset(DateTime.now(), s.timezone, -1)}',
                      ),
                      child: Text('补 ${p.title}'),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    },
  );
}
