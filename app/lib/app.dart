import 'features/plans/plan_picker.dart';

import 'dart:async';

import 'package:app_links/app_links.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/app_controller.dart';
import 'features/auth/auth_page.dart';
import 'features/checkin/checkin_page.dart';
import 'features/checkin/memo_page.dart';
import 'features/history/history_page.dart';
import 'features/plans/plans_page.dart';
import 'features/reports/reports_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/ai_settings_page.dart';
import 'features/settings/notifications_page.dart';
import 'features/team/invite_page.dart';
import 'features/team/team_page.dart';
import 'features/today/today_page.dart';
import 'ui/design.dart';
import 'ui/app_appearance.dart';
import 'features/settings/appearance_page.dart';
import 'platform/providers.dart';
import 'domain/notification_route.dart';
import 'domain/invitation.dart';

const appLocales = [Locale('zh', 'CN')];
const appDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class BetterTogetherApp extends ConsumerStatefulWidget {
  const BetterTogetherApp({super.key});
  @override
  ConsumerState<BetterTogetherApp> createState() => _AppState();
}

class _AppState extends ConsumerState<BetterTogetherApp> {
  late final GoRouter router;
  StreamSubscription<bool>? auth;
  StreamSubscription<Uri>? links;
  @override
  void initState() {
    super.initState();
    final repository = ref.read(repositoryProvider);
    router = GoRouter(
      initialLocation: '/today',
      redirect: (context, state) {
        if (state.uri.scheme == 'bettertogether') {
          if (state.uri.host == 'invite') {
            return '/invite?token=${Uri.encodeComponent(state.uri.pathSegments.lastOrNull ?? '')}';
          }
          if (state.uri.host == 'auth') return '/today';
        }
        final loggedIn = repository.isSignedIn;
        if (!loggedIn && state.uri.path != '/login') {
          return '/login?next=${Uri.encodeComponent(state.uri.toString())}';
        }
        if (loggedIn && state.uri.path == '/login') {
          final next = state.uri.queryParameters['next'];
          return next != null && next.startsWith('/') && !next.startsWith('//')
              ? next
              : '/today';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const AuthPage()),
        ShellRoute(
          builder: (_, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
            GoRoute(path: '/team', builder: (_, _) => const TeamPage()),
            GoRoute(path: '/plans', builder: (_, _) => const PlansPage()),
            GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
          ],
        ),
        GoRoute(
          path: '/checkin',
          builder: (_, state) => CheckinPage(
            planId: state.uri.queryParameters['plan'],
            redoOf: state.uri.queryParameters['redo'],
            targetDate: state.uri.queryParameters['date'],
          ),
        ),
        GoRoute(
          path: '/memo/:id',
          builder: (_, state) => MemoPage(
            id: state.pathParameters['id']!,
            sealed: state.uri.queryParameters['sealed'] == '1',
          ),
        ),
        GoRoute(path: '/plan/new', builder: (_, _) => const PlanEditorPage()),
        GoRoute(
          path: '/plan/:id',
          builder: (_, state) => PlanDetailLoader(
            id: state.pathParameters['id']!,
            builder: (plan) => PlanEditorPage(plan: plan),
          ),
        ),
        GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
        GoRoute(
          path: '/invite',
          builder: (_, state) =>
              InvitePage(token: state.uri.queryParameters['token']),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(
          path: '/settings/appearance',
          builder: (_, _) => const AppearancePage(),
        ),
        GoRoute(
          path: '/settings/ai',
          builder: (_, _) => const AiSettingsPage(),
        ),
        GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPage()),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsPage(),
        ),
        GoRoute(path: '/auth/callback', redirect: (_, _) => '/today'),
        GoRoute(
          path: '/invite/:token',
          builder: (_, state) =>
              InvitePage(token: state.pathParameters['token']),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('链接暂不可用')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/today'),
            child: const Text('回到今日'),
          ),
        ),
      ),
    );
    auth = repository.authChanges.listen((_) => router.refresh());
    links = AppLinks().uriLinkStream.listen((uri) {
      final token = invitationToken(uri.toString());
      if (token != null) {
        router.go('/invite?token=${Uri.encodeComponent(token)}');
      }
    });
    unawaited(
      ref.read(pushServiceProvider).start(repository, (payload) async {
        final controller = ref.read(appControllerProvider.notifier);
        try {
          await controller.refresh();
        } catch (_) {
          // The notification center remains reachable if refresh is unavailable.
        }
        if (!mounted) return;
        final snapshot = ref.read(appControllerProvider).asData?.value;
        router.go(
          notificationRoute(
            payload['kind']?.toString() ?? '',
            payload['target_id']?.toString(),
            snapshot,
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    auth?.cancel();
    links?.cancel();
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Better Together',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(
      Brightness.light,
      appearance: ref.watch(appearanceProvider),
    ),
    darkTheme: buildTheme(
      Brightness.dark,
      appearance: ref.watch(appearanceProvider),
    ),
    locale: appLocales.first,
    supportedLocales: appLocales,
    localizationsDelegates: appDelegates,
    routerConfig: router,
    builder: (context, child) => Column(
      children: [
        if (ref.read(repositoryProvider).isDemo)
          Material(
            color: Palette.sun,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 16,
                  ),
                  child: Text(
                    '本机演示模式 · 示例数据不会上传',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.ink, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: ref.read(repositoryProvider).isDemo
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child!,
                )
              : child!,
        ),
      ],
    ),
  );
}

class SetupApp extends StatelessWidget {
  const SetupApp({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Better Together',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    locale: appLocales.first,
    supportedLocales: appLocales,
    localizationsDelegates: appDelegates,
    home: Scaffold(
      body: SafeArea(
        child: PageBody(
          children: [
            const SizedBox(height: 70),
            const Text(
              'Better Together',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 32),
            EmptyMessage(title: '连接好，就一起出发。', body: message),
          ],
        ),
      ),
    ),
  );
}
