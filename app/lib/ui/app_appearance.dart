import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device preference, deliberately independent of the signed-in account.
enum AppAppearance {
  classic,
  tuantuan;

  String get label => switch (this) {
    classic => '经典纸面',
    tuantuan => '团团陪你',
  };

  String get description => switch (this) {
    classic => '米纸、深林绿与盖章记录',
    tuantuan => '卡通伙伴、青草绿与圆润按钮',
  };
}

abstract interface class AppearanceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesAppearanceStore implements AppearanceStore {
  static const preferenceKey = 'better_together.appearance.v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(preferenceKey);

  @override
  Future<void> write(String value) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      preferenceKey,
      value,
    );
    if (!saved) throw StateError('Appearance preference was not saved');
  }
}

class AppearanceLoadResult {
  const AppearanceLoadResult({
    this.appearance = AppAppearance.classic,
    this.error,
  });

  final AppAppearance appearance;
  final String? error;
}

/// Production main awaits this before runApp to avoid flashing the old theme.
/// Read failures are visible through appearanceStatusProvider and are never
/// written back over the existing preference automatically.
Future<AppearanceLoadResult> loadAppearance(AppearanceStore store) async {
  try {
    final value = await store.read();
    if (value == null) return const AppearanceLoadResult();
    for (final appearance in AppAppearance.values) {
      if (appearance.name == value) {
        return AppearanceLoadResult(appearance: appearance);
      }
    }
    return const AppearanceLoadResult(
      error: '当前版本暂不支持已保存的外观，正在使用经典纸面。请选择外观后重新保存。',
    );
  } catch (_) {
    return const AppearanceLoadResult(error: '外观偏好暂未读取，正在使用经典纸面。可以重试，或重新选择外观。');
  }
}

final appearanceStoreProvider = Provider<AppearanceStore>(
  (ref) => SharedPreferencesAppearanceStore(),
);

final initialAppearanceProvider = Provider<AppearanceLoadResult?>(
  (ref) => null,
);

class AppearanceStatus {
  const AppearanceStatus({
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final bool loading;
  final bool saving;
  final String? error;
}

final appearanceStatusProvider =
    NotifierProvider<AppearanceStatusController, AppearanceStatus>(
      AppearanceStatusController.new,
    );

class AppearanceStatusController extends Notifier<AppearanceStatus> {
  @override
  AppearanceStatus build() {
    final initial = ref.watch(initialAppearanceProvider);
    return AppearanceStatus(loading: initial == null, error: initial?.error);
  }

  void update(AppearanceStatus value) => state = value;
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppAppearance>(
      AppearanceController.new,
    );

class AppearanceController extends Notifier<AppAppearance> {
  int _revision = 0;
  Future<void> _initialLoad = Future<void>.value();

  Future<void> get ready => _initialLoad;

  @override
  AppAppearance build() {
    final revision = ++_revision;
    final initial = ref.watch(initialAppearanceProvider);
    if (initial != null) {
      _initialLoad = Future<void>.value();
      return initial.appearance;
    }
    _initialLoad = Future<void>.microtask(() => _load(revision));
    return AppAppearance.classic;
  }

  Future<void> _load(int revision) async {
    if (!ref.mounted || revision != _revision) return;
    final result = await loadAppearance(ref.read(appearanceStoreProvider));
    if (!ref.mounted || revision != _revision) return;
    state = result.appearance;
    ref
        .read(appearanceStatusProvider.notifier)
        .update(AppearanceStatus(error: result.error));
  }

  Future<void> retryLoad() async {
    if (ref.read(appearanceStatusProvider).saving) return;
    final revision = ++_revision;
    ref
        .read(appearanceStatusProvider.notifier)
        .update(const AppearanceStatus(loading: true));
    await _load(revision);
  }

  /// Commit the device preference before changing the visible theme. A failed
  /// write keeps the current UI and exposes recovery beside the selection.
  Future<bool> setAppearance(AppAppearance appearance) async {
    final status = ref.read(appearanceStatusProvider);
    if (status.saving) return false;
    if (appearance == state && !status.loading && status.error == null) {
      return true;
    }
    final revision = ++_revision;
    ref
        .read(appearanceStatusProvider.notifier)
        .update(const AppearanceStatus(saving: true));
    try {
      await ref.read(appearanceStoreProvider).write(appearance.name);
      if (!ref.mounted || revision != _revision) return false;
      state = appearance;
      ref
          .read(appearanceStatusProvider.notifier)
          .update(const AppearanceStatus());
      return true;
    } catch (_) {
      if (!ref.mounted || revision != _revision) return false;
      ref
          .read(appearanceStatusProvider.notifier)
          .update(const AppearanceStatus(error: '外观选择未保存，当前界面保持不变。请重新选择后重试。'));
      return false;
    }
  }
}
