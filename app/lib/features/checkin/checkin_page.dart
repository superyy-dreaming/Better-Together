import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_controller.dart';
import '../../data/ai_timing.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';
import '../../ui/tuantuan.dart';
import '../../platform/photo_preparation.dart';
import 'checkin_draft.dart';
import 'checkin_draft_provider.dart';
import 'checkin_group_card.dart';
import 'recognition_card.dart';
import 'photo_preview_grid.dart';

class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key, this.planId, this.redoOf, this.targetDate});
  final String? planId, redoOf, targetDate;
  @override
  ConsumerState<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends ConsumerState<CheckinPage> {
  late final CheckinDraft draft;
  List<DraftPhoto> get photos => draft.photos;
  final note = TextEditingController();
  final reason = TextEditingController();
  CheckinDraftKey get draftKey => (
    planId: widget.planId,
    redoOf: widget.redoOf,
    targetDate: widget.targetDate,
  );
  String get submissionId => draft.batchId;
  bool busy = false, picking = false;
  String progress = '';
  final Map<String, Plan> availablePlans = {};
  bool get makeup => widget.targetDate != null && widget.redoOf == null;
  @override
  void initState() {
    super.initState();
    draft = ref.read(checkinDraftProvider(draftKey))
      ..addListener(_draftChanged);
    note.text = draft.note;
    reason.text = draft.makeupReason;
    note.addListener(() => draft.note = note.text);
    reason.addListener(() => draft.makeupReason = reason.text);
    unawaited(_loadPlans());
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    draft.removeListener(_draftChanged);
    note.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> choosePhoto() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.camera),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'album'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await pick(source);
  }

  Future<void> pick(String source) async {
    if (busy || picking || draft.sessionChanged) return;
    setState(() => picking = true);
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (source == 'camera') {
        final file = await picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: true,
        );
        files = file == null ? [] : [file];
      } else {
        files = await picker.pickMultiImage(
          limit: maxPhotosPerCheckin - photos.length,
          requestFullMetadata: true,
        );
      }
      AiTiming.selectionStarted(draft.batchId, files.length);
      for (final file in files.take(maxPhotosPerCheckin - photos.length)) {
        AiTiming.mark('original_read_start', batch: draft.batchId);
        final prepared = await preparePickedPhoto(file.path);
        AiTiming.mark(
          'original_read_end',
          batch: draft.batchId,
          bytes: prepared.bytes.length,
        );
        if (!mounted || draft.sessionChanged) return;
        await draft.add(
          prepared,
          source,
          capturedAt: source == 'camera' ? DateTime.now() : null,
        );
      }
    } catch (e) {
      if (mounted) feedback(context, '照片未加入：$e');
    } finally {
      AiTiming.selectionEnded(draft.batchId);
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> nextStep() async {
    if (busy || picking || draft.sessionChanged || photos.isEmpty) return;
    setState(() {
      busy = true;
      progress = '正在整理照片';
    });
    try {
      await draft.startRecognition();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadPlans() async {
    final repository = ref.read(repositoryProvider);
    if (repository.isDemo) return;
    String? cursor;
    try {
      do {
        final page = jsonObject(
          await repository.action(
            'read_page',
            args: {
              'collection': 'plans',
              'status': 'active',
              'cursor': cursor,
              'limit': 100,
            },
          ),
        );
        if (!mounted || draft.sessionChanged) return;
        for (final row in jsonList(page['items'])) {
          final plan = Plan.fromJson(jsonObject(row));
          availablePlans[plan.id] = plan;
        }
        cursor = nullableString(page['next_cursor']);
      } while (cursor != null);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) feedback(context, '计划列表未完整读取，已载入的计划仍可使用。重新打开此页可重试。');
    }
  }

  Future<void> submit() async {
    if (busy || picking || draft.processing || draft.sessionChanged) return;
    if (photos.isEmpty) {
      feedback(context, '先拍一张，或选择今天的照片');
      return;
    }
    if (makeup && reason.text.trim().isEmpty) {
      feedback(context, '写一句补卡原因，让记录更完整');
      return;
    }
    if (!draft.canConfirm) {
      feedback(context, '这些照片还不能提交。请按照片下方提示重试或换图。');
      return;
    }
    setState(() {
      busy = true;
      progress = '正在确认照片';
    });
    try {
      final excluded = photos.where((photo) => !photo.canArchive).length;
      if (excluded > 0) {
        final accepted = await confirmAction(
          context,
          '剔除 $excluded 张未通过的照片？',
          '只有通过检查或等待 AI 补识别的照片会归档和盖章。被拒绝的照片不会上传。',
          accept: '确认使用其余照片',
        );
        if (!accepted || !mounted || draft.sessionChanged) return;
      }
      final controller = ref.read(appControllerProvider.notifier);
      final expected = photos.where((photo) => photo.canArchive).length;
      final valid = await draft.archiveConfirmed(
        onProgress: (index, total) {
          if (mounted) setState(() => progress = '正在私有归档第 $index/$total 张原图');
        },
      );
      if (!mounted || draft.sessionChanged) return;
      if (valid.isEmpty) {
        if (mounted) feedback(context, '这些照片还不能提交。请查看每张照片下的提示，换图后再试。');
        return;
      }
      if (valid.length != expected) {
        feedback(context, '部分原图尚未归档，请查看照片提示后重试。已保存的照片会复用，暂未创建打卡。');
        return;
      }
      setState(() => progress = '正在盖章');
      AiTiming.mark('stamp_start', batch: draft.batchId);
      final result = await controller.act(
        'submit_checkin_batch',
        args: {
          ...draft.groupPayload(),
          'media_ids': valid,
          'note': note.text.trim(),
          'target_date': widget.targetDate,
          'makeup_reason': makeup ? reason.text.trim() : null,
          'redo_of': widget.redoOf,
          'idempotency_key': submissionId,
        },
      );
      AiTiming.mark('stamp_end', batch: draft.batchId);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ref.invalidate(checkinDraftProvider(draftKey));
      final data = jsonObject(result);
      final ids = jsonList(
        data['checkin_ids'] ?? data['ids'] ?? (result is List ? result : null),
      );
      final id = ids.isNotEmpty
          ? ids.first.toString()
          : nullableString(data['id']);
      if (id != null) {
        context.pushReplacement('/memo/$id?sealed=1');
      } else {
        context.go('/today');
        feedback(context, '已盖章。纪要将在记录里自动更新。');
      }
    } catch (e) {
      if (mounted) feedback(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) => PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            makeup
                ? '补上昨天的记录'
                : widget.redoOf != null
                ? '重新打卡'
                : '记录今天',
          ),
          leading: IconButton(
            tooltip: '关闭打卡',
            onPressed: busy ? null : () => context.pop(),
            icon: const Icon(CupertinoIcons.xmark),
          ),
        ),
        body: PageBody(
          children: [
            if (isTuanTuan(context))
              const TuanTuanHero(
                title: '你负责行动，\n我帮你整理！',
                body: '先整理照片，下一步识别，再确认盖章。',
                pose: TuanTuanPose.camera,
              )
            else ...[
              Text(
                '留下一份\n今天的证据。',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text('整理照片 → 下一步识别 → 确认分组并盖章'),
            ],
            const SizedBox(height: 20),
            if (photos.isEmpty && draft.canAddPhotos)
              Paper(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const Icon(
                      CupertinoIcons.camera,
                      size: 44,
                      color: Palette.muted,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '拍下你刚完成的事',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '书页、跑道，或认真吃的一餐。\n支持今天的照片与记录截图。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: picking ? null : choosePhoto,
                        icon: const Icon(CupertinoIcons.camera),
                        label: const Text('现在选一张'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            if (photos.isNotEmpty) ...[
              if (!draft.recognitionStarted)
                PhotoPreviewGrid(draft: draft, enabled: !busy && !picking),
              if (draft.recognitionStarted &&
                  (draft.processing ||
                      photos.any(
                        (p) => p.error != null || p.uploadError != null,
                      )))
                ...photos.map(
                  (photo) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: RecognitionCard(
                      photo: photo,
                      plans: s.plans,
                      onSourceChanged: busy || !draft.canAddPhotos
                          ? null
                          : (source) => draft.changeSource(photo, source),
                      onRemove: busy ? null : () => draft.remove(photo),
                      onRetry:
                          busy ||
                              picking ||
                              !draft.recognitionStarted ||
                              photo.processing ||
                              photo.uploaded != null
                          ? null
                          : () => draft.recognize(photo),
                    ),
                  ),
                ),
              if (!draft.recognitionStarted) ...[
                const SizedBox(height: 10),
                const Text('照片已整理好。点击下一步后才会开始识别，你可以在这里继续添加或删除照片。'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('next-checkin'),
                    onPressed: busy || picking ? null : nextStep,
                    child: Text(busy ? progress : '下一步'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                if (!draft.processing &&
                    photos.every((p) => p.uploaded == null))
                  TextButton.icon(
                    onPressed: busy ? null : draft.returnToPreview,
                    icon: const Icon(CupertinoIcons.back),
                    label: const Text('返回整理照片'),
                  ),
                Text(
                  draft.processing
                      ? '正在识别，完成后会按计划拆成记录。'
                      : '已整理为 ${draft.groups.length} 条记录。可以移动照片、修改整条计划或编辑纪要。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                if (!draft.processing)
                  for (final group in draft.groups) ...[
                    CheckinGroupCard(
                      key: ValueKey('checkin-group-${group.planId ?? 'all'}'),
                      draft: draft,
                      group: group,
                      plans: {
                        for (final p in s.plans) p.id: p,
                        ...availablePlans,
                      }.values.toList(),
                      enabled: !busy,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
              Text(
                '已选 ${photos.length}/9 张',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            if (photos.isNotEmpty && draft.canAddPhotos)
              OutlinedButton.icon(
                onPressed:
                    busy || picking || !draft.canAddPhotos || photos.length >= 9
                    ? null
                    : choosePhoto,
                icon: const Icon(CupertinoIcons.add),
                label: const Text('继续选一张'),
              ),
            const SizedBox(height: 22),
            if (draft.recognitionStarted)
              TextField(
                controller: note,
                enabled: !busy,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '想留下一句话（可选）',
                  hintText: '今天完成了什么，有什么感受？',
                ),
              ),
            if (draft.recognitionStarted && makeup) ...[
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '补卡原因'),
              ),
            ],
            if (draft.recognitionStarted) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('confirm-checkin'),
                  onPressed: busy || picking || !draft.canConfirm
                      ? null
                      : () => submit(),
                  child: Text(
                    busy
                        ? progress
                        : draft.processing
                        ? '正在识别'
                        : '确认分组、归档并盖章',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '识别仅发送压缩图，原图在确认后私有存档。AI 暂不可用也可按 ALL 盖章，当天后台补识别；日期或证据检查未通过的照片不可提交。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
