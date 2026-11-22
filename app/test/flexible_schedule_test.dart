import 'package:better_together/domain/models.dart';
import 'package:better_together/domain/rules.dart';
import 'package:better_together/features/plans/plans_page.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/ui/design.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  zones.initializeTimeZones();
  test('fixed interval crosses DST and month using calendar dates', () {
    const p = Plan(
      id: 'p',
      title: '冥想',
      category: 'mindfulness',
      scheduleKind: 'interval',
      intervalDays: 2,
      anchorDate: '2026-10-31',
    );
    expect(
      planIsDue(
        p,
        DateTime.parse('2026-11-02T08:30:00Z'),
        'America/Los_Angeles',
      ),
      isTrue,
    );
    expect(
      planIsDue(
        p,
        DateTime.parse('2026-11-01T09:30:00Z'),
        'America/Los_Angeles',
      ),
      isFalse,
    );
    expect(
      planIsDue(
        p,
        DateTime.parse('2026-10-29T09:30:00Z'),
        'America/Los_Angeles',
      ),
      isFalse,
    );
  });
  test(
    'weekly target has no daily deadline and roundtrips authoritative progress',
    () {
      final p = Plan.fromJson({
        'id': 'p',
        'title': '喝水',
        'category': 'water',
        'schedule_kind': 'weekly_target',
        'weekly_target_days': 3,
        'weekly_target': 2,
        'weekly_completed': 3,
        'extra_days': 1,
        'weekly_streak': 4,
      });
      expect(planIsDue(p, DateTime.now(), 'Asia/Shanghai'), isFalse);
      final saved = Plan.fromJson(p.toJson());
      expect(saved.extraDays, 1);
      expect(saved.weeklyStreak, 4);
      expect(saved.scheduleLabel, '每周完成 3 天');
    },
  );
  test('period target roundtrips schedule and pending configuration', () {
    final plan = Plan.fromJson({
      'id': 'p',
      'title': '晨间阅读',
      'category': 'study',
      'schedule_kind': 'period_target',
      'period_days': 5,
      'period_target_days': 3,
      'period_target': 3,
      'period_completed': 2,
      'period_start': '2026-11-20',
      'period_end': '2026-11-24',
      'next_config': {
        'schedule_kind': 'period_target',
        'period_days': 8,
        'period_target_days': 4,
      },
      'effective_on': '2026-11-23',
    });
    expect(plan.scheduleLabel, '每 5 天完成 3 天');
    expect(plan.pendingScheduleLabel, '每 8 天完成 4 天');
    expect(plan.periodCompleted, 2);
    expect(Plan.fromJson(plan.toJson()).periodStart, '2026-11-20');
  });
  test(
    'editing a plan keeps pending frequency when status also changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = DemoRepository(clock: () => DateTime(2026, 11, 21, 10));
      final snapshot = await repo.bootstrap();
      final original = snapshot.plans.first;
      await repo.action(
        'save_plan',
        args: {
          'schema_version': 2,
          'id': original.id,
          'title': original.title,
          'goal': original.goal,
          'category': original.category,
          'schedule_kind': 'period_target',
          'period_days': 5,
          'period_target_days': 3,
          'interval_days': 2,
          'anchor_date': '2026-11-21',
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'start_time': original.startTime,
          'deadline': original.deadline,
          'visibility': original.visibility,
          'status': 'paused',
        },
      );
      final updated = (await repo.bootstrap()).plans.firstWhere(
        (p) => p.id == original.id,
      );
      expect(updated.status, original.status);
      expect(updated.scheduleKind, original.scheduleKind);
      expect(updated.pendingScheduleLabel, '每 5 天完成 3 天');
      expect(updated.pendingChanges?['status'], 'paused');
      expect(updated.effectiveOn, '2026-11-23');
      await repo.action(
        'save_plan',
        args: {
          'schema_version': 2,
          'id': original.id,
          'title': original.title,
          'goal': original.goal,
          'category': original.category,
          'schedule_kind': 'period_target',
          'period_days': 8,
          'period_target_days': 4,
          'interval_days': 2,
          'anchor_date': '2026-11-21',
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'start_time': original.startTime,
          'deadline': original.deadline,
          'visibility': original.visibility,
          'status': 'paused',
        },
      );
      final editedAgain = (await repo.bootstrap()).plans.firstWhere(
        (p) => p.id == original.id,
      );
      expect(editedAgain.pendingScheduleLabel, '每 8 天完成 4 天');
      await repo.dispose();
    },
  );
  for (final appearance in AppAppearance.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'plan frequencies fit 375 large text $appearance $brightness',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = const Size(375, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final repo = DemoRepository();
          await repo.bootstrap();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [repositoryProvider.overrideWithValue(repo)],
              child: MaterialApp(
                theme: buildTheme(brightness, appearance: appearance),
                home: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: const PlanEditorPage(
                    plan: Plan(
                      id: 'p',
                      title: '喝水',
                      category: 'water',
                      scheduleKind: 'weekly_target',
                      anchorDate: '2026-11-20',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('频率方式'));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('开始日期'));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await repo.dispose();
        },
      );
    }
  }
}
