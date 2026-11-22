import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/design.dart';
import '../../ui/tuantuan.dart';

/// The same receipt is used on screen and by the isolated image renderer.
/// It receives one report, never a team snapshot or another member's profile.
class ReportReceipt extends StatelessWidget {
  const ReportReceipt({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) => Paper(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Better Together',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Icon(
              isTuanTuan(context)
                  ? CupertinoIcons.star_fill
                  : CupertinoIcons.doc_text,
              color: isTuanTuan(context)
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          '${report.weekStart} 开始的一周',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(report.stage == 'final' ? '最终周报' : '阶段周报 · 周一 12:05 更新最终版'),
        if (report.generatedAt != null)
          Text(
            '生成于 ${report.generatedAt!.toLocal().toString().substring(0, 16)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 10),
        Text(
          report.title.isEmpty ? '每一步，都留下了痕迹。' : report.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        Text(report.summary, style: Theme.of(context).textTheme.bodyLarge),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
        if (report.metrics['completion_rate'] is num)
          _ReportMetricOverview(report: report),
        if (report.metrics['by_category'] is Map)
          _CategoryBarChart(
            values: jsonObject(report.metrics['by_category']),
            title: report.kind == 'team' ? '小队分类构成' : '本周记录构成',
          ),
        ...report.metrics.entries
            .where(
              (e) =>
                  e.key != 'plans' &&
                  e.key != 'by_category' &&
                  e.key != 'completion_rate' &&
                  e.key != 'completed' &&
                  e.key != 'expected' &&
                  e.key != 'makeup' &&
                  e.key != 'members',
            )
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${metricLabel(e.key)}  ${formatMetric(e.value)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        if (report.metrics['plans'] is List) ...[
          _PlanProgressChart(values: jsonList(report.metrics['plans'])),
        ],
        if (report.highlights.isNotEmpty) ...[
          const SectionTitle('留住这几刻'),
          ...report.highlights.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                h is String
                    ? h
                    : stringValue(
                        jsonObject(h)['summary'] ?? jsonObject(h)['title'],
                      ),
              ),
            ),
          ),
        ],
        if (report.suggestion.isNotEmpty) ...[
          const SectionTitle('给下周的一点建议'),
          Text(
            stringValue(
              report.suggestion['text'] ?? report.suggestion['summary'],
            ),
          ),
        ],
        const SizedBox(height: 24),
        const StampLabel(text: '有证据的坚持'),
      ],
    ),
  );
}

class _ReportMetricOverview extends StatelessWidget {
  const _ReportMetricOverview({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final metrics = report.metrics;
    final double rate = ((metrics['completion_rate'] as num).toDouble())
        .clamp(0.0, 1.0)
        .toDouble();
    final completed = intValue(metrics['completed']);
    final expected = intValue(metrics['expected']);
    final makeup = intValue(metrics['makeup']);
    final members = intValue(metrics['members']);
    final label = report.kind == 'team' ? '小队完成率' : '本周完成率';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CompletionRing(value: rate, size: 94),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(label: '完成', value: '$completed'),
                    _MetricChip(label: '应打卡', value: '$expected'),
                    if (makeup > 0) _MetricChip(label: '补卡', value: '$makeup'),
                    if (report.kind == 'team' && members > 0)
                      _MetricChip(label: '成员', value: '$members 人'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(10),
    ),
    child: RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: [
          TextSpan(text: '$label\n'),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _CompletionRing extends StatelessWidget {
  const _CompletionRing({required this.value, required this.size});
  final double value, size;

  @override
  Widget build(BuildContext context) {
    final textColor = isTuanTuan(context)
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _CompletionRingPainter(
              value: value,
              track: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .7),
              progress: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionRingPainter extends CustomPainter {
  const _CompletionRingPainter({
    required this.value,
    required this.track,
    required this.progress,
  });
  final double value;
  final Color track, progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progress
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CompletionRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.progress != progress;
}

class _CategoryBarChart extends StatelessWidget {
  const _CategoryBarChart({required this.values, required this.title});
  final JsonMap values;
  final String title;

  @override
  Widget build(BuildContext context) {
    final rows = values.entries
        .where((entry) => entry.value is num && (entry.value as num) > 0)
        .map((entry) => MapEntry(entry.key, (entry.value as num).toInt()))
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxValue = rows.map((e) => e.value).reduce(math.max);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...rows.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      metricLabel(entry.key),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // Adjacent text exposes the category and actual count.
                    // Relative bar length is not a completion percentage.
                    child: ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 11,
                          value: entry.value / maxValue,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: .55),
                          valueColor: AlwaysStoppedAnimation(
                            _categoryColor(context, entry.key),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${entry.value}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanProgressChart extends StatelessWidget {
  const _PlanProgressChart({required this.values});
  final List<Object?> values;

  @override
  Widget build(BuildContext context) {
    final plans = values.map(jsonObject).where((plan) {
      return plan['expected'] is num && plan['completed'] is num;
    }).toList();
    if (plans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每个小目标', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...plans.map((plan) {
            final expected = (plan['expected'] as num).toDouble();
            final completed = (plan['completed'] as num).toDouble();
            final double progress = expected <= 0
                ? 0.0
                : (completed / expected).clamp(0.0, 1.0).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(stringValue(plan['title']))),
                      Text(
                        '${completed.round()}/${expected.round()} 天',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 9,
                      value: progress,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: .55),
                      valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

Color _categoryColor(BuildContext context, String category) =>
    switch (category) {
      'exercise' => Theme.of(context).colorScheme.secondary,
      'food' => const Color(0xFFC58A21),
      'water' => const Color(0xFF4B8FA5),
      'mindfulness' => const Color(0xFF7C6AA6),
      'meditation' => const Color(0xFF7C6AA6),
      _ => Theme.of(context).colorScheme.primary,
    };

String metricLabel(String value) => switch (value) {
  'completed' => '已完成',
  'expected' => '应打卡',
  'makeup' => '已补卡',
  'completion_rate' => '完成率',
  'streak' => '连续天数',
  'extra_days' => '超额完成天数',
  'total_checkins' => '打卡次数',
  'likes' => '收到的赞',
  'comments' => '队友回应',
  'pokes' => '收到提醒',
  'uncategorized' => '未归类',
  'unclassified' => '未归类',
  'checkins' => '打卡次数',
  'by_category' => '分类记录',
  'study' => '学习',
  'exercise' => '运动',
  'food' => '饮食',
  'water' => '饮水',
  'mindfulness' => '冥想',
  'meditation' => '冥想',
  'sleep' => '作息',
  'all' => '未归类',
  'custom' => '自定义',
  'members' => '小队人数',
  'received' => '收到回应',
  'attendance' => '全勤天数',
  'improvement' => '完成率提升',
  _ => value,
};

String formatMetric(Object? value) => value is Map
    ? jsonObject(value).entries
          .map((e) => '${metricLabel(e.key)} ${e.value}')
          .join(' · ')
    : value is List
    ? value.join('、')
    : stringValue(value);
