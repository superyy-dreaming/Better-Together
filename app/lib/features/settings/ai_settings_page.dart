import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/app_controller.dart';
import '../../data/app_repository.dart';
import '../../domain/ai_settings.dart';
import '../../domain/models.dart';
import '../../ui/design.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  late final AppRepository _repository;
  StreamSubscription<bool>? _auth;
  AiSettings? _saved;
  String? _owner, _error, _message, _operation;
  String _protocol = 'chat_completions';
  bool _enabled = false, _loading = true, _dirty = false, _confirming = false;
  int _request = 0;

  bool get _busy => _loading || _operation != null || _confirming;
  bool get _addressChanged =>
      _saved?.hasKey == true &&
      normalizedAiBaseUrl(_baseUrl.text) !=
          normalizedAiBaseUrl(_saved!.baseUrl);

  @override
  void initState() {
    super.initState();
    _repository = ref.read(repositoryProvider);
    _owner = _repository.currentUserId;
    _auth = _repository.authChanges.listen((_) {
      if (!mounted || _owner == _repository.currentUserId) return;
      _request++;
      _owner = _repository.currentUserId;
      _apiKey.clear();
      _baseUrl.clear();
      _model.clear();
      setState(() {
        _saved = null;
        _operation = null;
        _message = null;
        _dirty = false;
      });
      unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _auth?.cancel();
    _apiKey.clear();
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  bool _isCurrent(int request) =>
      mounted && request == _request && _owner == _repository.currentUserId;

  String _safeError(Object issue) {
    var message = issue is AppException ? issue.message : '暂时无法完成操作，请检查网络后重试。';
    final secret = _apiKey.text.trim();
    if (secret.isNotEmpty) message = message.replaceAll(secret, '［密钥已隐藏］');
    return message;
  }

  void _apply(AiSettings value) {
    _saved = value;
    _baseUrl.text = value.baseUrl;
    _model.text = value.model;
    _protocol = value.protocol;
    _enabled = value.enabled;
    _apiKey.clear();
    _dirty = false;
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.action('get_ai_settings');
      final value = AiSettings.fromJson(jsonObject(result));
      if (_isCurrent(request)) setState(() => _apply(value));
    } catch (issue) {
      if (_isCurrent(request)) setState(() => _error = _safeError(issue));
    } finally {
      if (_isCurrent(request)) setState(() => _loading = false);
    }
  }

  void _changed() {
    setState(() {
      _dirty = true;
      _message = null;
      _error = null;
    });
  }

  bool _allowRealService() {
    if (!_repository.isSignedIn || _owner != _repository.currentUserId) {
      setState(() => _error = '账号状态已改变，请返回后重新打开 AI 设置。');
      return false;
    }
    if (!_repository.isDemo) return true;
    setState(() {
      _error = '请先连接真实账号，再保存或测试 AI 服务。演示模式不会保存密钥，也不会发送请求。';
      _message = null;
    });
    return false;
  }

  Future<void> _submit({required bool test}) async {
    if (_busy || !_allowRealService()) return;
    if (!_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final args = <String, Object?>{
      'enabled': _enabled,
      'base_url': _baseUrl.text.trim(),
      'protocol': _protocol,
      'model': _model.text.trim(),
      if (_apiKey.text.trim().isNotEmpty) 'api_key': _apiKey.text.trim(),
    };
    await _perform(test ? 'test_ai_settings' : 'save_ai_settings', args, (
      result,
    ) {
      if (test) {
        if (jsonObject(result)['ok'] != true) {
          throw const AppException('invalid_response', '连接测试未通过，请核对服务配置。');
        }
        _message = jsonObject(result)['format'] == 'json_object'
            ? '连接测试通过：图片与 JSON Object，本机严格校验。测试未保存配置。'
            : '连接测试通过：图片与严格 JSON Schema。测试未保存配置。';
      } else {
        _apply(AiSettings.fromJson(jsonObject(result)));
        _message = _saved!.enabled
            ? '已保存，后续识别将使用你的自定义服务。'
            : '已保存配置，AI 当前停用。仍可正常打卡。';
      }
    });
  }

  Future<void> _perform(
    String action,
    JsonMap args,
    void Function(Object?) apply,
  ) async {
    final request = ++_request;
    setState(() {
      _operation = action;
      _error = null;
      _message = null;
    });
    try {
      final result = await _repository.action(action, args: args);
      if (_isCurrent(request)) setState(() => apply(result));
    } catch (issue) {
      if (_isCurrent(request)) setState(() => _error = _safeError(issue));
    } finally {
      if (_isCurrent(request)) setState(() => _operation = null);
    }
  }

  Future<void> _disable() async {
    if (_busy || _saved?.enabled != true || !_allowRealService()) return;
    await _perform(
      'save_ai_settings',
      {..._saved!.withoutKey, 'enabled': false},
      (result) {
        _apply(AiSettings.fromJson(jsonObject(result)));
        _message = 'AI 已停用，配置和密钥保留在本机。照片仍可盖章。';
      },
    );
  }

  Future<void> _clear() async {
    if (_busy || !_allowRealService()) return;
    final owner = _owner;
    setState(() => _confirming = true);
    final accepted = await confirmAction(
      context,
      '清除自定义 AI 配置？',
      '将清除这台设备上当前账号的服务地址、模型和密钥。AI 将停用，已有打卡和纪要保留。',
      accept: '清除配置',
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!accepted || _busy || owner != _repository.currentUserId) return;
    await _perform('delete_ai_settings', const {}, (result) {
      if (jsonObject(result)['deleted'] != true) {
        throw const AppException('invalid_response', '配置尚未确认清除，请重试。');
      }
      _apply(AiSettings.fromJson(jsonObject(result)));
      _message = '已清除本机配置。可以先打卡，重新配置后补生成。';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 识别')),
    body: _loading
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator.adaptive(),
                SizedBox(height: 16),
                Text('正在读取 AI 配置'),
              ],
            ),
          )
        : _saved == null
        ? PageBody(
            children: [
              EmptyMessage(
                title: '暂时无法读取配置',
                body: _error ?? '请重新连接后再试。',
                action: FilledButton(
                  onPressed: _load,
                  child: const Text('重新读取'),
                ),
              ),
            ],
          )
        : Form(
            key: _form,
            child: PageBody(
              children: [
                // Keep all fields mounted so Form.validate also checks fields
                // outside the viewport and preserves their inline errors.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Paper(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _saved!.enabled
                                ? '本机 AI 已启用'
                                : _saved!.hasKey
                                ? 'AI 已停用'
                                : '尚未配置 AI',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _saved!.enabled
                                ? '识别用压缩图由这台设备直接发送到你填写的站点。密钥只保存在本机安全存储，不会上传到 Better Together 服务器。'
                                : '应用不提供默认 AI 服务。未配置或识别失败时仍可拍照、归档和盖章，纪要可稍后补生成。',
                          ),
                        ],
                      ),
                    ),
                    if (_repository.isDemo) ...[
                      const SizedBox(height: 16),
                      const Text('演示模式，配置不会保存。请连接真实账号后再填写密钥。'),
                    ],
                    const SectionTitle('连接你的服务'),
                    const Text(
                      '启用后，你的照片、纪要内容会发送给下方指定服务。请使用你信任的服务商，并了解其数据保留方式。',
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      key: const ValueKey('ai-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用 AI 识别'),
                      subtitle: const Text('修改后点击保存才会生效'),
                      value: _enabled,
                      onChanged: _busy
                          ? null
                          : (value) {
                              _enabled = value;
                              _changed();
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('ai-base-url'),
                      controller: _baseUrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '服务地址',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: 'https://api.example.com/v1',
                        helperText: '填写 HTTPS 接口基础地址，例如以 /v1 结尾。',
                        helperMaxLines: 3,
                        errorMaxLines: 3,
                      ),
                      validator: validateAiBaseUrl,
                      onChanged: (_) => _changed(),
                    ),
                    if (_addressChanged) ...[
                      const SizedBox(height: 8),
                      const Text('服务地址已改变，请填写该服务的新密钥。已有密钥不会发送到新地址。'),
                    ],
                    const SizedBox(height: 20),
                    const Text('Chat Completions，支持图片与结构化 JSON。'),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const ValueKey('ai-model'),
                      controller: _model,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '模型名称',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: '服务商提供的完整模型名称',
                        errorMaxLines: 3,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请填写模型名称';
                        }
                        if (value.trim().length > 200 ||
                            RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
                          return '模型名称格式不正确，请核对';
                        }
                        return null;
                      },
                      onChanged: (_) => _changed(),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const ValueKey('ai-api-key'),
                      controller: _apiKey,
                      enabled: !_busy && !_repository.isDemo,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [],
                      decoration: InputDecoration(
                        labelText: 'API 密钥',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: _saved!.hasKey
                            ? '已保存密钥，留空可继续使用'
                            : '填写服务商提供的 API 密钥',
                        helperText: _saved!.hasKey
                            ? '已有密钥不会回显。仅服务地址未改变时，留空才会沿用。'
                            : '密钥仅存 iOS Keychain 或 Android Keystore 保护的本机存储，不上传服务器。',
                        helperMaxLines: 4,
                        errorMaxLines: 3,
                      ),
                      validator: (value) {
                        final key = value?.trim() ?? '';
                        if (key.isEmpty &&
                            (!_saved!.hasKey || _addressChanged)) {
                          return _addressChanged
                              ? '地址已改变，请填写新密钥'
                              : '请填写 API 密钥';
                        }
                        if (key.length > 8192 ||
                            RegExp(r'[\x00-\x20\x7f]').hasMatch(key)) {
                          return '密钥不能包含空格或控制字符';
                        }
                        return null;
                      },
                      onChanged: (_) => _changed(),
                    ),
                    const SizedBox(height: 20),
                    const Text('测试连接只发送一张合成图片，检查图片识别和结构化返回，不使用你的照片，也不会保存配置。'),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey('ai-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          key: const ValueKey('ai-message'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    OutlinedButton(
                      key: const ValueKey('ai-test'),
                      onPressed: _busy ? null : () => _submit(test: true),
                      child: Text(
                        _operation == 'test_ai_settings' ? '正在测试连接' : '测试连接',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('ai-save'),
                      onPressed: _busy ? null : () => _submit(test: false),
                      child: Text(
                        _operation == 'save_ai_settings' ? '正在保存' : '保存配置',
                      ),
                    ),
                    if (_dirty) ...[
                      const SizedBox(height: 8),
                      const Text('当前修改尚未保存。'),
                    ],
                    if (_saved!.enabled) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        key: const ValueKey('ai-disable'),
                        onPressed: _busy ? null : _disable,
                        child: const Text('停用自定义服务，保留配置'),
                      ),
                    ],
                    if (_saved!.hasKey ||
                        _saved!.baseUrl.isNotEmpty ||
                        _saved!.model.isNotEmpty)
                      TextButton(
                        key: const ValueKey('ai-clear'),
                        onPressed: _busy ? null : _clear,
                        child: Text(
                          _operation == 'delete_ai_settings'
                              ? '正在清除'
                              : '清除自定义配置和密钥',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
  );
}
