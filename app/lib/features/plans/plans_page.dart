import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../data/app_controller.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';
import '../../ui/tuantuan.dart';

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});
  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  final query = TextEditingController();
  String category = 'all', status = 'active';
  List<Plan> plans = [];
  String? next, issue;
  bool busy = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final version = ++revision;
    setState(() {
      busy = true;
      issue = null;
    });
    try {
      final page = jsonObject(
        await ref
            .read(repositoryProvider)
            .action(
              'read_page',
              args: {
                'collection': 'plans',
                'query': query.text.trim(),
                'category': category,
                'status': status,
                if (more && next != null) 'cursor': next,
              },
            ),
      );
      if (!mounted || version != revision) return;
      final rows = jsonList(page['items'])
          .map((v) => Plan.fromJson(jsonObject(v)))
          .toList();
      setState(() {
        plans = more
            ? {
                ...{for (final p in plans) p.id: p},
                ...{for (final p in rows) p.id: p},
              }.values.toList()
            : rows;
        next = nullableString(page['next_cursor']);
      });
    } catch (e) {
      if (mounted && version == revision) setState(() => issue = e.toString());
    } finally {
      if (mounted && version == revision) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的计划'),
      actions: [
        IconButton(
          tooltip: '历史记录',
          onPressed: () => context.push('/history'),
          icon: const Icon(CupertinoIcons.calendar),
        ),
        IconButton(
          tooltip: '新建计划',
          onPressed: () async {
            await context.push('/plan/new');
            if (mounted) await load();
          },
          icon: const Icon(CupertinoIcons.add),
        ),
      ],
    ),
    body: PageBody(
      onRefresh: load,
      children: [
        if (isTuanTuan(context))
          const TuanTuanHero(
            title: '找到你的节奏。',
            body: '固定星期、滚动周期或间隔排期，都可以是适合你的坚持。',
            pose: TuanTuanPose.read,
          ),
        const SizedBox(height: 16),
        TextField(
          controller: query,
          decoration: InputDecoration(
            labelText: '搜索计划名称',
            suffixIcon: IconButton(
              tooltip: '搜索',
              onPressed: load,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => load(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
                      label: Text(c == 'all' ? '全部分类' : CategoryMark.label(c)),
                      selected: category == c,
                      onSelected: (_) {
                        setState(() => category = c);
                        load();
                      },
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: '计划状态'),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('进行中')),
            DropdownMenuItem(value: 'paused', child: Text('已暂停')),
            DropdownMenuItem(value: 'ended', child: Text('已结束')),
            DropdownMenuItem(value: 'all', child: Text('全部状态')),
          ],
          onChanged: (v) {
            setState(() => status = v!);
            load();
          },
        ),
        const SizedBox(height: 20),
        if (busy) const LinearProgressIndicator(),
        if (issue != null)
          TextButton(onPressed: load, child: Text('$issue，点击重试')),
        if (!busy && issue == null && plans.isEmpty)
          const EmptyMessage(title: '还没有符合条件的计划', body: '换个条件，或创建一个适合你的新目标。'),
        ...plans.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Paper(
              child: InkWell(
                onTap: () async {
                  final saved = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute<Object?>(
                      builder: (_) => PlanEditorPage(plan: p),
                    ),
                  );
                  if (mounted) {
                    await load();
                    final effectiveOn = saved is Map
                        ? nullableString(saved['effective_on'])
                        : null;
                    if (effectiveOn != null && context.mounted) {
                      feedback(context, '计划修改已保存，将于 $effectiveOn 生效');
                    }
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CategoryMark(p.category),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const Icon(CupertinoIcons.chevron_right, size: 16),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (p.goal.isNotEmpty) Text(p.goal),
                    Text('当前频率 · ${p.scheduleLabel}'),
                    if (p.pendingScheduleLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '已保存，${p.effectiveOn ?? '下周'} 生效 · ${p.pendingScheduleLabel}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      p.scheduleKind == 'weekly_target'
                          ? '本周 ${p.weeklyCompleted}/${p.weeklyTarget} 天 · 连续达标 ${p.weeklyStreak} 周'
                          : p.scheduleKind == 'period_target'
                          ? '本周期 ${p.periodCompleted}/${p.periodTarget} 天 · 连续达标 ${p.periodStreak} 期'
                          : '${p.startTime} - ${p.deadline} · 连续完成 ${p.streak ?? 0} 次',
                    ),
                    if (p.extraDays > 0 && p.scheduleKind == 'weekly_target')
                      Text('比本周目标多 ${p.extraDays} 天'),
                    if (p.periodExtraDays > 0 &&
                        p.scheduleKind == 'period_target')
                      Text('本周期比目标多 ${p.periodExtraDays} 天'),
                    Text(
                      p.visibility == 'private' ? '仅自己可见' : '小队可见',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (next != null)
          OutlinedButton(
            onPressed: busy ? null : () => load(more: true),
            child: const Text('加载更多计划'),
          ),
      ],
    ),
  );
}

class PlanEditorPage extends ConsumerStatefulWidget {
  const PlanEditorPage({super.key, this.plan});
  final Plan? plan;
  @override
  ConsumerState<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends ConsumerState<PlanEditorPage> {
  final _form = GlobalKey<FormState>();
  JsonMap get _pending => widget.plan?.pendingChanges ?? const {};
  Object? _config(String key, Object? current) =>
      _pending.containsKey(key) ? _pending[key] : current;

  late final TextEditingController title = TextEditingController(
    text: stringValue(_config('title', widget.plan?.title)),
  );
  late final TextEditingController goal = TextEditingController(
    text: stringValue(_config('goal', widget.plan?.goal)),
  );
  late String category = stringValue(
    _config('category', widget.plan?.category),
    'study',
  );
  late Set<int> days = jsonList(
    _config('weekdays', widget.plan?.weekdays ?? [1, 2, 3, 4, 5]),
  ).map((v) => intValue(v)).where((v) => v >= 1 && v <= 7).toSet();
  late String start = stringValue(
        _config('start_time', widget.plan?.startTime),
        '08:00',
      ),
      end = stringValue(_config('deadline', widget.plan?.deadline), '21:00'),
      visibility = stringValue(
        _config('visibility', widget.plan?.visibility),
        'team',
      ),
      status = stringValue(_config('status', widget.plan?.status), 'active');
  late String scheduleKind = _initialScheduleKind();
  String _initialScheduleKind() {
    final kind = stringValue(
      _config('schedule_kind', widget.plan?.scheduleKind),
      'weekdays',
    );
    return kind == 'weekly_target' ? 'period_target' : kind;
  }

  int _initialPeriodTarget() {
    if (_pending.containsKey('period_target_days')) {
      return intValue(_pending['period_target_days'], 3);
    }
    if (_pending.containsKey('weekly_target_days')) {
      return intValue(_pending['weekly_target_days'], 3);
    }
    if (widget.plan?.scheduleKind == 'weekly_target') {
      return widget.plan!.weeklyTargetDays;
    }
    return widget.plan?.periodTargetDays ?? 3;
  }

  late final TextEditingController period = TextEditingController(
    text: '${intValue(_config('period_days', widget.plan?.periodDays), 7)}',
  );
  late final TextEditingController periodTarget = TextEditingController(
    text: '${_initialPeriodTarget()}',
  );
  late final interval = TextEditingController(
    text: '${intValue(_config('interval_days', widget.plan?.intervalDays), 2)}',
  );
  late String anchor =
      nullableString(_config('anchor_date', widget.plan?.anchorDate)) ??
      localDate(
        DateTime.now(),
        ref.read(appControllerProvider).asData?.value.timezone ??
            'Asia/Shanghai',
      );
  bool busy = false;
  @override
  void dispose() {
    interval.dispose();
    period.dispose();
    periodTarget.dispose();
    title.dispose();
    goal.dispose();
    super.dispose();
  }

  Future<void> chooseTime(bool isStart) async {
    final current = (isStart ? start : end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(current[0]),
        minute: int.parse(current[1]),
      ),
    );
    if (picked != null) {
      setState(() {
        final value =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        if (isStart) {
          start = value;
        } else {
          end = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.plan == null ? '新建计划' : '调整计划')),
    body: PageBody(
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '给坚持一个具体的名字',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                children:
                    [
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
                            label: Text(CategoryMark.label(c)),
                            selected: category == c,
                            onSelected: (_) => setState(() {
                              category = c;
                              if (widget.plan == null) {
                                final template = switch (c) {
                                  'study' => ('读几页书', '用书页照片记录今天的阅读'),
                                  'exercise' => ('动一动', '用运动照片或记录截图留证'),
                                  'food' => ('认真吃一餐', '拍下今天的一餐'),
                                  'sleep' => ('规律作息', '用当天作息记录截图留证'),
                                  'water' => ('记得喝水', '用照片或记录截图留证，饮水量可手填'),
                                  'mindfulness' => ('留一点安静', '用照片或冥想记录截图留证'),
                                  _ => ('', ''),
                                };
                                title.text = template.$1;
                                goal.text = template.$2;
                              }
                            }),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: '计划名称',
                  hintText: '例如：每晚读 10 页书',
                ),
                maxLength: 60,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '给计划起个名字' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: goal,
                decoration: const InputDecoration(labelText: '目标与完成方式'),
                maxLines: 3,
                maxLength: 300,
              ),
              const SectionTitle('执行频率'),
              DropdownButtonFormField<String>(
                initialValue: scheduleKind,
                decoration: const InputDecoration(labelText: '频率方式'),
                items: [
                  DropdownMenuItem(value: 'weekdays', child: Text('固定星期')),
                  DropdownMenuItem(
                    value: 'period_target',
                    child: Text('每几天完成几天'),
                  ),
                  DropdownMenuItem(value: 'interval', child: Text('每隔几天')),
                ],
                onChanged: (v) => setState(() => scheduleKind = v!),
              ),
              const SizedBox(height: 16),
              if (widget.plan?.scheduleKind == 'weekly_target' &&
                  !_pending.containsKey('schedule_kind')) ...[
                const Text('这是旧的自然周目标。保存后将改为固定天数周期，原记录不变。'),
                const SizedBox(height: 12),
              ],
              if (scheduleKind == 'period_target') ...[
                TextFormField(
                  key: const ValueKey('period-days-field'),
                  controller: period,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '周期长度',
                    suffixText: '天',
                    helperText: '1 至 365 天，从开始日期起固定分段',
                  ),
                  validator: (value) {
                    final days = int.tryParse(value ?? '');
                    return days == null || days < 1 || days > 365
                        ? '请输入 1 至 365 天'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('period-target-days-field'),
                  controller: periodTarget,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '周期内完成天数',
                    suffixText: '天',
                  ),
                  validator: (value) {
                    final target = int.tryParse(value ?? '');
                    final length = int.tryParse(period.text);
                    return target == null ||
                            target < 1 ||
                            length == null ||
                            target > length
                        ? '完成天数需在 1 至周期长度之间'
                        : null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '每 ${period.text} 天为一个固定周期，任意日期完成 ${periodTarget.text} 天即达标。同一天多次记录只计一天。',
                ),
              ],
              if (scheduleKind == 'interval')
                TextFormField(
                  controller: interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每隔几天执行',
                    helperText: '1 至 365 天，以开始日期固定排期',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 365 ? '请输入 1 至 365' : null;
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始日期'),
                subtitle: Text(anchor),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final initial = DateTime.parse(anchor);
                  final now = DateTime.parse(
                    localDate(
                      DateTime.now(),
                      ref.read(appControllerProvider).requireValue.timezone,
                    ),
                  );
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: widget.plan == null ? now : DateTime(2000),
                    lastDate: now.add(const Duration(days: 3650)),
                  );
                  if (chosen != null) {
                    setState(
                      () => anchor =
                          '${chosen.year}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}',
                    );
                  }
                },
              ),
              if (scheduleKind == 'weekdays')
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(
                    7,
                    (i) => FilterChip(
                      label: Text(['一', '二', '三', '四', '五', '六', '日'][i]),
                      selected: days.contains(i + 1),
                      onSelected: (v) => setState(
                        () => v ? days.add(i + 1) : days.remove(i + 1),
                      ),
                    ),
                  ),
                ),
              const SectionTitle('打卡时段'),
              Paper(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开始时间'),
                      trailing: Text(start),
                      onTap: () => chooseTime(true),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('截止时间'),
                      trailing: Text(end),
                      onTap: () => chooseTime(false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('仅自己可见'),
                subtitle: const Text('私密计划不计入小队完成率'),
                value: visibility == 'private',
                onChanged: (v) =>
                    setState(() => visibility = v ? 'private' : 'team'),
              ),
              if (widget.plan != null) ...[
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '计划状态'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('进行中')),
                    DropdownMenuItem(value: 'paused', child: Text('暂停')),
                    DropdownMenuItem(value: 'ended', child: Text('结束')),
                  ],
                  onChanged: (v) => setState(() => status = v!),
                ),
                const SizedBox(height: 14),
                const Text('频率与时段修改从下周开始执行，本周记录和统计保持不变。保存后会显示待生效日期。'),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!_form.currentState!.validate()) return;
                          if (scheduleKind == 'weekdays' && days.isEmpty) {
                            feedback(context, '至少选择一天');
                            return;
                          }
                          final periodDays = int.tryParse(period.text) ?? 0;
                          final targetDays =
                              int.tryParse(periodTarget.text) ?? 0;
                          if (scheduleKind == 'period_target' &&
                              (periodDays < 1 ||
                                  periodDays > 365 ||
                                  targetDays < 1 ||
                                  targetDays > periodDays)) {
                            feedback(context, '完成天数需在 1 至周期长度之间');
                            return;
                          }
                          setState(() => busy = true);
                          final result = await runAction(
                            context,
                            ref,
                            'save_plan',
                            {
                              'schema_version': 2,
                              'schedule_kind': scheduleKind,
                              if (scheduleKind == 'period_target') ...{
                                'period_days': periodDays,
                                'period_target_days': targetDays,
                              },
                              if (scheduleKind == 'interval')
                                'interval_days': int.tryParse(interval.text),
                              'anchor_date': anchor,
                              'id': widget.plan?.id,
                              'title': title.text.trim(),
                              'goal': goal.text.trim(),
                              'category': category,
                              'weekdays': scheduleKind == 'weekdays'
                                  ? (days.toList()..sort())
                                  : [1, 2, 3, 4, 5, 6, 7],
                              'start_time': start,
                              'deadline': end,
                              'visibility': visibility,
                              'status': status,
                            },
                          );
                          if (mounted) {
                            setState(() => busy = false);
                            if (result != null && context.mounted) {
                              context.pop(result);
                            }
                          }
                        },
                  child: Text(busy ? '正在保存' : '保存计划'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
