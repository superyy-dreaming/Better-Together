import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:better_together/data/ai/secure_ai_store.dart';
import 'package:better_together/data/ai/ai_transport.dart';
import 'package:better_together/data/ai/device_ai_service.dart';
import 'package:better_together/data/ai/ai_task_queue.dart';
import 'package:better_together/data/ai/ai_contract.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/platform/photo_dates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:timezone/data/latest.dart' as tzdata;

class MemorySecrets implements AiSecretStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

const photoId = '10000000-0000-4000-8000-000000000001';
const planId = '20000000-0000-4000-8000-000000000001';
final request = PhotoRecognitionRequest(
  analysisBytes: Uint8List.fromList([1, 2, 3]),
  photoId: photoId,
  batchId: 'batch',
  source: 'camera',
  originalSha256: 'digest',
);
JsonMap memo({double confidence = .9, List<JsonMap> fields = const []}) => {
  'assignments': [
    {
      'photo_id': photoId,
      'plan_id': planId,
      'confidence': confidence,
      'reason': '可见书页',
    },
  ],
  'groups': [
    {
      'photo_ids': [photoId],
      'plan_id': planId,
      'summary': '书页有标记。',
      'fields': fields,
    },
  ],
};
final context = <String, Object?>{
  'timezone': 'Asia/Shanghai',
  'local_date': '2026-11-21',
  'plans': [
    {'id': planId, 'category': 'study', 'title': '学习', 'goal': ''},
  ],
};
http.Response response(Object value) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': jsonEncode(value)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<SecureAiStore> configured({MemorySecrets? storage}) async {
  final store = SecureAiStore(storage: storage ?? MemorySecrets());
  await store.write(
    'owner',
    await store.input(
      'owner',
      enabled: true,
      baseUrl: 'https://models.example.test/v1',
      model: 'synthetic-model',
      apiKey: 'synthetic-key-not-a-real-secret',
    ),
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  test(
    'first-use example is inert; clear stays empty and accounts are isolated',
    () async {
      final storage = MemorySecrets(),
          store = SecureAiStore(storage: MemorySecrets());
      expect((await store.read('owner')).usable, false);
      expect(
        (await store.read('owner')).settings.baseUrl,
        SecureAiStore.exampleUrl,
      );
      final ready = await configured(storage: storage);
      expect((await ready.read('owner')).usable, true);
      expect((await ready.read('other')).apiKey, isEmpty);
      expect(
        (await ready.read('owner')).toString(),
        isNot(contains('synthetic-key')),
      );
      expect(
        (await ready.read('owner')).settings.withoutKey.toString(),
        isNot(contains('synthetic-key')),
      );
      await ready.clear('owner');
      expect((await ready.read('owner')).settings.baseUrl, isEmpty);
      expect(storage.values.values.join(), isNot(contains('synthetic-key')));
    },
  );
  test('retained key never follows an endpoint change and disable saves model changes', () async {
    final store = await configured();
    expect(
      () => store.input(
        'owner',
        enabled: true,
        baseUrl: 'https://other.example.test/v1',
        model: 'x',
        apiKey: '',
      ),
      throwsA(isA<AppException>()),
    );
    final service = DeviceAiService(
      currentOwner: () => 'owner',
      api: (name, {args = const {}}) async =>
          throw StateError('no backend for settings'),
      store: store,
    );
    final metadata = jsonObject(
      await service.settingsAction('save_ai_settings', {
        'enabled': false,
        'base_url': 'https://models.example.test/v1',
        'model': 'edited-model',
      }),
    );
    expect(metadata['model'], 'edited-model');
    expect(metadata['enabled'], false);
    expect(
      (await store.read('owner')).apiKey,
      'synthetic-key-not-a-real-secret',
    );
    expect(metadata.toString(), isNot(contains('synthetic-key')));
    await service.dispose();
  });
  test('direct Chat Completions keeps step-2 parameters and sends no AI key to business API', () async {
    final store = await configured();
    final requests = <http.Request>[], business = <JsonMap>[];
    final service = DeviceAiService(
      currentOwner: () => 'owner',
      store: store,
      api: (name, {args = const {}}) async {
        business.add(args);
        expect(name, 'ai_context');
        return context;
      },
      transport: AiTransport(
        clientFactory: () => MockClient((r) async {
          requests.add(r);
          return response(memo());
        }),
      ),
    );
    final value = await service.recognize(request);
    expect(value.isReady, true, reason: value.errorCode);
    expect(requests.length, 1);
    final r = requests.single, body = jsonObject(jsonDecode(r.body));
    expect(r.url.toString(), 'https://models.example.test/v1/chat/completions');
    expect(
      r.headers['Authorization'],
      'Bearer synthetic-key-not-a-real-secret',
    );
    expect(r.followRedirects, false);
    expect(body['max_completion_tokens'], 6500);
    expect(body['response_format'], containsPair('type', 'json_schema'));
    expect(jsonEncode(body), contains('data:image/jpeg;base64,'));
    expect(jsonEncode(business), isNot(contains('synthetic-key')));
    await service.dispose();
  });
  test(
    'unconfigured, wrong key and timeout remain pending, never fabricate ready',
    () async {
      for (final mode in ['absent', 'wrong', 'timeout', 'malformed']) {
        var calls = 0;
        final service = DeviceAiService(
          currentOwner: () => 'owner',
          store: mode == 'absent'
              ? SecureAiStore(storage: MemorySecrets())
              : await configured(),
          api: (name, {args = const {}}) async => context,
          transport: AiTransport(
            clientFactory: () => MockClient((r) async {
              calls++;
              if (mode == 'wrong') {
                return http.Response('synthetic-key-not-a-real-secret', 401);
              }
              if (mode == 'timeout') throw TimeoutException('do not expose me');
              return response({'broken': 'synthetic-key-not-a-real-secret'});
            }),
          ),
        );
        final result = await service.recognize(request);
        expect(result.isPending, true, reason: mode);
        expect(result.error, isNot(contains('synthetic-key')));
        expect(calls, mode == 'absent' ? 0 : 1);
        await service.dispose();
      }
    },
  );
  test('nested candidate arrays are reported before a provider call', () async {
    var calls = 0;
    final service = DeviceAiService(
      currentOwner: () => 'owner',
      store: await configured(),
      api: (name, {args = const {}}) async => {
        ...context,
        'plans': [context['plans']],
      },
      transport: AiTransport(
        clientFactory: () => MockClient((r) async {
          calls++;
          return response(memo());
        }),
      ),
    );
    final result = await service.recognize(request);
    expect(result.isPending, true);
    expect(result.errorCode, 'ai_context');
    expect(calls, 0);
    await service.dispose();
  });
  test(
    'account/config changes cancel late recognition before it becomes usable',
    () async {
      var owner = 'owner';
      final gate = Completer<void>();
      final service = DeviceAiService(
        currentOwner: () => owner,
        store: await configured(),
        api: (name, {args = const {}}) async => context,
        transport: AiTransport(
          clientFactory: () => MockClient((r) async {
            await gate.future;
            return response(memo());
          }),
        ),
      );
      final future = service.recognize(request);
      await Future<void>.delayed(Duration.zero);
      owner = 'other';
      service.invalidate();
      gate.complete();
      final result = await future;
      expect(result.isPending, true);
      expect(result.errorCode, 'ai_cancelled');
      await service.dispose();
    },
  );
  test(
    'screenshot retains two calls and exact complete date in step 2',
    () async {
      final names = <String>[];
      final service = DeviceAiService(
        currentOwner: () => 'owner',
        store: await configured(),
        api: (name, {args = const {}}) async => context,
        transport: AiTransport(
          clientFactory: () => MockClient((r) async {
            final body = jsonObject(jsonDecode(r.body));
            final name = stringValue(
              jsonObject(
                jsonObject(body['response_format'])['json_schema'],
              )['name'],
            );
            names.add(name);
            return response(
              name == 'exercise_screenshot'
                  ? {
                      'date': '2026-11-21',
                      'is_exercise_record': true,
                      'confidence': .95,
                      'fields': [],
                    }
                  : memo(),
            );
          }),
        ),
      );
      final value = await service.recognize(
        PhotoRecognitionRequest(
          analysisBytes: request.bytes,
          photoId: photoId,
          batchId: 'batch',
          source: 'screenshot',
          originalSha256: 'digest',
        ),
      );
      expect(value.screenshotDate, '2026-11-21', reason: value.errorCode);
      expect(names, ['exercise_screenshot', 'checkin_memo']);
      await service.dispose();
    },
  );
  test('unknown screenshot date is pending; old screenshot is rejected before memo', () async {
    for (final day in [null, '2026-11', '2020-01-01']) {
      var calls = 0;
      final service = DeviceAiService(
        currentOwner: () => 'owner',
        store: await configured(),
        api: (name, {args = const {}}) async => context,
        transport: AiTransport(
          clientFactory: () => MockClient((r) async {
            calls++;
            return response({
              'date': day,
              'is_exercise_record': true,
              'confidence': .95,
              'fields': [],
            });
          }),
        ),
      );
      final value = await service.recognize(
        PhotoRecognitionRequest(
          analysisBytes: request.bytes,
          photoId: photoId,
          batchId: 'batch',
          source: 'screenshot',
          originalSha256: 'digest',
        ),
      );
      expect(value.status, day == '2020-01-01' ? 'rejected' : 'pending');
      expect(calls, 1);
      await service.dispose();
    }
  });
  test('connection test uses synthetic pixels, checks JSON capability, does not save', () async {
    final storage = MemorySecrets(), calls = <JsonMap>[];
    final service = DeviceAiService(
      currentOwner: () => 'owner',
      store: SecureAiStore(storage: storage),
      api: (name, {args = const {}}) async => throw StateError('No server'),
      transport: AiTransport(
        clientFactory: () => MockClient((r) async {
          final body = jsonObject(jsonDecode(r.body));
          calls.add(body);
          final messages = jsonList(body['messages']);
          final content = jsonList(jsonObject(messages.last)['content']);
          final url = stringValue(
            jsonObject(jsonObject(content.single)['image_url'])['url'],
          );
          final image = img.decodeJpg(base64Decode(url.split(',').last))!;
          final colors = List.generate(6, (i) {
            final pixel = image.getPixel(
              (i % 3) * 100 + 50,
              (i ~/ 3) * 100 + 50,
            );
            if (pixel.r > 180 && pixel.g > 150) return 'yellow';
            if (pixel.r > 180) return 'red';
            if (pixel.b > 180) return 'blue';
            return 'green';
          });
          return response({'colors': colors});
        }),
      ),
    );
    final result = jsonObject(
      await service.settingsAction('test_ai_settings', {
        'base_url': 'https://models.example.test/v1',
        'model': 'test',
        'api_key': 'synthetic-probe-key',
      }),
    );
    expect(result['ok'], true);
    expect(result['saved'], false);
    expect(storage.values, isEmpty);
    expect(calls.length, 1);
    await service.dispose();
  });
  test('source validation and confidence threshold preserve factual nonnumeric summary', () {
    final plans = jsonList(context['plans']).map(jsonObject).toList();
    expect(
      validatePhotoMemo(
        memo(confidence: .79),
        photoId: photoId,
        plans: plans,
      ).planId,
      isNull,
    );
    expect(
      validatePhotoMemo(
        memo(confidence: .8),
        photoId: photoId,
        plans: plans,
      ).planId,
      planId,
    );
    final raw = [
      for (final source in ['manual', 'timer', 'health', 'ai', 'screenshot'])
        {
          'key': 'duration',
          'label': '时长',
          'value': '30 分钟',
          'source': source,
          'confidence': .9,
        },
    ];
    expect(validateGeneratedFields(raw, 'exercise', []), isEmpty);
    expect(
      validateGeneratedFields(raw, 'exercise', [
        const MemoField(
          key: 'duration',
          label: '时长',
          value: '30 分钟',
          source: 'screenshot',
          confidence: .9,
        ),
      ]).single.source,
      'screenshot',
    );
    final food = validateGeneratedFields(
      [
        {
          'key': 'calories',
          'label': '热量',
          'value': '400-600 千卡',
          'source': 'ai',
          'confidence': .9,
        },
      ],
      'food',
      [],
    );
    expect(food.single.value, contains('估算'));
    expect(
      validateGeneratedFields(
        [
          {
            'key': 'calories',
            'label': '热量',
            'value': '500 千卡',
            'source': 'ai',
            'confidence': .9,
          },
        ],
        'food',
        [],
      ),
      isEmpty,
    );
  });
  test('complete date and EXIF calendar validation do not guess', () {
    expect(completeDate('2026-02-30'), false);
    expect(completeDate('2026-11-21'), true);
    expect(
      photoCalendarDate('2026:11:20 23:30:00', '+00:00', 'Asia/Shanghai'),
      '2026-11-21',
    );
    expect(photoCalendarDate(null, null, 'Asia/Shanghai'), isNull);
  });
  test(
    'same-day retry window preserves 32 attempt cap and DST local dates',
    () {
      final now = DateTime.parse('2026-11-21T15:59:50Z');
      expect(
        nextAiRetry(
          attempt: 1,
          created: now,
          timezone: 'Asia/Shanghai',
          now: now,
        ),
        isNull,
      );
      final earlier = DateTime.parse('2026-11-21T04:00:00Z');
      expect(
        nextAiRetry(
          attempt: 1,
          created: earlier,
          timezone: 'Asia/Shanghai',
          now: earlier,
        ),
        earlier.add(const Duration(seconds: 30)),
      );
      expect(
        nextAiRetry(
          attempt: 32,
          created: earlier,
          timezone: 'Asia/Shanghai',
          now: earlier,
        ),
        isNull,
      );
      final task = AiPendingTask(
        mediaId: photoId,
        owner: 'owner',
        createdAt: earlier.toIso8601String(),
      );
      expect(task.toJson().keys, isNot(contains('secret')));
    },
  );
}
