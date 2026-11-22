import '../../domain/models.dart';
import '../app_repository.dart';

const _nullableText = {
  'type': ['string', 'null'],
};
const aiFieldSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'key': {'type': 'string', 'minLength': 1, 'maxLength': 100},
    'label': {'type': 'string', 'minLength': 1, 'maxLength': 100},
    'value': {'type': 'string', 'maxLength': 500},
    'source': {
      'type': 'string',
      'enum': ['ai', 'screenshot', 'timer', 'health', 'manual'],
    },
    'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
  },
  'required': ['key', 'label', 'value', 'source', 'confidence'],
};
const aiMemoSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'assignments': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'photo_id': {'type': 'string'},
          'plan_id': _nullableText,
          'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
          'reason': {'type': 'string', 'maxLength': 500},
        },
        'required': ['photo_id', 'plan_id', 'confidence', 'reason'],
      },
    },
    'groups': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'plan_id': _nullableText,
          'photo_ids': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 1,
            'items': {'type': 'string'},
          },
          'summary': {'type': 'string', 'maxLength': 2000},
          'fields': {'type': 'array', 'maxItems': 30, 'items': aiFieldSchema},
        },
        'required': ['plan_id', 'photo_ids', 'summary', 'fields'],
      },
    },
  },
  'required': ['assignments', 'groups'],
};
const aiScreenshotSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'date': _nullableText,
    'is_exercise_record': {'type': 'boolean'},
    'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
    'fields': {'type': 'array', 'maxItems': 30, 'items': aiFieldSchema},
  },
  'required': ['date', 'is_exercise_record', 'confidence', 'fields'],
};
const aiReportSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'fact_ids': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 4,
      'items': {'type': 'string'},
    },
  },
  'required': ['fact_ids'],
};

bool completeDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final day = DateTime.tryParse(value);
  return day != null && day.toIso8601String().substring(0, 10) == value;
}

/// Model-generated fields cannot impersonate device measurements or user edits.
List<MemoField> validateGeneratedFields(
  List<Object?> raw,
  String category,
  List<MemoField> screenshotFields,
) {
  final fields = <MemoField>[];
  for (final value in raw) {
    final field = MemoField.fromJson(jsonObject(value));
    if (!['ai', 'screenshot'].contains(field.source)) continue;
    if (field.source == 'screenshot' &&
        !screenshotFields.any(
          (f) => f.key == field.key && f.value == field.value,
        )) {
      continue;
    }
    final name = field.key + field.label;
    if (RegExp(
          r'duration|distance|volume|water_ml|sleep|meditation|时长|距离|消耗|饮水量|毫升|睡眠',
          caseSensitive: false,
        ).hasMatch(name) &&
        field.source != 'screenshot') {
      continue;
    }
    final calories = RegExp(
      r'calor|energy|热量|卡路里',
      caseSensitive: false,
    ).hasMatch(name);
    if (calories && category != 'food' && field.source != 'screenshot') {
      continue;
    }
    if (calories && category == 'food') {
      final text = field.value.toString();
      if (!RegExp(r'\d+(?:\.\d+)?\s*[-~至到]\s*\d+(?:\.\d+)?').hasMatch(text)) {
        continue;
      }
      fields.add(
        MemoField(
          key: field.key,
          label: field.label,
          value: text.contains('估算') ? text : '$text（估算）',
          source: field.source,
          confidence: field.confidence,
        ),
      );
    } else {
      fields.add(field);
    }
  }
  return fields;
}

PhotoRecognition validatePhotoMemo(
  JsonMap value, {
  required String photoId,
  required List<JsonMap> plans,
  String? screenshotDate,
  List<MemoField> screenshotFields = const [],
}) {
  final assignments = jsonList(value['assignments']);
  final groups = jsonList(value['groups']);
  if (assignments.length != 1 || groups.length != 1) {
    throw const AppException('ai_invalid_result', '识别结果不完整，可先打卡。');
  }
  final assignment = jsonObject(assignments.single),
      group = jsonObject(groups.single);
  if (assignment['photo_id'] != photoId ||
      jsonList(group['photo_ids']).length != 1 ||
      jsonList(group['photo_ids']).single != photoId) {
    throw const AppException('ai_photo_mismatch', '识别结果与图片不符，可先打卡。');
  }
  final proposed = nullableString(assignment['plan_id']);
  if (proposed != null && !plans.any((p) => p['id'] == proposed)) {
    throw const AppException('ai_plan_mismatch', '识别建议的计划不可用，可手动选择。');
  }
  final confidence = (assignment['confidence'] as num).toDouble();
  final id = confidence >= .8 ? proposed : null;
  final category =
      plans.where((p) => p['id'] == id).firstOrNull?['category']?.toString() ??
      'all';
  var summary = stringValue(group['summary']);
  // Preserve the old measurement-summary safety filter until step 8's sourced
  // summary review. Independent per-photo results are retained for that work.
  if (['exercise', 'sleep', 'water', 'mindfulness', 'all'].contains(category)) {
    summary = summary
        .split(RegExp(r'(?<=[。！？])'))
        .where(
          (s) => !RegExp(
            r'分钟|小时|秒|公里|千米|千卡|大卡|卡路里|kcal|km|毫升|ml|升|\d\s*m\b',
            caseSensitive: false,
          ).hasMatch(s),
        )
        .join('');
  }
  if (category == 'food') {
    summary = summary
        .split(RegExp(r'(?<=[。！？])'))
        .where(
          (s) =>
              !RegExp(r'热量|卡路里|千卡|kcal|大卡', caseSensitive: false).hasMatch(s) ||
              (RegExp(r'\d+\s*[-~至到]\s*\d+').hasMatch(s) && s.contains('估算')),
        )
        .join('');
  }
  return PhotoRecognition(
    photoId: photoId,
    status: 'ready',
    planId: id,
    confidence: confidence,
    summary: summary,
    fields: validateGeneratedFields(
      jsonList(group['fields']),
      category,
      screenshotFields,
    ),
    screenshotDate: screenshotDate,
  );
}
