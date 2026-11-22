import 'dart:io';

import 'package:better_together/app.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/team/invite_page.dart';
import 'package:better_together/features/team/invite_scanner_page.dart';
import 'package:better_together/ui/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';


class FixtureRepository extends DemoRepository {
  bool joined = false;
  @override
  Future<AppSnapshot> bootstrap() async {
    final state = (await super.bootstrap()).toJson();
    if (!joined) state['team'] = null;
    return AppSnapshot.fromJson(state);
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'join_team') {
      if (args['token'] != 'ABCD23EF') throw StateError('Unexpected code');
      joined = true;
      return {'id': 'fixture'};
    }
    if (action == 'create_invite') {
      return {'token': 'ABCD23EF', 'url': 'bettertogether://invite/ABCD23EF'};
    }
    return super.action(action, args: args);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native invite UI, manual join and invitation sharing', (tester) async {
    final repository = FixtureRepository();
    Future<void> render(Brightness brightness, {double scale = 1}) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
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

    await render(Brightness.light);
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot(
      '${Platform.operatingSystem}-invite-join-light',
    );
    await tester.tap(find.byKey(const ValueKey('invite-scan')));
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('扫码加入小队'), findsOneWidget);
    await binding.takeScreenshot('${Platform.operatingSystem}-invite-camera');
    Navigator.of(tester.element(find.byType(InviteScannerPage))).pop();
    await tester.pumpAndSettle();
    await render(Brightness.dark, scale: 1.6);
    await binding.takeScreenshot(
      '${Platform.operatingSystem}-invite-join-dark-large',
    );
    await render(Brightness.light);
    await tester.enterText(
      find.byKey(const ValueKey('invite-code')),
      'abcd 23ef',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-generate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(QrImageView));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('${Platform.operatingSystem}-invite-share');
    expect(find.text('ABCD 23EF'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
  });
}
