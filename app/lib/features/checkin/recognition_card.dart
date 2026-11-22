import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../data/ai_timing.dart';
import '../../ui/design.dart';
import 'checkin_draft.dart';

class RecognitionCard extends StatelessWidget {
  const RecognitionCard({
    super.key,
    required this.photo,
    required this.plans,
    this.onRemove,
    this.onRetry,
    this.onSourceChanged,
  });

  final ValueChanged<String>? onSourceChanged;
  final DraftPhoto photo;
  final List<Plan> plans;
  final VoidCallback? onRemove, onRetry;

  @override
  Widget build(BuildContext context) {
    final result = photo.recognition;
    if (AiTiming.enabled && !photo.processing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AiTiming.mark(
          'photo_visible',
          photo: photo.id,
          state: photo.phase.name,
          once: true,
        );
      });
    }
    final plan = plans.where((plan) => plan.id == result?.planId).firstOrNull;
    final phaseLabel = switch (photo.phase) {
      DraftPhotoPhase.preview => '已加入预览，点击下一步开始识别',
      DraftPhotoPhase.preparing => '正在准备压缩图',
      DraftPhotoPhase.recognizing => '正在识别这张照片',
      DraftPhotoPhase.ready => '识别完成，等待确认',
      DraftPhotoPhase.pending => 'AI 暂不可用，可按 ALL 盖章',
      DraftPhotoPhase.rejected => '这张照片暂不可提交',
    };
    return Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  photo.analysis?.bytes ?? photo.original.bytes,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  cacheWidth: 640,
                  semanticLabel: '${sourceLabel(photo.source)}，待确认照片',
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 180,
                    child: Center(child: Text('照片预览暂不可用')),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton.filled(
                  tooltip: '移除这张照片',
                  onPressed: onRemove,
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                if (photo.processing) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    phaseLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          if (photo.source != 'camera' && photo.uploaded == null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: photo.source,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(labelText: '这张图片的类型'),
              items: const [
                DropdownMenuItem(value: 'album', child: Text('普通照片，核对拍摄日期')),
                DropdownMenuItem(
                  value: 'screenshot',
                  child: Text('记录截图，核对画面日期'),
                ),
              ],
              onChanged: photo.processing || onSourceChanged == null
                  ? null
                  : (value) => onSourceChanged!(value!),
            ),
          ],
          if (photo.phase != DraftPhotoPhase.preview &&
              result?.isReady == true) ...[
            const SizedBox(height: 10),
            Text(result!.summary.isEmpty ? '这张照片已完成识别。' : result.summary),
            const SizedBox(height: 10),
            Text('计划建议：${plan?.title ?? 'ALL，等待你选择'}'),
            if (result.confidence != null)
              Text(
                '归类置信度：${(result.confidence! * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (result.screenshotDate != null)
              Text(
                '截图记录日期：${result.screenshotDate}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if ((result.confidence ?? 1) < .7) ...[
              const SizedBox(height: 8),
              const Text('这次归类把握较低，请核对下方的本次记录标签。'),
            ],
            ...result.fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${field.label}：${field.displayValue} · ${sourceLabel(field.source)}',
                ),
              ),
            ),
          ],
          if (photo.error != null) ...[
            const SizedBox(height: 10),
            Text(
              photo.error!,
              style: TextStyle(
                color: photo.phase == DraftPhotoPhase.rejected
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
          if (photo.phase == DraftPhotoPhase.pending) ...[
            const SizedBox(height: 10),
            Text(
              photo.uploaded == null
                  ? '原图尚未上传。确认后保留盖章，当天后台继续整理，不会编造纪要或运动数据。'
                  : '原图已私有归档，等待盖章。当日后台继续整理，不会编造纪要或运动数据。',
            ),
          ],
          if (photo.uploadError != null) ...[
            const SizedBox(height: 10),
            Text(
              photo.uploadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (!photo.processing &&
              photo.phase != DraftPhotoPhase.preview &&
              photo.phase != DraftPhotoPhase.ready &&
              photo.uploaded == null)
            TextButton(onPressed: onRetry, child: const Text('重新检查这张')),
        ],
      ),
    );
  }
}
