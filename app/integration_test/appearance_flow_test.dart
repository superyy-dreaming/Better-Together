import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:better_together/ui/tuantuan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native appearance switching preserves data, route and preference',
    (tester) async {
      // 只接入本机演示仓库，不调用生产 main、认证、Storage 或业务接口。
      // 临时替换的两个本机偏好在结束时恢复，不清空其他偏好或用户数据。
      const demoKey = 'better_together_demo_v1';
      const appearanceKey = SharedPreferencesAppearanceStore.preferenceKey;
      final preferences = await SharedPreferences.getInstance();
      final previousDemo = preferences.getString(demoKey);
      final previousAppearance = preferences.getString(appearanceKey);
      final repositories = <DemoRepository>[];
      final store = SharedPreferencesAppearanceStore();
      var androidSurfaceConverted = false;

      GoRouter router() =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
              as GoRouter;

      ProviderContainer container() => ProviderScope.containerOf(
        tester.element(find.byType(BetterTogetherApp)),
      );

      Future<void> mount(
        DemoRepository repository,
        AppearanceStore store,
      ) async {
        final initial = await loadAppearance(store);
        expect(initial.error, isNull);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repository),
              appearanceStoreProvider.overrideWithValue(store),
              initialAppearanceProvider.overrideWithValue(initial),
            ],
            child: const BetterTogetherApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> shot(String name) async {
        if (Platform.isAndroid && !androidSurfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          androidSurfaceConverted = true;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await binding.takeScreenshot(
          '${Platform.operatingSystem}-appearance-$name',
        );
      }

      Future<void> choose(AppAppearance appearance) async {
        final option = find.byKey(ValueKey('appearance-${appearance.name}'));
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(container().read(appearanceProvider), appearance);
        expect(container().read(appearanceStatusProvider).saving, isFalse);
        expect(container().read(appearanceStatusProvider).error, isNull);
        expect(await store.read(), appearance.name);
        // 等待成功提示消失，截图只展示当前页面本身。
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      Future<void> restorePreference(String key, String? value) async {
        if (value == null) {
          await preferences.remove(key);
        } else {
          await preferences.setString(key, value);
        }
      }

      try {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await preferences.remove(demoKey);
        await store.write(AppAppearance.classic.name);
        final repository = DemoRepository();
        repositories.add(repository);
        final baseline = await repository.bootstrap();
        final baselineData = baseline.toJson()..remove('feed_ids')..remove('history_ids');
        final completed = baseline.checkins.firstWhere(
          (record) =>
              record.userId == baseline.profile.id && record.isCompleted,
        );

        await mount(repository, store);
        final navigation = router();
        final controller = container().read(appControllerProvider.notifier);
        expect(container().read(appearanceProvider), AppAppearance.classic);
        expect(find.text('今天，也一起。'), findsOneWidget);
        await shot('classic-today-light');

        // 从用户可见的设置入口进入，不直接操作偏好控制器。
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('界面外观'));
        await tester.tap(find.text('界面外观'));
        await tester.pumpAndSettle();
        expect(navigation.state.uri.path, '/settings/appearance');
        await shot('choices-classic-light');
        await choose(AppAppearance.tuantuan);
        expect(identical(router(), navigation), isTrue);
        expect(navigation.state.uri.path, '/settings/appearance');
        expect(
          identical(
            container().read(appControllerProvider.notifier),
            controller,
          ),
          isTrue,
        );
        expect(
          (container().read(appControllerProvider).requireValue.toJson()..remove('feed_ids')..remove('history_ids')),
          baselineData,
        );
        await shot('choices-tuantuan-light');

        // 两次返回仍保留原设置与首页栈，切换主题不应重建路由。
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(navigation.state.uri.path, '/settings');
        expect(find.text('团团陪你'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(navigation.state.uri.path, '/today');
        expect(find.byType(TuanTuanHero), findsWidgets);
        expect(
          (container().read(appControllerProvider).requireValue.toJson()..remove('feed_ids')..remove('history_ids')),
          baselineData,
        );
        await shot('tuantuan-today-light');

        for (final screen in ['team', 'plans', 'reports']) {
          navigation.go('/$screen');
          await tester.pumpAndSettle();
          expect(find.byType(TuanTuanHero), findsWidgets);
          await shot('tuantuan-$screen-light');
        }
        navigation.go('/today');
        await tester.pumpAndSettle();
        navigation.push('/checkin');
        await tester.pumpAndSettle();
        expect(find.text('你负责行动，\n我帮你整理！'), findsOneWidget);
        expect(find.text('现在选一张'), findsOneWidget);
        await shot('tuantuan-checkin-light');
        navigation.pop();
        await tester.pumpAndSettle();
        navigation.push('/memo/${completed.id}?sealed=1');
        await tester.pumpAndSettle();
        expect(find.text('好耶，\n又完成一件！'), findsOneWidget);
        expect(find.text(completed.summary), findsOneWidget);
        await shot('tuantuan-memo-light');

        navigation.go('/today');
        await tester.pumpAndSettle();
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        await shot('tuantuan-today-dark');
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await shot('tuantuan-today-large-dark');
        for (final screen in ['team', 'plans', 'reports']) {
          navigation.go('/$screen');
          await tester.pumpAndSettle();
          await shot('tuantuan-$screen-large-dark');
        }
        navigation.go('/today');
        await tester.pumpAndSettle();
        navigation.push('/checkin');
        await tester.pumpAndSettle();
        await shot('tuantuan-checkin-large-dark');
        navigation.pop();
        await tester.pumpAndSettle();
        navigation.push('/memo/${completed.id}?sealed=1');
        await tester.pumpAndSettle();
        await shot('tuantuan-memo-large-dark');
        navigation.go('/today');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await shot('tuantuan-settings-large-dark');
        await tester.ensureVisible(find.text('界面外观'));
        await tester.tap(find.text('界面外观'));
        await tester.pumpAndSettle();
        await shot('choices-tuantuan-large-dark');

        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await tester.pumpAndSettle();
        await choose(AppAppearance.classic);
        expect(identical(router(), navigation), isTrue);
        navigation.go('/today');
        await tester.pumpAndSettle();
        expect(find.text('今天，也一起。'), findsOneWidget);
        expect(find.byType(TuanTuanHero), findsNothing);
        expect(
          (container().read(appControllerProvider).requireValue.toJson()..remove('feed_ids')..remove('history_ids')),
          baselineData,
        );
        await shot('classic-restored-light');

        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('界面外观'));
        await tester.tap(find.text('界面外观'));
        await tester.pumpAndSettle();
        await choose(AppAppearance.tuantuan);

        // 拆卸整棵应用和 ProviderScope，并从原生偏好重读以模拟重新启动。
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await preferences.reload();
        final restoredStore = SharedPreferencesAppearanceStore();
        final restored = await loadAppearance(restoredStore);
        expect(restored.appearance, AppAppearance.tuantuan);
        expect(restored.error, isNull);
        final restartedRepository = DemoRepository();
        repositories.add(restartedRepository);
        await mount(restartedRepository, restoredStore);
        expect(identical(router(), navigation), isFalse);
        expect(container().read(appearanceProvider), AppAppearance.tuantuan);
        expect(find.byType(TuanTuanHero), findsWidgets);
        expect(
          (container().read(appControllerProvider).requireValue.toJson()..remove('feed_ids')..remove('history_ids')),
          baselineData,
        );
        expect((await restartedRepository.bootstrap()).toJson()..remove('feed_ids')..remove('history_ids'), baselineData);
        await shot('tuantuan-restored-after-restart');
      } finally {
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        for (final repository in repositories) {
          await repository.dispose();
        }
        await restorePreference(demoKey, previousDemo);
        await restorePreference(appearanceKey, previousAppearance);
      }
    },
  );
}
