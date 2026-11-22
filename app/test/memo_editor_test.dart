import 'package:better_together/app.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/memo_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'edited food calories retain range schema and manual provenance',
    (tester) async {
      JsonMap? result;
      final checkin = Checkin(
        id: 'food',
        userId: 'me',
        localDate: '2026-11-18',
        createdAt: DateTime(2026, 11, 18),
        category: 'food',
        fields: const [
          MemoField(
            key: 'calorie_range',
            label: '热量',
            value: {'min': 400, 'max': 600, 'unit': 'kcal', 'estimated': true},
            source: 'ai',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appDelegates,
          supportedLocales: appLocales,
          locale: appLocales.first,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<JsonMap>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => MemoEditor(checkin: checkin),
                  );
                },
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '下限'), '450');
      await tester.enterText(find.widgetWithText(TextField, '上限'), '650');
      await tester.ensureVisible(find.text('保存我的版本'));
      await tester.tap(find.text('保存我的版本'));
      await tester.pumpAndSettle();
      final field = jsonObject(jsonList(result!['fields']).single);
      expect(field['source'], 'manual');
      expect(field['value'], {
        'min': 450.0,
        'max': 650.0,
        'unit': 'kcal',
        'estimated': true,
      });
    },
  );
}
