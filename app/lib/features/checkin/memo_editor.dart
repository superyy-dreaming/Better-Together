import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/design.dart';

class MemoEditor extends StatefulWidget {
  const MemoEditor({super.key, required this.checkin});
  final Checkin checkin;
  @override
  State<MemoEditor> createState() => _MemoEditorState();
}

class _MemoEditorState extends State<MemoEditor> {
  late final summary = TextEditingController(text: widget.checkin.summary);
  late final fields = {
    for (final f in widget.checkin.fields)
      f.key: TextEditingController(text: f.value == null ? '' : f.displayValue),
  };
  late final ranges = <String, (TextEditingController, TextEditingController)>{
    for (final f in widget.checkin.fields.where((f) => f.value is Map))
      f.key: (
        TextEditingController(text: stringValue(jsonObject(f.value)['min'])),
        TextEditingController(text: stringValue(jsonObject(f.value)['max'])),
      ),
  };
  @override
  void dispose() {
    summary.dispose();
    for (final pair in ranges.values) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    final updated = <JsonMap>[];
    for (final f in widget.checkin.fields) {
      if (ranges.containsKey(f.key)) {
        final pair = ranges[f.key]!;
        if (pair.$1.text.trim().isEmpty && pair.$2.text.trim().isEmpty) {
          continue;
        }
        final min = double.tryParse(pair.$1.text.trim());
        final max = double.tryParse(pair.$2.text.trim());
        if (min == null || max == null || min < 0 || max <= min) {
          feedback(context, '请填写有效的热量上下限，上限需要大于下限');
          return;
        }
        final old = jsonObject(f.value);
        updated.add(
          min == old['min'] && max == old['max']
              ? f.toJson()
              : {
                  ...f.toJson(),
                  'value': {
                    'min': min,
                    'max': max,
                    'unit': 'kcal',
                    'estimated': true,
                  },
                  'source': 'manual',
                  'confidence': null,
                },
        );
        continue;
      }
      final text = fields[f.key]!.text.trim();
      if (text.isEmpty) continue;
      if (text == (f.value == null ? '' : f.displayValue)) {
        updated.add(f.toJson());
        continue;
      }
      updated.add({
        ...f.toJson(),
        'value': text.isEmpty ? null : text,
        'source': 'manual',
        'confidence': null,
      });
    }
    Navigator.pop(context, <String, Object?>{
      'summary': summary.text.trim(),
      'fields': updated,
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .85,
    minChildSize: .5,
    maxChildSize: .95,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: EdgeInsets.fromLTRB(
        22,
        24,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      children: [
        Text('用你的话记录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: summary,
          minLines: 3,
          maxLines: 7,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: '纪要摘要'),
        ),
        ...widget.checkin.fields.map(
          (f) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ranges.containsKey(f.key)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${f.label}（估算，千卡）'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ranges[f.key]!.$1,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '下限',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: ranges[f.key]!.$2,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '上限',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('两项都留空可移除该字段，修改后标记为手填。'),
                    ],
                  )
                : TextField(
                    controller: fields[f.key],
                    readOnly:
                        widget.checkin.category == 'exercise' &&
                        RegExp(
                          r'duration|distance|calor|energy|时长|距离|消耗|热量',
                          caseSensitive: false,
                        ).hasMatch(f.key + f.label),
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText:
                          widget.checkin.category == 'exercise' &&
                              RegExp(
                                r'duration|distance|calor|energy|时长|距离|消耗|热量',
                                caseSensitive: false,
                              ).hasMatch(f.key + f.label)
                          ? '来源：${sourceLabel(f.source)}。运动数值保留原始来源，请用新截图补充记录。'
                          : '当前来源：${sourceLabel(f.source)}。修改后标记为手填。',
                      helperMaxLines: 3,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: save, child: const Text('保存我的版本')),
      ],
    ),
  );
}
