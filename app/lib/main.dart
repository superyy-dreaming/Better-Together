import 'package:flutter/widgets.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app.dart';
import 'ui/app_appearance.dart';
import 'data/app_controller.dart';
import 'data/app_repository.dart';
import 'data/demo_repository.dart';
import 'data/supabase_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLinks();
  tz.initializeTimeZones();
  const demo = bool.fromEnvironment('DEMO_MODE');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  final appearanceStore = SharedPreferencesAppearanceStore();
  final appearance = await loadAppearance(appearanceStore);
  AppRepository? repository;
  String? issue;
  try {
    if (demo) {
      repository = DemoRepository();
    } else if (Uri.tryParse(url)?.scheme == 'https' && key.isNotEmpty) {
      await Supabase.initialize(url: url, publishableKey: key);
      repository = SupabaseAppRepository(
        Supabase.instance.client,
        supabaseUrl: url,
        anonKey: key,
      );
    } else {
      issue = '此安装包尚未连接服务。请使用已配置的内测版本，或联系内测负责人。';
    }
  } catch (_) {
    issue = '服务初始化未完成。请检查网络后重新打开应用。你的云端记录不会因此改变。';
  }
  if (repository == null) {
    runApp(SetupApp(message: issue!));
  } else {
    if (repository is SupabaseAppRepository) { await repository.startAiTasks(); }
    runApp(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          appearanceStoreProvider.overrideWithValue(appearanceStore),
          initialAppearanceProvider.overrideWithValue(appearance),
        ],
        child: const BetterTogetherApp(),
      ),
    );
  }
}
