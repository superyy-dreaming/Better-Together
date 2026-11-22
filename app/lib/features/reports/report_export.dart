import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import 'report_receipt.dart';

bool canExportPersonalReport(WeeklyReport report, String currentUserId) =>
    currentUserId.isNotEmpty &&
    report.kind == 'personal' &&
    report.userId == currentUserId;

class ReportExportException implements Exception {
  const ReportExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ReportImage {
  const ReportImage({
    required this.png,
    required this.width,
    required this.height,
  });
  final Uint8List png;
  final int width, height;
}

/// Lays out the entire receipt without a scroll viewport. A screen boundary can
/// be unpainted after scrolling; this private render tree always paints all text.
Future<ReportImage> renderPersonalReport({
  required BuildContext context,
  required WeeklyReport report,
  required String currentUserId,
  double logicalWidth = 390,
  double pixelRatio = 2,
}) async {
  if (!canExportPersonalReport(report, currentUserId)) {
    throw const ReportExportException('只能导出你自己的个人周报。');
  }
  if (!logicalWidth.isFinite ||
      logicalWidth < 280 ||
      logicalWidth > 700 ||
      !pixelRatio.isFinite ||
      pixelRatio < 1 ||
      pixelRatio > 3) {
    throw ArgumentError('Invalid report image dimensions');
  }

  final theme = Theme.of(context);
  final media = MediaQuery.of(context).copyWith(
    size: Size(logicalWidth, 1),
    padding: EdgeInsets.zero,
    viewPadding: EdgeInsets.zero,
    viewInsets: EdgeInsets.zero,
  );
  final boundary = RenderRepaintBoundary();
  final overflow = RenderConstrainedOverflowBox(
    minWidth: logicalWidth,
    maxWidth: logicalWidth,
    minHeight: 0,
    maxHeight: double.infinity,
    alignment: Alignment.topLeft,
    child: boundary,
  );
  final renderView = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(Size(logicalWidth, 1)),
      physicalConstraints: BoxConstraints.tight(Size(logicalWidth, 1)),
      devicePixelRatio: 1,
    ),
    child: overflow,
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final focusManager = FocusManager();
  final owner = BuildOwner(focusManager: focusManager);
  RenderObjectToWidgetElement<RenderBox>? root;
  ui.Image? image;
  try {
    renderView.prepareInitialFrame();
    root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: MediaQuery(
          data: media,
          child: Theme(
            data: theme,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ReportReceipt(report: report),
                ),
              ),
            ),
          ),
        ),
      ),
    ).attachToRenderTree(owner);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.flushLayout();
    final width = (boundary.size.width * pixelRatio).ceil();
    final height = (boundary.size.height * pixelRatio).ceil();
    // Fail explicitly before allocating an excessive bitmap; never crop data.
    if (height > 16384 || width * height > 16000000) {
      throw const ReportExportException('周报超出长图尺寸限制，请使用“发到小队”分享完整周报。');
    }
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const ReportExportException('图片编码未完成，请重新生成长图。');
    }
    return ReportImage(
      png: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } finally {
    image?.dispose();
    if (root != null) {
      root.update(RenderObjectToWidgetAdapter<RenderBox>(container: boundary));
      owner.buildScope(root);
      owner.finalizeTree();
    }
    pipeline.rootNode = null;
    renderView.child = null;
    overflow.child = null;
    boundary.dispose();
    overflow.dispose();
    renderView.dispose();
    focusManager.dispose();
    pipeline.dispose();
  }
}

typedef ReportImageSharer = Future<ShareResult> Function({
  required BuildContext context,
  required WeeklyReport report,
  required String currentUserId,
  required Rect shareOrigin,
});

Future<ShareResult> sharePersonalReportImage({
  required BuildContext context,
  required WeeklyReport report,
  required String currentUserId,
  required Rect shareOrigin,
}) async {
  final image = await renderPersonalReport(
    context: context,
    report: report,
    currentUserId: currentUserId,
  );
  if (!context.mounted) {
    throw const ReportExportException('页面已离开，长图未分享。');
  }
  final directory = await getTemporaryDirectory();
  // A separate directory prevents an old file being overwritten while a share
  // extension is still reading it. The OS owns temporary file eviction.
  final exportDirectory = await directory.createTemp('better-together-report-');
  final file = File('${exportDirectory.path}/better-together.png');
  await file.writeAsBytes(image.png, flush: true);
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      text: 'Better Together · 我的这一周',
      sharePositionOrigin: shareOrigin,
    ),
  );
}
