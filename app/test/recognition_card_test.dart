import 'package:better_together/app.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/checkin_draft.dart';
import 'package:better_together/features/checkin/recognition_card.dart';
import 'package:better_together/platform/photo_preparation.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

final _png = img.encodePng(img.Image(width: 2, height: 2));
const _plan = Plan(id: 'exercise', title: '每天户外运动', category: 'exercise');
const _summary = '沿江慢跑，完成了今天的户外运动。';
const _fields = [
  MemoField(
    key: 'duration_minutes',
    label: '运动时长',
    value: '24 分钟',
    source: 'timer',
  ),
  MemoField(key: 'calories', label: '运动消耗', source: 'manual'),
];

DraftPhoto _photo(
  DraftPhotoPhase phase, {
  double confidence = .92,
  String summary = _summary,
}) {
  final photo = DraftPhoto(
    id: 'photo',
    original: PreparedPhoto(_png, 'original.png', 'image/png'),
    source: 'screenshot',
  )..phase = phase;
  if (phase != DraftPhotoPhase.preparing) {
    photo.analysis = AnalysisPhoto(
      bytes: _png,
      originalSha256: 'a' * 64,
      width: 2,
      height: 2,
    );
  }
  photo.recognition = switch (phase) {
    DraftPhotoPhase.ready => PhotoRecognition(
      photoId: photo.id,
      status: 'ready',
      planId: _plan.id,
      confidence: confidence,
      summary: summary,
      fields: _fields,
      screenshotDate: '2026-11-18',
    ),
    DraftPhotoPhase.pending => PhotoRecognition(
      photoId: photo.id,
      status: 'pending',
      error: '识别连接暂时中断，请重试或稍后确认。',
    ),
    DraftPhotoPhase.rejected => PhotoRecognition(
      photoId: photo.id,
      status: 'rejected',
      summary: '被拒绝的识别结果不能显示为成功纪要。',
      fields: _fields,
      error: '截图记录日期不是小队所在时区的今天，请换一张。',
    ),
    _ => null,
  };
  photo.error = photo.recognition?.error;
  return photo;
}

Widget _harness({
  required DraftPhoto photo,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  List<Plan> plans = const [_plan],
  VoidCallback? onRemove,
  VoidCallback? onRetry,
}) => MaterialApp(
  localizationsDelegates: appDelegates,
  supportedLocales: appLocales,
  locale: appLocales.first,
  theme: buildTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: RecognitionCard(
        photo: photo,
        plans: plans,
        onRemove: onRemove,
        onRetry: onRetry,
      ),
    ),
  ),
);

