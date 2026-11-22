import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:better_together/ui/record_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'supplied demo photos reset, display and survive native storage',
    (tester) async {
      const demoKey = 'better_together_demo_v1';
      const appearanceKey = SharedPreferencesAppearanceStore.preferenceKey;
      // Only use this opt-in after an explicit request to replace local demo data.
      const applyFixtures = bool.fromEnvironment('APPLY_DEMO_FIXTURES');
      final preferences = await SharedPreferences.getInstance();
      final previousDemo = preferences.getString(demoKey);
      final previousAppearance = preferences.getString(appearanceKey);
      final repository = DemoRepository();
      final store = SharedPreferencesAppearanceStore();
      var succeeded = false;
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          appearanceStoreProvider.overrideWithValue(store),
          initialAppearanceProvider.overrideWithValue(
            const AppearanceLoadResult(),
          ),
        ],
      );

      Future<void> restore(String key, String? value) async {
        if (value == null) {
          await preferences.remove(key);
        } else {
          await preferences.setString(key, value);
        }
      }

      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await binding.takeScreenshot('ios-new-assets-$name');
      }

      try {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const BetterTogetherApp(),
          ),
        );
        await tester.pumpAndSettle();
        final router =
            tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
                as GoRouter;
        router.push('/settings');
        await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('重置为讲解场景'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
        await tester.tap(find.text('重置为讲解场景'));
        await tester.pumpAndSettle();
        expect(find.textContaining('20 张合成测试照片'), findsOneWidget);
        await tester.tap(find.text('重置演示数据'));
        await tester.pumpAndSettle();
        final snapshot = await repository.bootstrap();
        final photos = snapshot.checkins.expand((c) => c.photos).toList();
        expect(photos, hasLength(20));
        // Decode every bundled original on the actual iOS renderer.
        final context = tester.element(find.byType(BetterTogetherApp));
        for (final photo in photos) {
          Object? failure;
          await precacheImage(
            AssetImage(photo.url.substring('asset:'.length)),
            context,
            onError: (error, _) => failure = error,
          );
          expect(failure, isNull, reason: photo.url);
        }
        router.go('/today');
        await shot('today');
        router.push('/memo/today-study');
        await tester.pumpAndSettle();
        expect(find.textContaining('英语单词、中文释义和例句'), findsWidgets);
        await shot('study');
        router.go('/today');
        router.push('/memo/food-breakfast');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(RecordImage).first);
        await tester.tap(find.byType(RecordImage).first);
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        await shot('photo-fullscreen');
        await tester.drag(find.byType(PageView), const Offset(-320, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await shot('photo-next');
      await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        router.go('/team');
        await tester.pumpAndSettle();
        expect(find.textContaining('热量约 400-650'), findsNothing);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
        await shot('team');

        for (final appearance in AppAppearance.values) {
          router.go('/settings/appearance');
          await tester.pumpAndSettle();
          final option = find.byKey(ValueKey('appearance-${appearance.name}'));
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pumpAndSettle();
          router.go('/reports');
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('本周完成率'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await shot('${appearance.name}-personal-report');
          await tester.scrollUntilVisible(
            find.text('小队周报'),
            -450,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('小队周报'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('小队完成率'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await shot('${appearance.name}-team-report');
        }
        succeeded = true;
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.dispose();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        if (!succeeded || !applyFixtures) await restore(demoKey, previousDemo);
        await restore(appearanceKey, previousAppearance);
      }
    },
  );
}
