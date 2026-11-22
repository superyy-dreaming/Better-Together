import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_repository.dart';
import '../../data/ai_timing.dart';
import '../../domain/models.dart';
import '../../platform/photo_preparation.dart';

enum DraftPhotoPhase {
  preview,
  preparing,
  recognizing,
  ready,
  pending,
  rejected,
}

class DraftPhoto {
  DraftPhoto({
    required this.id,
    required this.original,
    required this.source,
    this.capturedAt,
  });
  final String id;
  String source;
  final PreparedPhoto original;
  final DateTime? capturedAt;
  AnalysisPhoto? analysis;
  PhotoRecognition? recognition;
  UploadedPhoto? uploaded;
  DraftPhotoPhase phase = DraftPhotoPhase.preview;
  String? assignedPlanId;
  bool manuallyAssigned = false;
  String? error, uploadError;
  int _recognitionVersion = 0;
  bool _recognitionActive = false;

  bool get processing =>
      phase == DraftPhotoPhase.preparing ||
      phase == DraftPhotoPhase.recognizing;
  bool get canArchive =>
      analysis != null &&
      (phase == DraftPhotoPhase.ready || phase == DraftPhotoPhase.pending);
}

class _RecognitionJob {
  _RecognitionJob(this.photo, this.version);
  final DraftPhoto photo;
  final int version;
  final completed = Completer<void>();
}

class DraftGroup {
  DraftGroup({required this.planId, required this.photos});
  final String? planId;
  final List<DraftPhoto> photos;

  String get summary => photos
      .map((photo) => photo.recognition?.summary.trim() ?? '')
      .where((summary) => summary.isNotEmpty)
      .join('\n');

  List<MemoField> get fields => [
    for (final photo in photos) ...?photo.recognition?.fields,
  ];
}

typedef AnalysisPreparer = Future<AnalysisPhoto> Function(Uint8List original);

/// Keeps originals and previews in memory until the user confirms archiving.
class CheckinDraft extends ChangeNotifier {
  static const maxConcurrentRecognitions = 4;

  CheckinDraft({
    required this.repository,
    String? batchId,
    this.selectedPlanId,
    AnalysisPreparer? prepare,
  }) : batchId = batchId ?? const Uuid().v4(),
       _owner = repository.currentUserId,
       _prepare = prepare ?? preparePhotoForRecognition {
    _authSubscription = repository.authChanges.listen((_) {
      if (sessionChanged) {
        _sessionInvalidated = true;
        _photos.clear();
        _changed();
      }
    });
  }

  final AppRepository repository;
  final String batchId;
  final String? _owner;
  final AnalysisPreparer _prepare;
  late final StreamSubscription<bool> _authSubscription;
  final List<DraftPhoto> _photos = [];
  final List<_RecognitionJob> _recognitionQueue = [];
  final Map<String, String> _summaryOverrides = {};
  final Set<String> _editedSummaries = {};
  int _activeRecognitions = 0;
  final String? selectedPlanId;
  String note = '', makeupReason = '';
  bool _disposed = false,
      _archiving = false,
      _sessionInvalidated = false,
      _recognitionStarted = false;
  List<DraftPhoto> get photos => List.unmodifiable(_photos);
  bool get sessionChanged =>
      _sessionInvalidated ||
      _owner == null ||
      repository.currentUserId != _owner;
  bool get preparing =>
      _photos.any((photo) => photo.phase == DraftPhotoPhase.preparing);
  bool get recognizing =>
      _photos.any((photo) => photo.phase == DraftPhotoPhase.recognizing);
  bool get processing => preparing || recognizing;
  bool get recognitionStarted => _recognitionStarted;
  bool get canAddPhotos =>
      !_recognitionStarted && !_archiving && !sessionChanged;
  bool get archiving => _archiving;
  bool get canConfirm =>
      !sessionChanged &&
      !processing &&
      !archiving &&
      !_photos.any((photo) => photo.phase == DraftPhotoPhase.preview) &&
      _photos.any((photo) => photo.canArchive);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The plan selected for a photo is intentionally kept separate from the
  /// model suggestion. A late result can therefore never overwrite a user
  /// decision made on the grouping screen.
  String? effectivePlanId(DraftPhoto photo) {
    if (photo.manuallyAssigned) return photo.assignedPlanId;
    final result = photo.recognition;
    if (result == null || !result.isReady || (result.confidence ?? 0) < .8) {
      return null;
    }
    return result.planId;
  }