void _viewport(WidgetTester tester, double width, {double height = 812}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('ready displays the returned summary and field provenance', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(photo: _photo(DraftPhotoPhase.ready)));
    await tester.pumpAndSettle();

    expect(find.text('识别完成，等待确认'), findsOneWidget);
    expect(find.text(_summary), findsOneWidget);
    expect(find.text('计划建议：每天户外运动'), findsOneWidget);
    expect(find.text('归类置信度：92%'), findsOneWidget);
    expect(find.text('截图记录日期：2026-11-18'), findsOneWidget);
    expect(find.text('运动时长：24 分钟 · 计时'), findsOneWidget);
    expect(find.text('运动消耗：未记录 · 手填'), findsOneWidget);
    expect(find.text('重新检查这张'), findsNothing);
    expect(find.text('照片预览暂不可用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('low confidence asks for review without replacing the result', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(photo: _photo(DraftPhotoPhase.ready, confidence: .61)),
    );
    await tester.pumpAndSettle();

    expect(find.text('归类置信度：61%'), findsOneWidget);
    expect(find.text('这次归类把握较低，请核对下方的本次记录标签。'), findsOneWidget);
    expect(find.text(_summary), findsOneWidget);
    expect(find.text('计划建议：每天户外运动'), findsOneWidget);
  });

  testWidgets('pending states the outage and never invents exercise results', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(photo: _photo(DraftPhotoPhase.pending)));
    await tester.pumpAndSettle();

    expect(find.text('AI 暂不可用，可按 ALL 盖章'), findsOneWidget);
    expect(find.text('识别连接暂时中断，请重试或稍后确认。'), findsOneWidget);
    expect(find.text('原图尚未上传。确认后保留盖章，当天后台继续整理，不会编造纪要或运动数据。'), findsOneWidget);
    expect(find.text('识别完成，等待确认'), findsNothing);
    expect(find.text(_summary), findsNothing);
    expect(find.textContaining('归类置信度：'), findsNothing);
    expect(find.textContaining('计划建议：'), findsNothing);
    expect(find.textContaining('运动时长：'), findsNothing);
    expect(find.textContaining('运动消耗：'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.text('重新检查这张'), findsOneWidget);
  });

  testWidgets('rejected does not display a success summary or ALL permission', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(photo: _photo(DraftPhotoPhase.rejected)));
    await tester.pumpAndSettle();

    expect(find.text('这张照片暂不可提交'), findsOneWidget);
    expect(find.text('截图记录日期不是小队所在时区的今天，请换一张。'), findsOneWidget);
    expect(find.text('识别完成，等待确认'), findsNothing);
    expect(find.text('AI 暂不可用，可按 ALL 盖章'), findsNothing);
    expect(find.text('被拒绝的识别结果不能显示为成功纪要。'), findsNothing);
    expect(find.textContaining('运动时长：'), findsNothing);
    expect(find.textContaining('确认后保留盖章'), findsNothing);
    expect(find.text('重新检查这张'), findsOneWidget);
  });

  testWidgets('remove and retry are reachable after scrolling on a phone', (
    tester,
  ) async {
    _viewport(tester, 375, height: 500);
    var removed = 0;
    var retried = 0;
    await tester.pumpWidget(
      _harness(
        photo: _photo(DraftPhotoPhase.pending),
        textScale: 1.4,
        onRemove: () => removed++,
        onRetry: () => retried++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('重新检查这张'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新检查这张'));
    expect(retried, 1);
    await tester.ensureVisible(find.byTooltip('移除这张照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除这张照片'));
    expect(removed, 1);
    expect(tester.takeException(), isNull);
  });

  for (final width in [375.0, 768.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'all phases fit ${width.toInt()}px at 1.4x in ${brightness.name}',
        (tester) async {
          _viewport(tester, width);
          for (final phase in DraftPhotoPhase.values) {
            final photo = _photo(
              phase,
              confidence: .61,
              summary:
                  '今天沿着河边完成户外运动，照片里的路线和时间需要由本人核对。'
                  '确认前可以调整本次记录标签，缺少来源的运动数据保持未记录。',
            );
            await tester.pumpWidget(
              _harness(
                photo: photo,
                brightness: brightness,
                textScale: 1.4,
                plans: const [
                  Plan(
                    id: 'exercise',
                    title: '每天下班后与队友一起完成一段户外运动',
                    category: 'exercise',
                  ),
                ],
                onRemove: () {},
                onRetry: () {},
              ),
            );
            // Preparing and recognizing intentionally keep animating.
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull, reason: phase.name);

            final card = tester.getRect(find.byType(RecognitionCard));
            expect(card.left, greaterThanOrEqualTo(20));
            expect(card.right, lessThanOrEqualTo(width - 20));
            for (final text
                in find
                    .descendant(
                      of: find.byType(RecognitionCard),
                      matching: find.byType(Text),
                    )
                    .evaluate()) {
              final rect = tester.getRect(find.byWidget(text.widget));
              expect(
                rect.left,
                greaterThanOrEqualTo(card.left),
                reason: '${phase.name}: ${text.widget}',
              );
              expect(
                rect.right,
                lessThanOrEqualTo(card.right),
                reason: '${phase.name}: ${text.widget}',
              );
            }
          }
        },
      );
    }
  }
}
