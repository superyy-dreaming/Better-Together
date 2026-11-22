import 'dart:typed_data';

typedef JsonMap = Map<String, Object?>;

JsonMap jsonObject(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, Object?>{};
List<Object?> jsonList(Object? value) => value is List ? value : const [];
String stringValue(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;
int intValue(Object? value, [int fallback = 0]) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
bool boolValue(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;
DateTime dateValue(Object? value) =>
    DateTime.tryParse(stringValue(value)) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
String? nullableString(Object? value) => value?.toString();

String categoryLabel(String category) => switch (category) {
  'study' => '学习',
  'exercise' => '运动',
  'food' => '饮食',
  'water' => '饮水',
  'meditation' => '冥想',
  'sleep' => '作息',
  'custom' => '自定义',
  _ => 'ALL',
};
String sourceLabel(String source) => switch (source) {
  'ai' => 'AI 识别',
  'screenshot' => '记录截图',
  'timer' => '计时',
  'health' => '健康数据',
  'manual' => '手填',
  'camera' => '实时拍摄',
  'album' => '相册照片',
  _ => source,
};
String checkinStatusLabel(String status) => switch (status) {
  'stamped' => '已盖章',
  'makeup' => '已补卡',
  'redo_required' => '待重打',
  'incomplete' => '未完成',
  _ => '处理中',
};

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.timezone = 'Asia/Shanghai',
    this.notificationPreferences = const {},
    this.makeupRemaining = 2,
    this.pausedWeek = false,
    this.weeklyStreak = 0,
    this.streak = 0,
  });
  final int weeklyStreak;
  final String id, nickname, timezone;
  final String? avatarUrl;
  final Map<String, bool> notificationPreferences;
  final int makeupRemaining;
  final int streak;
  final bool pausedWeek;
  factory UserProfile.fromJson(JsonMap json) => UserProfile(
    weeklyStreak: intValue(json['weekly_streak']),
    id: stringValue(json['id']),
    nickname: stringValue(json['nickname'], '新朋友'),
    avatarUrl: nullableString(json['avatar_url']),
    timezone: stringValue(json['timezone'], 'Asia/Shanghai'),
    notificationPreferences: jsonObject(json['notification_preferences'])
        .map((k, v) => MapEntry(k, boolValue(v, true))),
    makeupRemaining: intValue(json['makeup_remaining'], 2),
    pausedWeek: boolValue(json['paused_week']),
    streak: intValue(json['streak']),
  );
  JsonMap toJson() => {
    'weekly_streak': weeklyStreak,
    'id': id,
    'nickname': nickname,
    'avatar_url': avatarUrl,
    'timezone': timezone,
    'notification_preferences': notificationPreferences,
    'makeup_remaining': makeupRemaining,
    'paused_week': pausedWeek,
    'streak': streak,
  };
}

class TeamMember {
  const TeamMember({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.status = 'not_started',
  });
  final String id, nickname, status;
  final String? avatarUrl;
  factory TeamMember.fromJson(JsonMap json) => TeamMember(
    id: stringValue(json['id']),
    nickname: stringValue(json['nickname']),
    avatarUrl: nullableString(json['avatar_url']),
    status: stringValue(json['status'], 'not_started'),
  );
  JsonMap toJson() => {
    'id': id,
    'nickname': nickname,
    'avatar_url': avatarUrl,
    'status': status,
  };
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.timezone,
    required this.ownerId,
    this.weeklyStreak = 0,
    this.streak = 0,
    this.visibilityEpoch = 0,
    this.members = const [],
  });
  final int weeklyStreak;
  final String id, name, timezone, ownerId;
  final int streak, visibilityEpoch;
  final List<TeamMember> members;
  factory Team.fromJson(JsonMap json) => Team(
    weeklyStreak: intValue(json['weekly_streak']),
    id: stringValue(json['id']),
    name: stringValue(json['name']),
    timezone: stringValue(json['timezone'], 'Asia/Shanghai'),
    ownerId: stringValue(json['owner_id']),
    streak: intValue(json['streak']),
    visibilityEpoch: intValue(json['visibility_epoch']),
    members: jsonList(json['members'])
        .map((v) => TeamMember.fromJson(jsonObject(v)))
        .toList(),
  );
  JsonMap toJson() => {
    'weekly_streak': weeklyStreak,
    'id': id,
    'name': name,
    'timezone': timezone,
    'owner_id': ownerId,
    'streak': streak,
    'visibility_epoch': visibilityEpoch,
    'members': members.map((v) => v.toJson()).toList(),
  };
}

