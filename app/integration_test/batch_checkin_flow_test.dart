import 'package:better_together/ui/app_appearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/batch_flow_scenario.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native batch preview grouping edits and stamping', (
    tester,
  ) async {
    const key = 'better_together_demo_v1';
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getString(key);
    try {
      for (final appearance in AppAppearance.values) {
        await preferences.remove(key);
        await runBatchFlow(
          tester,
          appearance: appearance,
          native: true,
          screenshot: (name) async {
            await binding.takeScreenshot('ios-batch-$name');
          },
        );
      }
    } finally {
      if (previous == null) {
        await preferences.remove(key);
      } else {
        await preferences.setString(key, previous);
      }
    }
  });
}
