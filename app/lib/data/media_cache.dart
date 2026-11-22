import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import 'app_controller.dart';
import 'app_repository.dart';

final mediaCacheProvider = Provider<PrivateMediaCache>((ref) {
  final service = PrivateMediaCache(ref.watch(repositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Authorization and bytes have separate lifetimes. Signed URLs are never cache
/// keys, and an on-disk image alone never authorizes a new session to display it.
class PrivateMediaCache extends ChangeNotifier {
  PrivateMediaCache(
    this.repository, {
    BaseCacheManager? cache,
    this.cacheDirectory,
  }) : _manager = cache {
    _user = repository.currentUserId;
    _auth = repository.authChanges.listen((_) {
      if (_user != repository.currentUserId) {
        _user = repository.currentUserId;
        unawaited(
          clear().catchError((Object error) {
            debugPrint('private_media_cleanup_pending: ${error.runtimeType}');
          }),
        );
      }
    });
  }
  final AppRepository repository;
  final Future<Directory> Function()? cacheDirectory;
  Future<void>? _pruning;
  BaseCacheManager? _manager;
  BaseCacheManager get _cache => _manager ??= CacheManager(
    Config(
      'better_together_private_v2',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 1500,
    ),
  );
  final _access = <String, JsonMap>{};
  final _authorizing = <String, Future<JsonMap>>{};
  final _pending = <String, Completer<JsonMap>>{};
  final _downloads = <String, Future<File>>{};
  StreamSubscription<bool>? _auth;
  Timer? _batch;
  String? _user;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _cleanup = Future.value();

  Future<JsonMap> _authorize(String reference, String variant) {
    final key = '$reference/$variant';
    final cached = _access[key];
    if (cached != null &&
        dateValue(cached['expires_at'])
            .isAfter(DateTime.now().add(const Duration(seconds: 20)))) {
      return Future.value(cached);
    }
    if (_authorizing.containsKey(key)) return _authorizing[key]!;
    final result = Completer<JsonMap>();
    _pending[key] = result;
    _batch ??= Timer(const Duration(milliseconds: 16), _flush);
    late final Future<JsonMap> work;
    work = result.future.whenComplete(() {
      if (identical(_authorizing[key], work)) _authorizing.remove(key);
    });
    _authorizing[key] = work;
    return work;
  }

  Future<void> _flush() async {
    _batch = null;
    final batch = Map<String, Completer<JsonMap>>.of(_pending);
    _pending.clear();
    final epoch = _epoch;
    final entries = batch.entries.toList();
    for (var start = 0; start < entries.length; start += 50) {
      final chunk = entries.skip(start).take(50).toList();
      try {
        final result = jsonObject(
          await repository.action(
            'media_urls',
            args: {
              'refs': chunk.map((e) {
                final split = e.key.lastIndexOf('/');
                return {
                  'ref': e.key.substring(0, split),
                  'variant': e.key.substring(split + 1),
                };
              }).toList(),
            },
          ),
        );
        final rows = {
          for (final item in jsonList(result['items']))
            '${jsonObject(item)['ref']}/${jsonObject(item)['variant']}':
                jsonObject(item),
        };
        for (final entry in chunk) {
          if (_disposed || epoch != _epoch) {
            throw const AppException('session_changed', '图片访问权限已更新');
          }
          final row = rows[entry.key];
          if (row == null || row['allowed'] != true || row['url'] == null) {
            entry.value.completeError(
              const AppException('media_forbidden', '照片已删除或不再可见'),
            );
          } else {
            _access[entry.key] = row;
            entry.value.complete(row);
          }
        }
      } catch (error, stack) {
        for (final entry in chunk) {
          if (!entry.value.isCompleted) entry.value.completeError(error, stack);
        }
      }
    }
  }

  Future<File> get(
    String reference, {
    String variant = 'thumbnail',
    String version = '1',
  }) async {
    final user = repository.currentUserId;
    if (user == null) throw const AppException('unauthenticated', '请先登录');
    final epoch = _epoch;
    await _cleanup;
    final key = '$user|$reference|$version|$variant';
    if (_downloads[key] != null) return _downloads[key]!;
    final future = _get(reference, variant, key, epoch);
    _downloads[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_downloads[key], future)) _downloads.remove(key);
    }
  }

  Future<File> _get(
    String reference,
    String variant,
    String key,
    int epoch,
  ) async {
    late JsonMap access;
    try {
      access = await _authorize(reference, variant);
    } on AppException catch (error) {
      if (error.code == 'media_forbidden') await _cache.removeFile(key);
      rethrow;
    }
    if (epoch != _epoch || _disposed) {
      throw const AppException('session_changed', '图片访问权限已更新');
    }
    final cached = await _cache.getFileFromCache(key);
    if (cached != null &&
        await cached.file.exists() &&
        DateTime.now().difference((await cached.file.stat()).modified) <
            const Duration(days: 7)) {
      if (epoch != _epoch || _disposed) {
        throw const AppException('session_changed', '图片访问权限已更新');
      }
      return File(cached.file.path);
    }
    try {
      final result = await _cache.downloadFile(
        stringValue(access['url']),
        key: key,
      );
      if (epoch != _epoch || _disposed) {
        await _cache.removeFile(key);
        throw const AppException('session_changed', '图片访问权限已更新');
      }
      _pruning ??= _prune().whenComplete(() => _pruning = null);
      await _pruning;
      return File(result.file.path);
    } catch (_) {
      _access.remove('$reference/$variant');
      rethrow;
    }
  }

  Future<void> _prune() async {
    final dir = cacheDirectory != null
        ? await cacheDirectory!()
        : Directory(
            '${(await getTemporaryDirectory()).path}/better_together_private_v2',
          );
    if (!await dir.exists()) return;
    final rows = <(File, FileStat)>[];
    await for (final file in dir.list()) {
      if (file is File) rows.add((file, await file.stat()));
    }
    rows.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var total = rows.fold<int>(0, (n, r) => n + r.$2.size);
    for (final row in rows) {
      if (total <= 200 * 1024 * 1024 &&
          DateTime.now().difference(row.$2.modified) <
              const Duration(days: 7)) {
        break;
      }
      await row.$1.delete();
      total -= row.$2.size;
    }
  }

  void invalidateAccess() {
    _epoch++;
    _access.clear();
    _downloads.clear();
    _authorizing.clear();
    _batch?.cancel();
    _batch = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const AppException('session_changed', '图片访问权限已更新'),
        );
      }
    }
    _pending.clear();
  }

  Future<void> clear() {
    invalidateAccess();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _cleanup = _cleanup.catchError((Object _) {}).then((_) async {
      await _cache.emptyCache();
    });
    notifyListeners();
    return _cleanup;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _batch?.cancel();
    _auth?.cancel();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const AppException('disposed', '图片视图已关闭'));
      }
    }
    _pending.clear();
    if (_manager != null) unawaited(_manager!.dispose());
    super.dispose();
  }
}
