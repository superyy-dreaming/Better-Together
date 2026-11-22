import 'dart:async';
import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/features/auth/auth_failure.dart';
import 'package:better_together/features/auth/auth_page.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginRepository extends DemoRepository {
  Object? failure;
  Completer<void>? gate;
  int appleCalls = 0;
  int emailCalls = 0;
  @override
  Future<void> signInWithApple() async {
    appleCalls++;
    await gate?.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    emailCalls++;
  }

  @override
  Future<void> verifyEmailOtp(String email, String token) async {
    if (failure != null) throw failure!;
  }
}

Future<void> mount(WidgetTester tester, LoginRepository repository) async {
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
        theme: buildTheme(Brightness.light),
        localizationsDelegates: appDelegates,
        supportedLocales: appLocales,
        locale: const Locale('zh', 'CN'),
        home: const AuthPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
  });
}

Future<void> press(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  test('server errors are mapped without exposing raw credentials or URLs', () {
    const secret = 'https://private.example?token=secret';
    for (final code in [
      'provider_disabled',
      'invalid_jwt',
      'otp_expired',
      'over_email_send_rate_limit',
      'email_address_not_authorized',
      'signup_disabled',
      'unexpected',
    ]) {
      final message = authFailureMessage(AuthApiException(secret, code: code));
      expect(message, isNotNull);
      expect(message, isNot(contains(secret)));
      expect(message, isNot(contains('AuthApiException')));
    }
    expect(authFailureMessage(Exception(secret)), isNot(contains(secret)));
  });

  test('cancelled Apple authorization is not a failure', () {
    expect(
      authFailureMessage(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'private',
        ),
      ),
      isNull,
    );
    expect(
      authFailureMessage(const SocketException('private')),
      contains('网络'),
    );
  });

  testWidgets(
    'Apple errors allow retry, duplicate submission is blocked, cancel clears error',
    (tester) async {
      final repository = LoginRepository()
        ..failure = const AuthApiException(
          'private-token',
          code: 'provider_disabled',
        );
      await mount(tester, repository);
      await press(tester, 'auth-apple');
      await tester.pumpAndSettle();
      expect(find.textContaining('Apple 登录服务尚未就绪'), findsOneWidget);
      expect(find.textContaining('private-token'), findsNothing);

      repository.gate = Completer<void>();
      repository.failure = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'cancelled',
      );
      final button = tester.widget<SignInWithAppleButton>(
        find.byKey(const ValueKey('auth-apple')),
      );
      // Invoke the same pre-rebuild callback twice to cover the race, not only
      // the disabled button after a frame has been rendered.
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(repository.appleCalls, 2);
      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-error')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email validation and changing email clears stale code and error',
    (tester) async {
      final repository = LoginRepository();
      await mount(tester, repository);
      await press(tester, 'auth-email-submit');
      await tester.pumpAndSettle();
      expect(find.text('请填写有效的邮箱地址。'), findsOneWidget);
      expect(repository.emailCalls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'synthetic@example.com',
      );
      await press(tester, 'auth-email-submit');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-code')),
        '12345678',
      );
      repository.failure = const AuthApiException(
        'expired',
        code: 'otp_expired',
      );
      await press(tester, 'auth-email-submit');
      await tester.pumpAndSettle();
      expect(find.textContaining('验证码无效或已过期'), findsOneWidget);
      final change = find.text('修改邮箱或重新获取验证码');
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-error')), findsNothing);
      expect(find.byKey(const ValueKey('auth-code')), findsNothing);
      await press(tester, 'auth-email-submit');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('auth-code')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );
}
