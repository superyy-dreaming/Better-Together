import 'package:better_together/ui/app_appearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/batch_flow_scenario.dart';

void main() {
  for (final appearance in AppAppearance.values) {
    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('group flow ${appearance.name} fits $width with large text', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        const links = MethodChannel('com.llfbandit.app_links/events');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          links,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            links,
            null,
          ),
        );
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        tester.platformDispatcher.platformBrightnessTestValue = width == 375
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await runBatchFlow(tester, appearance: appearance);
      });
    }
  }
}
