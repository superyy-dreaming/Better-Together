import 'dart:async';

import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/ai_settings.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/settings/ai_settings_page.dart';
import 'package:better_together/ui/design.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiRepository extends DemoRepository {
  JsonMap metadata = {
    'enabled': true,
    'base_url': 'https://api.example.com/v1',
    'protocol': 'chat_completions',
    'model': 'vision-model',
    'has_key': true,
  };
  final commands = <({String action, JsonMap args})>[];
  final sessions = StreamController<bool>.broadcast();
  Completer<void>? gate;
  bool fail = false, failRead = false, demo = false;
  String? user = 'owner';

  @override
  bool get isDemo => demo;
  @override
  bool get isSignedIn => user != null;
  @override
  String? get currentUserId => user;
  @override
  Stream<bool> get authChanges => sessions.stream;

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'get_ai_settings') {
      if (failRead) throw const AppException('network', '配置暂时无法读取');
      return {...metadata};
    }
    commands.add((action: action, args: args));
    if (gate != null) await gate!.future;
    if (fail) throw const AppException('network', '连接暂时中断，请重试');
    if (action == 'save_ai_settings') {
      metadata = {
        'enabled': args['enabled'],
        'base_url': normalizedAiBaseUrl(stringValue(args['base_url'])),
        'protocol': args['protocol'],
        'model': args['model'],
        'has_key': true,
      };
      return {...metadata};
    }
    if (action == 'test_ai_settings') return {'ok': true};
    if (action == 'delete_ai_settings') return {'deleted': true, ...const AiSettings().withoutKey, 'has_key':false};
    throw StateError('Unexpected action $action');
  }

  @override
  Future<void> dispose() async {
    await sessions.close();
    await super.dispose();
  }
}

