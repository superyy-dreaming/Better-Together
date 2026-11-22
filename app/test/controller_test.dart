import 'dart:async';

import 'package:better_together/data/app_controller.dart';
import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppSnapshot snapshot(String name) => AppSnapshot(
  profile: UserProfile(id: 'owner', nickname: name),
);

class ControlledRepository extends DemoRepository {
  final updates = StreamController<void>.broadcast();
  final sessions = StreamController<bool>.broadcast();
  String? user = 'owner';
  final pending = <Completer<AppSnapshot>>[];
  AppSnapshot current = snapshot('原记录');
  bool queuedReads = false;
  bool failReads = false;
  int readCount = 0;
  JsonMap Function(JsonMap)? pageResponse;

  @override
  Stream<void> get changes => updates.stream;
  @override
  Stream<bool> get authChanges => sessions.stream;
  @override
  String? get currentUserId => user;
  @override
  bool get isSignedIn => user != null;

  @override
  Future<AppSnapshot> bootstrap() async {
    readCount++;
    if (failReads) throw const AppException('network', '网络暂不可用');
    if (!queuedReads) return current;
    final result = Completer<AppSnapshot>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<Object?> action(String action, {JsonMap args = const {}}) async {
    if (action == 'read_page' && pageResponse != null) {
      return pageResponse!(args);
    }
    return {'saved': true};
  }

  @override
  Future<void> dispose() async {
    await updates.close();
    await sessions.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledRepository repository;
  late ProviderContainer container;

  setUp(() async {
    repository = ControlledRepository();
    container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repository)],
    );
    await container.read(appControllerProvider.notifier).ready;
    // Initial auth status settles before triggering explicit reads.
    await Future<void>.delayed(Duration.zero);
    await container.read(appControllerProvider.notifier).ready;
  });

  tearDown(() async {
    container.dispose();
    await repository.dispose();
  });

  for (final collection in ['checkins', 'history', 'notifications']) {
    test(
      '$collection background revalidation keeps later pages while explicit refresh resets them',
      () async {
        var firstPageText = '原内容';
        repository.pageResponse = (args) {
          expect(args['collection'], collection);
          final nextPage = args['cursor'] == 'after-first';
          return {
            'items': [
              {
                'id': nextPage ? 'second' : 'first',
                'user_id': 'owner',
                'summary': nextPage ? '第二页内容' : firstPageText,
                'title': nextPage ? '第二页内容' : firstPageText,
                'created_at': nextPage
                    ? '2026-11-20T08:00:00Z'
                    : '2026-11-21T08:00:00Z',
              },
            ],
            'next_cursor': nextPage ? 'after-second' : 'after-first',
          };
        };
        final controller = container.read(appControllerProvider.notifier);
        List<String> visibleIds() {
          final current = container.read(appControllerProvider).requireValue;
          return switch (collection) {
            'checkins' => current.feedIds!,
            'history' => current.historyIds!,
            _ => current.notifications.map((item) => item.id).toList(),
          };
        }

        final first = await controller.loadPage(collection);
        expect(visibleIds(), ['first']);
        final second = await controller.loadPage(
          collection,
          cursor: first['next_cursor'] as String,
          append: true,
        );
        expect(second['next_cursor'], 'after-second');
        expect(visibleIds(), ['first', 'second']);

        firstPageText = '更新后的内容';
        await controller.loadPage(collection, revalidate: true);
        expect(visibleIds(), ['first', 'second']);
        final refreshed = container.read(appControllerProvider).requireValue;
        expect(
          collection == 'notifications'
              ? refreshed.notifications.firstWhere((item) => item.id == 'first').title
              : refreshed.checkins.firstWhere((item) => item.id == 'first').summary,
          '更新后的内容',
        );

        final restarted = await controller.loadPage(collection);
        expect(visibleIds(), ['first']);
        expect(restarted['next_cursor'], 'after-first');
      },
    );
  }

  test('concurrent refreshes coalesce into one follow-up read', () async {
    repository.queuedReads = true;
    final controller = container.read(appControllerProvider.notifier);
    final first = controller.refresh();
    final second = controller.refresh();
    final third = controller.refresh();
    expect(repository.pending.length, 1);
    repository.pending[0].complete(snapshot('正在同步'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.pending.length, 2);
    repository.pending[1].complete(snapshot('最新记录'));
    await Future.wait([first, second, third]);
    expect(repository.pending.length, 2);
    expect(container.read(appControllerProvider).requireValue.profile.nickname, '最新记录');
  });

  test('switching account while a read is pending starts an independent read', () async {
    repository.queuedReads = true;
    final old = container.read(appControllerProvider.notifier).refresh();
    repository.user = 'second-user';
    repository.sessions.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.pending.length, 2);
    repository.pending[1].complete(AppSnapshot(profile: const UserProfile(id: 'second-user', nickname: '新账号')));
    await Future<void>.delayed(Duration.zero);
    repository.pending[0].complete(snapshot('旧账号'));
    await old;
    expect(container.read(appControllerProvider).requireValue.profile.id, 'second-user');
  });

  test('refresh failure keeps data and exposes an observable error', () async {
    repository.failReads = true;
    await expectLater(
      container.read(appControllerProvider.notifier).refresh(),
      throwsA(isA<AppException>()),
    );
    expect(
      container.read(appControllerProvider).requireValue.profile.nickname,
      '原记录',
    );
    expect(container.read(syncErrorProvider), '网络暂不可用');
      expect(container.read(actionErrorProvider), isNull);
  });

  test(
    'successful departure removes the old team snapshot even when reload fails',
    () async {
      repository.failReads = true;
      await container.read(appControllerProvider.notifier).act('leave_team');
      expect(container.read(appControllerProvider).hasValue, isFalse);
      expect(container.read(syncErrorProvider), '网络暂不可用');
      expect(container.read(actionErrorProvider), isNull);
    },
  );

  test(
    'a successful write stays successful if the following read fails',
    () async {
      repository.failReads = true;
      final result = await container
          .read(appControllerProvider.notifier)
          .act('save_profile', args: {'nickname': '已保存'});
      expect(jsonObject(result)['saved'], isTrue);
      expect(container.read(syncErrorProvider), '网络暂不可用');
      expect(container.read(actionErrorProvider), isNull);
    },
  );

  test(
    'realtime bursts refresh once and pick up asynchronous memo changes',
    () async {
      final before = repository.readCount;
      repository.current = snapshot('AI 已完成');
      repository.updates.add(null);
      repository.updates.add(null);
      repository.updates.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repository.readCount, before + 1);
      expect(
        container.read(appControllerProvider).requireValue.profile.nickname,
        'AI 已完成',
      );
    },
  );

  test(
    'sign-out immediately removes data and a late request cannot restore it',
    () async {
      repository.queuedReads = true;
      final lateRead = container.read(appControllerProvider.notifier).refresh();
      repository.user = null;
      repository.sessions.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appControllerProvider).hasValue, isFalse);
      repository.pending.single.complete(snapshot('旧账号私密记录'));
      await lateRead;
      expect(container.read(appControllerProvider).hasValue, isFalse);
    },
  );

  test(
    'switching directly between accounts drops previous data while loading',
    () async {
      repository.queuedReads = true;
      repository.user = 'second-user';
      repository.sessions.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appControllerProvider).hasValue, isFalse);
      await Future<void>.delayed(Duration.zero);
      repository.pending.last.complete(
        AppSnapshot(
          profile: const UserProfile(id: 'second-user', nickname: '第二个账号'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(appControllerProvider).requireValue.profile.id,
        'second-user',
      );
    },
  );
}
