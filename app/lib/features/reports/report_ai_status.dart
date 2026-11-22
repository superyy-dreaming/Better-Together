import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/app_controller.dart';
import '../../domain/models.dart';

/// Mounted only for the owner's personal report, never during image export.
class ReportAiStatus extends ConsumerStatefulWidget {
  const ReportAiStatus({super.key, required this.report});
  final WeeklyReport report;
  @override
  ConsumerState<ReportAiStatus> createState() => _ReportAiStatusState();
}

class _ReportAiStatusState extends ConsumerState<ReportAiStatus> {
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    if (widget.report.aiStatus != 'ready') Future.microtask(generate);
  }

  Future<void> generate() async {
    if (busy || !mounted) return;
    final repository = ref.read(repositoryProvider);
    if (repository.isDemo || repository.currentUserId != widget.report.userId) {
      return;
    }
    setState(() => busy = true);
    try {
      final result = jsonObject(
        await repository.action(
          'generate_report_ai',
          args: {'report_id': widget.report.id},
        ),
      );
      if (!mounted) return;
      if (['ready', 'cached'].contains(result['state'])) {
        await ref
            .read(appControllerProvider.notifier)
            .loadPage('reports', append: true);
      } else {
        setState(
          () => message = stringValue(result['message'], '当前显示规则版摘要，可稍后补生成。'),
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = 'AI 摘要暂不可用，规则版周报仍完整保留。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.report.aiStatus == 'ready') return const Text('AI 从本周事实中整理了摘要。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(busy ? '正在用本机 AI 整理摘要，统计已可查看。' : message ?? '当前显示规则版摘要。'),
        if (!busy)
          TextButton(onPressed: generate, child: const Text('补生成 AI 摘要')),
      ],
    );
  }
}
