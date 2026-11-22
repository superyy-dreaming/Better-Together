import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_controller.dart';
import '../domain/models.dart';
import 'design.dart';

class SnapshotView extends ConsumerWidget {
  const SnapshotView({super.key, required this.builder});
  final Widget Function(AppSnapshot snapshot) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appControllerProvider)
      .when(
        data: (snapshot) {
          final issue = ref.watch(syncErrorProvider);
          final syncing = ref.watch(syncBusyProvider);
          return Column(
            children: [
              if (syncing)
                const LinearProgressIndicator(
                  minHeight: 2,
                  semanticsLabel: '正在后台同步',
                ),
              if (issue != null)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '同步尚未完成，当前显示上次记录。$issue',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(appControllerProvider.notifier)
                                    .refresh();
                              } catch (_) {
                                /* Error remains visible. */
                              }
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: builder(snapshot)),
            ],
          );
        },
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator.adaptive(),
              SizedBox(height: 16),
              Text('正在同步你的记录'),
            ],
          ),
        ),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyMessage(
            title: '暂时无法同步',
            body: '$error',
            action: FilledButton(
              onPressed: () =>
                  ref.read(appControllerProvider.notifier).refresh(),
              child: const Text('重新连接'),
            ),
          ),
        ),
      );
}

Future<JsonMap?> runAction(
  BuildContext context,
  WidgetRef ref,
  String action, [
  JsonMap args = const {},
]) async {
  try {
    final result = await ref
        .read(appControllerProvider.notifier)
        .act(action, args: args);
    return result is Map ? jsonObject(result) : {'result': result};
  } catch (error) {
    if (context.mounted) feedback(context, error.toString());
    return null;
  }
}
