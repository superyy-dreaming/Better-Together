import 'dart:io';
import 'dart:typed_data';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native core flow, screenshots, dark mode and large type', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final previous = DemoRepository();
    await previous.action('delete_account', args: {'confirmation': 'DELETE'});
    await previous.dispose();
    final repository = DemoRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: const BetterTogetherApp(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> shot(String name) async {
      if (Platform.isAndroid && name == 'today-light') {
        await binding.convertFlutterSurfaceToImage();
      }
      await tester.pumpAndSettle();
      await binding.takeScreenshot('${Platform.operatingSystem}-$name');
    }

    GoRouter router() => GoRouter.of(tester.element(find.text('今天，也一起。')));
    final navigation = router();
    expect(find.text('今天，也一起。'), findsOneWidget);
    await shot('today-light');
    await tester.tap(find.text('小队').last);
    await tester.pumpAndSettle();
    await shot('team-light');
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建计划'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '每天认真读书');
    await shot('plan-editor');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周报').last);
    await tester.pumpAndSettle();
    await shot('report-light');
    navigation.push('/history');
    await tester.pumpAndSettle();
    await shot('history-light');
    expect(tester.takeException(), isNull);
    navigation.pop();
    await tester.pumpAndSettle();
    navigation.go('/today');
    await tester.pumpAndSettle();
    navigation.push('/checkin');
    await tester.pumpAndSettle();
    await shot('checkin-empty');
    navigation.pop();
    await tester.pumpAndSettle();
    final snapshot = await repository.bootstrap();
    final fixture = img.Image(width: 160, height: 120);
    img.fill(fixture, color: img.ColorRgb8(23, 62, 46));
    final media = await repository.upload(
      PhotoUpload(
        bytes: Uint8List.fromList(img.encodeJpg(fixture)),
        filename: 'synthetic.jpg',
        source: 'camera',
        capturedAt: DateTime.now(),
        batchId: 'integration-native',
      ),
    );
    final result = jsonObject(
      await repository.action(
        'submit_checkin',
        args: {
          'media_ids': [media.id],
          'plan_id': snapshot.plans.first.id,
          'note': '模拟器合成图片测试',
          'idempotency_key': 'integration-native',
        },
      ),
    );
    final id = jsonList(result['checkin_ids']).first.toString();
    final container = ProviderScope.containerOf(
      tester.element(find.text('今天，也一起。')),
    );
    await container.read(appControllerProvider.notifier).refresh();
    navigation.push('/memo/$id?sealed=1');
    await tester.pumpAndSettle();
    expect(find.text('今天的坚持，已盖章'), findsOneWidget);
    await shot('memo-stamped');
    await tester.tap(find.byTooltip('编辑纪要'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我完成了今天的阅读');
    await tester.ensureVisible(find.text('保存我的版本'));
    await tester.tap(find.text('保存我的版本'));
    await tester.pumpAndSettle();
    expect(find.text('我完成了今天的阅读'), findsOneWidget);
    navigation.go('/today');
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await shot('today-dark');
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pumpAndSettle();
    await shot('today-large-dark');
    navigation.push('/settings');
    await tester.pumpAndSettle();
    await shot('settings-large-dark');
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
  });
}
