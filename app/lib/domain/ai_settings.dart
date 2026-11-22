import 'models.dart';

/// Device-only configuration metadata. Keys never belong in this public model.
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.baseUrl = '',
    this.protocol = 'chat_completions',
    this.model = '',
    this.hasKey = false,
    this.format = 'json_schema',
    this.revision = '',
  });

  final bool enabled, hasKey;
  final String baseUrl, protocol, model, format, revision;

  factory AiSettings.fromJson(JsonMap data) {
    if (data['enabled'] is! bool ||
        data['has_key'] is! bool ||
        data['base_url'] is! String ||
        data['model'] is! String ||
        data['protocol'] != 'chat_completions') {
      throw const FormatException('Invalid AI settings metadata');
    }
    return AiSettings(
      enabled: data['enabled']! as bool,
      hasKey: data['has_key']! as bool,
      baseUrl: data['base_url']! as String,
      protocol: data['protocol']! as String,
      model: data['model']! as String,
      format: stringValue(data['format'], 'json_schema'),
      revision: stringValue(data['revision']),
    );
  }

  JsonMap get withoutKey => {
    'enabled': enabled,
    'base_url': baseUrl,
    'protocol': protocol,
    'model': model,
    'format': format,
    'revision': revision,
  };
}

/// Chat Completions base address. Redirects are rejected by the device client.
String normalizedAiBaseUrl(String value) {
  var normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
  for (final suffix in ['/chat/completions', '/responses']) {
    if (normalized.endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length);
      break;
    }
  }
  return Uri.tryParse(normalized)?.toString() ?? normalized;
}

String? validateAiBaseUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return '请输入完整的 HTTPS 服务地址';
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    return '地址不能包含账号、密码、查询参数或片段';
  }
  if ((value?.length ?? 0) > 2048) return '服务地址过长，请核对';
  return null;
}
