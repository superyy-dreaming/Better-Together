import 'dart:async';

import 'package:better_together/ui/app_appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(
    AppearanceStore store, {
    AppearanceLoadResult? initial,
  }) {
    final container = ProviderContainer(
      overrides: [
        appearanceStoreProvider.overrideWithValue(store),
        if (initial != null)
          initialAppearanceProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('new installation retains classic appearance without writing', () async {
    final store = _MemoryStore();
    final container = containerFor(store);
    await container.read(appearanceProvider.notifier).ready;

    expect(container.read(appearanceProvider), AppAppearance.classic);
    expect(container.read(appearanceStatusProvider).loading, isFalse);
    expect(container.read(appearanceStatusProvider).error, isNull);
    expect(store.writes, 0);
  });

  test('saved cartoon appearance is restored before the first frame', () async {
    final store = _MemoryStore('tuantuan');
    final initial = await loadAppearance(store);
    final container = containerFor(store, initial: initial);

    expect(container.read(appearanceProvider), AppAppearance.tuantuan);
    expect(container.read(appearanceStatusProvider).loading, isFalse);
    await container.read(appearanceProvider.notifier).ready;
    expect(store.reads, 1);
  });

  test(
    'both appearance choices persist through a new application root',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesAppearanceStore();
      final first = containerFor(store, initial: await loadAppearance(store));
      expect(
        await first
            .read(appearanceProvider.notifier)
            .setAppearance(AppAppearance.tuantuan),
        isTrue,
      );

      final second = containerFor(store, initial: await loadAppearance(store));
      expect(second.read(appearanceProvider), AppAppearance.tuantuan);
      expect(
        await second
            .read(appearanceProvider.notifier)
            .setAppearance(AppAppearance.classic),
        isTrue,
      );

      final third = containerFor(store, initial: await loadAppearance(store));
      expect(third.read(appearanceProvider), AppAppearance.classic);
      expect(
        (await SharedPreferences.getInstance()).getString(
          SharedPreferencesAppearanceStore.preferenceKey,
        ),
        'classic',
      );
    },
  );

  test('failed save keeps the current UI and allows a later retry', () async {
    final store = _MemoryStore('classic')..failWrite = true;
    final container = containerFor(
      store,
      initial: const AppearanceLoadResult(),
    );
    final controller = container.read(appearanceProvider.notifier);

    expect(await controller.setAppearance(AppAppearance.tuantuan), isFalse);
    expect(container.read(appearanceProvider), AppAppearance.classic);
    expect(store.value, 'classic');
    expect(container.read(appearanceStatusProvider).saving, isFalse);
    expect(container.read(appearanceStatusProvider).error, contains('未保存'));

    store.failWrite = false;
    expect(await controller.setAppearance(AppAppearance.tuantuan), isTrue);
    expect(container.read(appearanceProvider), AppAppearance.tuantuan);
    expect(store.value, 'tuantuan');
    expect(container.read(appearanceStatusProvider).error, isNull);
  });

  test('an old pending read cannot replace a newly saved selection', () async {
    final pending = Completer<String?>();
    final store = _MemoryStore('classic')..pendingRead = pending;
    final container = containerFor(store);
    final controller = container.read(appearanceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    expect(store.reads, 1);

    expect(await controller.setAppearance(AppAppearance.tuantuan), isTrue);
    pending.complete('classic');
    await controller.ready;

    expect(container.read(appearanceProvider), AppAppearance.tuantuan);
    expect(store.value, 'tuantuan');
  });

  test('selection before the deferred load begins owns the result', () async {
    final store = _MemoryStore('classic');
    final container = containerFor(store);
    final controller = container.read(appearanceProvider.notifier);
    final saving = controller.setAppearance(AppAppearance.tuantuan);
    await controller.ready;
    expect(await saving, isTrue);

    expect(store.reads, 0);
    expect(container.read(appearanceProvider), AppAppearance.tuantuan);
    expect(container.read(appearanceStatusProvider).error, isNull);
  });

  test('read errors remain visible until a successful recovery', () async {
    final store = _MemoryStore('tuantuan')..failRead = true;
    final container = containerFor(store);
    final controller = container.read(appearanceProvider.notifier);
    await controller.ready;

    expect(container.read(appearanceProvider), AppAppearance.classic);
    expect(container.read(appearanceStatusProvider).error, contains('暂未读取'));
    expect(store.value, 'tuantuan');
    expect(store.writes, 0);

    store.failRead = false;
    await controller.retryLoad();
    expect(container.read(appearanceProvider), AppAppearance.tuantuan);
    expect(container.read(appearanceStatusProvider).error, isNull);
  });

  test(
    'saving disables competing writes and preserves write ordering',
    () async {
      final pending = Completer<void>();
      final store = _MemoryStore('classic')..pendingWrite = pending;
      final container = containerFor(
        store,
        initial: const AppearanceLoadResult(),
      );
      final controller = container.read(appearanceProvider.notifier);
      final saving = controller.setAppearance(AppAppearance.tuantuan);

      expect(container.read(appearanceStatusProvider).saving, isTrue);
      expect(container.read(appearanceProvider), AppAppearance.classic);
      expect(await controller.setAppearance(AppAppearance.classic), isFalse);
      await controller.retryLoad();
      expect(store.writes, 1);
      expect(store.reads, 0);

      pending.complete();
      expect(await saving, isTrue);
      expect(container.read(appearanceProvider), AppAppearance.tuantuan);
      expect(container.read(appearanceStatusProvider).saving, isFalse);
    },
  );

  test(
    'unsupported saved appearance is visible and not silently replaced',
    () async {
      final store = _MemoryStore('future-appearance');
      final container = containerFor(store);
      final controller = container.read(appearanceProvider.notifier);
      await controller.ready;

      expect(container.read(appearanceProvider), AppAppearance.classic);
      expect(container.read(appearanceStatusProvider).error, contains('暂不支持'));
      expect(store.value, 'future-appearance');
      expect(store.writes, 0);

      expect(await controller.setAppearance(AppAppearance.classic), isTrue);
      expect(store.value, 'classic');
      expect(container.read(appearanceStatusProvider).error, isNull);
    },
  );

  test(
    'disposing before a deferred read does not start storage work',
    () async {
      final store = _MemoryStore('tuantuan');
      final container = ProviderContainer(
        overrides: [appearanceStoreProvider.overrideWithValue(store)],
      );
      final ready = container.read(appearanceProvider.notifier).ready;
      container.dispose();
      await ready;
      expect(store.reads, 0);
    },
  );
}

class _MemoryStore implements AppearanceStore {
  _MemoryStore([this.value]);

  String? value;
  bool failRead = false;
  bool failWrite = false;
  int reads = 0;
  int writes = 0;
  Completer<String?>? pendingRead;
  Completer<void>? pendingWrite;

  @override
  Future<String?> read() async {
    reads++;
    if (failRead) throw StateError('Storage unavailable');
    return pendingRead?.future ?? value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    if (failWrite) throw StateError('Storage unavailable');
    if (pendingWrite != null) await pendingWrite!.future;
    this.value = value;
  }
}
