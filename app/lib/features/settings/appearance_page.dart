import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/app_appearance.dart';
import '../../ui/design.dart';
import '../../ui/tuantuan.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    final status = ref.watch(appearanceStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('界面外观')),
      body: PageBody(
        children: [
          Text('选一个喜欢的日常', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          const Text('切换后立即生效，记住本机的选择。浅色与深色仍跟随系统。'),
          const SizedBox(height: 24),
          if (status.loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(semanticsLabel: '正在读取外观偏好'),
            ),
          if (status.error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                status.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (!status.saving)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(appearanceProvider.notifier).retryLoad(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新读取'),
                ),
              ),
            const SizedBox(height: 12),
          ],
          for (final appearance in AppAppearance.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _AppearanceOption(
                appearance: appearance,
                selected: current == appearance,
                busy: status.saving,
                onSelect: () async {
                  final saved = await ref
                      .read(appearanceProvider.notifier)
                      .setAppearance(appearance);
                  if (saved && context.mounted) {
                    feedback(context, '已切换为${appearance.label}');
                  }
                },
              ),
            ),
          if (status.saving)
            Semantics(liveRegion: true, child: const Text('正在保存外观选择…')),
          const SizedBox(height: 6),
          Text(
            '只改变界面样式，计划、打卡、纪要与小队记录都保持不变。随时可以切回。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.appearance,
    required this.selected,
    required this.busy,
    required this.onSelect,
  });

  final AppAppearance appearance;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cartoon = appearance == AppAppearance.tuantuan;
    return Semantics(
      selected: selected,
      button: true,
      label: '${appearance.label}，${selected ? '当前外观' : '点击切换'}',
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('appearance-${appearance.name}'),
          onTap: busy ? null : onSelect,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cartoon
                        ? const Color(0xFFEFF8DF)
                        : const Color(0xFFF6F3EA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cartoon ? '今天也一起加油。' : '今天，也一起。',
                              style: TextStyle(
                                color: cartoon
                                    ? const Color(0xFF356C1E)
                                    : Palette.forest,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              cartoon ? '团团陪你，记住每一步' : '纸面记录，留下每一次坚持',
                              style: const TextStyle(
                                color: Color(0xFF4C5C42),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (cartoon)
                        const TuanTuanMascot(
                          pose: TuanTuanPose.wave,
                          width: 82,
                          height: 100,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFB33112),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text(
                            '已盖章',
                            style: TextStyle(
                              color: Color(0xFFB33112),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appearance.label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  appearance.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (selected) ...[
                  const SizedBox(height: 8),
                  Text('正在使用', style: TextStyle(color: colors.primary)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