Future<void> mountAi(
  WidgetTester tester,
  AiRepository repository, {
  Brightness brightness = Brightness.light,
  double scale = 1,
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
      child: MaterialApp(
        theme: buildTheme(brightness),
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
            textScaler: TextScaler.linear(scale),
          ),
          child: const AiSettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder input(String key) => find.byKey(ValueKey(key));

Future<void> pressAi(WidgetTester tester, String key) async {
  await tester.ensureVisible(input(key));
  // ensureVisible changes the scroll position; layout/hit-testing catches up
  // on the next frame. Tap only after the reveal and focus scroll settle.
  await tester.pumpAndSettle();
  await tester.tap(input(key));
  await tester.pump();
}

Future<void> closeAi(WidgetTester tester, AiRepository repository) async {
  await tester.pumpWidget(const SizedBox());
  await repository.dispose();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  test('metadata never contains secrets and normalizes endpoint suffixes', () {
    final value = AiSettings.fromJson({
      'enabled': false,
      'base_url': 'https://example.com/v1',
      'protocol': 'chat_completions',
      'model': 'model',
      'has_key': true,
      'api_key': 'not-a-real-secret',
    });
    expect(value.withoutKey.containsKey('api_key'), isFalse);
    expect(
      normalizedAiBaseUrl('https://example.com/v1/responses/'),
      'https://example.com/v1',
    );
    expect(
      normalizedAiBaseUrl('https://example.com/v1/chat/completions'),
      'https://example.com/v1',
    );
    expect(validateAiBaseUrl('http://example.com'), isNotNull);
    expect(validateAiBaseUrl('https://key@example.com/v1'), isNotNull);
    expect(validateAiBaseUrl('https://example.com/v1?key=secret'), isNotNull);
    expect(validateAiBaseUrl('https://example.com/v1'), isNull);
    expect(() => AiSettings.fromJson({}), throwsFormatException);
  });

  testWidgets('shows fields and preserves saved key without revealing it', (
    tester,
  ) async {
    final repository = AiRepository();
    await mountAi(tester, repository);
    expect(find.text('本机 AI 已启用'), findsOneWidget);
    expect(find.text('服务地址'), findsOneWidget);
    expect(find.text('Chat Completions，支持图片与结构化 JSON。'), findsOneWidget);
    expect(find.text('模型名称'), findsOneWidget);
    final field = tester.widget<TextFormField>(input('ai-api-key'));
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining('你的照片、纪要内容会发送'), findsOneWidget);
    await pressAi(tester, 'ai-save');
    await tester.pumpAndSettle();
    expect(repository.commands.single.action, 'save_ai_settings');
    expect(repository.commands.single.args.containsKey('api_key'), isFalse);
    expect(find.textContaining('已保存，后续识别'), findsOneWidget);
    await closeAi(tester, repository);
  });

  testWidgets(
    'a new endpoint requires a fresh key and clears it after saving',
    (tester) async {
      final repository = AiRepository();
      await mountAi(tester, repository);
      await tester.enterText(
        input('ai-base-url'),
        'https://new.example.com/v1',
      );
      await tester.pump();
      expect(find.textContaining('已有密钥不会发送到新地址'), findsOneWidget);
      await pressAi(tester, 'ai-save');
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
      expect(find.text('地址已改变，请填写新密钥'), findsOneWidget);
      await tester.enterText(input('ai-api-key'), 'test-only-secret');
      await pressAi(tester, 'ai-save');
      await tester.pumpAndSettle();
      expect(repository.commands.single.args['api_key'], 'test-only-secret');
      expect(
        tester.widget<TextFormField>(input('ai-api-key')).controller!.text,
        isEmpty,
      );
      await closeAi(tester, repository);
    },
  );

  testWidgets('connection test uses draft once and does not save settings', (
    tester,
  ) async {
    final repository = AiRepository()..gate = Completer<void>();
    await mountAi(tester, repository);
    await tester.enterText(input('ai-model'), 'unsaved-model');
    await pressAi(tester, 'ai-test');
    await pressAi(tester, 'ai-test');
    expect(repository.commands.length, 1);
    expect(repository.commands.single.action, 'test_ai_settings');
    expect(repository.commands.single.args['model'], 'unsaved-model');
    expect(tester.widget<FilledButton>(input('ai-save')).onPressed, isNull);
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('测试未保存配置'), findsOneWidget);
    expect(repository.metadata['model'], 'vision-model');
    await closeAi(tester, repository);
  });

  testWidgets('failure keeps form input and enables retry', (tester) async {
    final repository = AiRepository()..fail = true;
    await mountAi(tester, repository);
    await tester.enterText(input('ai-model'), 'keep-this-model');
    await tester.enterText(input('ai-api-key'), 'test-only-secret');
    await pressAi(tester, 'ai-save');
    await tester.pumpAndSettle();
    expect(find.text('连接暂时中断，请重试'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(input('ai-model')).controller!.text,
      'keep-this-model',
    );
    expect(
      tester.widget<TextFormField>(input('ai-api-key')).controller!.text,
      'test-only-secret',
    );
    expect(tester.widget<FilledButton>(input('ai-save')).onPressed, isNotNull);
    await closeAi(tester, repository);
  });

  testWidgets(
    'disabling retains configuration and clearing needs confirmation',
    (tester) async {
      final repository = AiRepository();
      await mountAi(tester, repository);
      await pressAi(tester, 'ai-disable');
      await tester.pumpAndSettle();
      expect(repository.commands.single.args['enabled'], false);
      expect(repository.commands.single.args.containsKey('api_key'), isFalse);
      expect(find.text('AI 已停用'), findsOneWidget);
      await pressAi(tester, 'ai-clear');
      await tester.pumpAndSettle();
      expect(repository.commands.length, 1);
      expect(find.text('清除自定义 AI 配置？'), findsOneWidget);
      await tester.tap(find.text('清除配置'));
      await tester.pumpAndSettle();
      expect(repository.commands.last.action, 'delete_ai_settings');
      expect(
        tester.widget<TextFormField>(input('ai-base-url')).controller!.text,
        isEmpty,
      );
      await closeAi(tester, repository);
    },
  );

  testWidgets('read error has retry and demo never sends a save or test', (
    tester,
  ) async {
    final repository = AiRepository()..failRead = true;
    await mountAi(tester, repository);
    expect(find.text('暂时无法读取配置'), findsOneWidget);
    repository.failRead = false;
    repository.demo = true;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(find.textContaining('演示模式，配置不会保存'), findsOneWidget);
    expect(tester.widget<TextFormField>(input('ai-api-key')).enabled, isFalse);
    await pressAi(tester, 'ai-test');
    expect(find.textContaining('请先连接真实账号，再保存或测试'), findsOneWidget);
    expect(repository.commands, isEmpty);
    await closeAi(tester, repository);
  });

  testWidgets('account switch clears typed key before the next configuration', (
    tester,
  ) async {
    final repository = AiRepository();
    await mountAi(tester, repository);
    await tester.enterText(input('ai-api-key'), 'first-account-secret');
    repository.user = 'second-owner';
    repository.metadata = {
      'enabled': false,
      'base_url': '',
      'protocol': 'chat_completions',
      'model': '',
      'has_key': false,
    };
    repository.sessions.add(true);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(input('ai-api-key')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextFormField>(input('ai-base-url')).controller!.text,
      isEmpty,
    );
    expect(find.text('尚未配置 AI'), findsOneWidget);
    await closeAi(tester, repository);
  });

  for (final brightness in Brightness.values) {
    testWidgets('large text form remains usable in $brightness', (
      tester,
    ) async {
      final repository = AiRepository()
        ..metadata['protocol'] = 'chat_completions';
      await mountAi(tester, repository, brightness: brightness, scale: 1.6);
      await pressAi(tester, 'ai-test');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('测试未保存配置'), findsOneWidget);
      await closeAi(tester, repository);
    });
  }

  test(
    'demo repository rejects real AI configuration without persisting key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = DemoRepository();
      final value = AiSettings.fromJson(
        jsonObject(await repository.action('get_ai_settings')),
      );
      expect(value.hasKey, false);
      for (final action in [
        'save_ai_settings',
        'test_ai_settings',
        'delete_ai_settings',
      ]) {
        await expectLater(
          repository.action(action, args: {'api_key': 'test-only-secret'}),
          throwsA(
            isA<AppException>().having(
              (issue) => issue.code,
              'code',
              'demo_ai_unavailable',
            ),
          ),
        );
      }
      final preferences = await SharedPreferences.getInstance();
      for (final key in preferences.getKeys()) {
        expect(
          preferences.get(key).toString(),
          isNot(contains('test-only-secret')),
        );
      }
      await repository.dispose();
    },
  );
}
