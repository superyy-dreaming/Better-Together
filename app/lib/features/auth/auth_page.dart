import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../data/app_controller.dart';
import '../../data/app_repository.dart';
import '../../ui/design.dart';
import 'auth_failure.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final email = TextEditingController();
  final code = TextEditingController();
  bool sent = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> execute(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = authFailureMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: PageBody(
        children: [
          const SizedBox(height: 44),
          Text(
            'Better\nTogether',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontSize: 48, height: 1.05),
          ),
          const SizedBox(height: 24),
          const StampLabel(text: '各自坚持，一起变好'),
          const SizedBox(height: 30),
          Text(
            '把小目标，\n过成每一天。',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text('留下今天的一张照片，让朋友看见你的坚持。'),
          const SizedBox(height: 30),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('auth-email'),
                  controller: email,
                  enabled: !busy && !sent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: '邮箱地址'),
                  autocorrect: false,
                ),
                if (sent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('auth-code'),
                    controller: code,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: const InputDecoration(labelText: '邮件中的验证码'),
                  ),
                ],
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  key: const ValueKey('auth-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('auth-email-submit'),
            onPressed: busy
                ? null
                : () => execute(() async {
                    final repository = ref.read(repositoryProvider);
                    if (sent) {
                      if (code.text.trim().isEmpty) {
                        throw const AppException('otp_missing', '');
                      }
                      await repository.verifyEmailOtp(
                        email.text.trim(),
                        code.text.trim(),
                      );
                    } else {
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(email.text.trim())) {
                        throw const AppException('email_invalid', '');
                      }
                      await repository.sendEmailOtp(email.text.trim());
                      if (mounted) setState(() => sent = true);
                    }
                  }),
            child: Text(
              busy
                  ? '正在连接'
                  : sent
                  ? '验证并继续'
                  : '获取邮箱验证码',
            ),
          ),
          if (sent)
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      sent = false;
                      error = null;
                      code.clear();
                    }),
              child: const Text('修改邮箱或重新获取验证码'),
            ),
          const SizedBox(height: 16),
          AbsorbPointer(
            absorbing: busy,
            child: SignInWithAppleButton(
              key: const ValueKey('auth-apple'),
              onPressed: busy
                  ? () async {}
                  : () => execute(ref.read(repositoryProvider).signInWithApple),
              text: '通过 Apple 继续',
              height: 52,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '照片与纪要保存在你的账号中。加入小队后，仅队友可见你选择公开的计划；退出后历史记录仅自己可见。',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
