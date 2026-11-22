import 'dart:convert';

import 'package:better_together/data/supabase_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }
  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('email OTP sends to the intended address and creates no session', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    });
    final client = SupabaseClient(
      'https://project.example.test',
      'test-anon-key',
      httpClient: transport,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: MemoryPkceStorage(),
      ),
    );
    final repository = SupabaseAppRepository(
      client,
      supabaseUrl: 'https://project.example.test',
      anonKey: 'test-anon-key',
      httpClient: transport,
    );
    addTearDown(() async {
      await repository.dispose();
      await client.dispose();
      transport.close();
    });

    await repository.sendEmailOtp('  member@example.test  ');

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/otp');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['email'], 'member@example.test');
    expect(body['create_user'], true);
    expect(repository.isSignedIn, false);
  });

  test('email verification keeps all eight digits and establishes session', () async {
    late http.Request sent;
    final transport = MockClient((request) async {
      sent = request;
      return http.Response(jsonEncode({
        'access_token': 'synthetic-test-token',
        'refresh_token': 'synthetic-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {'id': 'email-member', 'aud': 'authenticated'},
      }), 200);
    });
    final client = SupabaseClient(
      'https://project.example.test',
      'test-anon-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final repository = SupabaseAppRepository(
      client,
      supabaseUrl: 'https://project.example.test',
      anonKey: 'test-anon-key',
      httpClient: transport,
    );
    addTearDown(() async {
      await repository.dispose();
      await client.dispose();
      transport.close();
    });
    final signedIn = repository.authChanges.firstWhere((value) => value);

    await repository.verifyEmailOtp(' member@example.test ', ' 01234567 ');

    expect(sent.url.path, '/auth/v1/verify');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['email'], 'member@example.test');
    expect(body['token'], '01234567');
    expect(body['type'], 'email');
    expect(await signedIn, true);
    expect(repository.isSignedIn, true);
    expect(repository.currentUserId, 'email-member');
  });
}
