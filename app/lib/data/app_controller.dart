import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import 'app_repository.dart';
import 'media_cache.dart';

/// Main chooses production or explicitly requested demo. Missing configuration
/// is a setup screen, never an implicit switch to sample data.
final repositoryProvider = Provider<AppRepository>(
  (ref) => throw StateError('AppRepository must be injected'),
);

final authStateProvider = StreamProvider<bool>((ref) async* {
  final repository = ref.watch(repositoryProvider);
  yield repository.isSignedIn;
  yield* repository.authChanges;
});

final appControllerProvider =
    NotifierProvider<AppController, AsyncValue<AppSnapshot>>(AppController.new);
final actionErrorProvider = NotifierProvider<ActionError, String?>(
  ActionError.new,
);

final syncErrorProvider = NotifierProvider<ActionError, String?>(
  ActionError.new,
);
final syncBusyProvider = NotifierProvider<SyncBusy, bool>(SyncBusy.new);

class SyncBusy extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

class ActionError extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

class AppController extends Notifier<AsyncValue<AppSnapshot>>
    with WidgetsBindingObserver {
  AppRepository get _repository => ref.read(repositoryProvider);
  int _readRevision = 0;
  int _sessionEpoch = 0;
  String? _sessionId;
  StreamSubscription<void>? _changes;
  Timer? _debounce;
  Future<void>? _refreshing;
  bool _refreshAgain = false;
  final _pageRequests = <String, Future<JsonMap>>{};
  final _pageDirty = <String>{};
  final _loadedCollections = <String>{};
  Future<void> _initialLoad = Future.value();
  Future<AppSnapshot> get ready async {
    await _initialLoad;
    return state.requireValue;
  }

  @override
  AsyncValue<AppSnapshot> build() {
    _readRevision++;
    final repository = ref.watch(repositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _sessionId = repository.currentUserId;
    final auth = repository.authChanges.listen((_) {
      final next = repository.currentUserId;
      if (next == _sessionId) return;
      _sessionId = next;
      _sessionEpoch++;
      _readRevision++;
      _refreshing = null;
      _refreshAgain = false;
      _pageRequests.clear();
      _pageDirty.clear();
      _loadedCollections.clear();
      _debounce?.cancel();

      unawaited(_changes?.cancel());
      _changes = null;
      // Drop the old account snapshot immediately, including Riverpod's
      // previous-data slot. Network recovery must never retain another user.
      state = next == null
          ? AsyncError(
              const AppException('unauthenticated', '请先登录'),
              StackTrace.current,
            )
          : const AsyncLoading<AppSnapshot>();
      if (next != null) unawaited(refresh().catchError((Object _) {}));
    });
    ref.onDispose(() {
      _readRevision++;
      WidgetsBinding.instance.removeObserver(this);
      _debounce?.cancel();

      unawaited(auth.cancel());
      unawaited(_changes?.cancel());
      _changes = null;
    });
    if (_sessionId == null) {
      return AsyncError(
        const AppException('unauthenticated', '请先登录'),
        StackTrace.current,
      );
    }
    _initialLoad = Future<void>.microtask(() async {
      try {
        await refresh();
      } catch (_) {
        /* The explicit AsyncError is visible. */
      }
    });
    return const AsyncLoading<AppSnapshot>();
  }

  void _startRealtime(AppRepository repository) {
    if (_changes != null || !repository.isSignedIn) return;
    _changes = repository.changes.listen(
      (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () async {
          if (!ref.mounted || !repository.isSignedIn) return;
          try {
            final scopes = repository is ScopedRepository
                ? (repository as ScopedRepository).takeInvalidatedCollections()
                : <String>{};
            if (scopes.contains('membership')) {
              _discardSharedData();
              await _clearMedia();
            }
            await refresh();
            for (final collection in scopes.intersection(_loadedCollections)) {
              await loadPage(collection, revalidate: true);
            }
          } catch (_) {
            // refresh exposes the issue while retaining the latest snapshot.
          }
        });
      },
      onError: (Object error) {
        if (ref.mounted && repository.isSignedIn) {
          ref.read(syncErrorProvider.notifier).set(error.toString());
        }
      },
    );
  }

  Future<void> refresh() {
    if (_refreshing != null) {
      _refreshAgain = true;
      return _refreshing!;
    }
    final epoch = _sessionEpoch;
    ref.read(syncBusyProvider.notifier).set(true);
    final work = () async {
      do {
        _refreshAgain = false;
        await _refreshOnce();
      } while (_refreshAgain && ref.mounted && _sessionEpoch == epoch);
    }();
    _refreshing = work;
    return work.whenComplete(() {
      if (identical(_refreshing, work)) {
        _refreshing = null;
        if (ref.mounted) ref.read(syncBusyProvider.notifier).set(false);
      }
    });
  }

  Future<void> _refreshOnce() async {
    final revision = ++_readRevision;
    final session = _repository.currentUserId;
    if (session == null) {
      state = AsyncError(
        const AppException('unauthenticated', '请先登录'),
        StackTrace.current,
      );
      return;
    }
    final previous = state;
    if (!previous.hasValue) state = const AsyncLoading<AppSnapshot>();
    try {
      final snapshot = await _repository.bootstrap();
      if (!ref.mounted ||
          revision != _readRevision ||
          _repository.currentUserId != session) {
        return;
      }
      final old = state.asData?.value;
      final membershipChanged =
          old != null && _membershipKey(old) != _membershipKey(snapshot);
      if (membershipChanged) {
        await _clearMedia();
        if (!ref.mounted ||
            revision != _readRevision ||
            _repository.currentUserId != session) {
          return;
        }
        _loadedCollections.clear();
      }
      final json = snapshot.toJson();
      if (old != null &&
          !membershipChanged &&
          _repository is ScopedRepository) {
        json['checkins'] = _mergeRows(
          old.checkins.map((v) => v.toJson()).toList(),
          snapshot.checkins.map((v) => v.toJson()).toList(),
        );
        json['reports'] = old.reports.map((v) => v.toJson()).toList();
        json['overdue'] = old.overdue.map((v) => v.toJson()).toList();
        json['feed_ids'] = old.feedIds;
        json['history_ids'] = old.historyIds;
      }
      state = AsyncData(AppSnapshot.fromJson(json));
      _startRealtime(_repository);
      ref.read(syncErrorProvider.notifier).set(null);
    } catch (error, trace) {
      if (!ref.mounted ||
          revision != _readRevision ||
          _repository.currentUserId != session) {
        return;
      }
      final denied =
          error is AppException &&
          [
            'unauthenticated',
            'UNAUTHORIZED',
            'FORBIDDEN',
            'http_401',
            'http_403',
          ].contains(error.code);
      if (!previous.hasValue || denied) {
        state = AsyncError<AppSnapshot>(error, trace);
      }
      ref.read(syncErrorProvider.notifier).set(error.toString());
      rethrow;
    }
  }

  Future<Object?> act(String action, {JsonMap args = const {}}) async {
    ref.read(actionErrorProvider.notifier).set(null);
    try {
      final session = _repository.currentUserId;
      final result = await _repository.action(
        action,
        args: {
          ...args,
          if (_repository is ScopedRepository) 'response_version': 2,
        },
      );
      if (!ref.mounted || session != _repository.currentUserId) {
        throw const AppException('session_changed', '账号已切换，请重新打开页面');
      }
      final privacyChanged = [
        'leave_team',
        'manage_team',
        'delete_account',
      ].contains(action);
      if (privacyChanged) {
        _readRevision++;
        await _clearMedia();
        if (!ref.mounted || session != _repository.currentUserId) return result;
        _loadedCollections.clear();
        state = const AsyncLoading<AppSnapshot>();
      }
      final data = jsonObject(result);
      if (data['updated_profile'] is Map && state.hasValue) {
        final previous = state.requireValue;
        final value = previous.toJson();
        value['profile'] = {
          ...previous.profile.toJson(),
          ...jsonObject(data['updated_profile']),
        };
        state = AsyncData(AppSnapshot.fromJson(value));
      }
      if (data['updated_checkins'] is List) {
        _mergeCollection('record', jsonList(data['updated_checkins']));
      }
      if (action != 'delete_account') {
        if (_repository is ScopedRepository && !privacyChanged) {
          unawaited(refresh().catchError((Object _) {}));
        } else {
          try {
            await refresh();
          } catch (_) {
            /* A committed write stays committed. */
          }
        }
      }
      return result;
    } catch (error) {
      ref.read(actionErrorProvider.notifier).set(error.toString());
      rethrow;
    }
  }

  List<Object?> _mergeRows(List<Object?> previous, List<Object?> incoming) {
    final rows = <String, JsonMap>{
      for (final row in previous)
        stringValue(jsonObject(row)['id']): jsonObject(row),
    };
    for (final row in incoming) {
      final value = jsonObject(row);
      rows[stringValue(value['id'])] = value;
    }
    return rows.values.toList();
  }

  void _mergeCollection(
    String collection,
    List<Object?> rows, {
    bool replace = false,
  }) {
    final previous = state.asData?.value;
    if (previous == null) return;
    final key = ['history', 'record'].contains(collection)
        ? 'checkins'
        : collection;
    final value = previous.toJson();
    if (collection == 'checkins' || collection == 'history') {
      final idsKey = collection == 'history' ? 'history_ids' : 'feed_ids';
      final ids = rows.map((r) => stringValue(jsonObject(r)['id']));
      value[idsKey] = replace
          ? ids.toList()
          : {...jsonList(value[idsKey]), ...ids}.toList();
      value[key] = _mergeRows(jsonList(value[key]), rows);
    } else {
      value[key] = replace ? rows : _mergeRows(jsonList(value[key]), rows);
    }
    state = AsyncData(AppSnapshot.fromJson(value));
  }

  Future<JsonMap> loadPage(
    String collection, {
    String? query,
    String? category,
    String? status,
    String? cursor,
    String? month,
    bool append = false,
    bool revalidate = false,
  }) {
    final key = '$collection|$query|$category|$status|$cursor|$month';
    if (_pageRequests[key] != null) {
      if (revalidate) _pageDirty.add(key);
      return _pageRequests[key]!;
    }
    final session = _repository.currentUserId;
    final epoch = _sessionEpoch;
    final work = () async {
      late JsonMap page;
      do {
        _pageDirty.remove(key);
        page = jsonObject(
          await _repository.action(
            'read_page',
            args: {
              'collection': collection,
              'query': ?query,
              'category': ?category,
              'status': ?status,
              'cursor': ?cursor,
              'month': ?month,
            },
          ),
        );
        if (ref.mounted &&
            epoch == _sessionEpoch &&
            _repository.currentUserId == session) {
          _loadedCollections.add(collection);
          // Plans are independently paged by their list UI; today's scope stays intact.
          // Background first-page checks must retain later pages: their UI
          // cursor still points past those rows. Explicit refresh resets them.
          _mergeCollection(
            collection,
            jsonList(page['items']),
            replace:
                !append &&
                !revalidate &&
                [
                  'checkins',
                  'history',
                  'reports',
                  'overdue',
                  'notifications',
                ].contains(collection),
          );
        }
      } while (_pageDirty.contains(key) &&
          ref.mounted &&
          epoch == _sessionEpoch);
      return page;
    }();
    _pageRequests[key] = work;
    return work.whenComplete(() {
      if (identical(_pageRequests[key], work)) _pageRequests.remove(key);
    });
  }

  Future<void> ensureCheckin(String id) async {
    final session = _repository.currentUserId;
    try {
      final result = await _repository.action('get_checkin', args: {'id': id});
      if (ref.mounted && _repository.currentUserId == session) {
        _mergeCollection('record', [result]);
      }
    } on AppException catch (error) {
      if (ref.mounted &&
          _repository.currentUserId == session &&
          ['FORBIDDEN', 'http_403', '42501'].contains(error.code)) {
        final previous = state.asData?.value;
        if (previous != null) {
          final json = previous.toJson();
          json['checkins'] = previous.checkins
              .where((c) => c.id != id)
              .map((c) => c.toJson())
              .toList();
          state = AsyncData(AppSnapshot.fromJson(json));
          await _clearMedia();
        }
      }
      rethrow;
    }
  }

  String _membershipKey(AppSnapshot value) {
    final ids = value.team?.members.map((m) => m.id).toList() ?? <String>[];
    ids.sort();
    return '${value.team?.id}|${value.team?.visibilityEpoch}|${ids.join(',')}';
  }

  Future<void> _clearMedia() async {
    if (_repository is! ScopedRepository) return;
    try {
      await ref.read(mediaCacheProvider).clear();
    } catch (_) {
      // Access is revoked synchronously even if on-disk cleanup needs retry.
      if (ref.mounted) {
        ref.read(syncErrorProvider.notifier).set('图片缓存清理未完成，重新打开图片时会再次验证权限');
      }
    }
  }

  void _discardSharedData() {
    final value = state.asData?.value;
    if (value == null) return;
    final data = value.toJson();
    data['team'] = null;
    data['checkins'] = value.checkins
        .where((c) => c.userId == _sessionId)
        .map((c) => c.toJson())
        .toList();
    data['reports'] = <Object?>[];
    data['overdue'] = <Object?>[];
    state = AsyncData(AppSnapshot.fromJson(data));
  }

  Future<UploadedPhoto> upload(PhotoUpload photo) => _repository.upload(photo);

  Future<PhotoRecognition> recognize(PhotoRecognitionRequest photo) =>
      _repository.recognize(photo);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.mounted &&
        _repository.isSignedIn) {
      unawaited(refresh().catchError((Object _) {}));
    }
  }
}
