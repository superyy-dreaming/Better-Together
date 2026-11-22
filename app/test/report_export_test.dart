import 'dart:async';
import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/reports/report_export.dart';
import 'package:better_together/features/reports/report_receipt.dart';
import 'package:better_together/features/reports/reports_page.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

const ownReport = WeeklyReport(
  id: 'personal-report',
  userId: 'me',
  weekStart: '2026-11-09',
  title: '我自己的这一周',
  summary: '合成测试数据。',
);

class ReportsRepository extends DemoRepository {
  final actions = <String>[];
  @override
  Future<AppSnapshot> bootstrap() async => const AppSnapshot(
    profile: UserProfile(id: 'me', nickname: '本人'),
    reports: [
      ownReport,
      WeeklyReport(
        id: 'peer-report',
        userId: 'peer',
        weekStart: '2026-11-09',
        title: '队友个人隐私数据',
      ),
      WeeklyReport(
        id: 'unknown-report',
        weekStart: '2026-11-09',
        title: '未知归属数据',
      ),
      WeeklyReport(
        id: 'team-report',
        kind: 'team',
        weekStart: '2026-11-09',
        title: '小队合计数据',
      ),
    ],
  );
  @override
  String? get currentUserId => 'me';
  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'read_page') {
      return {
        'items': (await bootstrap()).reports.map((v) => v.toJson()).toList(),
        'next_cursor': null,
      };
    }
    actions.add(action);
    return null;
  }
}

