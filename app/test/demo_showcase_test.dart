import 'dart:convert';
import 'dart:io';

import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const storageKey = 'better_together_demo_v1';
final showcaseClock = DateTime.utc(2026, 11, 22, 8);

Future<JsonMap> storedState() async => jsonObject(
  jsonDecode((await SharedPreferences.getInstance()).getString(storageKey)!),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first load retains all 20 supplied originals and each photo summary',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = DemoRepository(clock: () => showcaseClock);
      addTearDown(repo.dispose);
      final state = await repo.bootstrap();
      final raw = await storedState();
      expect(raw['demo_seed_version'], 3);
      expect(state.team!.members, hasLength(5));
      final photos = state.checkins.expand((c) => c.photos).toList();
      expect(photos, hasLength(20));
      expect(photos.map((p) => p.url).toSet(), hasLength(20));
      final supplied = Directory('assets/demo/test-photos')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .map((f) => 'asset:${f.path}')
          .toSet();
      expect(photos.map((p) => p.url).toSet(), supplied);
      for (final photo in photos) {
        expect(photo.recognition!.summary, isNotEmpty);
        expect(photo.url, startsWith('asset:assets/demo/test-photos/'));
        expect(photo.recognition!.origin, 'demo_fixture');
        expect(photo.recognition!.toJson()['origin'], 'demo_fixture');
      }
      for (final check in jsonList(raw['checkins']).map(jsonObject)) {
        for (final photo in jsonList(check['photos']).map(jsonObject)) {
          expect(jsonObject(photo['recognition'])['origin'], 'demo_fixture');
          expect(photo['demo_fixture'], isTrue);
        }
      }
      final mixed = state.checkins
          .where((c) => c.batchId == 'demo-mixed-batch')
          .toList();
      expect(mixed, hasLength(3));
      expect(mixed.map((c) => c.planId).toSet(), {'study', 'exercise', 'food'});
      expect(mixed.map((c) => c.photos.single.url.split('/').last).toSet(), {
        'study-01.jpg',
        'sport-04.jpg',
        'food-01.jpg',
      });
    },
  );

  test('screen readings keep actual date and photo-only sports never invent numbers', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = DemoRepository(clock: () => DateTime.utc(2026, 12, 5, 8));
    addTearDown(repo.dispose);
    final state = await repo.bootstrap();
    final screenshotRecord = state.checkins.firstWhere(
      (c) => c.id == 'exercise-2',
    );
    expect(screenshotRecord.localDate, '2026-11-22');
    expect(
      screenshotRecord.photos.single.recognition!.screenshotDate,
      '2026-11-22',
    );
    expect(screenshotRecord.fields.map((f) => f.value).toList(), [
      1935,
      5.20,
      312,
    ]);
    expect(
      screenshotRecord.fields.every((f) => f.source == 'screenshot'),
      isTrue,
    );
    final treadmill = state.checkins.firstWhere((c) => c.id == 'exercise-1');
    expect(treadmill.planId, isNull);
    expect(treadmill.photos.single.recognition!.screenshotDate, isNull);
    expect(treadmill.photos.single.recognition!.status, 'pending');
    expect(treadmill.summary, contains('日期待核实'));
    expect(treadmill.fields.map((f) => f.value).toList(), [2120, 5.02, 286]);
    for (final record in state.checkins) {
      for (final photo in record.photos) {
        if (RegExp(r'sport-0[3-6]\.jpg$').hasMatch(photo.url)) {
          expect(photo.recognition!.fields, isEmpty);
          expect(record.fields, isEmpty);
        }
        if (photo.url.contains('/life-')) {
          expect(record.planId, isNull);
          expect(record.category, 'all');
        }
      }
      if (record.category == 'food') {
        for (final field in record.fields) {
          final range = jsonObject(field.value);
          expect(range['estimated'], true);
          expect(range['min'], lessThan(range['max'] as num));
          expect(field.source, 'ai');
          expect(field.label, contains('估算'));
        }
      }
    }
  });

  test('weekly charts derive counts, deduplicate plan days and exclude private data', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = DemoRepository(clock: () => showcaseClock);
    addTearDown(repo.dispose);
    final state = await repo.bootstrap();
    final personal = state.reports.firstWhere((r) => r.id == 'demo-report');
    final team = state.reports.firstWhere((r) => r.id == 'demo-team-report');
    expect(personal.weekStart, '2026-11-16');
    expect(personal.metrics['checkins'], 15);
    expect(personal.metrics['completed'], 9);
    expect(personal.metrics['expected'], 21);
    expect(personal.metrics['completion_rate'], 9 / 21);
    expect(personal.metrics['by_category'], {
      'study': 2,
      'exercise': 4,
      'food': 4,
      'uncategorized': 5,
    });
    final exercise = jsonList(personal.metrics['plans'])
        .map(jsonObject)
        .firstWhere((p) => p['id'] == 'exercise');
    expect(exercise['completed'], 3); // Two Sunday records count as one day.
    expect(exercise['expected'], 4);
    expect(team.metrics['members'], 5);
    expect(team.metrics['completed'], 8);
    expect(team.metrics['expected'], 39);
    expect(team.metrics['checkins'], 9);
    expect(team.metrics['makeup'], 1);
    expect(team.metrics['by_category'], {'study': 4, 'exercise': 5});
    expect(state.plans.firstWhere((p) => p.id == 'water').periodCompleted, 0);
    expect(state.plans.firstWhere((p) => p.id == 'water').periodTarget, 3);
    expect(
      state.plans.firstWhere((p) => p.id == 'meditation').category,
      'meditation',
    );
    final peer = state.reports.firstWhere((r) => r.id == 'demo-peer-report');
    expect(peer.shared, isTrue);
    expect(peer.metrics['checkins'], 1);
  });

  test(
    'feed excludes private records before pagination; history is owner-only',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = DemoRepository(clock: () => showcaseClock);
      addTearDown(repo.dispose);
      final state = await repo.bootstrap();
      final allPrivate = state.checkins.where(
        (c) => c.category == 'food' || c.planId == null,
      );
      for (final record in allPrivate) {
        expect(state.feedIds, isNot(contains(record.id)));
        expect(state.historyIds, contains(record.id));
      }
      final feed = jsonObject(
        await repo.action('read_page', args: {'collection': 'checkins'}),
      );
      final history = jsonObject(
        await repo.action('read_page', args: {'collection': 'history'}),
      );
      final feedRows = jsonList(feed['items']).map(jsonObject).toList();
      expect(feedRows, hasLength(10)); // Includes one redo-required entry.
      expect(feedRows.every((c) => c['visibility'] == 'team'), isTrue);
      final historyRows = jsonList(history['items']).map(jsonObject).toList();
      expect(historyRows, hasLength(15));
      expect(historyRows.every((c) => c['user_id'] == 'demo-owner'), isTrue);
      expect(history['next_cursor'], isNull);
    },
  );

  test(
    'explicit reset changes only demo state and the new fixtures persist',
    () async {
      SharedPreferences.setMockInitialValues({
        'production-session': 'untouched-session',
        'appearance': 'tuantuan',
      });
      final repo = DemoRepository(clock: () => showcaseClock);
      final initial = await repo.bootstrap();
      await repo.action('save_profile', args: {'nickname': '临时演示名'});
      await repo.action('reset_demo_showcase');
      final reset = await repo.bootstrap();
      expect(reset.profile.nickname, '知夏');
      expect(reset.checkins.length, initial.checkins.length);
      expect(reset.checkins.expand((c) => c.photos).length, 20);
      await repo.dispose();
      final restored = DemoRepository(clock: () => showcaseClock);
      addTearDown(restored.dispose);
      final persisted = await restored.bootstrap();
      expect(
        persisted.checkins.map((c) => c.toJson()).toList(),
        reset.checkins.map((c) => c.toJson()).toList(),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('production-session'), 'untouched-session');
      expect(prefs.getString('appearance'), 'tuantuan');
    },
  );

  test(
    'existing demo state is never silently replaced by the new seed',
    () async {
      final legacy = {
        'demo_seed_version': 2,
        'profile': {'id': 'demo-owner', 'nickname': '保留我的改动'},
        'plans': <Object?>[],
        'checkins': <Object?>[],
        'reports': <Object?>[],
      };
      SharedPreferences.setMockInitialValues({storageKey: jsonEncode(legacy)});
      final repo = DemoRepository(clock: () => showcaseClock);
      addTearDown(repo.dispose);
      final state = await repo.bootstrap();
      expect(state.profile.nickname, '保留我的改动');
      expect(state.checkins, isEmpty);
      expect(await storedState(), legacy);
    },
  );
}
