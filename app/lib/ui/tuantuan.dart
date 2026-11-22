import 'package:material_ui/material_ui.dart';

import 'app_appearance.dart';

/// Kept in the theme so every route (including sheets) follows the same choice.
@immutable
class AppearanceTheme extends ThemeExtension<AppearanceTheme> {
  const AppearanceTheme(this.appearance);
  final AppAppearance appearance;

  @override
  AppearanceTheme copyWith({AppAppearance? appearance}) =>
      AppearanceTheme(appearance ?? this.appearance);

  @override
  AppearanceTheme lerp(covariant AppearanceTheme? other, double t) =>
      other == null || t < .5 ? this : other;
}

bool isTuanTuan(BuildContext context) =>
    Theme.of(context).extension<AppearanceTheme>()?.appearance ==
    AppAppearance.tuantuan;

enum TuanTuanPose { wave, camera, celebrate, read, stand }

class TuanTuanMascot extends StatelessWidget {
  const TuanTuanMascot({
    super.key,
    this.pose = TuanTuanPose.wave,
    this.width = 120,
    this.height = 140,
  });

  final TuanTuanPose pose;
  final double width, height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/tuantuan/tuantuan-${pose.name}.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

/// Illustration is decorative. The title and body carry all useful information.
/// No looping animation: reduced-motion users see the same complete feedback.
class TuanTuanHero extends StatelessWidget {
  const TuanTuanHero({
    super.key,
    required this.title,
    required this.body,
    this.pose = TuanTuanPose.wave,
  });

  final String title, body;
  final TuanTuanPose pose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(width: 12),
            TuanTuanMascot(pose: pose, width: 104, height: 126),
          ],
        ),
        const SizedBox(height: 6),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class TuanTuanProgress extends StatelessWidget {
  const TuanTuanProgress({
    super.key,
    required this.done,
    required this.total,
    required this.teamLabel,
  });

  final int done, total;
  final String teamLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.primary.withValues(alpha: .35),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total > 0 && done == total ? '今天的目标，完成啦！' : '一点点，也是在前进',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$done / $total',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 14,
            borderRadius: BorderRadius.circular(10),
            color: colors.primary,
            backgroundColor: colors.primary.withValues(alpha: .15),
            semanticsLabel: '今日计划完成进度，已完成 $done 项，共 $total 项',
          ),
          const SizedBox(height: 14),
          Text(teamLabel, style: TextStyle(color: colors.onPrimaryContainer)),
        ],
      ),
    );
  }
}
