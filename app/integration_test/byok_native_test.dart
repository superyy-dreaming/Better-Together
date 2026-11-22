import 'dart:io';
import 'package:better_together/data/ai/device_ai_service.dart';
import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/settings/ai_settings_page.dart';
import 'package:better_together/ui/app_appearance.dart';
import 'package:better_together/ui/design.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

class NativeSettingsRepository extends DemoRepository {
 NativeSettingsRepository(){
  ai=DeviceAiService(currentOwner:()=>currentUserId,api:(name,{args=const {}})async=>throw StateError('Native settings must not call the backend'));
 }
 final String testOwner='native-byok-${const Uuid().v4()}';
 late final DeviceAiService ai;
 @override bool get isDemo=>false;
 @override String? get currentUserId=>testOwner;
 @override Future<Object?> action(String name,{JsonMap args=const {}})=>ai.settingsAction(name,args);
 @override Future<void> dispose() async {await ai.store.clear(testOwner);await ai.dispose();await super.dispose();}
}
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('native secure store, account isolation, empty reset and accessible settings in both appearances', (tester)async {
  final repo=NativeSettingsRepository();bool converted=false;
  Future<void> shot(String name)async {
   if(Platform.isAndroid && !converted){await binding.convertFlutterSurfaceToImage();converted=true;}
   await tester.pumpAndSettle();expect(tester.takeException(),isNull);
   await binding.takeScreenshot('${Platform.operatingSystem}-byok-$name');
  }
  Future<void> show(AppAppearance appearance,Brightness brightness,double scale)async {
   await tester.pumpWidget(const SizedBox());
   await tester.pumpWidget(ProviderScope(overrides:[repositoryProvider.overrideWithValue(repo)],child:MaterialApp(
    theme:buildTheme(brightness,appearance:appearance),
    localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalCupertinoLocalizations.delegate,GlobalWidgetsLocalizations.delegate],
    supportedLocales:const [Locale('zh','CN')],locale:const Locale('zh','CN'),
    home:MediaQuery(data:MediaQueryData(size:tester.view.physicalSize/tester.view.devicePixelRatio,textScaler:TextScaler.linear(scale)),child:const AiSettingsPage()))));
   await tester.pumpAndSettle();
  }
  Future<void> press(String key)async {
   final f=find.byKey(ValueKey(key));await tester.ensureVisible(f);await tester.pumpAndSettle();await tester.tap(f);await tester.pumpAndSettle();
  }
  try {
   await show(AppAppearance.classic,Brightness.light,1);
   expect(find.text('尚未配置 AI'),findsOneWidget);
   await shot('classic-light');
   await press('ai-save');expect(find.text('请填写 API 密钥'),findsOneWidget);
   await tester.ensureVisible(find.byKey(const ValueKey('ai-api-key')));
   await tester.enterText(find.byKey(const ValueKey('ai-api-key')),'native-synthetic-only');
   await press('ai-save');
   expect(tester.widget<TextFormField>(find.byKey(const ValueKey('ai-api-key'))).controller!.text,isEmpty);
   final stored=await repo.ai.store.read(repo.testOwner);
   expect(stored.apiKey,'native-synthetic-only');expect(stored.settings.enabled,false);
   expect((await repo.ai.store.read('${repo.testOwner}-other')).apiKey,isEmpty);
   await shot('saved-key-hidden');
   for(final appearance in AppAppearance.values){
    await show(appearance,Brightness.dark,1.6);
    await tester.ensureVisible(find.byKey(const ValueKey('ai-model')));await tester.pumpAndSettle();
    await shot('${appearance.name}-dark-large');
    await tester.ensureVisible(find.byKey(const ValueKey('ai-save')));await tester.pumpAndSettle();
    await shot('${appearance.name}-actions-large');
   }
   await press('ai-clear');await tester.tap(find.text('清除配置'));await tester.pumpAndSettle();
   expect((await repo.ai.store.read(repo.testOwner)).apiKey,isEmpty);
   await show(AppAppearance.tuantuan,Brightness.light,1);
   expect(tester.widget<TextFormField>(find.byKey(const ValueKey('ai-base-url'))).controller!.text,isEmpty);
   await shot('cleared-stays-empty');
   await tester.pumpWidget(const SizedBox());
  }finally{await repo.dispose();}
 });
}
