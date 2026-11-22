import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_repository.dart';
import '../domain/models.dart';

enum PushStatus { inactive, permissionNeeded, registering, ready, unavailable }

class PushState {
  const PushState(this.status, this.message);
  final PushStatus status;
  final String message;
}

/// Native APNs on iOS and JPush on Android. A failed push registration never
/// invalidates in-app notifications. Call requestPermission from a user action.
class PushService with WidgetsBindingObserver {
  static const _channel = MethodChannel('better_together/push');
  final state = ValueNotifier(const PushState(PushStatus.inactive, '应用内通知可用'));
  AppRepository? _repository;
  void Function(JsonMap)? _onOpen;
  StreamSubscription<bool>? _auth;
  String? _token, _registeredToken;
  bool _disposed = false;

  Future<void> start(
    AppRepository repository,
    void Function(JsonMap) onOpen,
  ) async {
    _repository = repository;
    _onOpen = onOpen;
    if (repository.isDemo || (!Platform.isIOS && !Platform.isAndroid)) return;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleNative);
    await _auth?.cancel();
    _auth = repository.authChanges.listen((signedIn) {
      if (signedIn) {
        unawaited(_startNative());
      } else {
        _registeredToken = null;
        unawaited(_stopNative());
      }
    });
    if (repository.isSignedIn) await _startNative();
  }

  Future<void> _startNative() async {
    try {
      final result = jsonObject(await _channel.invokeMethod<Object?>('start'));
      if (result['status'] == 'unconfigured') {
        _set(PushStatus.unavailable, '远程通知尚未配置，应用内通知仍可用');
      } else if (result['status'] == 'authorized') {
        _set(PushStatus.registering, '正在连接远程通知');
        final token = stringValue(result['token']);
        if (token.isNotEmpty) await _register(token);
      } else {
        _set(PushStatus.permissionNeeded, '可在这里开启系统通知，应用内通知仍可用');
      }
    } on PlatformException {
      _set(PushStatus.unavailable, '远程通知暂不可用，应用内通知仍可用');
    } on MissingPluginException {
      _set(PushStatus.unavailable, '此运行环境未启用远程通知');
    }
  }

  Future<bool> requestPermission() async {
    if (_repository == null || _repository!.isDemo) return false;
    try {
      final allowed =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (allowed) {
        await _startNative();
      } else {
        _set(PushStatus.permissionNeeded, '系统通知未开启，应用内通知仍可用');
      }
      return allowed;
    } on PlatformException catch (error) {
      _set(PushStatus.unavailable, error.message ?? '远程通知暂不可用');
      return false;
    } on MissingPluginException {
      _set(PushStatus.unavailable, '此运行环境未启用远程通知');
      return false;
    }
  }

  Future<void> _handleNative(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'token':
        final token = stringValue(call.arguments);
        if (token.isNotEmpty) await _register(token);
      case 'open':
        _onOpen?.call(jsonObject(call.arguments));
      case 'registrationError':
        _set(PushStatus.unavailable, stringValue(call.arguments, '远程通知暂不可用'));
    }
  }

  Future<void> _register(String token) async {
    final repository = _repository;
    _token = token;
    if (repository == null || !repository.isSignedIn || repository.isDemo) {
      return;
    }
    if (_registeredToken == token) {
      _set(PushStatus.ready, '系统通知已连接');
      return;
    }
    try {
      await repository.action(
        'register_device',
        args: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'provider': Platform.isIOS ? 'apns' : 'jpush',
          'token': token,
        },
      );
      _registeredToken = token;
      _set(PushStatus.ready, '系统通知已连接');
    } catch (_) {
      // Retry on app resume or explicit permission action; never mark the
      // business notification failed because its transport is unavailable.
      _set(PushStatus.unavailable, '远程通知尚未同步，下次打开应用会重试。应用内通知仍可用');
    }
  }

  /// Must be awaited before signing out, while the JWT can still remove the
  /// account/device binding. Failure is surfaced so the UI can explain it.
  Future<void> stop() async {
    final token = _token;
    if (token != null &&
        _repository?.isSignedIn == true &&
        !_repository!.isDemo) {
      await _repository!.action('unregister_device', args: {'token': token});
    }
    _registeredToken = null;
    await _stopNative();
  }

  Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      _set(PushStatus.unavailable, '系统通知暂停状态待确认');
    } on MissingPluginException {
      /* Unsupported runtime has no active device. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _repository?.isSignedIn == true &&
        _repository?.isDemo == false) {
      unawaited(_startNative());
    }
  }

  void _set(PushStatus status, String message) {
    if (!_disposed) state.value = PushState(status, message);
  }

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _auth?.cancel();
    _channel.setMethodCallHandler(null);
    state.dispose();
  }
}
