import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import 'app_repository.dart';
import 'demo_showcase.dart';

/// An opt-in, local-only walkthrough. It does not claim to perform AI inference,
/// deliver notifications, join a remote team, or validate screenshots.
class DemoRepository implements AppRepository {
  DemoRepository({
    DateTime Function()? clock,
    Future<Directory> Function()? directoryProvider,
  }) : _clock = clock ?? DateTime.now,
       _directoryProvider =
           directoryProvider ?? getApplicationSupportDirectory {
    tzdata.initializeTimeZones();
  }
  static const _storageKey = 'better_together_demo_v1';
  static const showcaseSeedVersion = demoShowcaseSeedVersion;
  static const _uid = 'demo-owner';
  final DateTime Function() _clock;
  final Future<Directory> Function() _directoryProvider;
  final _events = StreamController<bool>.broadcast();
  final _uuid = const Uuid();
  JsonMap? _state;
  bool _signedIn = true;
  @override
  bool get isDemo => true;
  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get currentUserId => _signedIn ? _uid : null;
  @override
  Stream<bool> get authChanges => _events.stream;
  @override
  Stream<void> get changes => const Stream<void>.empty();

  Future<void> _load() async {
    if (_state != null) return;
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    if (stored != null) {
      try {
        _state = jsonObject(jsonDecode(stored));
      } on FormatException {
        throw const AppException(
          'demo_data_unreadable',
          '本地演示记录无法读取，请在设置中清除演示数据后重试',
        );
      }
    } else {
      _state = _seed();
      await _save();
    }
  }

  Future<void> _save() async => (await SharedPreferences.getInstance())
      .setString(_storageKey, jsonEncode(_state));
  List<JsonMap> _rows(String key) =>
      jsonList(_state![key]).map(jsonObject).toList();
  String get _zone => stringValue(
    jsonObject(_state!['team'])['timezone'],
    stringValue(jsonObject(_state!['profile'])['timezone'], 'Asia/Shanghai'),
  );
  String get _today => localDate(_clock(), _zone);
  String _nextWeekStart(String date) {
    final current = DateTime.parse('${date}T00:00:00Z');
    final nextMonday = current.add(Duration(days: 8 - current.weekday));
    return localDate(nextMonday, 'UTC');
  }

  String get _nickname =>
      stringValue(jsonObject(_state!['profile'])['nickname']);
  String _id() => _uuid.v4();

  @override
  Future<AppSnapshot> bootstrap() async {
    if (!_signedIn) throw const AppException('unauthenticated', '请先进入演示模式');
    await _load();
    return AppSnapshot.fromJson(_snapshot());
  }

  bool _isTeamVisible(JsonMap row) {
    if (_state!['team'] == null) return false;
    if (row.containsKey('visibility')) return row['visibility'] == 'team';
    // Older local seeds did not carry visibility on checkins. Resolve their
    // plan while keeping unassigned records private, as the live API does.
    final plan = _rows('plans')
        .where((p) => p['id'] == row['plan_id'])
        .firstOrNull;
    return plan?['visibility'] == 'team';
  }

  JsonMap _snapshot() => {
    ..._state!,
    'feed_ids': [
      for (final c in _rows('checkins'))
        if (_isTeamVisible(c)) c['id'],
    ],
    'history_ids': [
      for (final c in _rows('checkins'))
        if (c['user_id'] == _uid) c['id'],
    ],
  };

  JsonMap _seed() => buildDemoShowcase(_clock());

