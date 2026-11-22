import 'dart:math' as math;

import '../domain/models.dart';
import '../domain/rules.dart';

/// Hand-authored, local-only fixtures for the supplied 20-image test pack.
/// These are neither live BYOK results nor evidence of model accuracy.
const demoShowcaseSeedVersion = 3;
const _owner = 'demo-owner';
const _zone = 'Asia/Shanghai';
const _assetRoot = 'asset:assets/demo/test-photos/';

JsonMap buildDemoShowcase(DateTime clock) {
  final now = clock.toUtc();
  final today = DateTime.parse('${localDate(now, _zone)}T00:00:00Z');
  final monday = today.subtract(Duration(days: today.weekday - 1));
  String date(DateTime value) => value.toIso8601String().substring(0, 10);
  String day(int ago) => date(today.subtract(Duration(days: ago)));
  final week = date(monday);
  final plans =
      <JsonMap>[
            {
              'id': 'study',
              'title': '每天读 20 页',
              'category': 'study',
              'goal': '给阅读和学习笔记留一点时间',
              'schedule_kind': 'weekdays',
              'start_time': '07:30',
              'deadline': '22:00',
            },
            {
              'id': 'exercise',
              'title': '出门走一走',
              'category': 'exercise',
              'goal': '记录散步、跑步或其他运动，不从照片推算时长',
              'schedule_kind': 'interval',
              'interval_days': 2,
              'anchor_date': day(6),
              'start_time': '17:00',
              'deadline': '20:00',
            },
            {
              'id': 'water',
              'title': '每 5 天喝够水',
              'category': 'water',
              'goal': '每 5 天完成 3 天记录，等待添加自己的饮水凭证',
              'schedule_kind': 'period_target',
              'period_days': 5,
              'period_target_days': 3,
              'weekly_target_days': 3,
              'start_time': '08:00',
              'deadline': '22:00',
            },
            {
              'id': 'food',
              'title': '好好吃饭',
              'category': 'food',
              'goal': '记录看得见的食物，热量只作区间估算',
              'schedule_kind': 'weekdays',
              'visibility': 'private',
              'start_time': '07:00',
              'deadline': '21:00',
            },
            {
              'id': 'meditation',
              'title': '睡前冥想 10 分钟',
              'category': 'meditation',
              'goal': '每周完成 3 天，等待添加凭证',
              'schedule_kind': 'weekly_target',
              'weekly_target_days': 3,
              'start_time': '21:00',
              'deadline': '23:00',
            },
          ]
          .map(
            (p) => <String, Object?>{
              'user_id': _owner,
              'weekdays': [1, 2, 3, 4, 5, 6, 7],
              'anchor_date': week,
              'visibility': 'team',
              'status': 'active',
              ...p,
            },
          )
          .toList();
  final planById = {for (final p in plans) p['id']: p};

  JsonMap field(
    String key,
    String label,
    Object value, {
    String source = 'ai',
  }) => {
    'key': key,
    'label': label,
    'value': value,
    'source': source,
    'confidence': .94,
  };
  JsonMap foodEstimate(int low, int high) => field('calories', '热量（估算）', {
    'min': low,
    'max': high,
    'unit': 'kcal',
    'estimated': true,
  });
  final fixtures = <String, JsonMap>{
    'study-01': {'summary': '笔记本上写有英语单词、中文释义和例句。'},
    'study-02': {'summary': '教材中介绍工业革命的内容被荧光笔划线，旁边放着一杯咖啡。'},
    'study-03': {'summary': '电脑显示代码编辑器，旁边的纸质笔记记录了编程要点。'},
    'study-04': {'summary': '图书馆桌面上摊着一本书，书页上放着眼镜。'},
    'study-05': {'summary': '纸面写有数学公式、计算过程和几何图。'},
    'sport-01': {
      'summary': '跑步机屏幕显示 35:20、5.02 km 和 286 kcal；未显示完整日期，日期待核实。',
      'source': 'screenshot',
      'recognition_status': 'pending',
      'fields': [
        field('duration_seconds', '运动时长（秒）', 2120, source: 'screenshot'),
        field('distance', '距离（km）', 5.02, source: 'screenshot'),
        field('calories', '消耗（kcal）', 286, source: 'screenshot'),
      ],
    },
    'sport-02': {
      'summary': '运动记录页显示 2026年11月22日，距离 5.20 km、时长 32分15秒、消耗 312 kcal。',
      'source': 'screenshot',
      'screenshot_date': '2026-11-22',
      'fields': [
        field('duration_seconds', '运动时长（秒）', 1935, source: 'screenshot'),
        field('distance', '距离（km）', 5.20, source: 'screenshot'),
        field('calories', '消耗（kcal）', 312, source: 'screenshot'),
      ],
    },
    'sport-03': {'summary': '画面中有人站在健身房的哑铃架前；未记录运动时长或消耗。'},
    'sport-04': {'summary': '公园跑道边拍下了跑鞋和树荫；未记录运动时长、距离或消耗。'},
    'sport-05': {'summary': '画面中有人在客厅的瑜伽垫上拉伸；未记录运动时长或消耗。'},
    'sport-06': {'summary': '河边骑行道旁停着一辆自行车；未记录骑行距离、时长或消耗。'},
    'food-01': {
      'summary': '餐碗里有鸡胸肉、鸡蛋、玉米和蔬菜。热量约 400-650 kcal（估算）。',
      'fields': [foodEstimate(400, 650)],
    },
    'food-02': {
      'summary': '碗里是牛肉面，旁边放着一小碟配菜。热量约 550-850 kcal（估算）。',
      'fields': [foodEstimate(550, 850)],
    },
    'food-03': {'summary': '盘中有煎蛋、吐司和香肠，旁边是一杯牛奶。'},
    'food-04': {'summary': '桌上放着草莓、香蕉等水果拼盘和一碗酸奶。'},
    'food-05': {'summary': '家常饭菜包括米饭、炒菜、蒸鱼和汤；照片未提供食材重量。'},
    'life-01': {'summary': '沙发旁摆着木吉他和打开的乐谱，没有对应计划，保留 ALL。'},
    'life-02': {'summary': '桌面上有正在绘制的山水水彩、调色盘和画笔，保留 ALL。'},
    'life-03': {'summary': '傍晚街道上有人牵着金毛散步，仅作生活记录，保留 ALL。'},
    'life-04': {'summary': '桌面上有写着“静心”的书法纸、毛笔和墨碟，保留 ALL。'},
  };

  JsonMap comment(String id, String user, String name, String text) => {
    'id': id,
    'user_id': user,
    'nickname': name,
    'content': text,
    'created_at': now.subtract(const Duration(minutes: 18)).toIso8601String(),
    'is_challenge': false,
  };
  JsonMap record(
    String id,
    String user,
    String name,
    String? planId,
    List<String> files,
    int ago, {
    String? batchId,
    String? targetDate,
    String status = 'stamped',
    int minutes = 0,
    int likes = 0,
    int challenges = 0,
    List<JsonMap> comments = const [],
  }) {
    final localDay = targetDate ?? day(ago);
    final photos = files.map((key) {
      final fixture = fixtures[key]!;
      final photoId = 'demo-photo-$id-$key';
      final pending = fixture['recognition_status'] == 'pending';
      return <String, Object?>{
        'id': photoId, 'url': '$_assetRoot$key.jpg',
        'source': fixture['source'] ?? 'album',
        // A local fixture timestamp; it is not claimed to be original EXIF.
        'captured_at': '${localDay}T04:00:00Z',
        'demo_fixture': true,
        'plan_id': planId, 'confidence': planId == null ? 0.0 : .94,
        'recognition': {
          'photo_id': photoId,
          'status': pending ? 'pending' : 'ready',
          'plan_id': planId,
          'confidence': planId == null ? 0.0 : .94,
          'summary': fixture['summary'],
          'fields': fixture['fields'] ?? <Object?>[],
          'screenshot_date': fixture['screenshot_date'],
          'origin': 'demo_fixture',
          if (pending)
            'error': {
              'code': 'date_unverified',
              'message': '合成素材未显示完整日期，待核实；已保留可见读数。',
            },
        },
      };
    }).toList();
    final category = planId == null ? 'all' : planById[planId]!['category'];
    final fields = <Object?>[
      for (final file in files) ...jsonList(fixtures[file]!['fields']),
    ];
    final summary = files
        .map((key) => stringValue(fixtures[key]!['summary']))
        .join('\n');
    return {
      'id': id,
      'user_id': user,
      'nickname': name,
      'plan_id': planId,
      'category': category,
      'visibility': planId == null
          ? 'private'
          : planById[planId]!['visibility'],
      'batch_id': batchId ?? 'seed-$id',
      'local_date': localDay,
      'status': status,
      'is_makeup': status == 'makeup',
      'is_late': status == 'makeup',
      'created_at': now
          .subtract(Duration(days: ago, minutes: minutes))
          .toIso8601String(),
      'summary': summary,
      'memo_status': 'ready',
      'classification_pending': false,
      'fields': fields,
      'photos': photos,
      'demo_fixture': true,
      'likes': likes,
      'liked': false,
      'comments': comments,
      'challenge_count': challenges,
      'challenge_threshold': 3,
    };
  }

  final checkins = <JsonMap>[
    record(
      'today-study',
      _owner,
      '知夏',
      'study',
      ['study-01'],
      0,
      batchId: 'demo-mixed-batch',
      minutes: 78,
      likes: 3,
      comments: [
        comment('demo-comment-1', 'demo-yu', '小予', '把例句和释义放在一起，很方便回看。'),
      ],
    ),
    record(
      'today-exercise',
      _owner,
      '知夏',
      'exercise',
      ['sport-04'],
      0,
      batchId: 'demo-mixed-batch',
      minutes: 42,
      likes: 2,
    ),
    record(
      'today-dinner',
      _owner,
      '知夏',
      'food',
      ['food-01'],
      0,
      batchId: 'demo-mixed-batch',
      minutes: 12,
    ),
    record(
      'friend-exercise',
      'demo-yu',
      '小予',
      'exercise',
      ['sport-03'],
      0,
      minutes: 26,
      likes: 5,
      challenges: 1,
      comments: [comment('demo-comment-2', _owner, '知夏', '今天也给运动留了一点时间。')],
    ),
    record(
      'friend-study',
      'demo-chen',
      '陈一',
      'study',
      ['study-03'],
      0,
      minutes: 105,
      likes: 1,
    ),
    record(
      'friend-makeup',
      'demo-an',
      '安然',
      'study',
      ['study-04'],
      1,
      status: 'makeup',
    ),
    record(
      'friend-challenge',
      'demo-lin',
      '林晓',
      'study',
      ['study-05'],
      2,
      status: 'redo_required',
      challenges: 3,
    ),
    record('study-1', _owner, '知夏', 'study', ['study-02'], 1),
    record('exercise-1', _owner, '知夏', null, ['sport-01'], 2),
    record(
      'exercise-2',
      _owner,
      '知夏',
      'exercise',
      ['sport-02'],
      0,
      targetDate: '2026-11-22',
      minutes: 120,
    ),
    record('exercise-3', _owner, '知夏', 'exercise', ['sport-05'], 4),
    record('exercise-4', _owner, '知夏', 'exercise', ['sport-06'], 6),
    record('food-noodles', _owner, '知夏', 'food', ['food-02'], 1),
    record('food-breakfast', _owner, '知夏', 'food', ['food-03', 'food-04'], 2),
    record('food-home', _owner, '知夏', 'food', ['food-05'], 3),
    record('life-guitar', _owner, '知夏', null, ['life-01'], 0, minutes: 160),
    record('life-watercolor', _owner, '知夏', null, ['life-02'], 0, minutes: 180),
    record('life-walk', _owner, '知夏', null, ['life-03'], 1),
    record('life-calligraphy', _owner, '知夏', null, ['life-04'], 1),
  ];
  final personalMetrics = _weekMetrics(plans, checkins, _owner, monday);
  final memberPlans = <String, List<JsonMap>>{
    _owner: plans,
    'demo-yu': [planById['exercise']!],
    'demo-chen': [planById['study']!],
    'demo-lin': [planById['study']!],
    'demo-an': [planById['study']!],
  };
  final members = <JsonMap>[
    {'id': _owner, 'nickname': '知夏', 'status': 'in_progress'},
    {'id': 'demo-yu', 'nickname': '小予', 'status': 'completed'},
    {'id': 'demo-chen', 'nickname': '陈一', 'status': 'completed'},
    {'id': 'demo-lin', 'nickname': '林晓', 'status': 'not_started'},
    {'id': 'demo-an', 'nickname': '安然', 'status': 'makeup'},
  ];
  final teamMetrics = _teamMetrics(memberPlans, checkins, monday);
  final peerMetrics = _weekMetrics(
    memberPlans['demo-yu']!,
    checkins,
    'demo-yu',
    monday,
    publicOnly: true,
  );
  for (final plan in plans) {
    final domainPlan = Plan.fromJson(plan);
    final stats = _planCounts(domainPlan, checkins, _owner, monday);
    plan['weekly_target'] = stats['expected'];
    plan['weekly_completed'] = stats['completed'];
    plan['extra_days'] = stats['extra_days'];
    plan['weekly_streak'] =
        domainPlan.scheduleKind == 'weekly_target' &&
            intValue(stats['expected']) > 0 &&
            intValue(stats['completed']) >= intValue(stats['expected'])
        ? 1
        : 0;
    if (domainPlan.scheduleKind == 'period_target') {
      final anchor = DateTime.parse('${domainPlan.anchorDate}T00:00:00Z');
      final elapsed = today.difference(anchor).inDays;
      final periodStart = anchor.add(
        Duration(
          days: (elapsed ~/ domainPlan.periodDays) * domainPlan.periodDays,
        ),
      );
      plan['period_start'] = date(periodStart);
      plan['period_end'] = date(
        periodStart.add(Duration(days: domainPlan.periodDays - 1)),
      );
      plan['period_target'] = domainPlan.periodTargetDays;
      plan['period_completed'] = 0;
      plan['period_streak'] = 0;
    }
    plan['streak'] = streakForPlan(
      domainPlan,
      checkins.map(Checkin.fromJson).toList(),
      _owner,
      now,
      _zone,
    );
    final todayRecords = checkins.where(
      (c) =>
          c['user_id'] == _owner &&
          c['plan_id'] == plan['id'] &&
          c['local_date'] == day(0) &&
          _isCompleted(c),
    );
    plan['today_record_count'] = todayRecords.length;
    plan['today_checkin_id'] = todayRecords.firstOrNull?['id'];
  }
  JsonMap report(
    String id,
    String user,
    String kind,
    String title,
    String summary,
    JsonMap metrics, {
    bool shared = false,
  }) => {
    'id': id,
    'user_id': user,
    'week_start': week,
    'kind': kind,
    'title': title,
    'summary': summary,
    'metrics': metrics,
    'stage': 'phase',
    'generated_at': now.toIso8601String(),
    'ai_status': 'rules',
    'shared': shared,
    'refreshed': false,
    'demo_fixture': true,
  };
  JsonMap notification(
    String id,
    String kind,
    String title,
    String body,
    String target,
  ) => {
    'id': id,
    'kind': kind,
    'title': title,
    'body': body,
    'target_id': target,
    'read': false,
    'created_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
  };
  return {
    'demo_seed_version': demoShowcaseSeedVersion,
    'demo_dataset': 'better-together-test-photos-2026-11-22',
    'profile': {
      'id': _owner,
      'nickname': '知夏',
      'timezone': _zone,
      'makeup_remaining': 2,
      'notification_preferences': {
        'all': true,
        'poke': true,
        'overdue': true,
        'report': true,
        'interaction': true,
        'challenge': true,
      },
    },
    'team': {
      'id': 'demo-team',
      'name': '把日子过好小队',
      'timezone': _zone,
      'owner_id': _owner,
      'streak': 0,
      'members': members,
    },
    'plans': plans,
    'checkins': checkins,
    'feed_ids': [
      for (final c in checkins)
        if (c['visibility'] == 'team') c['id'],
    ],
    'history_ids': [
      for (final c in checkins)
        if (c['user_id'] == _owner) c['id'],
    ],
    'reports': [
      {
        ...report(
          'demo-report',
          _owner,
          'personal',
          '看得见的这一周',
          '本周留下 ${personalMetrics['checkins']} 条记录，完成 ${personalMetrics['completed']} / ${personalMetrics['expected']} 个计划日。照片与纪要均为本地合成演示数据。',
          personalMetrics,
        ),
        'highlights': [
          '英语笔记与阅读书页都有留下记录。',
          '普通运动照片不推算时长，运动截图单独展示读数。',
          '吉他和生活散步保留 ALL，不冒充计划完成。',
        ],
        'suggestion': {'text': '继续记录实际做过的事。饮水和冥想计划还没有凭证，完成后再补充。'},
      },
      {
        ...report(
          'demo-team-report',
          _owner,
          'team',
          '把日子过好小队 · 本周合影',
          '5 位成员本周留下 ${teamMetrics['checkins']} 条公开记录，共完成 ${teamMetrics['completed']} 个计划日。仅统计小队可见内容，全部为本地合成演示数据。',
          teamMetrics,
        ),
        'highlights': [
          '小予留下健身房记录，陈一记录编程学习。',
          '安然补上阅读凭证，林晓的数学记录等待重打。',
          '生活兴趣记录保留 ALL，私人饮食记录不进入小队周报。',
        ],
      },
      report(
        'demo-peer-report',
        'demo-yu',
        'personal',
        '给运动留一点时间',
        '本周记录了一次健身房到场，没有从照片推算时长或消耗。本地合成演示数据。',
        peerMetrics,
        shared: true,
      ),
    ],
    'overdue': [
      {
        'id': 'demo-overdue',
        'user_id': 'demo-lin',
        'plan_id': 'study',
        'title': '今天的学习记录',
        'nickname': '林晓',
        'deadline_at': now
            .subtract(const Duration(minutes: 48))
            .toIso8601String(),
        'status': 'open',
        'poke_count': 1,
        'poked': false,
      },
    ],
    'notifications': [
      notification(
        'demo-notification',
        'report',
        '你的素材周报已生成',
        '查看这套合成素材组成的本地演示周报。',
        'demo-report',
      ),
      notification(
        'demo-notification-comment',
        'interaction',
        '小予评论了你的学习记录',
        '把例句和释义放在一起，很方便回看。',
        'today-study',
      ),
      notification(
        'demo-notification-challenge',
        'challenge',
        '林晓的记录进入待重打',
        '这是质疑过半状态的本地演示，请查看记录。',
        'friend-challenge',
      ),
      notification(
        'demo-notification-overdue',
        'overdue',
        '林晓还没有完成今天的学习记录',
        '可以轻轻戳一下，提醒队友别忘了。',
        'demo-overdue',
      ),
    ],
    '_showcase_member_plan_ids': {
      for (final e in memberPlans.entries)
        e.key: e.value.map((p) => p['id']).toList(),
    },
    '_media': <Object?>[],
    '_idempotency': <String, Object?>{},
    '_challenge_dates': <Object?>[],
  };
}

