import 'dart:async';
import 'dart:io' as io;

import 'package:better_together/data/media_cache.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:file/local.dart';
import 'package:flutter_test/flutter_test.dart';

class AccessRepository extends DemoRepository {
  String? user = 'owner';
  bool allowed = true;
  int reads = 0;
  final sessions = StreamController<bool>.broadcast();
  @override
  String? get currentUserId => user;
  @override
  Stream<bool> get authChanges => sessions.stream;
  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    expect(action, 'media_urls');
    reads++;
    return {
      'items': jsonList(args['refs'])
          .map(
            (v) => {
              ...jsonObject(v),
              'allowed': allowed,
              'url': allowed ? 'https://private.example/signed-$reads' : null,
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
          )
          .toList(),
    };
  }
}

class ByteCache extends Fake implements BaseCacheManager {
  ByteCache(this.dir);
  final io.Directory dir;
  final rows = <String, FileInfo>{};
  int downloads = 0, clears = 0;
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => rows[key];
  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloads++;
    final file = const LocalFileSystem().file('${dir.path}/$downloads.jpg');
    await file.writeAsBytes([1, 2, 3]);
    return rows[key!] = FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 7)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {
    final row = rows.remove(key);
    if (row != null && await row.file.exists()) await row.file.delete();
  }

  @override
  Future<void> emptyCache() async {
    clears++;
    for (final key in rows.keys.toList()) {
      await removeFile(key);
    }
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory dir;
  late AccessRepository repo;
  late ByteCache disk;
  late PrivateMediaCache cache;
  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('bt-cache-test');
    repo = AccessRepository();
    disk = ByteCache(dir);
    cache = PrivateMediaCache(
      repo,
      cache: disk,
      cacheDirectory: () async => dir,
    );
  });
  tearDown(() async {
    cache.dispose();
    await repo.sessions.close();
    await dir.delete(recursive: true);
  });
  test(
    'stable identity reuses bytes after the signed grant is renewed',
    () async {
      await cache.get('media:one');
      expect(disk.downloads, 1);
      expect(repo.reads, 1);
      cache.invalidateAccess();
      await cache.get('media:one');
      expect(repo.reads, 2);
      expect(disk.downloads, 1);
    },
  );
  test(
    'parallel references batch grants and duplicate image downloads coalesce',
    () async {
      await Future.wait([
        cache.get('media:one'),
        cache.get('media:one'),
        cache.get('media:two'),
      ]);
      expect(repo.reads, 1);
      expect(disk.downloads, 2);
    },
  );
  test('revoked access is checked before returning disk bytes', () async {
    await cache.get('media:one');
    repo.allowed = false;
    cache.invalidateAccess();
    await expectLater(cache.get('media:one'), throwsA(isA<AppException>()));
    expect(disk.rows, isEmpty);
  });
  test(
    'account switch clears cached bytes and notifies rendered images',
    () async {
      await cache.get('media:one');
      int invalidations = 0;
      cache.addListener(() => invalidations++);
      repo.user = 'other';
      repo.sessions.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(disk.clears, 1);
      expect(disk.rows, isEmpty);
      expect(invalidations, 1);
      await cache.get('media:one');
      expect(disk.rows.keys.single, startsWith('other|'));
    },
  );
}
