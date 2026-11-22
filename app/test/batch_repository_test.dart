import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'demo batch is atomic, owner scoped, same-batch and idempotent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('batch-repository-');
      var repository = DemoRepository(directoryProvider: () async => dir);
      try {
        final baseline = await repository.bootstrap();
        Future<UploadedPhoto> upload(int n, String batch) => repository.upload(
          PhotoUpload(
            bytes: Uint8List.fromList([n, 10, 20]),
            filename: '$n.jpg',
            source: 'camera',
            batchId: batch,
          ),
        );
        final a = await upload(1, 'batch-a'),
            b = await upload(2, 'batch-b'),
            c = await upload(3, 'batch-a');
        JsonMap group(String id) => {
          'media_ids': [id],
          'plan_id': null,
          'plan_selection': 'all',
          'fields': [],
          'summary': '',
        };
        final invalid = {
          'groups': [group(a.id), group(b.id)],
          'idempotency_key': 'mixed-batch-id',
        };
        await expectLater(
          repository.action('submit_checkin_batch', args: invalid),
          throwsA(isA<AppException>()),
        );
        expect(
          (await repository.bootstrap()).checkins.length,
          baseline.checkins.length,
        );
        await expectLater(
          repository.action(
            'submit_checkin_batch',
            args: {
              'groups': [group(a.id), group(a.id)],
              'idempotency_key': 'duplicate-photo',
            },
          ),
          throwsA(isA<AppException>()),
        );
        final valid = {
          'groups': [group(a.id), group(c.id)],
          'idempotency_key': 'valid-batch-id',
        };
        final saved = jsonObject(
          await repository.action('submit_checkin_batch', args: valid),
        );
        final again = jsonObject(
          await repository.action('submit_checkin_batch', args: valid),
        );
        expect(again, saved);
        expect(jsonList(saved['checkin_ids']), hasLength(2));
        expect(
          (await repository.bootstrap()).checkins.length,
          baseline.checkins.length + 2,
        );
        await expectLater(
          repository.action(
            'submit_checkin_batch',
            args: {...valid, 'idempotency_key': 'reuse-photo'},
          ),
          throwsA(isA<AppException>()),
        );
        final preferences = await SharedPreferences.getInstance();
        final stored = jsonObject(
          jsonDecode(preferences.getString('better_together_demo_v1')!),
        );
        final media = jsonList(stored['_media']).map(jsonObject).toList();
        expect(
          media.singleWhere((p) => p['id'] == a.id)['checkin_id'],
          jsonList(saved['checkin_ids']).first,
        );
        media.singleWhere((p) => p['id'] == b.id)['user_id'] = 'another-owner';
        stored['_media'] = media;
        await preferences.setString(
          'better_together_demo_v1',
          jsonEncode(stored),
        );
        await repository.dispose();
        repository = DemoRepository(directoryProvider: () async => dir);
        await expectLater(
          repository.action(
            'submit_checkin_batch',
            args: {
              'groups': [group(b.id)],
              'idempotency_key': 'other-owner',
            },
          ),
          throwsA(isA<AppException>()),
        );
      } finally {
        await repository.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
