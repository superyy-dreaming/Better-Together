import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/supabase_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as timezone;

/// Opt-in real-service smoke. Credentials come only from an ignored local file.
/// Uses a dedicated synthetic account, never clears existing user data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real account AI settings navigation and native accessibility', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    const email = String.fromEnvironment('TEST_EMAIL');
    const password = String.fromEnvironment('TEST_PASSWORD');
    if (email.isEmpty || password.isEmpty || url.isEmpty || key.isEmpty) {
      fail(
        'Provide the private simulator configuration for this opt-in smoke.',
      );
    }
    timezone.initializeTimeZones();
    await Supabase.initialize(url: url, publishableKey: key);
    final client = Supabase.instance.client;
    await client.auth.signInWithPassword(email: email, password: password);
    final repository = SupabaseAppRepository(
      client,
      supabaseUrl: url,
      anonKey: key,
    );
    await repository.action('save_profile', args: {'nickname': '模拟器测试账号'});
    await repository.bootstrap();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: const BetterTogetherApp(),
      ),
    );
    Future<void> until(Finder finder) async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (finder.evaluate().isNotEmpty) return;
      }
      expect(finder, findsOneWidget);
    }

    await until(find.text('今天，也一起。'));
    final router = GoRouter.of(tester.element(find.text('今天，也一起。')));
    router.push('/settings');
    await until(find.text('AI 识别'));
    await tester.ensureVisible(find.text('AI 识别'));
    await tester.tap(find.text('AI 识别'));
    await until(find.byKey(const ValueKey('ai-base-url')));
    await tester.pumpAndSettle();
    expect(find.text('演示模式，配置不会保存。请连接真实账号后再填写密钥。'), findsNothing);
    await binding.takeScreenshot(
      '${Platform.operatingSystem}-ai-settings-light',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ai-save')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot(
      '${Platform.operatingSystem}-ai-settings-actions',
    );
    // Empty required fields must be rejected locally, without a provider call.
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pumpAndSettle();
    expect(find.text('请填写 API 密钥'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-model')),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot(
      '${Platform.operatingSystem}-ai-settings-large-dark',
    );
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    router.go('/today');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
    // The test account session remains in the simulator for the normal build.
  });
}
