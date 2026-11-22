import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('missing configuration is explicit and does not enter demo', (
    tester,
  ) async {
    await tester.pumpWidget(const SetupApp(message: '服务尚未配置'));
    expect(find.text('服务尚未配置'), findsOneWidget);
    expect(find.text('本机演示模式 · 示例数据不会上传'), findsNothing);
  });
  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('core navigation renders at width $width with large text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final repository = DemoRepository();
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          child: const BetterTogetherApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天，也一起。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('计划').last);
      await tester.pumpAndSettle();
      expect(find.text('我的计划'), findsOneWidget);
      await tester.tap(find.byTooltip('新建计划'));
      await tester.pumpAndSettle();
      expect(find.text('给坚持一个具体的名字'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.text('我的计划')));
      router.push('/history');
      await tester.pumpAndSettle();
      final days = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      expect(days, findsNWidgets(28));
      for (final day in days.evaluate()) {
        final size = tester.getSize(find.byElementPredicate((e) => e == day));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('周报').last);
      await tester.pumpAndSettle();
      expect(find.text('这一周，值得记住'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('小队').last);
      await tester.pumpAndSettle();
      expect(find.text('有人同行，每一步都算数。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.dispose();
    });
  }
}