  JsonMap _require(List<JsonMap> rows, String id) => rows.firstWhere(
    (row) => row['id'] == id,
    orElse: () => throw const AppException('not_found', '这条记录已不可用，请刷新后重试'),
  );

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    await _load();
    if (!_signedIn) throw const AppException('unauthenticated', '请先进入演示模式');
    final before = jsonObject(jsonDecode(jsonEncode(_state)));
    try {
      return await _performAction(action, args);
    } catch (_) {
      // Validation may inspect several mutable records. A rejected action must
      // not consume a photo or makeup allowance in the local walkthrough.
      _state = before;
      rethrow;
    }
  }

  Future<Object?> _performAction(String action, JsonMap args) async {
    Object? result = <String, Object?>{};
    switch (action) {
      case 'reset_demo_showcase':
        final media = _rows('_media');
        for (final image in media) {
          final path = stringValue(image['path']);
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
        }
        _state = _seed();
        result = {
          'reset': true,
          'demo': true,
          'seed_version': showcaseSeedVersion,
        };
        break;
      case 'bootstrap':
        return _snapshot();
      case 'get_ai_settings':
        return {
          'enabled': false,
          'base_url': '',
          'protocol': 'chat_completions',
          'model': '',
          'has_key': false,
        };
      case 'save_ai_settings':
      case 'test_ai_settings':
      case 'delete_ai_settings':
        throw const AppException(
          'demo_ai_unavailable',
          '请先连接真实账号，再保存或测试 AI 服务。演示模式不会保存密钥，也不会发送请求。',
        );
      case 'save_profile':
        final profile = jsonObject(_state!['profile']);
        if (args.containsKey('avatar_url') &&
            args['avatar_url'] != null &&
            !stringValue(args['avatar_url']).startsWith('preset:') &&
            !_rows('_media').any(
              (row) =>
                  row['source'] == 'avatar' &&
                  row['path'] == args['avatar_url'],
            )) {
          throw const AppException('avatar_not_owned', '请先选择并上传自己的头像');
        }
        for (final key in [
          'nickname',
          'avatar_url',
          'notification_preferences',
        ]) {
          if (args.containsKey(key)) profile[key] = args[key];
        }
        if (args.containsKey('timezone') && _state!['team'] == null) {
          profile['timezone'] = args['timezone'];
        }
        _state!['profile'] = profile;
        final checks = _rows('checkins');
        for (final check in checks.where((row) => row['user_id'] == _uid)) {
          check['nickname'] = profile['nickname'];
        }
        _state!['checkins'] = checks;
        final team = jsonObject(_state!['team']);
        if (team.isNotEmpty) {
          final members = jsonList(team['members']).map(jsonObject).toList();
          final mine = _require(members, _uid);
          mine['nickname'] = profile['nickname'];
          mine['avatar_url'] = profile['avatar_url'];
          team['members'] = members;
          _state!['team'] = team;
        }
      case 'get_checkin':
        return _require(_rows('checkins'), stringValue(args['id']));
      case 'get_plan':
        return _require(_rows('plans'), stringValue(args['id']));
      case 'read_page':
        final collection = stringValue(args['collection']);
        final rows = _rows(collection == 'history' ? 'checkins' : collection)
            .where((row) {
              if (collection == 'checkins' && !_isTeamVisible(row)) {
                return false;
              }
              if (collection == 'history' && row['user_id'] != _uid) {
                return false;
              }
              return (args['query'] == null ||
                      stringValue(row['title'])
                          .contains(stringValue(args['query']))) &&
                  (args['category'] == null ||
                      args['category'] == 'all' ||
                      row['category'] == args['category']) &&
                  (args['status'] == null ||
                      args['status'] == 'all' ||
                      row['status'] == args['status']);
            })
            .toList();
        final offset = int.tryParse(stringValue(args['cursor'])) ?? 0;
        return {
          'items': rows.skip(offset).take(20).toList(),
          'next_cursor': rows.length > offset + 20 ? '${offset + 20}' : null,
        };
      case 'save_plan':
        final plans = _rows('plans');
        final id = nullableString(args['id']);
        final weekdays = jsonList(args['weekdays']);
        final kind = stringValue(args['schedule_kind'], 'weekdays');
        final periodDays = intValue(args['period_days']);
        final periodTargetDays = intValue(args['period_target_days']);
        final intervalDays = intValue(args['interval_days']);
        final validKind = const {
          'weekdays',
          'weekly_target',
          'period_target',
          'interval',
        }.contains(kind);
        final validPeriod =
            kind != 'period_target' ||
            (periodDays >= 1 &&
                periodDays <= 365 &&
                periodTargetDays >= 1 &&
                periodTargetDays <= periodDays);
        final validInterval =
            kind != 'interval' || (intervalDays >= 1 && intervalDays <= 365);
        if (stringValue(args['title']).trim().isEmpty ||
            weekdays.isEmpty ||
            !validKind ||
            !validPeriod ||
            !validInterval) {
          throw const AppException('invalid_plan', '请填写计划名称，并至少选择一天');
        }
        if (id == null) {
          final plan = {...args, 'id': _id()};
          plans.add(plan);
          result = plan;
        } else {
          final plan = _require(plans, id);
          final effective = _nextWeekStart(_today);
          final nextConfig = {...jsonObject(plan['next_config']), ...args};
          plan['pending_changes'] = nextConfig;
          plan['next_config'] = nextConfig;
          plan['effective_on'] = effective;
          result = {'id': id, 'effective_on': effective};
        }
        _state!['plans'] = plans;
      case 'create_team':
        if (_state!['team'] != null) {
          throw const AppException('already_in_team', '请先退出当前小队');
        }
        if (stringValue(args['name']).trim().isEmpty) {
          throw const AppException('team_name', '给小队起个名字吧');
        }
        _state!['team'] = {
          'id': _id(),
          'name': args['name'],
          'timezone': args['timezone'] ?? 'Asia/Shanghai',
          'owner_id': _uid,
          'streak': 0,
          'members': [
            {'id': _uid, 'nickname': _nickname, 'status': 'not_started'},
          ],
        };
      case 'create_invite':
        result = {
          'token': 'DEMO2345',
          'url': 'bettertogether://invite/DEMO2345',
          'demo': true,
        };
      case 'join_team':
        throw const AppException('demo_local_only', '演示模式不连接其他账号，请使用正式登录加入小队');
      case 'leave_team':
        _state!['team'] = null;
        _state!['checkins'] = _rows('checkins')
            .where((row) => row['user_id'] == _uid)
            .toList();
        _state!['overdue'] = <Object?>[];
      case 'manage_team':
        final team = jsonObject(_state!['team']);
        if (team['owner_id'] != _uid) {
          throw const AppException('forbidden', '只有队长可以管理小队');
        }
        if (args['operation'] == 'rename') {
          team['name'] = args['name'];
          _state!['team'] = team;
        }
        if (args['operation'] == 'remove') {
          team['members'] = jsonList(team['members'])
              .where((v) => jsonObject(v)['id'] != args['member_id'])
              .toList();
          _state!['team'] = team;
        }
        if (args['operation'] == 'dissolve') {
          _state!['team'] = null;
          _state!['overdue'] = <Object?>[];
        }
      case 'pause_week':
        _state!['profile'] = {
          ...jsonObject(_state!['profile']),
          'paused_week': boolValue(args['paused']),
        };
      case 'submit_checkin':
        result = _submit(args);
      case 'submit_checkin_batch':
        result = _submitBatch(args);
      case 'edit_memo':
        final checks = _rows('checkins');
        final check = _require(checks, stringValue(args['checkin_id']));
        if (check['user_id'] != _uid) {
          throw const AppException('forbidden', '只能编辑自己的纪要');
        }
        final fields = jsonList(args['fields'])
            .map((v) => MemoField.fromJson(jsonObject(v)))
            .toList();
        final error = validateMemoFields(
          fields,
          stringValue(check['category']),
        );
        if (error != null) throw AppException('invalid_fields', error);
        check['summary'] = args['summary'];
        check['fields'] = args['fields'];
        check['memo_status'] = 'ready';
        _state!['checkins'] = checks;
      case 'assign_batch_fields':
        final checks = _rows('checkins');
        final original = _require(checks, stringValue(args['checkin_id']));
        final target = _require(checks, stringValue(args['target_checkin_id']));
        if (original['user_id'] != _uid ||
            target['user_id'] != _uid ||
            original['batch_id'] != target['batch_id']) {
          throw const AppException('batch_owner', '请选择本次打卡中的计划');
        }
        final fields = jsonList(original['unassigned_fields'])
            .map((v) => MemoField.fromJson(jsonObject(v)))
            .toList();
        final summary = stringValue(original['unassigned_summary']);
        if (fields.isEmpty && summary.isEmpty) {
          throw const AppException('no_draft', '没有待归属的手填内容');
        }
        final invalid = validateMemoFields(
          fields,
          stringValue(target['category']),
        );
        if (invalid != null) throw AppException('invalid_fields', invalid);
        final keys = fields.map((f) => f.key).toSet();
        target['fields'] = [
          ...jsonList(target['fields'])
              .where((v) => !keys.contains(jsonObject(v)['key'])),
          ...fields.map((f) => f.toJson()),
        ];
        if (summary.isNotEmpty) target['summary'] = summary;
        original['unassigned_fields'] = <Object?>[];
        original['unassigned_summary'] = '';
        _state!['checkins'] = checks;
      case 'reclassify':
        final checks = _rows('checkins');
        final check = _require(checks, stringValue(args['checkin_id']));
        if (check['user_id'] != _uid) {
          throw const AppException('forbidden', '只能修改自己的标签');
        }
        if (_clock().difference(dateValue(check['created_at'])).inHours >= 24) {
          throw const AppException('reclassify_window', '盖章已超过 24 小时，不能再修改标签');
        }
        final plan = _require(_rows('plans'), stringValue(args['plan_id']));
        check['plan_id'] = plan['id'];
        check['category'] = plan['category'];
        check['classification_pending'] = false;
        _state!['checkins'] = checks;
      case 'interact':
        _interact(args);
      case 'poke':
        final items = _rows('overdue');
        final item = _require(items, stringValue(args['overdue_id']));
        if (item['user_id'] == _uid) {
          throw const AppException('self_poke', '这条提醒属于你，可以直接补上打卡');
        }
        if (boolValue(item['poked'])) {
          throw const AppException('already_poked', '你已经戳过这条提醒了');
        }
        item['poked'] = true;
        item['poke_count'] = intValue(item['poke_count']) + 1;
        _state!['overdue'] = items;
      case 'mark_notifications':
        final ids = jsonList(args['ids']);
        final notices = _rows('notifications');
        for (final notice in notices.where((n) => ids.contains(n['id']))) {
          notice['read'] = true;
        }
        _state!['notifications'] = notices;
      case 'share_report':
        final reports = _rows('reports');
        final report = _require(reports, stringValue(args['report_id']));
        report['shared'] = true;
        _state!['reports'] = reports;
      case 'interact_report':
        final reports = _rows('reports');
        final report = _require(reports, stringValue(args['report_id']));
        if (_state!['team'] == null ||
            (report['kind'] != 'team' && !boolValue(report['shared']))) {
          throw const AppException('report_not_shared', '这份周报尚未分享到小队');
        }
        final kind = stringValue(args['kind']);
        if (kind == 'like') {
          final liked = boolValue(report['liked']);
          report['liked'] = !liked;
          report['likes'] = intValue(report['likes']) + (liked ? -1 : 1);
        } else if (kind == 'comment') {
          final content = stringValue(args['content']).trim();
          if (content.isEmpty || content.length > 500) {
            throw const AppException('comment_length', '请输入 1 至 500 字的回应');
          }
          report['comments'] = [
            ...jsonList(report['comments']),
            {
              'id': _id(),
              'user_id': _uid,
              'nickname': _nickname,
              'content': content,
              'is_challenge': false,
              'created_at': _clock().toUtc().toIso8601String(),
            },
          ];
        } else {
          throw const AppException('report_interaction', '周报支持点赞与普通评论');
        }
        _state!['reports'] = reports;
      case 'refresh_report':
        final reports = _rows('reports');
        final report = _require(reports, stringValue(args['report_id']));
        if (boolValue(report['refreshed'])) {
          throw const AppException('report_refresh_limit', '这份周报已经刷新过一次');
        }
        report['refreshed'] = true;
        _state!['reports'] = reports;
      case 'accept_suggestion':
        final report = _require(
          _rows('reports'),
          stringValue(args['report_id']),
        );
        final suggestion = jsonObject(report['suggestion']);
        final plans = _rows('plans');
        final plan = _require(plans, stringValue(suggestion['plan_id']));
        plan['pending_changes'] = {...plan, 'deadline': suggestion['deadline']};
        _state!['plans'] = plans;
      case 'delete_photo':
        final checks = _rows('checkins');
        for (final check in checks.where((c) => c['user_id'] == _uid)) {
          check['photos'] = jsonList(check['photos'])
              .where((p) => jsonObject(p)['id'] != args['photo_id'])
              .toList();
        }
        final media = _rows('_media');
        final removed = media
            .where((p) => p['id'] == args['photo_id'])
            .toList();
        for (final image in removed) {
          final path = stringValue(image['path']);
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
        }
        _state!['_media'] = media
            .where((p) => p['id'] != args['photo_id'])
            .toList();
        _state!['checkins'] = checks;
        result = {'deleted': true, 'cleanup_status': 'done'};
      case 'register_device':
        result = {'registered': false, 'demo': true};
      case 'unregister_device':
        result = {'updated': true, 'demo': true};
      case 'delete_account':
        if (args['confirmation'] != 'DELETE') {
          throw const AppException('confirmation', '请输入 DELETE 确认删除');
        }
        for (final image in _rows('_media')) {
          final path = stringValue(image['path']);
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
        }
        await (await SharedPreferences.getInstance()).remove(_storageKey);
        _state = null;
        await signOut();
        return null;
      default:
        throw AppException('unsupported_action', '演示模式暂不支持此操作：$action');
    }
    await _save();
    return result;
  }

  Object _submit(JsonMap args) {
    final token = stringValue(args['idempotency_key']);
    if (token.isEmpty) {
      throw const AppException('idempotency_required', '提交标识缺失，请重新打开打卡页');
    }
    final attempts = jsonObject(_state!['_idempotency']);
    if (attempts.containsKey(token)) return attempts[token]!;
    final ids = jsonList(args['media_ids']);
    if (ids.isEmpty ||
        ids.length > maxPhotosPerCheckin ||
        ids.toSet().length != ids.length) {
      throw const AppException('photo_limit', '请选择 1 至 9 张不同的照片');
    }
    final media = _rows('_media');
    final photos = ids.map((id) => _require(media, stringValue(id))).toList();
    if (photos.any((photo) => boolValue(photo['used']))) {
      throw const AppException('media_used', '这张照片已经用于打卡，请换一张');
    }
    if (photos.map((photo) => photo['batch_id']).toSet().length != 1) {
      throw const AppException('batch_mismatch', '请使用本次打卡选择的照片');
    }
    final planId = nullableString(args['plan_id']);
    final plan = planId == null ? null : _require(_rows('plans'), planId);
    final targetDate = stringValue(args['target_date'], _today);
    final isMakeup =
        args['makeup_reason'] != null &&
        stringValue(args['makeup_reason']).trim().isNotEmpty;
    if (isMakeup) {
      final profile = jsonObject(_state!['profile']);
      final target = DateTime.parse('${targetDate}T00:00:00Z');
      if (!canMakeup(
        now: _clock(),
        targetDay: target,
        timezone: _zone,
        remaining: intValue(profile['makeup_remaining']),
      )) {
        throw const AppException(
          'makeup_unavailable',
          '补卡需在次日 12:00 前完成，并有剩余补卡次数',
        );
      }
      profile['makeup_remaining'] = intValue(profile['makeup_remaining']) - 1;
      _state!['profile'] = profile;
    }
    final id = _id();
    final now = _clock().toUtc();
    for (final photo in photos) {
      photo['used'] = true;
    }
    _state!['_media'] = media;
    final fields = <JsonMap>[];
    if (intValue(args['timer_seconds']) > 0) {
      fields.add({
        'key': 'duration_seconds',
        'label': '运动时长（秒）',
        'value': args['timer_seconds'],
        'source': 'timer',
      });
    }
    final checkin = {
      'id': id,
      'user_id': _uid,
      'nickname': _nickname,
      'plan_id': planId,
      'category': plan?['category'] ?? 'all',
      'batch_id': photos.first['batch_id'],
      'local_date': targetDate,
      'status': isMakeup ? 'makeup' : 'stamped',
      'is_makeup': isMakeup,
      'is_late': false,
      'created_at': now.toIso8601String(),
      'summary': stringValue(args['note']),
      'memo_status': 'unavailable',
      // The walkthrough never queues or pretends to finish remote AI work.
      'classification_pending': false,
      'unassigned_fields': <Object?>[],
      'unassigned_summary': '',
      'fields': fields,
      'photos': photos
          .map(
            (p) => {
              'id': p['id'],
              'url': p['path'],
              'source': p['source'],
              'captured_at': p['captured_at'],
              'plan_id': planId,
            },
          )
          .toList(),
      'likes': 0,
      'liked': false,
      'comments': <Object?>[],
      'challenge_count': 0,
      'challenge_threshold': challengeThreshold(
        jsonList(jsonObject(_state!['team'])['members']).length,
      ),
    };
    final checks = _rows('checkins');
    if (args['redo_of'] != null) {
      final previous = _require(checks, stringValue(args['redo_of']));
      if (previous['user_id'] != _uid ||
          previous['status'] != 'redo_required') {
        throw const AppException('redo_unavailable', '这条打卡当前不需要重打');
      }
      previous['status'] = 'stamped';
      previous['redo_id'] = id;
    }
    checks.insert(0, checkin);
    _state!['checkins'] = checks;
    final overdue = _rows('overdue');
    for (final item in overdue.where(
      (v) => v['user_id'] == _uid && v['plan_id'] == planId,
    )) {
      item['status'] = 'resolved';
    }
    _state!['overdue'] = overdue;
    attempts[token] = {
      'checkin_ids': [id],
    };
    _state!['_idempotency'] = attempts;
    return attempts[token]!;
  }

  Object _submitBatch(JsonMap args) {
    final token = stringValue(args['idempotency_key']);
    if (token.isEmpty) {
      throw const AppException('idempotency_required', '提交标识缺失，请重新打开打卡页');
    }
    final attempts = jsonObject(_state!['_idempotency']);
    if (attempts.containsKey(token)) return attempts[token]!;
    final rawGroups = jsonList(args['groups']);
    if (rawGroups.isEmpty || rawGroups.length > maxPhotosPerCheckin) {
      throw const AppException('photo_limit', '请至少保留一条打卡记录');
    }
    final media = _rows('_media');
    final groups = <JsonMap>[];
    final usedIds = <String>{};
    String? batchId;
    for (final raw in rawGroups) {
      final group = jsonObject(raw);
      final ids = jsonList(group['media_ids'])
          .map((id) => stringValue(id))
          .toList();
      if (ids.isEmpty) {
        throw const AppException('photo_limit', '每条记录至少需要一张照片');
      }
      if (ids.length > maxPhotosPerCheckin) {
        throw const AppException('photo_limit', '一条记录最多包含 9 张照片');
      }
      if (ids.any((id) => !usedIds.add(id))) {
        throw const AppException('duplicate_photo', '一张照片只能归入一条记录');
      }
      final photos = ids.map((id) => _require(media, id)).toList();
      if (photos.any(
        (photo) =>
            photo['user_id'] != null && photo['user_id'] != _uid ||
            boolValue(photo['used']) ||
            photo['deleted_at'] != null,
      )) {
        throw const AppException('media_used', '这张照片已经用于打卡，请换一张');
      }
      final photoBatch = stringValue(photos.first['batch_id']);
      if (photoBatch.isEmpty ||
          photos.map((photo) => photo['batch_id']).toSet().length != 1 ||
          (batchId != null && batchId != photoBatch)) {
        throw const AppException('batch_mismatch', '请使用本次打卡选择的照片');
      }
      batchId ??= photoBatch;
      final planId = nullableString(group['plan_id']);
      final plan = planId == null ? null : _require(_rows('plans'), planId);
      if (plan != null &&
          (plan['user_id'] != null && plan['user_id'] != _uid ||
              stringValue(plan['status'], 'active') != 'active')) {
        throw const AppException('plan_unavailable', '请选择自己的进行中计划');
      }
      final selection = stringValue(
        group['plan_selection'],
        planId == null ? 'all' : 'ai',
      );
      if (!['all', 'manual', 'ai'].contains(selection) ||
          (selection == 'all' && planId != null)) {
        throw const AppException('invalid_selection', '计划归属标记无效');
      }
      if (selection == 'ai' &&
          photos.any((p) {
            final r = PhotoRecognition.fromJson(jsonObject(p['recognition']));
            return !r.isReady || (r.confidence ?? 0) < .8 || r.planId != planId;
          })) {
        throw const AppException('invalid_suggestion', '计划建议已变化，请重新确认分组');
      }
      final fields = <JsonMap>[
        for (final p in photos)
          ...jsonList(jsonObject(p['recognition'])['fields']).map(jsonObject),
      ];
      final fieldError = validateMemoFields(
        fields.map(MemoField.fromJson).toList(),
        stringValue(plan?['category'], 'all'),
      );
      if (fieldError != null) {
        throw AppException('invalid_fields', fieldError);
      }
      groups.add({
        'plan_id': planId,
        'photos': photos,
        'summary': stringValue(group['summary']),
        'fields': fields,
        'plan_selection': selection,
        'user_edited':
            boolValue(group['user_edited']) ||
            stringValue(args['note']).trim().isNotEmpty,
      });
    }
    if (groups.isEmpty ||
        usedIds.length > maxPhotosPerCheckin ||
        batchId == null) {
      throw const AppException('photo_limit', '请至少保留一条包含照片的记录');
    }
    var targetDate = stringValue(args['target_date'], _today);
    final redoId = nullableString(args['redo_of']);
    final checks = _rows('checkins');
    JsonMap? previous;
    if (redoId != null) {
      previous = _require(checks, redoId);
      final deadline = DateTime.tryParse(
        stringValue(previous['redo_deadline']),
      );
      if (groups.length != 1 ||
          previous['user_id'] != _uid ||
          previous['status'] != 'redo_required' ||
          deadline == null ||
          !_clock().isBefore(deadline) ||
          groups.single['plan_id'] != previous['plan_id']) {
        throw const AppException('redo_unavailable', '重打需在截止前保留原计划，且只能提交一条记录');
      }
      targetDate = stringValue(previous['local_date']);
    }
    final isMakeup = targetDate != _today && redoId == null;
    if (isMakeup) {
      if (groups.any((g) => g['plan_id'] == null)) {
        throw const AppException('makeup_plan_required', '补卡时请选择原计划');
      }
      final profile = jsonObject(_state!['profile']);
      final target = DateTime.tryParse('${targetDate}T00:00:00Z');
      if (target == null ||
          stringValue(args['makeup_reason']).trim().isEmpty ||
          !canMakeup(
            now: _clock(),
            targetDay: target,
            timezone: _zone,
            remaining: intValue(profile['makeup_remaining']),
          )) {
        throw const AppException(
          'makeup_unavailable',
          '补卡需在次日 12:00 前完成，填写原因并有剩余次数',
        );
      }
      profile['makeup_remaining'] = intValue(profile['makeup_remaining']) - 1;
      _state!['profile'] = profile;
    }
    final now = _clock().toUtc();
    final ids = <String>[];
    for (final group in groups) {
      final planId = nullableString(group['plan_id']);
      final plan = planId == null ? null : _require(_rows('plans'), planId);
      final photos = (group['photos'] as List).cast<JsonMap>();
      final id = _id();
      ids.add(id);
      for (final photo in photos) {
        photo['used'] = true;
        photo['checkin_id'] = id;
        photo['plan_id'] = planId;
      }
      _state!['checkins'] = [
        ..._rows('checkins'),
        {
          'id': id,
          'user_id': _uid,
          'nickname': _nickname,
          'plan_id': planId,
          'category': plan?['category'] ?? 'all',
          'batch_id': photos.first['batch_id'],
          'local_date': targetDate,
          'status': isMakeup ? 'makeup' : 'stamped',
          'is_makeup': isMakeup,
          'is_late': false,
          'created_at': now.toIso8601String(),
          'summary': [
            stringValue(group['summary']),
            stringValue(args['note']),
          ].where((value) => value.trim().isNotEmpty).join('\n'),
          'memo_status':
              boolValue(group['user_edited']) ||
                  photos.every(
                    (p) => jsonObject(p['recognition'])['status'] == 'ready',
                  )
              ? 'ready'
              : 'unavailable',
          'plan_selection': group['plan_selection'],
          'user_edited': group['user_edited'],
          'redo_of': redoId,
          'classification_pending': false,
          'unassigned_fields': <Object?>[],
          'unassigned_summary': '',
          'fields': jsonList(group['fields']),
          'photos': photos
              .map(
                (photo) => {
                  'id': photo['id'],
                  'url': photo['path'],
                  'source': photo['source'],
                  'captured_at': photo['captured_at'],
                  'plan_id': planId,
                  'recognition': photo['recognition'],
                },
              )
              .toList(),
          'likes': 0,
          'liked': false,
          'comments': <Object?>[],
          'challenge_count': 0,
          'challenge_threshold': challengeThreshold(
            jsonList(jsonObject(_state!['team'])['members']).length,
          ),
        },
      ];
      _state!['_media'] = media;
    }
    if (previous != null) {
      final savedChecks = _rows('checkins');
      final savedPrevious = _require(savedChecks, redoId!);
      savedPrevious['status'] = 'stamped';
      savedPrevious['redo_deadline'] = null;
      _state!['checkins'] = savedChecks;
    }
    final overdue = _rows('overdue');
    for (final row in overdue) {
      if (row['user_id'] == _uid &&
          row['local_date'] == targetDate &&
          groups.any(
            (g) => g['plan_id'] != null && g['plan_id'] == row['plan_id'],
          )) {
        row['status'] = 'resolved';
      }
    }
    _state!['overdue'] = overdue;
    final result = {'checkin_ids': ids, 'batch_id': batchId};
    attempts[token] = result;
    _state!['_idempotency'] = attempts;
    return result;
  }

  void _interact(JsonMap args) {
    final checks = _rows('checkins');
    final check = _require(checks, stringValue(args['checkin_id']));
    if (!['stamped', 'makeup'].contains(check['status'])) {
      throw const AppException('interaction_unavailable', '这条打卡当前不能点赞或评论');
    }
    final kind = stringValue(args['kind']);
    if (kind == 'like') {
      final wasLiked = boolValue(check['liked']);
      check['liked'] = !wasLiked;
      check['likes'] = intValue(check['likes']) + (wasLiked ? -1 : 1);
    } else {
      final content = stringValue(args['content']).trim();
      if (content.isEmpty) {
        throw AppException(
          'reason_required',
          kind == 'challenge' ? '请写一句质疑理由' : '写点什么再发送吧',
        );
      }
      final comments = jsonList(check['comments']).map(jsonObject).toList();
      if (kind == 'challenge') {
        if (check['user_id'] == _uid) {
          throw const AppException('self_challenge', '不能质疑自己的打卡');
        }
        if (comments.any(
          (c) => c['user_id'] == _uid && boolValue(c['is_challenge']),
        )) {
          throw const AppException('duplicate_challenge', '你已对这条打卡提出质疑');
        }
        final dates = jsonList(_state!['_challenge_dates']);
        if (dates.where((d) => d == _today).length >= maxChallengesPerDay) {
          throw const AppException('challenge_limit', '今天已发起 2 次质疑，请明天再试');
        }
        _state!['_challenge_dates'] = [...dates, _today];
        check['challenge_count'] = intValue(check['challenge_count']) + 1;
        if (intValue(check['challenge_count']) >=
            intValue(check['challenge_threshold'])) {
          check['status'] = 'redo_required';
        }
      }
      comments.add({
        'id': _id(),
        'user_id': _uid,
        'nickname': _nickname,
        'content': content,
        'is_challenge': kind == 'challenge',
        'created_at': _clock().toUtc().toIso8601String(),
      });
      check['comments'] = comments;
    }
    _state!['checkins'] = checks;
  }

  @override
  Future<PhotoRecognition> recognize(PhotoRecognitionRequest photo) async {
    if (!_signedIn) throw const AppException('unauthenticated', '请先进入演示模式');
    // No local persistence or network request: this is an explicit simulation.
    return PhotoRecognition(
      photoId: photo.photoId,
      status: 'pending',
      error: '演示模式不执行 AI 识别。可用实时拍摄体验 ALL 盖章，正式账号支持照片识别。',
    );
  }

  @override
  Future<UploadedPhoto> upload(PhotoUpload photo) async {
    if (!_signedIn) throw const AppException('unauthenticated', '请先进入演示模式');
    await _load();
    if (photo.source == 'avatar') {
      if (photo.bytes.isEmpty || photo.bytes.length > 20 * 1024 * 1024) {
        throw const AppException('avatar_size', '请选择小于 20 MB 的头像图片');
      }
      final folder = await _directoryProvider();
      final id = _id();
      final path =
          '${folder.path}/demo-avatar-$id.${photo.contentType == 'image/png' ? 'png' : 'jpg'}';
      final file = File(path);
      await file.writeAsBytes(photo.bytes, flush: true);
      final previous = _state;
      final media = _rows('_media');
      _state = {
        ..._state!,
        '_media': [
          ...media,
          {'id': id, 'path': path, 'source': 'avatar'},
        ],
      };
      try {
        await _save();
      } catch (_) {
        _state = previous;
        await file.delete();
        rethrow;
      }
      return UploadedPhoto(
        id: id,
        path: path,
        source: 'avatar',
        capturedAt: _clock(),
      );
    }
    if (photo.source == 'screenshot') {
      throw const AppException('demo_no_ocr', '本地演示不运行截图识别，请改用实时拍摄，或登录正式服务');
    }
    final captured =
        photo.capturedAt ?? (photo.source == 'camera' ? _clock() : null);
    if (captured == null) {
      throw const AppException('date_missing', '未找到拍摄日期，请换一张或现在拍摄');
    }
    if (localDate(captured, _zone) != _today) {
      throw const AppException('wrong_date', '这张不是今天拍的，请换一张今天的照片');
    }
    if (photo.bytes.isEmpty) {
      throw const AppException('empty_photo', '这张图片没有内容，请换一张');
    }
    final digest = sha256.convert(photo.bytes).toString();
    final media = _rows('_media');
    if (media.any((m) => m['digest'] == digest)) {
      throw const AppException('duplicate_photo', '这张照片已经添加过，请换一张');
    }
    final folder = await _directoryProvider();
    final path = '${folder.path}/demo-${_id()}.jpg';
    await File(path).writeAsBytes(photo.bytes, flush: true);
    final id = _id();
    media.add({
      'id': id,
      'path': path,
      'source': photo.source,
      'captured_at': captured.toUtc().toIso8601String(),
      'batch_id': photo.batchId,
      'user_id': _uid,
      'local_date': _today,
      'team_id': jsonObject(_state!['team'])['id'],
      'digest': digest,
      'used': false,
      'recognition': photo.recognition?.toJson(),
    });
    _state!['_media'] = media;
    await _save();
    return UploadedPhoto(
      id: id,
      path: path,
      source: photo.source,
      capturedAt: captured,
    );
  }

  @override
  Future<void> sendEmailOtp(String email) async =>
      throw const AppException('demo_local_only', '演示模式不发送邮件，请返回正式登录');
  @override
  Future<void> verifyEmailOtp(String email, String token) async =>
      throw const AppException('demo_local_only', '演示模式不验证账号');
  @override
  Future<void> signInWithApple() async =>
      throw const AppException('demo_local_only', '演示模式不连接 Apple 账号');
  @override
  Future<void> signOut() async {
    _signedIn = false;
    _events.add(false);
  }

  @override
  Future<void> dispose() => _events.close();
}