class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.category,
    this.goal = '',
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.startTime = '08:00',
    this.deadline = '21:00',
    this.visibility = 'team',
    this.status = 'active',
    this.streak,
    this.todayCheckinId,
    this.todayRecordCount = 0,
    this.scheduleKind = 'weekdays',
    this.weeklyTargetDays = 3,
    this.intervalDays = 2,
    this.anchorDate,
    this.weeklyTarget = 0,
    this.weeklyCompleted = 0,
    this.extraDays = 0,
    this.weeklyStreak = 0,
    this.periodDays = 7,
    this.periodTargetDays = 3,
    this.periodTarget = 0,
    this.periodCompleted = 0,
    this.periodExtraDays = 0,
    this.periodStreak = 0,
    this.periodStart,
    this.periodEnd,
    this.effectiveOn,
    this.pendingChanges,
  });
  final String id,
      title,
      category,
      goal,
      startTime,
      deadline,
      visibility,
      status;
  final String? todayCheckinId;
  final int todayRecordCount;
  final List<int> weekdays;
  final String scheduleKind;
  final String? anchorDate;
  final int weeklyTargetDays,
      intervalDays,
      weeklyTarget,
      weeklyCompleted,
      extraDays,
      weeklyStreak,
      periodDays,
      periodTargetDays,
      periodTarget,
      periodCompleted,
      periodExtraDays,
      periodStreak;
  final String? periodStart, periodEnd;
  final String? effectiveOn;
  final JsonMap? pendingChanges;
  bool get hasPendingChanges =>
      pendingChanges != null && pendingChanges!.isNotEmpty;

  String _scheduleLabelFor({
    required String kind,
    required int targetDays,
    required int period,
    required int interval,
    required String? anchor,
    required List<int> selectedWeekdays,
  }) => switch (kind) {
    'weekly_target' => '每周完成 $targetDays 天',
    'period_target' => '每 $period 天完成 $targetDays 天',
    'interval' => '每隔 $interval 天，自 ${anchor ?? "开始日"} 起',
    _ =>
      '每周 ${selectedWeekdays.map((d) => ['一', '二', '三', '四', '五', '六', '日'][d - 1]).join('、')}',
  };

  String get scheduleLabel => switch (scheduleKind) {
    _ => _scheduleLabelFor(
      kind: scheduleKind,
      targetDays: weeklyTargetDays,
      period: periodDays,
      interval: intervalDays,
      anchor: anchorDate,
      selectedWeekdays: weekdays,
    ),
  };

  String? get pendingScheduleLabel {
    final changes = pendingChanges;
    if (changes == null || changes.isEmpty) return null;
    final pendingWeekdays = jsonList(changes['weekdays'])
        .map((value) => intValue(value))
        .where((value) => value >= 1 && value <= 7)
        .toList();
    return _scheduleLabelFor(
      kind: stringValue(changes['schedule_kind'], scheduleKind),
      targetDays: intValue(
        changes['period_target_days'],
        intValue(changes['weekly_target_days'], periodTargetDays),
      ),
      period: intValue(changes['period_days'], periodDays),
      interval: intValue(changes['interval_days'], intervalDays),
      anchor: nullableString(changes['anchor_date']) ?? anchorDate,
      selectedWeekdays: pendingWeekdays.isEmpty ? weekdays : pendingWeekdays,
    );
  }

  /// Authoritative count; absent only in local walkthrough snapshots.
  final int? streak;
  bool get isActive => status == 'active';
  factory Plan.fromJson(JsonMap json) => Plan(
    todayCheckinId: nullableString(json['today_checkin_id']),
    todayRecordCount: intValue(json['today_record_count']),
    scheduleKind: stringValue(json['schedule_kind'], 'weekdays'),
    weeklyTargetDays: intValue(json['weekly_target_days'], 3),
    intervalDays: intValue(json['interval_days'], 2),
    anchorDate: nullableString(json['anchor_date']),
    weeklyTarget: intValue(json['weekly_target']),
    weeklyCompleted: intValue(json['weekly_completed']),
    extraDays: intValue(json['extra_days']),
    weeklyStreak: intValue(json['weekly_streak']),
    periodDays: intValue(json['period_days'], 7),
    periodTargetDays: intValue(json['period_target_days'], 3),
    periodTarget: intValue(json['period_target']),
    periodCompleted: intValue(json['period_completed']),
    periodExtraDays: intValue(json['period_extra_days']),
    periodStreak: intValue(json['period_streak']),
    periodStart: nullableString(json['period_start']),
    periodEnd: nullableString(json['period_end']),
    effectiveOn: nullableString(json['effective_on']),
    pendingChanges: json['next_config'] is Map
        ? jsonObject(json['next_config'])
        : null,
    id: stringValue(json['id']),
    title: stringValue(json['title']),
    category: stringValue(json['category'], 'custom'),
    goal: stringValue(json['goal']),
    weekdays: jsonList(json['weekdays']).map((v) => intValue(v)).toList(),
    startTime: stringValue(json['start_time'], '08:00').substring(0, 5),
    deadline: stringValue(json['deadline'], '21:00').substring(0, 5),
    visibility: stringValue(json['visibility'], 'team'),
    status: stringValue(json['status'], 'active'),
    streak: json['streak'] == null ? null : intValue(json['streak']),
  );
  JsonMap toJson() => {
    'today_checkin_id': todayCheckinId,
    'today_record_count': todayRecordCount,
    'schedule_kind': scheduleKind,
    'weekly_target_days': weeklyTargetDays,
    'interval_days': intervalDays,
    'anchor_date': anchorDate,
    'weekly_target': weeklyTarget,
    'weekly_completed': weeklyCompleted,
    'extra_days': extraDays,
    'weekly_streak': weeklyStreak,
    'period_days': periodDays,
    'period_target_days': periodTargetDays,
    'period_target': periodTarget,
    'period_completed': periodCompleted,
    'period_extra_days': periodExtraDays,
    'period_streak': periodStreak,
    'period_start': periodStart,
    'period_end': periodEnd,
    'effective_on': effectiveOn,
    'next_config': pendingChanges,
    'id': id,
    'title': title,
    'category': category,
    'goal': goal,
    'weekdays': weekdays,
    'start_time': startTime,
    'deadline': deadline,
    'visibility': visibility,
    'status': status,
    'streak': streak,
  };
}

