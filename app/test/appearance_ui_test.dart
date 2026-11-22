import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/features/checkin/checkin_page.dart';
import 'package:better_together/features/checkin/memo_page.dart';
import 'package:better_together/features/plans/plans_page.dart';
import 'package:better_together/features/reports/reports_page.dart';
import 'package:better_together/features/settings/appearance_page.dart';
import 'package:better_together/features/settings/settings_page.dart';
import 'package:better_together/features/team/team_page.dart';
import 'package:better_together/features/today/today_page.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:better_together/ui/tuantuan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      testWidgets(
        'cartoon routes fit $width with large text in ${brightness.name}',
        (tester) async {
          _configureView(tester, width: width, brightness: brightness);
          SharedPreferences.setMockInitialValues({});
          final repository = DemoRepository();
          final container = ProviderContainer(
            overrides: [
              repositoryProvider.overrideWithValue(repository),
              initialAppearanceProvider.overrideWithValue(
                const AppearanceLoadResult(appearance: AppAppearance.tuantuan),
              ),
            ],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            container.dispose();
            await repository.dispose();
          });

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const BetterTogetherApp(),
            ),
          );
          await tester.pumpAndSettle();
          final todayContext = tester.element(find.byType(TodayPage));
          final router = GoRouter.of(todayContext);
          expect(Theme.of(todayContext).brightness, brightness);
          expect(isTuanTuan(todayContext), isTrue);
          expect(find.byType(TuanTuanMascot), findsAtLeastNWidgets(1));
          expect(tester.takeException(), isNull, reason: 'today at $width');

          const pages = <String, Type>{
            '/team': TeamPage,
            '/plans': PlansPage,
            '/reports': ReportsPage,
            '/settings': SettingsPage,
            '/settings/appearance': AppearancePage,
            '/checkin': CheckinPage,
            '/memo/today-study?sealed=1': MemoPage,
          };
          for (final page in pages.entries) {
            router.go(page.key);
            await tester.pumpAndSettle();
            expect(find.byType(page.value), findsOneWidget);
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.key} at $width in ${brightness.name}',
            );
            // Exercise content below the first viewport and bottom controls.
            final scrollables = find.byType(Scrollable);
            if (scrollables.evaluate().isNotEmpty) {
              await tester.drag(scrollables.first, const Offset(0, -700));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${page.key} after scrolling at $width',
              );
            }
          }
        },
      );
    }
  }

  testWidgets(
    'settings switches both ways without replacing navigation or data',
    (tester) async {
      _configureView(tester, width: 375, brightness: Brightness.light);
      SharedPreferences.setMockInitialValues({});
      final repository = DemoRepository();
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          initialAppearanceProvider.overrideWithValue(
            const AppearanceLoadResult(),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const BetterTogetherApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(TodayPage)));
      final snapshot = container.read(appControllerProvider).requireValue;
      final userId = repository.currentUserId;
      router.go('/plans');
      await tester.pumpAndSettle();
      router.push('/settings');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('界面外观'));
      await tester.tap(find.text('界面外观'));
      await tester.pumpAndSettle();

      for (final appearance in [
        AppAppearance.tuantuan,
        AppAppearance.classic,
      ]) {
        final choice = find.byKey(ValueKey('appearance-${appearance.name}'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();

        expect(container.read(appearanceProvider), appearance);
        expect(router.state.uri.path, '/settings/appearance');
        final pageContext = tester.element(find.byType(AppearancePage));
        expect(GoRouter.of(pageContext), same(router));
        expect(isTuanTuan(pageContext), appearance == AppAppearance.tuantuan);
        expect(
          container.read(appControllerProvider).requireValue,
          same(snapshot),
        );
        expect(repository.currentUserId, userId);
        expect(repository.isSignedIn, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getString(
            SharedPreferencesAppearanceStore.preferenceKey,
          ),
          appearance.name,
        );
        expect(tester.takeException(), isNull);
      }

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('经典纸面'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(PlansPage), findsOneWidget);
      expect(router.state.uri.path, '/plans');
      expect(
        container.read(appControllerProvider).requireValue,
        same(snapshot),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

void _configureView(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
}) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}
