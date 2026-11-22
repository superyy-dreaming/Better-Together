import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/ui/photo_viewer.dart';
import 'package:better_together/ui/bear_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native flexible plans, bear picker, photo source sheet and gallery gestures',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString('better_together_demo_v1');
      final dir = await Directory.systemTemp.createTemp('bt-native-gallery');
      final repo = DemoRepository();
      bool converted = false;
      Future<void> shot(String name) async {
        if (Platform.isAndroid && !converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(
          '${Platform.operatingSystem}-flexible-$name',
        );
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo)],
            child: const BetterTogetherApp(),
          ),
        );
        await tester.pumpAndSettle();
        final router =
            tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
                as GoRouter;
        router.push('/settings');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('更换头像'));
        await tester.tap(find.text('更换头像'));
        await tester.pumpAndSettle();
        expect(find.byType(BearAvatar), findsAtLeastNWidgets(12));
        await shot('bear-picker');
        await tester.ensureVisible(find.widgetWithText(TextButton, '取消').last);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        router.go('/today');
        await tester.pumpAndSettle();
        router.push('/checkin');
        await tester.pumpAndSettle();
        expect(find.text('运动计时'), findsNothing);
        expect(find.text('当天相册'), findsNothing);
        await tester.tap(find.text('现在选一张'));
        await tester.pumpAndSettle();
        expect(find.text('拍照'), findsOneWidget);
        expect(find.text('从相册选择'), findsOneWidget);
        await shot('source-sheet');
        await tester.ensureVisible(find.widgetWithText(TextButton, '取消').last);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        router.go('/plans');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('新建计划'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('固定星期'));
        await tester.tap(find.text('固定星期').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('每几天完成几天').last);
        await tester.pumpAndSettle();
        expect(find.text('周期长度'), findsOneWidget);
        expect(find.text('周期内完成天数'), findsOneWidget);
        await shot('period-target-plan');
        await tester.enterText(
          find.byKey(const ValueKey('period-days-field')),
          '5',
        );
        await tester.enterText(
          find.byKey(const ValueKey('period-target-days-field')),
          '3',
        );
        await tester.enterText(find.byType(TextFormField).first, '五天三次练习');
        await tester.ensureVisible(find.text('保存计划'));
        await tester.tap(find.text('保存计划'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 6 && find.text('五天三次练习').evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        expect(find.text('五天三次练习'), findsOneWidget);
        expect(find.textContaining('每 5 天完成 3 天'), findsOneWidget);

        await tester.drag(find.byType(ListView).first, const Offset(0, 600));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('每天读 20 页'));
        await tester.tap(find.text('每天读 20 页'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('固定星期'));
        await tester.tap(find.text('固定星期').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('每几天完成几天').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('period-days-field')),
          '8',
        );
        await tester.enterText(
          find.byKey(const ValueKey('period-target-days-field')),
          '4',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('保存计划'));
        await tester.tap(find.text('保存计划'));
        await tester.pumpAndSettle();
        expect(find.textContaining('每 8 天完成 4 天'), findsOneWidget);
        expect(find.textContaining('已保存，'), findsAtLeastNWidgets(1));
        await shot('period-target-saved');

        router.go('/plan/new');
        await tester.pumpAndSettle();
        await tester.tap(find.text('固定星期').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('每隔几天').last);
        await tester.pumpAndSettle();
        await shot('interval-plan');
        router.go('/today');
        await tester.pumpAndSettle();
        final photos = <CheckinPhoto>[];
        for (var i = 0; i < 2; i++) {
          final file = File('${dir.path}/$i.png');
          final image = img.Image(width: 600, height: 800);
          img.fill(image, color: img.ColorRgb8(i == 0 ? 60 : 220, 140, 110));
          await file.writeAsBytes(img.encodePng(image));
          photos.add(
            CheckinPhoto(
              id: '$i',
              url: file.path,
              source: 'camera',
              capturedAt: DateTime.now(),
            ),
          );
        }
        showPhotoViewer(tester.element(find.byType(Scaffold).last), photos, 0);
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        await shot('gallery');
        final photo = find.byType(InteractiveViewer).first;
        await tester.tap(photo);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(photo);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<InteractiveViewer>(photo)
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1),
        );
        expect(
          tester.widget<PageView>(find.byType(PageView)).physics,
          isA<NeverScrollableScrollPhysics>(),
        );
        await shot('gallery-zoom');
        await tester.tap(photo);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(photo);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.dispose();
        await dir.delete(recursive: true);
        if (previous == null) {
          await prefs.remove('better_together_demo_v1');
        } else {
          await prefs.setString('better_together_demo_v1', previous);
        }
      }
    },
  );
}