bool _isCompleted(JsonMap row) =>
    row['status'] == 'stamped' || row['status'] == 'makeup';

/// Mirrors the existing weekly contract: scheduled days are deduplicated;
/// arbitrary period targets are separate from natural-week completion totals.
JsonMap _planCounts(
  Plan plan,
  List<JsonMap> checks,
  String user,
  DateTime monday,
) {
  final eligible = <String>[];
  if (plan.scheduleKind != 'period_target') {
    for (var offset = 0; offset < 7; offset++) {
      final date = monday.add(Duration(days: offset));
      final day = date.toIso8601String().substring(0, 10);
      if (plan.anchorDate != null && day.compareTo(plan.anchorDate!) < 0) {
        continue;
      }
      if (plan.scheduleKind == 'weekly_target' ||
          planIsDue(plan, date, _zone)) {
        eligible.add(day);
      }
    }
  }
  final relevant = checks.where(
    (c) =>
        c['user_id'] == user &&
        c['plan_id'] == plan.id &&
        eligible.contains(c['local_date']) &&
        _isCompleted(c),
  );
  final completed = relevant.map((c) => c['local_date']).toSet().length;
  final expected = plan.scheduleKind == 'weekly_target'
      ? math.min(plan.weeklyTargetDays, eligible.length)
      : eligible.length;
  return {
    'id': plan.id,
    'title': plan.title,
    'schedule_kind': plan.scheduleKind,
    'expected': expected,
    'completed': completed,
    'extra_days': math.max(0, completed - expected),
    'makeup': relevant
        .where((c) => c['is_makeup'] == true)
        .map((c) => c['local_date'])
        .toSet()
        .length,
    'completion_rate': expected == 0
        ? 0.0
        : math.min(1.0, completed / expected),
  };
}

