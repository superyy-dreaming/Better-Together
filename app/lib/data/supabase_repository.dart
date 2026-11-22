import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'app_repository.dart';
import 'ai/device_ai_service.dart';
import 'ai/ai_task_queue.dart';
import 'ai/secure_ai_store.dart';
import 'ai/ai_transport.dart';

class SupabaseAppRepository implements AppRepository, ScopedRepository {
  SupabaseAppRepository(
    this.client, {
    required this.supabaseUrl,
    required this.anonKey,
    http.Client? httpClient,
    SecureAiStore? aiStore,
    AiTransport? aiTransport,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null {
    deviceAi = DeviceAiService(
      currentOwner: () => currentUserId,
      api: (name, {args = const {}}) => action(name, args: args),
      store: aiStore,
      transport: aiTransport,
    );
    aiTasks = AiTaskQueue(
      ai: deviceAi,
      api: (name, {args = const {}}) => action(name, args: args),
      currentOwner: () => currentUserId,
      download: _downloadOwnPhoto,
    );
    var owner = currentUserId;
    _aiAuthSubscription = authChanges.listen((_) {
      if (owner != currentUserId) {
        owner = currentUserId;
        deviceAi.invalidate();
      }
    });
  }
  late final DeviceAiService deviceAi;
  late final AiTaskQueue aiTasks;
  Future<void> startAiTasks() => aiTasks.start();

  Future<Uint8List> _downloadOwnPhoto(String mediaId) async {
    final owner = currentUserId;
    final result = jsonObject(
      await action(
        'media_urls',
        args: {
          'refs': [
            {'ref': 'media:$mediaId', 'variant': 'original'},
          ],
        },
      ),
    );
    final rows = jsonList(result['items']);
    if (rows.isEmpty) throw const AppException('forbidden', '照片已不可用');
    final row = jsonObject(rows.first);
    final url = Uri.tryParse(stringValue(row['url']));
    if (row['allowed'] != true || url == null || url.scheme != 'https') {
      throw const AppException('forbidden', '照片已不可用');
    }
    final request = http.Request('GET', url)..followRedirects = false;
    final response = await _httpClient.send(request);
    if (response.statusCode != 200) {
      throw const AppException('photo_network', '原图暂不可读');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (owner != currentUserId) {
        throw const AppException('ai_cancelled', '账号已切换');
      }
      if (bytes.length + chunk.length > 20 * 1024 * 1024) {
        throw const AppException('photo_size', '原图过大');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  late final StreamSubscription<bool> _aiAuthSubscription;
  final SupabaseClient client;
  final String supabaseUrl, anonKey;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Set<RealtimeChannel> _channels = {};
  final Set<String> _dirtyCollections = {};
  @override
  Set<String> takeInvalidatedCollections() {
    final result = Set<String>.of(_dirtyCollections);
    _dirtyCollections.clear();
    return result;
  }

  @override
  bool get isDemo => false;
  @override
  bool get isSignedIn => client.auth.currentSession != null;
  @override
  String? get currentUserId => client.auth.currentUser?.id;
  @override
  Stream<bool> get authChanges =>
      client.auth.onAuthStateChange.map((event) => event.session != null);

  @override
  Stream<void> get changes {
    RealtimeChannel? channel;
    late final StreamController<void> events;
    events = StreamController<void>(
      onListen: () {
        if (!isSignedIn) return;
        channel = client.channel(
          'app-snapshot-${DateTime.now().microsecondsSinceEpoch}',
        );
        _channels.add(channel!);
        // RLS filters each event. No event payload is trusted as a complete
        // snapshot; changes trigger the authenticated bootstrap endpoint.
        for (final table in const [
          'profiles',
          'teams',
          'team_members',
          'plans',
          'checkins',
          'media',
          'interactions',
          'overdue_feed',
          'pokes',
          'reports',
          'report_interactions',
          'notifications',
        ]) {
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) {
              if (!events.isClosed) {
                _dirtyCollections.add(switch (table) {
                  'reports' || 'report_interactions' => 'reports',
                  'overdue_feed' || 'pokes' => 'overdue',
                  'notifications' => 'notifications',
                  'plans' => 'plans',
                  'team_members' => 'membership',
                  'checkins' || 'media' || 'interactions' => 'checkins',
                  _ => 'profile',
                });
                events.add(null);
              }
            },
          );
        }
        channel!.subscribe((status, error) {
          if (events.isClosed) return;
          if (status == RealtimeSubscribeStatus.subscribed) {
            // Close the gap between the initial read and subscription, and
            // recover events missed while a previous connection was offline.
            events.add(null);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            events.addError(
              const AppException(
                'realtime_unavailable',
                '实时同步暂时中断，当前记录仍保留。可下拉刷新；连接恢复后会自动同步。',
              ),
            );
          }
        });
      },
      onCancel: () async {
        if (channel != null) {
          _channels.remove(channel);
          await client.removeChannel(channel!);
        }
      },
    );
    return events.stream;
  }

  @override
  Future<AppSnapshot> bootstrap() async {
    final result = await action('bootstrap_v2');
    return AppSnapshot.fromJson(jsonObject(result));
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (!isSignedIn) throw const AppException('unauthenticated', '请先登录，再继续操作');
    if (action == 'generate_report_ai') {
      return deviceAi.generateReport(stringValue(args['report_id']));
    }
    if (action == 'retry_photo_ai') {
      final mediaId = stringValue(args['media_id']);
      final configuration = await deviceAi.store.read(currentUserId!);
      if (!configuration.usable) {
        throw const AppException(
          'ai_not_configured',
          '请先到设置中的 AI 识别填写并启用服务，已有打卡保留。',
        );
      }
      await this.action('ai_context', args: {'media_id': mediaId});
      await aiTasks.enqueue(mediaId, manual: true);
      return {'queued': true};
    }
    if (DeviceAiService.settingsActions.contains(action)) {
      return deviceAi.settingsAction(action, args);
    }
    if (args.containsKey('api_key') || args.containsKey('secret')) {
      throw const AppException(
        'credential_payload_rejected',
        'AI 密钥只能保存在本机设置中。',
      );
    }
    try {
      final response = await client.functions.invoke(
        'api',
        body: {'action': action, ...args},
      );
      final result = _unwrap(response.data, response.status);
      if (action == 'submit_checkin' || action == 'submit_checkin_batch') {
        aiTasks.wake();
      }
      if ([
        'leave_team',
        'join_team',
        'delete_photo',
        'delete_account',
      ].contains(action)) {
        deviceAi.invalidate();
      }
      return result;
    } on FunctionException catch (error) {
      throw _fromResponse(error.details, error.status);
    } on SocketException {
      throw const AppException('network', '暂时连不上服务，请检查网络后重试');
    } on http.ClientException {
      throw const AppException('network', '连接中断，请检查网络后重试');
    }
  }

  Object? _unwrap(Object? body, int status) {
    final json = jsonObject(body is String ? jsonDecode(body) : body);
    if (json['error'] != null || status >= 400) {
      throw _fromResponse(json, status);
    }
    return json['data'];
  }

  AppException _fromResponse(Object? body, int status) {
    final json = jsonObject(body);
    final error = jsonObject(json['error']);
    return AppException(
      stringValue(error['code'], 'http_$status'),
      stringValue(
        error['message'],
        status == 401 ? '登录已过期，请重新登录' : '暂时无法完成操作，请稍后重试',
      ),
    );
  }

  void _requireSameUser(String userId) {
    if (currentUserId != userId) {
      throw const AppException('session_changed', '账号状态已改变，请重新打开打卡页面');
    }
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async =>
      http.Response.fromStream(await _httpClient.send(request));

  @override
  Future<PhotoRecognition> recognize(PhotoRecognitionRequest photo) =>
      deviceAi.recognize(photo);

  @override
  Future<UploadedPhoto> upload(PhotoUpload photo) async {
    if (!isSignedIn) throw const AppException('unauthenticated', '请先登录，再上传照片');
    final userId = currentUserId!;
    if (photo.bytes.isEmpty) {
      throw const AppException('empty_photo', '这张图片没有内容，请换一张');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$supabaseUrl/functions/v1/media'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${client.auth.currentSession!.accessToken}',
      'apikey': anonKey,
    });
    request.fields.addAll({'source': photo.source, 'batch_id': photo.batchId});
    if (photo.photoId != null) request.fields['photo_id'] = photo.photoId!;
    if (photo.recognition != null) {
      request.fields['recognition_result'] = jsonEncode(
        photo.recognition!.toJson(),
      );
    }
    if (photo.capturedAt != null) {
      request.fields['captured_at'] = photo.capturedAt!
          .toUtc()
          .toIso8601String();
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        photo.bytes,
        filename: photo.filename,
        contentType: MediaType.parse(photo.contentType),
      ),
    );
    if (photo.analysisBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'analysis',
          photo.analysisBytes!,
          filename: 'analysis.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }
    try {
      final response = await _sendMultipart(request);
      _requireSameUser(userId);
      final uploaded = UploadedPhoto.fromJson(
        jsonObject(_unwrap(jsonDecode(response.body), response.statusCode)),
      );
      if (photo.source != 'avatar' && photo.recognition?.isReady != true) {
        await aiTasks.enqueue(uploaded.id);
      }
      return uploaded;
    } on SocketException {
      throw const AppException('network', '照片还未上传，请检查网络后重试');
    } on http.ClientException {
      throw const AppException('network', '照片上传中断，请重试');
    } on FormatException {
      throw const AppException('invalid_response', '照片服务暂不可用，请稍后重试');
    }
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    await client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
  }

  @override
  Future<void> verifyEmailOtp(String email, String token) async {
    await client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  @override
  Future<void> signInWithApple() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final rawNonce = client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      if (credential.identityToken == null) {
        throw const AppException('apple_token_missing', 'Apple 登录未返回身份信息，请重试');
      }
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
        nonce: rawNonce,
      );
    } else {
      await client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'bettertogether://auth/callback',
      );
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<void> dispose() async {
    await _aiAuthSubscription.cancel();
    await aiTasks.dispose();
    await deviceAi.dispose();
    for (final channel in _channels.toList()) {
      await client.removeChannel(channel);
    }
    _channels.clear();
    if (_ownsHttpClient) _httpClient.close();
  }
}