class MemoField {
  const MemoField({
    required this.key,
    required this.label,
    this.value,
    required this.source,
    this.confidence,
  });
  final String key, label, source;
  final Object? value;
  final double? confidence;
  String get displayValue {
    if (value == null || value == '') return '未记录';
    if (value is Map) {
      final range = jsonObject(value);
      if (range['min'] != null && range['max'] != null) {
        return '${range['min']}-${range['max']} ${range['unit'] ?? ''}（估算）';
      }
    }
    return value.toString();
  }

  factory MemoField.fromJson(JsonMap json) => MemoField(
    key: stringValue(json['key']),
    label: stringValue(json['label']),
    value: json['value'],
    source: stringValue(json['source'], 'manual'),
    confidence: json['confidence'] is num
        ? (json['confidence'] as num).toDouble()
        : null,
  );
  JsonMap toJson() => {
    'key': key,
    'label': label,
    'value': value,
    'source': source,
    'confidence': confidence,
  };
}

class CheckinPhoto {
  const CheckinPhoto({
    required this.id,
    required this.url,
    required this.source,
    required this.capturedAt,
    this.planId,
    this.confidence,
    this.cleanupStatus,
    this.recognition,
  });
  final PhotoRecognition? recognition;
  final String id, url, source;
  final DateTime capturedAt;
  final String? planId;
  final String? cleanupStatus;
  final double? confidence;
  factory CheckinPhoto.fromJson(JsonMap json) => CheckinPhoto(
    id: stringValue(json['id']),
    url: stringValue(json['url']),
    source: stringValue(json['source']),
    capturedAt: dateValue(json['captured_at']),
    planId: nullableString(json['plan_id']),
    cleanupStatus: nullableString(json['cleanup_status']),
    recognition: json['recognition'] is Map
        ? PhotoRecognition.fromJson(jsonObject(json['recognition']))
        : null,
    confidence: json['confidence'] is num
        ? (json['confidence'] as num).toDouble()
        : null,
  );
  JsonMap toJson() => {
    'id': id,
    'url': url,
    'source': source,
    'captured_at': capturedAt.toIso8601String(),
    'plan_id': planId,
    'cleanup_status': cleanupStatus,
    'recognition': recognition?.toJson(),
    'confidence': confidence,
  };
}

