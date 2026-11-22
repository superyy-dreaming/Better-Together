import 'dart:convert';
import 'dart:typed_data';

import 'package:better_together/data/supabase_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/data/ai/secure_ai_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_ai_test.dart' show MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('settings stay local and confirmed archive carries only results and untouched originals', () async {
    final calls = <http.Request>[], uploads = <http.Request>[];
    final cloud = MockClient((r) async {
      calls.add(r);
      if (r.url.path.endsWith('/api')) {
        return http.Response(
          jsonEncode({
            'data': {'awaiting_confirmation': true},
          }),
          200,
        );
      }
      throw StateError('Unexpected cloud request');
    });
    final client = SupabaseClient(
      'https://project.example.com',
      'synthetic-anon',
      httpClient: cloud,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'synthetic-session',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {'id': 'owner', 'aud': 'authenticated'},
      }),
    );
    final transport = MockClient((r) async {
      uploads.add(r);
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'photo',
            'path': 'owner/batch/photo.jpg',
            'source': 'camera',
            'captured_at': '2026-11-21T00:00:00Z',
          },
        }),
        200,
      );
    });
    final repository = SupabaseAppRepository(
      client,
      supabaseUrl: 'https://project.example.com',
      anonKey: 'synthetic-anon',
      httpClient: transport,
      aiStore: SecureAiStore(storage: MemorySecrets()),
    );
    await repository.action(
      'save_ai_settings',
      args: {
        'enabled': true,
        'base_url': 'https://models.example.test/v1',
        'model': 'synthetic',
        'api_key': 'synthetic-owner-key',
      },
    );
    expect(calls, isEmpty);
    const result = PhotoRecognition(
      photoId: 'photo',
      status: 'ready',
      summary: '可见书页。',
      confidence: .9,
    );
    final bytes = Uint8List.fromList(utf8.encode('unchanged-original'));
    await repository.upload(
      PhotoUpload(
        bytes: bytes,
        filename: 'original.jpg',
        source: 'camera',
        batchId: 'batch',
        analysisBytes: Uint8List.fromList([1, 2, 3]),
        photoId: 'photo',
        recognition: result,
      ),
    );
    expect(uploads.length, 1);
    final body = uploads.single.body;
    expect(body, contains('unchanged-original'));
    expect(body, contains('recognition_result'));
    expect(body, contains('可见书页。'));
    expect(body, isNot(contains('recognition_receipt')));
    expect(body, isNot(contains('synthetic-owner-key')));
    expect(calls, isEmpty);
    await repository.dispose();
    await client.dispose();
    cloud.close();
    transport.close();
  });
}