JsonMap _weekMetrics(
  List<JsonMap> plans,
  List<JsonMap> checks,
  String user,
  DateTime monday, {
  bool publicOnly = false,
}) {
  final first = monday.toIso8601String().substring(0, 10);
  final last = monday
      .add(const Duration(days: 6))
      .toIso8601String()
      .substring(0, 10);
  final records = checks
      .where(
        (c) =>
            c['user_id'] == user &&
            _isCompleted(c) &&
            stringValue(c['local_date']).compareTo(first) >= 0 &&
            stringValue(c['local_date']).compareTo(last) <= 0 &&
            (!publicOnly || c['visibility'] == 'team'),
      )
      .toList();
  final counts = plans
      .where((p) => !publicOnly || p['visibility'] == 'team')
      .map((p) => _planCounts(Plan.fromJson(p), records, user, monday))
      .toList();
  final expected = counts.fold<int>(
    0,
    (sum, p) => sum + intValue(p['expected']),
  );
  final completed = counts.fold<int>(
    0,
    (sum, p) =>
        sum + math.min(intValue(p['completed']), intValue(p['expected'])),
  );
  final categories = <String, Object?>{};
  for (final c in records) {
    final key = c['plan_id'] == null
        ? 'uncategorized'
        : stringValue(c['category']);
    categories[key] = intValue(categories[key]) + 1;
  }
  return {
    'completed': completed,
    'expected': expected,
    'completion_rate': expected == 0 ? 0.0 : completed / expected,
    'makeup': counts.fold<int>(0, (sum, p) => sum + intValue(p['makeup'])),
    'extra_days': counts.fold<int>(
      0,
      (sum, p) => sum + intValue(p['extra_days']),
    ),
    'checkins': records.length,
    'plans': counts.where((p) => intValue(p['expected']) > 0).toList(),
    'by_category': categories,
  };
}

JsonMap _teamMetrics(
  Map<String, List<JsonMap>> memberPlans,
  List<JsonMap> checks,
  DateTime monday,
) {
  final individuals = [
    for (final entry in memberPlans.entries)
      _weekMetrics(entry.value, checks, entry.key, monday, publicOnly: true),
  ];
  int sum(String key) =>
      individuals.fold<int>(0, (sum, m) => sum + intValue(m[key]));
  final categories = <String, Object?>{};
  for (final metrics in individuals) {
    for (final entry in jsonObject(metrics['by_category']).entries) {
      categories[entry.key] =
          intValue(categories[entry.key]) + intValue(entry.value);
    }
  }
  final expected = sum('expected');
  return {
    'members': memberPlans.length,
    'completed': sum('completed'),
    'expected': expected,
    'completion_rate': expected == 0 ? 0.0 : sum('completed') / expected,
    'checkins': sum('checkins'),
    'makeup': sum('makeup'),
    'extra_days': sum('extra_days'),
    'by_category': categories,
  };
}