class Comment {
  const Comment({
    this.avatarUrl,
    required this.id,
    required this.userId,
    required this.nickname,
    required this.content,
    required this.createdAt,
    this.isChallenge = false,
  });
  final String? avatarUrl;
  final String id, userId, nickname, content;
  final DateTime createdAt;
  final bool isChallenge;
  factory Comment.fromJson(JsonMap json) => Comment(
    avatarUrl: nullableString(json['avatar_url']),
    id: stringValue(json['id']),
    userId: stringValue(json['user_id']),
    nickname: stringValue(json['nickname']),
    content: stringValue(json['content']),
    createdAt: dateValue(json['created_at']),
    isChallenge: boolValue(json['is_challenge']),
  );
  JsonMap toJson() => {
    'avatar_url': avatarUrl,
    'id': id,
    'user_id': userId,
    'nickname': nickname,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'is_challenge': isChallenge,
  };
}

class Checkin {
  const Checkin({
    this.avatarUrl,
    required this.id,
    required this.userId,
    this.planId,
    this.batchId = '',
    required this.localDate,
    this.status = 'stamped',
    this.isMakeup = false,
    this.isLate = false,
    required this.createdAt,
    this.summary = '',
    this.memoStatus = 'pending',
    this.classificationPending = false,
    this.fields = const [],
    this.unassignedFields = const [],
    this.unassignedSummary = '',
    this.photos = const [],
    this.nickname = '',
    this.category = 'all',
    this.likes = 0,
    this.comments = const [],
    this.challengeCount = 0,
    this.challengeThreshold = 0,
    this.liked = false,
  });
  final String? avatarUrl;
  final String id,
      userId,
      batchId,
      localDate,
      status,
      summary,
      memoStatus,
      nickname,
      category;
  final String? planId;
  final bool isMakeup, isLate, liked, classificationPending;
  final String unassignedSummary;
  final DateTime createdAt;
  final List<MemoField> fields;
  final List<MemoField> unassignedFields;
  final List<CheckinPhoto> photos;
  final List<Comment> comments;
  final int likes, challengeCount, challengeThreshold;
  bool get isCompleted => status == 'stamped' || status == 'makeup';
  factory Checkin.fromJson(JsonMap json) => Checkin(
    avatarUrl: nullableString(json['avatar_url']),
    id: stringValue(json['id']),
    userId: stringValue(json['user_id']),
    planId: nullableString(json['plan_id']),
    batchId: stringValue(json['batch_id']),
    localDate: stringValue(json['local_date']),
    status: stringValue(json['status'], 'stamped'),
    isMakeup: boolValue(json['is_makeup']),
    isLate: boolValue(json['is_late']),
    createdAt: dateValue(json['created_at']),
    summary: stringValue(json['summary']),
    memoStatus: stringValue(json['memo_status'], 'pending'),
    classificationPending: boolValue(json['classification_pending']),
    unassignedSummary: stringValue(json['unassigned_summary']),
    unassignedFields: jsonList(json['unassigned_fields'])
        .map((v) => MemoField.fromJson(jsonObject(v)))
        .toList(),
    fields: jsonList(json['fields'])
        .map((v) => MemoField.fromJson(jsonObject(v)))
        .toList(),
    photos: jsonList(json['photos'])
        .map((v) => CheckinPhoto.fromJson(jsonObject(v)))
        .toList(),
    nickname: stringValue(json['nickname']),
    category: stringValue(json['category'], 'all'),
    likes: intValue(json['likes']),
    comments: jsonList(json['comments'])
        .map((v) => Comment.fromJson(jsonObject(v)))
        .toList(),
    challengeCount: intValue(json['challenge_count']),
    challengeThreshold: intValue(json['challenge_threshold']),
    liked: boolValue(json['liked']),
  );
  JsonMap toJson() => {
    'avatar_url': avatarUrl,
    'id': id,
    'user_id': userId,
    'plan_id': planId,
    'batch_id': batchId,
    'local_date': localDate,
    'status': status,
    'is_makeup': isMakeup,
    'is_late': isLate,
    'created_at': createdAt.toIso8601String(),
    'summary': summary,
    'memo_status': memoStatus,
    'classification_pending': classificationPending,
    'unassigned_fields': unassignedFields.map((v) => v.toJson()).toList(),
    'unassigned_summary': unassignedSummary,
    'fields': fields.map((v) => v.toJson()).toList(),
    'photos': photos.map((v) => v.toJson()).toList(),
    'nickname': nickname,
    'category': category,
    'likes': likes,
    'comments': comments.map((v) => v.toJson()).toList(),
    'challenge_count': challengeCount,
    'challenge_threshold': challengeThreshold,
    'liked': liked,
  };
}