  List<DraftGroup> get groups {
    final grouped = <String?, List<DraftPhoto>>{};
    for (final photo in _photos.where((photo) => photo.canArchive)) {
      grouped.putIfAbsent(effectivePlanId(photo), () => []).add(photo);
    }
    return grouped.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => DraftGroup(planId: entry.key, photos: entry.value))
        .toList();
  }

  String summaryFor(DraftGroup group) =>
      _summaryOverrides[_groupKey(group.planId)] ?? group.summary;

  void editGroupSummary(String? planId, String summary) {
    if (_archiving || sessionChanged) return;
    final key = _groupKey(planId);
    _summaryOverrides[key] = summary;
    _editedSummaries.add(key);
  }

  String _groupKey(String? planId) => planId ?? '__all__';

  void assignPhoto(DraftPhoto photo, String? planId) {
    if (_archiving || sessionChanged || !_photos.contains(photo)) return;
    final source = groups.where((g) => g.photos.contains(photo)).firstOrNull;
    if (source == null) return;
    _movePhotos(source, [photo], planId);
  }

  void assignGroup(DraftGroup group, String? planId) {
    if (_archiving || sessionChanged) return;
    _movePhotos(group, group.photos, planId);
  }

  void _movePhotos(DraftGroup source, List<DraftPhoto> moving, String? planId) {
    final fromKey = _groupKey(source.planId), toKey = _groupKey(planId);
    if (fromKey != toKey) {
      final wholeGroup = moving.length == source.photos.length;
      final target = groups.where((g) => g.planId == planId).firstOrNull;
      final carryEdit = wholeGroup && _editedSummaries.contains(fromKey);
      if (carryEdit || _editedSummaries.contains(toKey)) {
        final carried = carryEdit
            ? summaryFor(source)
            : DraftGroup(planId: planId, photos: moving).summary;
        _summaryOverrides[toKey] = [
          if (target != null) summaryFor(target),
          carried,
        ].where((s) => s.trim().isNotEmpty).join('\n');
        _editedSummaries.add(toKey);
      }
      if (wholeGroup) {
        _summaryOverrides.remove(fromKey);
        _editedSummaries.remove(fromKey);
      }
    }
    for (final photo in moving) {
      photo.assignedPlanId = planId;
      photo.manuallyAssigned = true;
    }
    _changed();
  }

  void remove(DraftPhoto photo) {
    if (_archiving) return;
    photo._recognitionVersion++;
    photo._recognitionActive = false;
    for (final job in _recognitionQueue.where((job) => job.photo == photo)) {
      if (!job.completed.isCompleted) job.completed.complete();
    }
    _recognitionQueue.removeWhere((job) => job.photo == photo);
    _photos.remove(photo);
    _pumpRecognitions();
    _changed();
  }

  Future<void> changeSource(DraftPhoto photo, String source) async {
    if (_archiving ||
        _recognitionStarted ||
        sessionChanged ||
        photo.uploaded != null ||
        photo.source == 'camera') {
      return;
    }
    photo.source = source;
    photo._recognitionVersion++;
    photo._recognitionActive = false;
    photo.recognition = null;
    photo.analysis = null;
    photo.assignedPlanId = null;
    photo.manuallyAssigned = false;
    photo.phase = DraftPhotoPhase.preview;
    _changed();
  }

  Future<void> add(
    PreparedPhoto original,
    String source, {
    DateTime? capturedAt,
  }) async {
    if (_disposed || !canAddPhotos || _photos.length >= 9) {
      return;
    }
    final photo = DraftPhoto(
      id: const Uuid().v4(),
      original: original,
      source: source,
      capturedAt: capturedAt,
    );
    if (selectedPlanId != null) {
      photo.manuallyAssigned = true;
      photo.assignedPlanId = selectedPlanId;
    }
    _photos.add(photo);
    AiTiming.mark(
      'photo_queued',
      batch: batchId,
      photo: photo.id,
      bytes: original.bytes.length,
    );
    _changed();
  }

  Future<void> startRecognition() async {
    if (_disposed ||
        _archiving ||
        _recognitionStarted ||
        sessionChanged ||
        _photos.isEmpty) {
      return;
    }
    _recognitionStarted = true;
    final pending = _photos
        .where((photo) => photo.phase == DraftPhotoPhase.preview)
        .map(recognize)
        .toList();
    _changed();
    await Future.wait(pending);
  }

  void returnToPreview() {
    if (_archiving ||
        processing ||
        sessionChanged ||
        _photos.any((p) => p.uploaded != null)) {
      return;
    }
    for (final photo in _photos) {
      photo._recognitionVersion++;
      photo.phase = DraftPhotoPhase.preview;
      photo.error = null;
    }
    _recognitionStarted = false;
    _changed();
  }

  Future<void> recognize(DraftPhoto photo) async {
    if (_disposed ||
        !_recognitionStarted ||
        _archiving ||
        sessionChanged ||
        photo._recognitionActive ||
        photo.uploaded != null ||
        !_photos.contains(photo)) {
      return;
    }
    photo._recognitionActive = true;
    final version = ++photo._recognitionVersion;
    photo.error = null;
    photo.recognition = null;
    photo.phase = photo.analysis == null
        ? DraftPhotoPhase.preparing
        : DraftPhotoPhase.recognizing;
    _changed();
    final job = _RecognitionJob(photo, version);
    _recognitionQueue.add(job);
    _pumpRecognitions();
    await job.completed.future;
  }

  bool _jobCurrent(_RecognitionJob job) =>
      !_disposed &&
      !sessionChanged &&
      _photos.contains(job.photo) &&
      job.version == job.photo._recognitionVersion;

  void _pumpRecognitions() {
    if (_disposed) return;
    while (_activeRecognitions < maxConcurrentRecognitions &&
        _recognitionQueue.isNotEmpty) {
      final job = _recognitionQueue.removeAt(0);
      if (!_jobCurrent(job)) {
        if (!job.completed.isCompleted) job.completed.complete();
        continue;
      }
      _activeRecognitions++;
      unawaited(
        _runRecognition(job).whenComplete(() {
          _activeRecognitions--;
          if (!job.completed.isCompleted) job.completed.complete();
          _pumpRecognitions();
        }),
      );
    }
  }

  Future<void> _runRecognition(_RecognitionJob job) async {
    final photo = job.photo;
    bool current() => _jobCurrent(job);
    try {
      AiTiming.mark('compression_start', batch: batchId, photo: photo.id);
      photo.analysis ??= await _prepare(photo.original.bytes);
      AiTiming.mark(
        'compression_end',
        batch: batchId,
        photo: photo.id,
        bytes: photo.analysis!.bytes.length,
      );
      if (!current()) return;
      photo.phase = DraftPhotoPhase.recognizing;
      _changed();
      final result = await repository.recognize(
        PhotoRecognitionRequest(
          analysisBytes: photo.analysis!.bytes,
          photoId: photo.id,
          batchId: batchId,
          source: photo.source,
          originalSha256: photo.analysis!.originalSha256,
          exifOriginal: photo.original.exifOriginal,
          exifOffset: photo.original.exifOffset,
          // Preview suggestions stay independent from the user's final tag.
        ),
      );
      if (!current()) return;
      if (result.photoId != photo.id) {
        throw const AppException('recognition_mismatch', '识别结果与照片不匹配，请重试');
      }
      photo.recognition = result;
      photo.error = result.error;
      photo.phase = result.isRejected
          ? DraftPhotoPhase.rejected
          : result.isReady
          ? DraftPhotoPhase.ready
          : DraftPhotoPhase.pending;
      AiTiming.mark(
        'photo_terminal',
        batch: batchId,
        photo: photo.id,
        state: photo.phase.name,
      );
    } catch (issue) {
      if (!current()) return;
      // Only the repository converts AI/network failures to pending. Evidence
      // and authorization rejection must remain blocked.
      final issueCode = issue is AppException ? issue.code.toLowerCase() : '';
      photo.phase = issue is AppException && issueCode == 'wrong_date'
          ? DraftPhotoPhase.rejected
          : DraftPhotoPhase.pending;
      photo.error = issue is AppException
          ? issue.message
          : '识别暂时不可用，可先按 ALL 盖章，稍后再补生成。';
      photo.recognition = PhotoRecognition(
        photoId: photo.id,
        status: photo.phase == DraftPhotoPhase.rejected
            ? 'rejected'
            : 'pending',
        error: photo.error,
      );
      AiTiming.mark(
        'photo_terminal',
        batch: batchId,
        photo: photo.id,
        state: photo.phase.name,
      );
    } finally {
      if (job.version == photo._recognitionVersion) {
        photo._recognitionActive = false;
      }
    }
    if (current()) _changed();
  }

  JsonMap groupPayload() {
    if (groups.isEmpty ||
        groups.any((g) => g.photos.any((p) => p.uploaded == null))) {
      throw const AppException('archive_incomplete', '原图尚未全部归档，请重试后盖章。');
    }
    return {
      'groups': [
        for (final group in groups)
          if (group.photos.any((photo) => photo.uploaded != null))
            {
              'plan_id': group.planId,
              'plan_selection':
                  group.photos.any((photo) => photo.manuallyAssigned)
                  ? 'manual'
                  : group.planId == null
                  ? 'all'
                  : 'ai',
              'media_ids': [
                for (final photo in group.photos)
                  if (photo.uploaded != null) photo.uploaded!.id,
              ],
              'summary': summaryFor(group),
              'user_edited': _editedSummaries.contains(_groupKey(group.planId)),
              'fields': group.fields.map((field) => field.toJson()).toList(),
            },
      ],
    };
  }

  Future<List<String>> archiveConfirmed({
    void Function(int, int)? onProgress,
  }) async {
    // Only terminal recognition results can reach the final confirmation step.
    if (!canConfirm || recognizing) return [];
    _archiving = true;
    _changed();
    final eligible = _photos.where((photo) => photo.canArchive).toList();
    final valid = <String>[];
    try {
      for (var index = 0; index < eligible.length; index++) {
        if (_disposed || sessionChanged) return [];
        final photo = eligible[index];
        onProgress?.call(index + 1, eligible.length);
        try {
          AiTiming.mark('archive_start', batch: batchId, photo: photo.id);
          photo.uploaded ??= await repository.upload(
            PhotoUpload(
              bytes: photo.original.bytes,
              filename: photo.original.filename,
              contentType: photo.original.contentType,
              source: photo.source,
              batchId: batchId,
              capturedAt: photo.capturedAt,
              analysisBytes: photo.analysis!.bytes,
              photoId: photo.id,
              recognition: photo.recognition,
            ),
          );
          if (_disposed || sessionChanged) return [];
          photo.uploadError = null;
          AiTiming.mark(
            'archive_end',
            batch: batchId,
            photo: photo.id,
            state: 'saved',
          );
          valid.add(photo.uploaded!.id);
        } catch (issue) {
          AiTiming.mark(
            'archive_end',
            batch: batchId,
            photo: photo.id,
            state: 'unconfirmed',
          );
          if (_disposed || sessionChanged) return [];
          photo.uploadError = issue is AppException
              ? issue.message
              : '原图尚未保存，请重试。';
        }
        _changed();
      }
    } finally {
      _archiving = false;
      _changed();
    }
    return valid;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final job in _recognitionQueue) {
      if (!job.completed.isCompleted) job.completed.complete();
    }
    _recognitionQueue.clear();
    unawaited(_authSubscription.cancel());
    _photos.clear();
    super.dispose();
  }
}