void main() {
  for (final appearance in AppAppearance.values) {
    testWidgets(
      'exports entire ${appearance.name} receipt with its theme and own-only data',
      (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var theme = buildTheme(Brightness.light, appearance: appearance);
        await tester.runAsync(() async {
          final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
            ..addFont(
              rootBundle.load(
                'packages/cupertino_icons/assets/CupertinoIcons.ttf',
              ),
            );
          await icons.load();
        });
        // Local QA can use a real CJK font. CI assertions also work with Ahem.
        final font = File('/System/Library/Fonts/STHeiti Light.ttc');
        if (font.existsSync()) {
          await tester.runAsync(() async {
            final loader = FontLoader('ReportQaFont')
              ..addFont(font.readAsBytes().then(ByteData.sublistView));
            await loader.load();
          });
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'ReportQaFont'),
          );
        }
        late BuildContext exportContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                exportContext = context;
                // No receipt is mounted in the visible tree.
                return const Scaffold(body: Text('导出检查'));
              },
            ),
          ),
        );
        final report = WeeklyReport(
          id: 'synthetic-long-report',
          userId: 'me',
          weekStart: '2026-11-09',
          title: '一小步，也算数',
          summary: '合成数据，仅用于长图导出验证。记录每次阅读、散步和认真吃饭的时刻，检查超过屏幕的内容是否完整保留。',
          metrics: const {
            'completed': 17,
            'expected': 21,
            'makeup': 1,
            'completion_rate': 17 / 21,
            'plans': [
              {'title': '每天读二十页', 'completed': 7, 'expected': 7},
              {'title': '沿河散步半小时', 'completed': 6, 'expected': 7},
              {'title': '记录每天的晚饭', 'completed': 4, 'expected': 7},
            ],
          },
          highlights: List.generate(
            18,
            (i) =>
                '第 ${i + 1} 次记录：今天抽出一点时间读书、出门散步。把这段真实而平常的生活留在收据上，下一次回看时还能想起当时的心情。',
          ),
          suggestion: const {'text': '最后一段完整性检查：下周继续按自己的节奏，给休息也留一点时间。'},
        );
        final output = await tester.runAsync(
          () => renderPersonalReport(
            context: exportContext,
            report: report,
            currentUserId: 'me',
          ),
        );
        expect(output, isNotNull);
        final decoded = img.decodePng(output!.png)!;
        expect(decoded.width, 780);
        expect(decoded.width, output.width);
        expect(decoded.height, output.height);
        expect(decoded.height, greaterThan(667 * 4));

        bool matchesColor(img.Pixel pixel, Color color) {
          final argb = color.toARGB32();
          return (pixel.r - ((argb >> 16) & 255)).abs() <= 2 &&
              (pixel.g - ((argb >> 8) & 255)).abs() <= 2 &&
              (pixel.b - (argb & 255)).abs() <= 2 &&
              pixel.a > 240;
        }

        // The isolated render tree must preserve the selected surface and theme
        // extension. In cartoon mode the header star is painted in primary; losing
        // the extension would render the classic document icon instead.
        expect(
          matchesColor(decoded.getPixel(0, 0), theme.scaffoldBackgroundColor),
          isTrue,
        );
        if (appearance == AppAppearance.tuantuan) {
          var primaryPixels = 0;
          for (var y = 0; y < 200; y++) {
            for (var x = 0; x < decoded.width; x++) {
              if (matchesColor(
                decoded.getPixel(x, y),
                theme.colorScheme.primary,
              )) {
                primaryPixels++;
              }
            }
          }
          expect(primaryPixels, greaterThan(100));
        }

        // The final stamp uses the selected theme's secondary color. Both edges
        // near the PNG bottom prove that content below the viewport is not cropped.
        final stampRows = <int>[];
        for (var y = decoded.height - 200; y < decoded.height; y++) {
          var stampPixels = 0;
          for (var x = 0; x < decoded.width; x++) {
            if (matchesColor(
              decoded.getPixel(x, y),
              theme.colorScheme.secondary,
            )) {
              stampPixels++;
            }
          }
          if (stampPixels > 100) stampRows.add(y);
        }
        expect(stampRows, isNotEmpty);
        expect(stampRows.last - stampRows.first, greaterThan(50));
        expect(decoded.height - stampRows.last, inInclusiveRange(55, 65));
        expect(tester.takeException(), isNull);

        await tester.runAsync(() async {
          final file = File(
            appearance == AppAppearance.classic
                ? '../output/qa/report-export.png'
                : '../output/qa/report-export-${appearance.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(output.png, flush: true);
        });

        for (final invalid in [
          const WeeklyReport(
            id: 'team',
            kind: 'team',
            userId: 'me',
            weekStart: '',
          ),
          const WeeklyReport(id: 'peer', userId: 'peer', weekStart: ''),
          const WeeklyReport(id: 'unknown', weekStart: ''),
        ]) {
          await expectLater(
            renderPersonalReport(
              context: exportContext,
              report: invalid,
              currentUserId: 'me',
            ),
            throwsA(isA<ReportExportException>()),
          );
        }
        await expectLater(
          renderPersonalReport(
            context: exportContext,
            report: ownReport,
            currentUserId: '',
          ),
          throwsA(isA<ReportExportException>()),
        );

        // Mount only after the first export to keep the regression for exporting a
        // never-mounted receipt. The displayed rate must come from 17 / 21, appear
        // once, and retain cartoon emphasis rather than a prototype fixture value.
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SingleChildScrollView(child: ReportReceipt(report: report)),
            ),
          ),
        );
        expect(find.text('81%'), findsOneWidget);
        expect(find.text('本周完成率'), findsOneWidget);
        expect(find.text('最后一段完整性检查：下周继续按自己的节奏，给休息也留一点时间。'), findsOneWidget);
        if (appearance == AppAppearance.tuantuan) {
          final rate = tester.widget<Text>(find.text('81%'));
          expect(rate.style?.color, theme.colorScheme.primary);
          expect(
            rate.style?.fontSize,
            greaterThan(theme.textTheme.titleMedium!.fontSize!),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'share is single-flight, recovers after failure and is own-only',
    (tester) async {
      final repository = ReportsRepository();
      var attempts = 0;
      var pending = Completer<ShareResult>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            localizationsDelegates: appDelegates,
            supportedLocales: appLocales,
            locale: appLocales.first,
            home: ReportsPage(
              imageSharer:
                  ({
                    required context,
                    required report,
                    required currentUserId,
                    required shareOrigin,
                  }) {
                    attempts++;
                    expect(report.id, 'personal-report');
                    expect(currentUserId, 'me');
                    expect(shareOrigin.width, greaterThan(44));
                    expect(shareOrigin.height, greaterThanOrEqualTo(44));
                    return pending.future;
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我自己的这一周'), findsOneWidget);
      expect(find.text('队友个人隐私数据'), findsNothing);
      expect(find.text('未知归属数据'), findsNothing);
      await tester.ensureVisible(find.text('保存图片分享'));
      final shareButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '保存图片分享'),
      );
      shareButton.onPressed!();
      shareButton.onPressed!();
      await tester.pump();
      expect(attempts, 1);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '正在生成'))
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('native share unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('长图暂未分享，请重新点击“保存图片分享”。'), findsOneWidget);
      expect(repository.actions, isEmpty);

      pending = Completer<ShareResult>();
      await tester.tap(find.text('保存图片分享'));
      pending.complete(const ShareResult('', ShareResultStatus.dismissed));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(repository.actions, isEmpty);
      pending = Completer<ShareResult>();
      await tester.tap(find.text('保存图片分享'));
      pending.complete(const ShareResult('', ShareResultStatus.success));
      await tester.pumpAndSettle();
      expect(repository.actions, ['share_report']);

      await tester.drag(find.byType(ListView), const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小队周报'));
      await tester.pumpAndSettle();
      expect(find.text('小队合计数据'), findsOneWidget);
      expect(find.text('保存图片分享'), findsNothing);
      expect(find.text('我自己的这一周'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.dispose();
    },
  );
}