class WeeklyReport {
  const WeeklyReport({
    this.stage = 'phase',
    this.aiStatus = 'rules',
    this.aiVersion = '',
    this.generatedAt,
    required this.id,
    required this.weekStart,
    this.kind = 'personal',
    this.summary = '',
    this.title = '',
    this.metrics = const {},
    this.highlights = const [],
    this.suggestion = const {},
    this.shared = false,
    this.refreshed = false,
    this.userId = '',
    this.likes = 0,
    this.liked = false,
    this.comments = const [],
  });
  final String stage, aiStatus, aiVersion;
  final DateTime? generatedAt;
  final String id, weekStart, kind, summary, title;
  final JsonMap metrics, suggestion;
  final List<Object?> highlights;
  final bool shared, refreshed;
  final String userId;
  final int likes;
  final bool liked;
  final List<Comment> comments;
  factory WeeklyReport.fromJson(JsonMap json) => WeeklyReport(
    stage: stringValue(json['stage'], 'phase'),
    aiStatus: stringValue(json['ai_status'], 'rules'),
    aiVersion: stringValue(json['ai_version']),
    generatedAt: json['generated_at'] == null
        ? null
        : dateValue(json['generated_at']),
    id: stringValue(json['id']),
    weekStart: stringValue(json['week_start']),
    kind: stringValue(json['kind'], 'personal'),
    summary: stringValue(json['summary']),
    title: stringValue(json['title']),
    metrics: jsonObject(json['metrics']),
    highlights: jsonList(json['highlights']),
    suggestion: json['suggestion'] is String
        ? {'text': json['suggestion']}
        : jsonObject(json['suggestion']),
    shared: boolValue(json['shared']),
    refreshed: boolValue(json['refreshed']),
    userId: stringValue(json['user_id']),
    likes: intValue(json['likes']),
    liked: boolValue(json['liked']),
    comments: jsonList(json['comments'])
        .map((v) => Comment.fromJson(jsonObject(v)))
        .toList(),
  );
  JsonMap toJson() => {
    'stage': stage,
    'ai_status': aiStatus,
    'ai_version': aiVersion,
    'generated_at': generatedAt?.toIso8601String(),
    'id': id,
    'week_start': weekStart,
    'kind': kind,
    'summary': summary,
    'title': title,
    'metrics': metrics,
    'highlights': highlights,
    'suggestion': suggestion,
    'shared': shared,
    'refreshed': refreshed,
    'user_id': userId,
    'likes': likes,
    'liked': liked,
    'comments': comments.map((c) => c.toJson()).toList(),
  };
}

