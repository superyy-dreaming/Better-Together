import 'dart:async';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/team/invite_page.dart';
import 'package:better_together/features/team/invite_scanner_page.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InviteRepository extends DemoRepository {
  final commands = <({String action, JsonMap args})>[];
  Completer<void>? gate;
  bool hasTeam = false;
  @override
  Future<AppSnapshot> bootstrap() async {
    final original = (await super.bootstrap()).toJson();
    if (!hasTeam) original['team'] = null;
    return AppSnapshot.fromJson(original);
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    commands.add((action: action, args: args));
    await gate?.future;
    if (action == 'create_invite') {
      return {'token': 'ABCD23EF', 'url': 'bettertogether://invite/ABCD23EF'};
    }
    if (action == 'join_team') {
      hasTeam = true;
      return {'id': 'team'};
    }
    return super.action(action, args: args);
  }
}

Future<void> mountInvite(
  WidgetTester tester,
  InviteRepository repository, {
  double width = 375,
  Brightness brightness = Brightness.light,
  double scale = 1,
  String? scanned,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        inviteScannerProvider.overrideWithValue((_) async => scanned),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        localizationsDelegates: appDelegates,
        supportedLocales: appLocales,
        locale: appLocales.first,
        home: const InvitePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scan fills code and requires explicit confirmation', (
    tester,
  ) async {
    final repository = InviteRepository();
    await mountInvite(tester, repository, scanned: 'ABCD23EF');
    await tapKey(tester, 'invite-scan');
    expect(repository.commands, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('invite-code')))
          .controller!
          .text,
      'ABCD23EF',
    );
    await tapKey(tester, 'invite-join');
    expect(repository.commands.single.args['token'], 'ABCD23EF');
    expect(find.text('小队与邀请'), findsOneWidget);
  });
  testWidgets('invalid input stays editable and manual code normalizes', (
    tester,
  ) async {
    final repository = InviteRepository();
    await mountInvite(tester, repository);
    await tapKey(tester, 'invite-join');
    expect(find.textContaining('请输入 8 位'), findsOneWidget);
    expect(repository.commands, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('invite-code')),
      'abcd 23ef',
    );
    await tapKey(tester, 'invite-join');
    expect(repository.commands.single.args['token'], 'ABCD23EF');
  });
  testWidgets('generation blocks same-frame duplicate calls', (tester) async {
    final repository = InviteRepository()..hasTeam = true;
    await mountInvite(tester, repository);
    repository.gate = Completer<void>();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('invite-generate')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(repository.commands, hasLength(1));
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('ABCD 23EF'), findsOneWidget);
  });
  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('invite layout $width $brightness large text', (
        tester,
      ) async {
        final repository = InviteRepository();
        await mountInvite(
          tester,
          repository,
          width: width,
          brightness: brightness,
          scale: 1.6,
        );
        await tester.scrollUntilVisible(
          find.text('创建小队'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
