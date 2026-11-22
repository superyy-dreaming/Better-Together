import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/checkin_draft_provider.dart';
import 'package:better_together/features/checkin/checkin_draft.dart';
import 'package:better_together/features/checkin/checkin_page.dart';
import 'package:better_together/platform/photo_preparation.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

class BatchFlowRepository extends DemoRepository {
  BatchFlowRepository(Directory directory)
    : super(directoryProvider: () async => directory);
  int recognitionCalls = 0, uploadCalls = 0, submits = 0;
  bool saved = false;
  @override
  Future<PhotoRecognition> recognize(PhotoRecognitionRequest photo) async {
    final exercise = recognitionCalls++ == 1;
    return PhotoRecognition(
      photoId: photo.photoId,
      status: 'ready',
      planId: exercise ? 'exercise' : 'study',
      confidence: .95,
      summary: exercise ? '截图中显示完成了一次步行。' : '照片中有翻开的书页。',
    );
  }

  @override
  Future<UploadedPhoto> upload(PhotoUpload photo) async {
    uploadCalls++;
    return super.upload(photo);
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'submit_checkin_batch') submits++;
    final result = await super.action(action, args: args);
    if (action == 'submit_checkin_batch') saved = true;
    return result;
  }
}

Future<void> runBatchFlow(
  WidgetTester tester, {
  AppAppearance appearance = AppAppearance.classic,
  bool native = false,
  Future<void> Function(String name)? screenshot,
}) async {
  final dir = Directory.systemTemp.createTempSync('better-batch-test-');
  final repository = BatchFlowRepository(dir);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      if (!native)
        checkinDraftProvider((planId: null, redoOf: null, targetDate: null))
            .overrideWith((ref) {
              final value = CheckinDraft(
                repository: repository,
                prepare: (bytes) async => AnalysisPhoto(
                  bytes: bytes,
                  originalSha256: 'test',
                  width: 160,
                  height: 120,
                ),
              );
              ref.onDispose(value.dispose);
              return value;
            }),
      initialAppearanceProvider.overrideWithValue(
        AppearanceLoadResult(appearance: appearance),
      ),
    ],
  );
  try {
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
    router.push('/checkin');
    await tester.pumpAndSettle();
    final draft = container.read(
      checkinDraftProvider((planId: null, redoOf: null, targetDate: null)),
    );
    for (var i = 0; i < 3; i++) {
      final pixels = img.Image(width: 160, height: 120);
      img.fill(pixels, color: img.ColorRgb8(80 + i * 40, 130, 90));
      img.drawString(
        pixels,
        'TEST ${i + 1}',
        font: img.arial24,
        x: 24,
        y: 44,
        color: img.ColorRgb8(255, 255, 255),
      );
      await draft.add(
        PreparedPhoto(img.encodePng(pixels), 'synthetic-$i.png', 'image/png'),
        'camera',
        capturedAt: DateTime.now(),
      );
    }
    await tester.pumpAndSettle();
    expect(repository.recognitionCalls, 0);
    expect(repository.uploadCalls, 0);
    await screenshot?.call('${appearance.name}-preview');
    // Navigation restores the same in-memory draft, without starting AI.
    router.pop();
    await tester.pumpAndSettle();
    router.push('/checkin');
    await tester.pumpAndSettle();
    expect(find.byType(CheckinPage), findsOneWidget);
    expect(
      identical(
        draft,
        container.read(
          checkinDraftProvider((planId: null, redoOf: null, targetDate: null)),
        ),
      ),
      isTrue,
    );
    final next = find.byKey(const ValueKey('next-checkin'));
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(repository.recognitionCalls, 3);
    expect(repository.uploadCalls, 0);
    expect(draft.groups, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('group-plan-study')));
    await tester.pumpAndSettle();
    await screenshot?.call('${appearance.name}-grouped');
    final memo = find.byKey(const ValueKey('group-memo-study'));
    await tester.ensureVisible(memo);
    await tester.pumpAndSettle();
    await tester.enterText(memo, '我确认的阅读记录');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    // Move one image using the actual visible plan selector.
    final photoSelector = find.byKey(
      ValueKey('photo-plan-${draft.photos.first.id}-study'),
    );
    await tester.ensureVisible(photoSelector);
    await tester.pumpAndSettle();
    await tester.tap(photoSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('出门走一走').last);
    await tester.pumpAndSettle();
    expect(
      draft.groups.singleWhere((g) => g.planId == 'exercise').photos,
      hasLength(2),
    );
    final whole = find.byKey(const ValueKey('group-plan-study'));
    await tester.ensureVisible(whole);
    await tester.pumpAndSettle();
    await tester.tap(whole);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALL，暂不归类').last);
    await tester.pumpAndSettle();
    expect(
      draft.groups.singleWhere((g) => g.planId == null).photos,
      hasLength(1),
    );
    expect(
      draft.summaryFor(draft.groups.singleWhere((g) => g.planId == null)),
      '我确认的阅读记录',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('group-plan-all')));
    await tester.pumpAndSettle();
    await screenshot?.call('${appearance.name}-edited');
    final confirm = find.byKey(const ValueKey('confirm-checkin'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(confirm);
      for (var i = 0; i < 500 && !repository.saved; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(repository.uploadCalls, 3);
    expect(repository.submits, 1);
    final records = (await repository.bootstrap()).checkins
        .where((c) => c.batchId == draft.batchId)
        .toList();
    expect(records, hasLength(2));
    expect(
      records.map((c) => c.photos.length).fold<int>(0, (a, b) => a + b),
      3,
    );
    expect(records.singleWhere((c) => c.planId == null).summary, '我确认的阅读记录');
    expect(
      records.every(
        (c) => c.photos.every((p) => p.recognition?.summary.isNotEmpty == true),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await screenshot?.call('${appearance.name}-stamped');
  } finally {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await repository.dispose();
    dir.deleteSync(recursive: true);
  }
}