class OverdueItem {
  const OverdueItem({
    required this.id,
    required this.userId,
    required this.planId,
    required this.title,
    required this.nickname,
    required this.deadlineAt,
    this.status = 'open',
    this.pokeCount = 0,
    this.poked = false,
  });
  final String id, userId, planId, title, nickname, status;
  final DateTime deadlineAt;
  final int pokeCount;
  final bool poked;
  factory OverdueItem.fromJson(JsonMap json) => OverdueItem(
    id: stringValue(json['id']),
    userId: stringValue(json['user_id']),
    planId: stringValue(json['plan_id']),
    title: stringValue(json['title']),
    nickname: stringValue(json['nickname']),
    deadlineAt: dateValue(json['deadline_at']),
    status: stringValue(json['status'], 'open'),
    pokeCount: intValue(json['poke_count']),
    poked: boolValue(json['poked']),
  );
  JsonMap toJson() => {
    'id': id,
    'user_id': userId,
    'plan_id': planId,
    'title': title,
    'nickname': nickname,
    'deadline_at': deadlineAt.toIso8601String(),
    'status': status,
    'poke_count': pokeCount,
    'poked': poked,
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.targetId,
  });
  final String id, kind, title, body;
  final DateTime createdAt;
  final bool read;
  final String? targetId;
  factory AppNotification.fromJson(JsonMap json) => AppNotification(
    id: stringValue(json['id']),
    kind: stringValue(json['kind']),
    title: stringValue(json['title']),
    body: stringValue(json['body']),
    createdAt: dateValue(json['created_at']),
    read: boolValue(json['read']),
    targetId: nullableString(json['target_id']),
  );
  JsonMap toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'body': body,
    'read': read,
    'created_at': createdAt.toIso8601String(),
    'target_id': targetId,
  };
}

class AppSnapshot {
  const AppSnapshot({
    this.serverUnreadCount,
    this.feedIds,
    this.historyIds,
    required this.profile,
    this.team,
    this.plans = const [],
    this.checkins = const [],
    this.reports = const [],
    this.overdue = const [],
    this.notifications = const [],
  });
  final UserProfile profile;
  final Team? team;
  final List<Plan> plans;
  final List<Checkin> checkins;
  final List<WeeklyReport> reports;
  final List<OverdueItem> overdue;
  final List<AppNotification> notifications;
  String get timezone => team?.timezone ?? profile.timezone;
  final List<String>? feedIds, historyIds;
  final int? serverUnreadCount;
  int get unreadCount =>
      serverUnreadCount ?? notifications.where((v) => !v.read).length;
  factory AppSnapshot.fromJson(JsonMap json) => AppSnapshot(
    feedIds: json['feed_ids'] == null
        ? null
        : jsonList(json['feed_ids']).map((v) => v.toString()).toList(),
    historyIds: json['history_ids'] == null
        ? null
        : jsonList(json['history_ids']).map((v) => v.toString()).toList(),
    serverUnreadCount: json['unread_count'] == null
        ? null
        : intValue(json['unread_count']),
    profile: UserProfile.fromJson(jsonObject(json['profile'])),
    team: json['team'] == null ? null : Team.fromJson(jsonObject(json['team'])),
    plans: jsonList(json['plans'])
        .map((v) => Plan.fromJson(jsonObject(v)))
        .toList(),
    checkins: jsonList(json['checkins'])
        .map((v) => Checkin.fromJson(jsonObject(v)))
        .toList(),
    reports: jsonList(json['reports'])
        .map((v) => WeeklyReport.fromJson(jsonObject(v)))
        .toList(),
    overdue: jsonList(json['overdue'])
        .map((v) => OverdueItem.fromJson(jsonObject(v)))
        .toList(),
    notifications: jsonList(json['notifications'])
        .map((v) => AppNotification.fromJson(jsonObject(v)))
        .toList(),
  );
  JsonMap toJson() => {
    'feed_ids': feedIds,
    'history_ids': historyIds,
    'unread_count': serverUnreadCount,
    'profile': profile.toJson(),
    'team': team?.toJson(),
    'plans': plans.map((v) => v.toJson()).toList(),
    'checkins': checkins.map((v) => v.toJson()).toList(),
    'reports': reports.map((v) => v.toJson()).toList(),
    'overdue': overdue.map((v) => v.toJson()).toList(),
    'notifications': notifications.map((v) => v.toJson()).toList(),
  };
}

