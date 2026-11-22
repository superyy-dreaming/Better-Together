import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/domain/rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test(
    'wire keeps classification, cleanup and private batch drafts independent',
    () {
      final record = Checkin.fromJson({
        'id': 'batch-root',
        'user_id': 'me',
        'batch_id': 'batch',
        'created_at': '2026-11-18T03:00:00Z',
        'local_date': '2026-11-18',
        'memo_status': 'ready',
        'classification_pending': true,
        'unassigned_summary': '仅本人可见的原始手填摘要',
        'unassigned_fields': [
          {
            'key': 'duration_seconds',
            'label': '时长',
            'value': 600,
            'source': 'manual',
          },
        ],
        'photos': [
          {
            'id': 'photo',
            'url': '',
            'source': 'camera',
            'captured_at': '2026-11-18T03:00:00Z',
            'cleanup_status': 'pending',
          },
        ],
      });
      final restored = Checkin.fromJson(record.toJson());
      expect(restored.memoStatus, 'ready');
      expect(restored.classificationPending, isTrue);
      expect(restored.photos.single.cleanupStatus, 'pending');
      expect(restored.photos.single.url, isEmpty);
      expect(restored.unassignedFields.single.value, 600);
      expect(restored.unassignedSummary, '仅本人可见的原始手填摘要');
    },
  );

  test(
    'demo assigns private batch fields exactly once and rejects other batches',
    () async {
      SharedPreferences.setMockInitialValues({});
      final initial = DemoRepository();
      await initial.bootstrap();
      final preferences = await SharedPreferences.getInstance();
      final stored = jsonObject(
        jsonDecode(preferences.getString('better_together_demo_v1')!),
      );
      final checks = jsonList(stored['checkins']).map(jsonObject).toList();
      final original = checks.firstWhere((c) => c['id'] == 'today-study');
      original['unassigned_fields'] = [
        {
          'key': 'duration_seconds',
          'label': '时长',
          'value': 600,
          'source': 'manual',
        },
      ];
      original['unassigned_summary'] = '我的手填摘要';
      original['classification_pending'] = true;
      checks.add({
        ...original,
        'id': 'target',
        'category': 'exercise',
        'plan_id': 'exercise',
        'fields': <Object?>[],
        'unassigned_fields': <Object?>[],
        'unassigned_summary': '',
      });
      stored['checkins'] = checks;
      await preferences.setString(
        'better_together_demo_v1',
        jsonEncode(stored),
      );
      await initial.dispose();
      final repository = DemoRepository();
      await repository.action(
        'edit_memo',
        args: {
          'checkin_id': 'today-study',
          'summary': '已编辑',
          'fields': <Object?>[],
        },
      );
      expect(
        (await repository.bootstrap()).checkins
            .firstWhere((c) => c.id == 'today-study')
            .classificationPending,
        isTrue,
      );
      await expectLater(
        repository.action(
          'assign_batch_fields',
          args: {'checkin_id': 'today-study', 'target_checkin_id': 'study-1'},
        ),
        throwsA(isA<AppException>()),
      );
      await repository.action(
        'assign_batch_fields',
        args: {'checkin_id': 'today-study', 'target_checkin_id': 'target'},
      );
      final result = await repository.bootstrap();
      final target = result.checkins.firstWhere((c) => c.id == 'target');
      expect(target.fields.single.value, 600);
      expect(target.summary, '我的手填摘要');
      expect(
        result.checkins
            .firstWhere((c) => c.id == 'today-study')
            .unassignedFields,
        isEmpty,
      );
      await expectLater(
        repository.action(
          'assign_batch_fields',
          args: {'checkin_id': 'today-study', 'target_checkin_id': 'target'},
        ),
        throwsA(isA<AppException>()),
      );
      await repository.dispose();
    },
  );

  test('team dates use the fixed team timezone, not device timezone', () {
    final instant = DateTime.utc(2026, 11, 18, 0, 30);
    expect(localDate(instant, 'Asia/Shanghai'), '2026-11-18');
    expect(localDate(instant, 'America/Los_Angeles'), '2026-11-17');
  });

  test('scheduled weekday is evaluated inside team timezone', () {
    const plan = Plan(
      id: 'reading',
      title: '阅读',
      category: 'study',
      weekdays: [2],
    );
    final instant = DateTime.utc(2026, 11, 18, 0, 30);
    expect(planIsDue(plan, instant, 'America/Los_Angeles'), isTrue);
    expect(planIsDue(plan, instant, 'Asia/Shanghai'), isFalse);
  });

  test(
    'challenge threshold is strictly greater than total team membership / 2',
    () {
      expect(challengeTriggersRedo(2, 5), isFalse);
      expect(challengeTriggersRedo(3, 5), isTrue);
      expect(challengeTriggersRedo(1, 3), isFalse);
      expect(challengeTriggersRedo(2, 3), isTrue);
      expect(
        challengeThreshold(2),
        2,
      ); // Author cannot vote; two-person team cannot overturn.
    },
  );

  test('late-night cutoff is 23:30 for deadline later than 23:30', () {
    final day = DateTime.utc(2026, 11, 18, 4);
    expect(
      overdueSyncAt(day, '23:50', 'Asia/Shanghai').toUtc(),
      DateTime.utc(2026, 11, 18, 15, 30),
    );
    expect(
      overdueSyncAt(day, '19:00', 'Asia/Shanghai').toUtc(),
      DateTime.utc(2026, 11, 18, 11, 30),
    );
    for (final deadline in ['23:10', '23:30', '23:59']) {
      expect(
        overdueSyncAt(day, deadline, 'Asia/Shanghai').toUtc(),
        DateTime.utc(2026, 11, 18, 15, 30),
      );
    }
  });

  test(
    'next-day noon handles DST local calendar rather than adding 24 hours',
    () {
      final original = DateTime.utc(2026, 3, 7, 18);
      expect(
        redoDeadline(original, 'America/New_York').toUtc(),
        DateTime.utc(2026, 3, 8, 16),
      );
    },
  );

  test('makeup needs quota, yesterday and submission before local noon', () {
    final day = DateTime.utc(2026, 11, 17, 4);
    expect(
      canMakeup(
        now: DateTime.utc(2026, 11, 18, 3, 59),
        targetDay: day,
        timezone: 'Asia/Shanghai',
        remaining: 1,
      ),
      isTrue,
    );
    expect(
      canMakeup(
        now: DateTime.utc(2026, 11, 18, 4),
        targetDay: day,
        timezone: 'Asia/Shanghai',
        remaining: 1,
      ),
      isFalse,
    );
    expect(
      canMakeup(
        now: DateTime.utc(2026, 11, 18, 3),
        targetDay: day,
        timezone: 'Asia/Shanghai',
        remaining: 0,
      ),
      isFalse,
    );
  });

  test('makeup freezes streak, a missed scheduled day resets it', () {
    const plan = Plan(id: 'p', title: '阅读', category: 'study');
    Checkin record(String date, String status) => Checkin(
      id: date,
      userId: 'me',
      planId: 'p',
      localDate: date,
      createdAt: DateTime.parse('${date}T12:00:00Z'),
      status: status,
    );
    final records = [
      record('2026-11-18', 'stamped'),
      record('2026-11-17', 'makeup'),
      record('2026-11-16', 'stamped'),
    ];
    expect(
      streakForPlan(
        plan,
        records,
        'me',
        DateTime.utc(2026, 11, 18, 5),
        'Asia/Shanghai',
      ),
      2,
    );
    expect(
      streakForPlan(
        plan,
        [records[0], records[2]],
        'me',
        DateTime.utc(2026, 11, 18, 5),
        'Asia/Shanghai',
      ),
      1,
    );
  });

  test(
    'calories cannot be precise, source-free exercise measurements rejected',
    () {
      expect(
        validateMemoFields([
          const MemoField(
            key: 'calories',
            label: '热量',
            value: 512,
            source: 'ai',
          ),
        ], 'food'),
        isNotNull,
      );
      expect(
        validateMemoFields([
          const MemoField(
            key: 'calories',
            label: '热量',
            value: {'min': 450, 'max': 650, 'estimated': true},
            source: 'ai',
          ),
        ], 'food'),
        isNull,
      );
      expect(
        validateMemoFields([
          const MemoField(
            key: 'duration_seconds',
            label: '时长',
            value: 1800,
            source: 'ai',
          ),
        ], 'exercise'),
        isNotNull,
      );
      expect(
        validateMemoFields([
          const MemoField(
            key: 'duration_seconds',
            label: '时长',
            value: 1800,
            source: 'timer',
          ),
        ], 'exercise'),
        isNull,
      );
    },
  );

  test('snapshot roundtrip retains private plan and field provenance', () {
    final original = AppSnapshot(
      profile: const UserProfile(id: 'me', nickname: '知夏'),
      plans: const [
        Plan(id: 'p', title: '晚餐', category: 'food', visibility: 'private'),
      ],
      checkins: [
        Checkin(
          id: 'c',
          userId: 'me',
          planId: 'p',
          localDate: '2026-11-18',
          createdAt: DateTime.utc(2026, 11, 18),
          fields: const [
            MemoField(
              key: 'dish',
              label: '菜品',
              value: '西红柿炒蛋',
              source: 'manual',
            ),
          ],
        ),
      ],
    );
    final restored = AppSnapshot.fromJson(original.toJson());
    expect(restored.plans.single.visibility, 'private');
    expect(restored.checkins.single.fields.single.source, 'manual');
  });

  test('demo is explicitly labelled and local actions persist, challenge rules applied', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = DemoRepository(
      clock: () => DateTime.utc(2026, 11, 18, 3),
    );
    expect(repository.isDemo, isTrue);
    final snapshot = await repository.bootstrap();
    expect(snapshot.plans.length, greaterThanOrEqualTo(5));
    await repository.action('save_profile', args: {'nickname': '小满'});
    await repository.action(
      'interact',
      args: {
        'checkin_id': 'friend-study',
        'kind': 'comment',
        'content': '一起加油',
      },
    );
    var updated = await repository.bootstrap();
    expect(updated.profile.nickname, '小满');
    expect(
      updated.checkins.firstWhere((c) => c.id == 'friend-study').challengeCount,
      0,
    );
    await expectLater(
      repository.action(
        'interact',
        args: {
          'checkin_id': 'friend-study',
          'kind': 'challenge',
          'content': '',
        },
      ),
      throwsA(isA<AppException>()),
    );
    await repository.action(
      'interact',
      args: {
        'checkin_id': 'friend-study',
        'kind': 'challenge',
        'content': '图片与计划不一致',
      },
    );
    updated = await repository.bootstrap();
    expect(
      updated.checkins.firstWhere((c) => c.id == 'friend-study').challengeCount,
      1,
    );
    expect(
      updated.checkins.firstWhere((c) => c.id == 'friend-study').status,
      'stamped',
    );
    await expectLater(
      repository.action(
        'interact',
        args: {
          'checkin_id': 'today-study',
          'kind': 'challenge',
          'content': '自己的记录',
        },
      ),
      throwsA(isA<AppException>()),
    );
    final restored = DemoRepository(clock: () => DateTime.utc(2026, 11, 18, 3));
    expect((await restored.bootstrap()).profile.nickname, '小满');
    await repository.dispose();
    await restored.dispose();
  });

  test('demo accepts a fourth active plan and rejects duplicate pokes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = DemoRepository(
      clock: () => DateTime.utc(2026, 11, 18, 3),
    );
    await repository.bootstrap();
    await repository.action('save_plan',args:{'title':'练琴','weekdays':[1]});
    expect((await repository.bootstrap()).plans.where((p)=>p.isActive).length,6);
    await repository.action('poke', args: {'overdue_id': 'demo-overdue'});
    await expectLater(
      repository.action('poke', args: {'overdue_id': 'demo-overdue'}),
      throwsA(isA<AppException>()),
    );
    await repository.dispose();
  });

  test('demo showcase reset restores current seed without touching production storage', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = DemoRepository(
      clock: () => DateTime.utc(2026, 11, 18, 3),
    );
    await repository.bootstrap();
    await repository.action('save_profile', args: {'nickname': '临时演示名'});
    await repository.action('reset_demo_showcase');
    final restored = await repository.bootstrap();
    expect(restored.profile.nickname, '知夏');
    expect(restored.team!.members.length, 5);
    expect(restored.plans.length, greaterThanOrEqualTo(5));
    expect(restored.checkins.any((c) => c.batchId == 'demo-mixed-batch'), isTrue);
    final stored = jsonDecode(
      (await SharedPreferences.getInstance()).getString('better_together_demo_v1')!,
    ) as Map;
    expect(stored['demo_seed_version'], DemoRepository.showcaseSeedVersion);
    await repository.dispose();
  });

  test('rejected demo redo does not consume photos or makeup quota', () async {
    SharedPreferences.setMockInitialValues({});
    final initial = DemoRepository(clock: () => DateTime.utc(2026, 11, 18, 3));
    await initial.bootstrap();
    final preferences = await SharedPreferences.getInstance();
    final stored = jsonObject(
      jsonDecode(preferences.getString('better_together_demo_v1')!),
    );
    stored['_media'] = [
      {
        'id': 'photo',
        'path': '/local-test/photo.jpg',
        'source': 'camera',
        'captured_at': '2026-11-18T03:00:00Z',
        'batch_id': 'batch',
        'used': false,
      },
    ];
    await preferences.setString('better_together_demo_v1', jsonEncode(stored));
    await initial.dispose();
    final repository = DemoRepository(
      clock: () => DateTime.utc(2026, 11, 18, 3),
    );
    final args = <String, Object?>{
      'idempotency_key': 'attempt',
      'media_ids': ['photo'],
      'target_date': '2026-11-17',
      'makeup_reason': '补上昨日记录',
      'redo_of': 'does-not-exist',
    };
    await expectLater(
      repository.action('submit_checkin', args: args),
      throwsA(isA<AppException>()),
    );
    expect((await repository.bootstrap()).profile.makeupRemaining, 2);
    args.remove('redo_of');
    final result = jsonObject(
      await repository.action('submit_checkin', args: args),
    );
    expect(jsonList(result['checkin_ids']), hasLength(1));
    expect((await repository.bootstrap()).profile.makeupRemaining, 1);
    await repository.dispose();
  });

  test('demo avatars persist locally without a capture date and synchronize members', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'better-avatar-test-',
    );
    final repository = DemoRepository(directoryProvider: () async => directory);
    try {
      final uploaded = await repository.upload(
        PhotoUpload(
          bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
          filename: 'avatar.png',
          source: 'avatar',
          batchId: 'avatar-batch',
          contentType: 'image/png',
        ),
      );
      expect(await File(uploaded.path).exists(), isTrue);
      await repository.action(
        'save_profile',
        args: {'avatar_url': uploaded.path},
      );
      final snapshot = await repository.bootstrap();
      expect(snapshot.profile.avatarUrl, uploaded.path);
      expect(
        snapshot.team!.members
            .firstWhere((m) => m.id == snapshot.profile.id)
            .avatarUrl,
        uploaded.path,
      );
      await expectLater(
        repository.action(
          'save_profile',
          args: {'avatar_url': '/someone-elses/photo.jpg'},
        ),
        throwsA(isA<AppException>()),
      );
      expect((await repository.bootstrap()).profile.avatarUrl, uploaded.path);
      await repository.action(
        'delete_account',
        args: {'confirmation': 'DELETE'},
      );
      expect(await File(uploaded.path).exists(), isFalse);
    } finally {
      await repository.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'demo report interactions require sharing and never allow challenges',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = DemoRepository();
      await repository.bootstrap();
      await expectLater(
        repository.action(
          'interact_report',
          args: {'report_id': 'demo-report', 'kind': 'like'},
        ),
        throwsA(isA<AppException>()),
      );
      await repository.action(
        'share_report',
        args: {'report_id': 'demo-report', 'method': 'feed'},
      );
      await repository.action(
        'interact_report',
        args: {'report_id': 'demo-report', 'kind': 'like'},
      );
      await repository.action(
        'interact_report',
        args: {
          'report_id': 'demo-report',
          'kind': 'comment',
          'content': '下周继续一起',
        },
      );
      final report = (await repository.bootstrap()).reports
          .firstWhere((r) => r.id == 'demo-report');
      expect(report.likes, 1);
      expect(report.comments.single.content, '下周继续一起');
      await expectLater(
        repository.action(
          'interact_report',
          args: {
            'report_id': 'demo-report',
            'kind': 'challenge',
            'content': '质疑',
          },
        ),
        throwsA(isA<AppException>()),
      );
      await repository.action(
        'interact_report',
        args: {'report_id': 'demo-report', 'kind': 'like'},
      );
      expect(
        (await repository.bootstrap()).reports
            .firstWhere((r) => r.id == 'demo-team-report')
            .likes,
        0,
      );
      expect(
        jsonObject(
          await repository.action(
            'unregister_device',
            args: {'token': 'local'},
          ),
        )['demo'],
        isTrue,
      );
      await repository.dispose();
    },
  );
}
