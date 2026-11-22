import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../data/app_controller.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';
import '../../ui/tuantuan.dart';
import 'report_export.dart';
import 'report_receipt.dart';
import 'report_ai_status.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key, this.imageSharer = sharePersonalReportImage});
  final ReportImageSharer imageSharer;
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String? nextPage, loadIssue;
  bool loadingPage = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(loadPage);
  }

  Future<void> loadPage({bool more = false}) async {
    if (loadingPage) return;
    setState(() => loadingPage = true);
    try {
      final page = await ref
          .read(appControllerProvider.notifier)
          .loadPage('reports', cursor: more ? nextPage : null, append: more);
      if (mounted) {
        setState(() {
          nextPage = nullableString(page['next_cursor']);
          loadIssue = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadIssue = e.toString());
    } finally {
      if (mounted) setState(() => loadingPage = false);
    }
  }

  String kind = 'personal';
  bool exporting = false;
  Future<void> shareImage(
    WeeklyReport report,
    String currentUserId,
    BuildContext buttonContext,
  ) async {
    if (exporting) return;
    if (!canExportPersonalReport(report, currentUserId)) {
      feedback(context, '只能导出你自己的个人周报。');
      return;
    }
    final box = buttonContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final result = await widget.imageSharer(
        context: context,
        report: report,
        currentUserId: currentUserId,
        shareOrigin: origin,
      );
      if (mounted && result.status == ShareResultStatus.success) {
        await runAction(context, ref, 'share_report', {
          'report_id': report.id,
          'method': 'image',
        });
      }
    } catch (error) {
      if (mounted) {
        feedback(
          context,
          error is ReportExportException
              ? error.message
              : '长图暂未分享，请重新点击“保存图片分享”。',
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) {
      final reports = s.reports
          .where(
            (r) =>
                r.kind == kind &&
                (kind == 'team' || canExportPersonalReport(r, s.profile.id)),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('这一周，值得记住')),
        body: PageBody(
          onRefresh: loadPage,
          children: [
            if (loadingPage) const LinearProgressIndicator(),
            if (loadIssue != null)
              TextButton(onPressed: loadPage, child: Text('$loadIssue，点击重试')),
            if (nextPage != null)
              TextButton(
                onPressed: loadingPage ? null : () => loadPage(more: true),
                child: const Text('加载更多'),
              ),
            if (isTuanTuan(context)) ...[
              TuanTuanHero(
                title: reports.isEmpty ? '每一点坚持，都值得记住。' : '这一周，\n又前进了一点。',
                body: kind == 'personal' ? '回看自己的进步，把喜欢的瞬间带走。' : '一起看看小队留下的脚印。',
                pose: reports.isEmpty
                    ? TuanTuanPose.read
                    : TuanTuanPose.celebrate,
              ),
              const SizedBox(height: 22),
            ],
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'personal', label: Text('我的周报')),
                ButtonSegment(value: 'team', label: Text('小队周报')),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setState(() => kind = v.first),
            ),
            const SizedBox(height: 24),
            if (reports.isEmpty)
              EmptyMessage(
                title: '坚持正在汇成一份周报',
                body: '每周日 20:00（${s.timezone}）自动生成。记录会如实呈现完成、补卡和未完成。',
              ),
            ...reports.map(
              (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReportReceipt(report: r),
                  if (kind == 'personal' && r.userId == s.profile.id)
                    ReportAiStatus(
                      key: ValueKey('${r.id}:${r.aiVersion}'),
                      report: r,
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (kind == 'personal')
                        FilledButton.icon(
                          onPressed: r.shared
                              ? null
                              : () => runAction(context, ref, 'share_report', {
                                  'report_id': r.id,
                                  'method': 'feed',
                                }),
                          icon: const Icon(CupertinoIcons.paperplane),
                          label: Text(r.shared ? '已发到小队' : '发到小队'),
                        ),
                      if (kind == 'personal')
                        Builder(
                          builder: (buttonContext) => OutlinedButton.icon(
                            onPressed: exporting
                                ? null
                                : () => shareImage(
                                    r,
                                    s.profile.id,
                                    buttonContext,
                                  ),
                            icon: const Icon(CupertinoIcons.share),
                            label: Text(exporting ? '正在生成' : '保存图片分享'),
                          ),
                        ),
                      if (kind == 'personal')
                        OutlinedButton(
                          onPressed: r.refreshed
                              ? null
                              : () => runAction(
                                  context,
                                  ref,
                                  'refresh_report',
                                  {'report_id': r.id},
                                ),
                          child: const Text('刷新周报'),
                        ),
                    ],
                  ),
                  if (r.suggestion['plan_id'] != null)
                    TextButton(
                      onPressed: () => runAction(
                        context,
                        ref,
                        'accept_suggestion',
                        {'report_id': r.id},
                      ),
                      child: const Text('采纳建议，调整下周'),
                    ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