class PhotoUpload {
  const PhotoUpload({
    required this.bytes,
    required this.filename,
    required this.source,
    required this.batchId,
    this.capturedAt,
    this.contentType = 'image/jpeg',
    this.analysisBytes,
    this.photoId,
    this.recognition,
  });
  final Uint8List bytes;
  final Uint8List? analysisBytes;
  final String filename, source, batchId, contentType;
  final String? photoId;
  final PhotoRecognition? recognition;
  final DateTime? capturedAt;
}

/// The compressed image goes directly to the user-selected service. Originals
/// are archived only after confirmation; no server AI receipt is involved.
class PhotoRecognitionRequest {
  const PhotoRecognitionRequest({
    required this.analysisBytes,
    required this.photoId,
    required this.batchId,
    required this.source,
    required this.originalSha256,
    this.planId,
    this.exifOriginal,
    this.exifOffset,
    this.archivedMediaId,
  });
  final Uint8List analysisBytes;
  Uint8List get bytes => analysisBytes;
  final String photoId, batchId, source, originalSha256;
  final String? planId;
  final String? exifOriginal, exifOffset, archivedMediaId;
}

class PhotoRecognition {
  const PhotoRecognition({
    required this.photoId,
    required this.status,
    this.planId,
    this.confidence,
    this.summary = '',
    this.fields = const [],
    this.screenshotDate,
    this.error,
    this.errorCode,
    this.origin = 'byok',
  });

  final String photoId, status, summary, origin;
  final String? planId, screenshotDate, error, errorCode;
  final double? confidence;
  final List<MemoField> fields;

  bool get isReady => status == 'ready';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  factory PhotoRecognition.fromJson(JsonMap json) {
    final status = json['status'];
    final confidence = json['confidence'];
    if (json['photo_id'] is! String ||
        stringValue(json['photo_id']).isEmpty ||
        !['ready', 'pending', 'rejected'].contains(status) ||
        (confidence != null &&
            (confidence is! num ||
                !confidence.isFinite ||
                confidence < 0 ||
                confidence > 1))) {
      throw const FormatException('Invalid photo recognition metadata');
    }
    for (final key in ['plan_id', 'summary', 'screenshot_date', 'origin']) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('Invalid photo recognition text');
      }
    }
    final error = json['error'];
    String? errorMessage, errorCode;
    if (error is String) {
      errorMessage = error;
    } else if (error is Map) {
      final detail = jsonObject(error);
      if (detail['message'] is! String ||
          (detail['code'] != null && detail['code'] is! String)) {
        throw const FormatException('Invalid photo recognition error');
      }
      errorMessage = nullableString(detail['message']);
      errorCode = nullableString(detail['code']);
    } else if (error != null) {
      throw const FormatException('Invalid photo recognition error');
    }
    final fields = json['fields'];
    if (fields != null &&
        (fields is! List || fields.any((field) => field is! Map))) {
      throw const FormatException('Invalid photo recognition fields');
    }
    return PhotoRecognition(
      photoId: stringValue(json['photo_id']),
      status: stringValue(status),
      planId: nullableString(json['plan_id']),
      confidence: (confidence as num?)?.toDouble(),
      summary: stringValue(json['summary']),
      fields: jsonList(fields)
          .map((field) => MemoField.fromJson(jsonObject(field)))
          .toList(),
      screenshotDate: nullableString(json['screenshot_date']),
      error: errorMessage,
      errorCode: errorCode,
      origin: stringValue(json['origin'], 'byok'),
    );
  }

  JsonMap toJson() => {
    'photo_id': photoId,
    'status': status,
    'plan_id': planId,
    'confidence': confidence ?? 0,
    'summary': summary,
    'fields': fields.map((f) => f.toJson()).toList(),
    'screenshot_date': screenshotDate,
    'origin': origin,
  };
}

class UploadedPhoto {
  const UploadedPhoto({
    required this.id,
    required this.path,
    required this.source,
    required this.capturedAt,
  });
  final String id, path, source;
  final DateTime capturedAt;
  factory UploadedPhoto.fromJson(JsonMap json) => UploadedPhoto(
    id: stringValue(json['id']),
    path: stringValue(json['path']),
    source: stringValue(json['source']),
    capturedAt: dateValue(json['captured_at']),
  );
}
