import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../domain/ai_settings.dart';
import '../../domain/models.dart';
import '../app_repository.dart';

/// Only the transport and this store can use credentials. Never attach this
/// object to a task, database payload, diagnostic, or presentation model.
class AiCredentials {
  const AiCredentials(this.settings, this.apiKey);
  final AiSettings settings;
  final String apiKey;
  bool get usable =>
      settings.enabled &&
      apiKey.isNotEmpty &&
      settings.baseUrl.isNotEmpty &&
      settings.model.isNotEmpty;
  @override
  String toString() => 'AiCredentials(<redacted>)';
}

abstract interface class AiSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformAiSecretStorage implements AiSecretStorage {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'better_together_byok',
    ),
    aOptions: AndroidOptions(
      storageNamespace: 'better_together_byok',
      resetOnError: false,
      migrateWithBackup: false,
    ),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecureAiStore {
  SecureAiStore({AiSecretStorage? storage})
    : _storage = storage ?? PlatformAiSecretStorage();
  final AiSecretStorage _storage;
  static const exampleUrl = 'https://api.siliconflow.cn/v1';
  static const exampleModel = 'deepseek-ai/DeepSeek-V4.1-Flash';
  String _key(String owner) {
    if (owner.isEmpty) throw const AppException('ai_account', '请先登录再配置 AI');
    return 'byok_v1_${sha256.convert(utf8.encode(owner))}';
  }

  Future<AiCredentials> read(String owner) async {
    try {
      final encoded = await _storage.read(_key(owner));
      if (encoded == null) {
        return const AiCredentials(
          AiSettings(baseUrl: exampleUrl, model: exampleModel),
          '',
        );
      }
      final data = jsonObject(jsonDecode(encoded));
      final key = data['secret'];
      if (data['v'] != 1 || key is! String || key.length > 8192) {
        throw const FormatException();
      }
      return AiCredentials(
        AiSettings.fromJson({...data, 'has_key': key.isNotEmpty}),
        key,
      );
    } catch (_) {
      // Never expose a platform error or corrupt stored text; do not erase it.
      throw const AppException(
        'ai_storage_unavailable',
        '设备安全存储暂不可读。可先打卡，解锁设备后重试。',
      );
    }
  }

  Future<AiCredentials> input(
    String owner, {
    required bool enabled,
    required String baseUrl,
    required String model,
    required String apiKey,
    String format = 'json_schema',
  }) async {
    final url = normalizedAiBaseUrl(baseUrl);
    if (validateAiBaseUrl(url) != null ||
        model.trim().isEmpty ||
        model.length > 200 ||
        apiKey.length > 8192 ||
        !['json_schema', 'json_object'].contains(format)) {
      throw const AppException('ai_configuration_invalid', '请核对接口地址、模型名和密钥。');
    }
    final saved = await read(owner);
    final secret = apiKey.trim().isNotEmpty
        ? apiKey.trim()
        : saved.settings.baseUrl == url
        ? saved.apiKey
        : '';
    if (secret.isEmpty) {
      throw const AppException('ai_key_required', '请输入 API Key；更换地址后需要重新填写。');
    }
    return AiCredentials(
      AiSettings(
        enabled: enabled,
        baseUrl: url,
        model: model.trim(),
        hasKey: true,
        format: format,
        revision: const Uuid().v4(),
      ),
      secret,
    );
  }

  Future<AiSettings> write(String owner, AiCredentials value) async {
    try {
      // One atomic secure-store item binds endpoint, revision and key together.
      await _storage.write(
        _key(owner),
        jsonEncode({
          'v': 1,
          ...value.settings.withoutKey,
          'secret': value.apiKey,
        }),
      );
      return value.settings;
    } catch (_) {
      throw const AppException('ai_storage_write', '配置尚未确认保存，请解锁设备后重试。');
    }
  }

  Future<AiSettings> disable(String owner) async {
    final saved = await read(owner);
    return write(
      owner,
      AiCredentials(
        AiSettings(
          baseUrl: saved.settings.baseUrl,
          model: saved.settings.model,
          hasKey: saved.apiKey.isNotEmpty,
          format: saved.settings.format,
          revision: const Uuid().v4(),
        ),
        saved.apiKey,
      ),
    );
  }

  Future<AiSettings> clear(String owner) async {
    // Replacing the single item removes the secret and records an empty
    // tombstone, so example values never silently reappear after clearing.
    return write(
      owner,
      AiCredentials(AiSettings(revision: const Uuid().v4()), ''),
    );
  }
}
