import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/memo_page.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const capturePreviews = bool.fromEnvironment('CAPTURE_MEMO_PREVIEWS');

class MemoRepository extends DemoRepository {
  MemoRepository({bool pending = false}) {
    Checkin card(
      String id,
      String plan, {
      String batch = 'batch',
      String user = 'me',
      String summary = '',
    }) => Checkin(
      id: id,
      userId: user,
      planId: plan,
      batchId: batch,
      localDate: '2026-11-18',
      createdAt: DateTime.utc(2026, 11, 18),
      memoStatus: 'ready',
      classificationPending: id == 'original' && pending,
      unassignedSummary: summary,
      summary: '照片纪要',
    );
    current = AppSnapshot(
      profile: const UserProfile(id: 'me', nickname: '知夏'),
      plans: const [
        Plan(
          id: 'private',
          title: '私人阅读',
          category: 'study',
          visibility: 'private',
        ),
        Plan(
          id: 'public',
          title: '一起散步',
          category: 'exercise',
          visibility: 'team',
        ),
      ],
      checkins: [
        card('original', 'private', summary: '只给自己写下的一段摘要'),
        card('public-target', 'public'),
        card('other-batch', 'public', batch: 'another'),
        card('other-user', 'public', user: 'teammate'),
      ],
    );
  }
  late AppSnapshot current;
  int assignments = 0, reads = 0;
  JsonMap? lastArgs;
  bool fail = false;
  Completer<void>? gate;
  @override
  String? get currentUserId => 'me';
  @override
  Future<AppSnapshot> bootstrap() async {
    reads++;
    return current;
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'get_checkin') {
      reads++;
      return current.checkins.firstWhere((c) => c.id == args['id']).toJson();
    }
    if (action != 'assign_batch_fields') {
      throw StateError('Unexpected action $action');
    }
    assignments++;
    lastArgs = args;
    if (gate != null) {
      await gate!.future;
    }
    if (fail) {
      throw const AppException('network', '连接暂时中断，请重试');
    }
    final json = current.toJson();
    json['checkins'] = current.checkins
        .map(
          (c) => {
            ...c.toJson(),
            if (c.id == args['checkin_id']) ...{
              'unassigned_summary': '',
              'unassigned_fields': <Object?>[],
            },
          },
        )
        .toList();
    current = AppSnapshot.fromJson(json);
    return {'updated': true};
  }
}

Future<void> mount(
  WidgetTester tester,
  MemoRepository repository, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(375, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repository)],
      child: RepaintBoundary(
        key: const ValueKey('memo-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: capturePreviews
              ? buildTheme(brightness).copyWith(
                  textTheme: buildTheme(brightness).textTheme
                      .apply(fontFamily: 'MemoPreview'),
                )
              : buildTheme(brightness),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 850),
              textScaler: TextScaler.linear(textScale),
            ),
            child: const MemoPage(id: 'original'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> selectPublic(WidgetTester tester) async {
  final target = find.byKey(const ValueKey('draft-target-public-target'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  await tester.ensureVisible(
    find.byKey(const ValueKey('confirm-draft-assignment')),
  );
  await tester.pump();
}

Future<void> close(WidgetTester tester, MemoRepository repository) async {
  await tester.pumpWidget(const SizedBox());
  await repository.dispose();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!capturePreviews) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('memo-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = await Directory('../output/qa').create(recursive: true);
    await File('${directory.path}/memo-draft-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  if (capturePreviews) {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() async {
      const fontPath = String.fromEnvironment('MEMO_PREVIEW_FONT');
      if (fontPath.isEmpty) {
        throw StateError('MEMO_PREVIEW_FONT must name a local Chinese font');
      }
      await (FontLoader('MemoPreview')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'draft remains readable in $brightness at 375px with large text',
      (tester) async {
        final repository = MemoRepository();
        await mount(tester, repository, brightness: brightness, textScale: 1.4);
        await capture(tester, '${brightness.name}-top');
        await selectPublic(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('确认发布到小队记录'), findsOneWidget);
        await capture(tester, '${brightness.name}-confirm');
        await close(tester, repository);
      },
    );
  }
  testWidgets(
    'summary-only draft is visible and only own same-batch cards are selectable',
    (tester) async {
      final repository = MemoRepository();
      await mount(tester, repository);
      expect(find.text('只给自己写下的一段摘要'), findsOneWidget);
      expect(find.text('仅你可见的待归属内容'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('draft-target-original')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('draft-target-public-target')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('draft-target-other-batch')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('draft-target-other-user')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('confirm-draft-assignment')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await close(tester, repository);
    },
  );

  testWidgets(
    'public target discloses visibility and one confirmation sends only once',
    (tester) async {
      final repository = MemoRepository()..gate = Completer<void>();
      await mount(tester, repository);
      await selectPublic(tester);
      expect(find.textContaining('小队成员可以看到'), findsOneWidget);
      expect(find.text('确认发布到小队记录'), findsOneWidget);
      expect(repository.assignments, 0);
      final confirm = find.byKey(const ValueKey('confirm-draft-assignment'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(repository.assignments, 1);
      expect(repository.lastArgs, {
        'checkin_id': 'original',
        'target_checkin_id': 'public-target',
      });
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('仅你可见的待归属内容'), findsNothing);
      await close(tester, repository);
    },
  );

  testWidgets('failed assignment retains draft and exposes retry action', (
    tester,
  ) async {
    final repository = MemoRepository()..fail = true;
    await mount(tester, repository);
    await selectPublic(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-draft-assignment')));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未归入，草稿仍保留'), findsOneWidget);
    expect(find.text('只给自己写下的一段摘要'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-draft-assignment')),
          )
          .onPressed,
      isNotNull,
    );
    expect(repository.assignments, 1);
    await close(tester, repository);
  });

  testWidgets(
    'classification keeps polling even when an edited memo is ready',
    (tester) async {
      final repository = MemoRepository(pending: true);
      await mount(tester, repository);
      expect(find.textContaining('记录保留在 ALL'), findsOneWidget);
      final initialReads = repository.reads;
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(repository.reads, initialReads + 1);
      expect(find.textContaining('记录保留在 ALL'), findsOneWidget);
      await close(tester, repository);
    },
  );
}
