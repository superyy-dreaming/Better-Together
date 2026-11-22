import 'dart:async';
import 'dart:typed_data';

import 'package:better_together/data/app_repository.dart';
import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/features/checkin/checkin_draft.dart';
import 'package:better_together/platform/photo_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

class DraftRepository extends DemoRepository {
  final requests = <PhotoRecognitionRequest>[];
  final uploads = <PhotoUpload>[];
  String status = 'ready';
  String? suggestion = 'study';
  final suggestions = <String?>[];
  bool rejected = false;
  Completer<void>? gate;
  Completer<void>? uploadGate;
  String? userId = 'draft-owner';
  int activeRecognitions = 0, maxConcurrentRecognitions = 0;
  int failuresRemaining = 0;
  Duration recognitionDelay = Duration.zero;
  final sessions = StreamController<bool>.broadcast();
  @override
  String? get currentUserId => userId;
  @override
  Stream<bool> get authChanges => sessions.stream;
  void switchUser(String? id) {
    userId = id;
    sessions.add(id != null);
  }

  @override
  Future<void> dispose() async {
    await sessions.close();
    await super.dispose();
  }

  @override
  Future<PhotoRecognition> recognize(PhotoRecognitionRequest request) async {
    requests.add(request);
    activeRecognitions++;
    if (activeRecognitions > maxConcurrentRecognitions) {
      maxConcurrentRecognitions = activeRecognitions;
    }
    try {
      if (gate != null) await gate!.future;
      if (recognitionDelay > Duration.zero) {
        await Future<void>.delayed(recognitionDelay);
      }
      if (rejected) throw const AppException('WRONG_DATE', '照片日期不符');
      if (failuresRemaining > 0) {
        failuresRemaining--;
        throw const AppException('AI_FAILED', 'AI 识别失败');
      }
      return PhotoRecognition(
        photoId: request.photoId,
        status: status,
        planId: suggestions.isEmpty ? suggestion : suggestions.removeAt(0),
        confidence: .8,
        summary: status == 'ready' ? '读完了几页' : '',
        error: status == 'pending' ? 'AI 暂不可用' : null,
      );
    } finally {
      activeRecognitions--;
    }
  }

  @override
  Future<UploadedPhoto> upload(PhotoUpload photo) async {
    uploads.add(photo);
    if (uploadGate != null) await uploadGate!.future;
    return UploadedPhoto(
      id: photo.photoId!,
      path: 'private/path',
      source: photo.source,
      capturedAt: DateTime.utc(2026, 11, 18),
    );
  }
}

final originalBytes = Uint8List.fromList([10, 20, 30]);
final analysisBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0]);
final original = PreparedPhoto(originalBytes, 'original.png', 'image/png');
Future<AnalysisPhoto> prepare(Uint8List _) async => AnalysisPhoto(
  bytes: analysisBytes,
  originalSha256: 'digest',
  width: 1600,
  height: 900,
);

void main() {
  test('recognition never archives before confirmation and binds unchanged bytes and device results', () async {
    final repository = DraftRepository();
    final draft = CheckinDraft(
      repository: repository,
      batchId: 'batch',
      prepare: prepare,
    );
    await draft.add(original, 'camera', capturedAt: DateTime.utc(2026, 11, 18));
    expect(repository.uploads, isEmpty);
    expect(repository.requests, isEmpty);
    expect(draft.photos.single.phase, DraftPhotoPhase.preview);
    expect(draft.canConfirm, false);
    await draft.startRecognition();
    expect(repository.requests.single.analysisBytes, analysisBytes);
    expect(repository.requests.single.originalSha256, 'digest');
    expect(draft.groups.any((g) => g.planId == 'study'), isTrue);
    expect(draft.selectedPlanId, isNull);
    expect(draft.canConfirm, true);
    final ids = await draft.archiveConfirmed();
    expect(ids, [draft.photos.single.id]);
    final upload = repository.uploads.single;
    expect(upload.bytes, originalBytes);
    expect(upload.analysisBytes, analysisBytes);
    expect(upload.recognition?.summary, '读完了几页');
    expect(upload.photoId, repository.requests.single.photoId);
    expect(upload.contentType, 'image/png');
    await draft.archiveConfirmed();
    expect(repository.uploads.length, 1);
    draft.dispose();
    await repository.dispose();
  });

  test(
    'AI pending permits ALL but evidence rejection cannot be archived',
    () async {
      final repository = DraftRepository()..status = 'pending';
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      await draft.add(original, 'screenshot');
      await draft.startRecognition();
      expect(draft.canConfirm, true);
      expect(draft.selectedPlanId, isNull);
      expect(draft.groups.single.planId, isNull);
      expect(await draft.archiveConfirmed(), hasLength(1));
      expect(repository.uploads.single.recognition?.status, 'pending');
      draft.dispose();
      await repository.dispose();

      // Evidence rejection is evaluated before the recognition step. Once
      // the user taps "下一步", the batch is intentionally locked for review.
      final rejectedRepository = DraftRepository()..rejected = true;
      final rejectedDraft = CheckinDraft(
        repository: rejectedRepository,
        prepare: prepare,
      );
      await rejectedDraft.add(original, 'album');
      expect(rejectedDraft.photos.single.phase, DraftPhotoPhase.preview);
      await rejectedDraft.startRecognition();
      expect(rejectedDraft.canConfirm, false);
      expect(rejectedDraft.photos.single.canArchive, false);
      expect(rejectedDraft.photos.single.error, '照片日期不符');
      await rejectedDraft.archiveConfirmed();
      expect(rejectedRepository.uploads, isEmpty);
      rejectedDraft.dispose();
      await rejectedRepository.dispose();
    },
  );

  test(
    'preview is editable without recognition; next starts exactly once',
    () async {
      final repository = DraftRepository()..gate = Completer<void>();
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      await draft.add(original, 'album');
      await draft.changeSource(draft.photos.single, 'screenshot');
      await draft.recognize(draft.photos.single);
      expect(repository.requests, isEmpty);
      await draft.add(original, 'camera');
      draft.remove(draft.photos.last);
      final started = draft.startRecognition();
      await draft.startRecognition();
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(1));
      await draft.add(original, 'camera');
      expect(draft.photos, hasLength(1));
      repository.gate!.complete();
      await started;
      expect(draft.canConfirm, isTrue);
      draft.dispose();
      await repository.dispose();
    },
  );

  test(
    'mixed plans split and moving a photo carries its own summary and fields',
    () async {
      final repository = DraftRepository()
        ..suggestions.addAll(['study', 'exercise', 'study']);
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      for (var i = 0; i < 3; i++) {
        await draft.add(original, 'camera');
      }
      await draft.startRecognition();
      for (var i = 0; i < 3; i++) {
        final p = draft.photos[i];
        p.recognition = PhotoRecognition(
          photoId: p.id,
          status: 'ready',
          planId: i == 1 ? 'exercise' : 'study',
          confidence: .9,
          summary: '照片摘要 $i',
          fields: [
            MemoField(key: 'content', label: '内容', value: '$i', source: 'ai'),
          ],
        );
      }
      expect(draft.groups.map((g) => g.photos.length), [2, 1]);
      draft.assignPhoto(draft.photos.first, 'exercise');
      expect(
        draft.groups.singleWhere((g) => g.planId == 'exercise').summary,
        '照片摘要 0\n照片摘要 1',
      );
      expect(
        draft.groups.singleWhere((g) => g.planId == 'study').summary,
        '照片摘要 2',
      );
      await draft.archiveConfirmed();
      final groups = jsonList(draft.groupPayload()['groups'])
          .map(jsonObject)
          .toList();
      expect(
        groups.singleWhere((g) => g['plan_id'] == 'exercise')['media_ids'],
        [draft.photos[0].id, draft.photos[1].id],
      );
      expect(
        jsonList(groups.singleWhere((g) => g['plan_id'] == 'study')['fields'])
            .map((f) => jsonObject(f)['value']),
        ['2'],
      );
      draft.dispose();
      await repository.dispose();
    },
  );

  test('whole-group plan changes preserve manual memo and late results cannot undo edits', () async {
    final repository = DraftRepository()..status = 'pending';
    final draft = CheckinDraft(repository: repository, prepare: prepare);
    await draft.add(original, 'camera');
    await draft.startRecognition();
    draft.editGroupSummary(null, '我确认的事实');
    draft.assignGroup(draft.groups.single, 'exercise');
    expect(draft.summaryFor(draft.groups.single), '我确认的事实');
    repository.status = 'ready';
    repository.suggestion = 'study';
    await draft.recognize(draft.photos.single);
    expect(draft.groups.single.planId, 'exercise');
    expect(draft.summaryFor(draft.groups.single), '我确认的事实');
    await draft.archiveConfirmed();
    final group = jsonObject(jsonList(draft.groupPayload()['groups']).single);
    expect(group['plan_selection'], 'manual');
    expect(group['user_edited'], isTrue);
    expect(group['summary'], '我确认的事实');
    expect(draft.photos.single.recognition!.summary, isNotEmpty);
    draft.dispose();
    await repository.dispose();
  });

  test(
    'low-confidence and incomplete photos stay ALL without hiding valid groups',
    () async {
      final repository = DraftRepository();
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      for (var i = 0; i < 3; i++) {
        await draft.add(original, 'camera');
      }
      await draft.startRecognition();
      draft.photos[1].recognition = PhotoRecognition(
        photoId: draft.photos[1].id,
        status: 'ready',
        planId: 'exercise',
        confidence: .79,
      );
      draft.photos[2].phase = DraftPhotoPhase.pending;
      draft.photos[2].recognition = PhotoRecognition(
        photoId: draft.photos[2].id,
        status: 'pending',
      );
      expect(
        draft.groups.singleWhere((g) => g.planId == null).photos,
        hasLength(2),
      );
      expect(
        draft.groups.singleWhere((g) => g.planId == 'study').photos,
        hasLength(1),
      );
      expect(draft.canConfirm, isTrue);
      expect(() => draft.groupPayload(), throwsA(isA<AppException>()));
      draft.returnToPreview();
      expect(draft.canAddPhotos, isTrue);
      expect(draft.canConfirm, isFalse);
      draft.dispose();
      await repository.dispose();
    },
  );

  test('mixed completed photos keep both plan groups', () async {
    final repository = DraftRepository();
    final draft = CheckinDraft(repository: repository, prepare: prepare);
    await draft.add(original, 'camera');
    repository.suggestions.add('exercise');
    await draft.add(original, 'camera');
    repository.suggestions.add('study');
    await draft.add(original, 'camera');
    repository.suggestions.add('study');
    await draft.startRecognition();
    expect(draft.groups.any((g) => g.planId == 'study'), isTrue);
    expect(draft.selectedPlanId, isNull);
    draft.dispose();
    await repository.dispose();
  });

  test(
    'removing a processing photo ignores its late result and never archives it',
    () async {
      final repository = DraftRepository()..gate = Completer<void>();
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      final pending = draft.add(original, 'camera');
      final recognition = draft.startRecognition();
      await Future<void>.delayed(Duration.zero);
      expect(draft.canConfirm, false);
      draft.remove(draft.photos.single);
      repository.gate!.complete();
      await Future.wait([pending, recognition]);
      expect(draft.photos, isEmpty);
      expect(repository.uploads, isEmpty);
      draft.dispose();
      await repository.dispose();
    },
  );

  test('manual plan survives recognition without premature archive', () async {
    final repository = DraftRepository()..gate = Completer<void>();
    final draft = CheckinDraft(
      repository: repository,
      selectedPlanId: 'exercise',
      prepare: prepare,
    );
    await draft.add(original, 'camera');
    final recognition = draft.startRecognition();
    await Future<void>.delayed(Duration.zero);
    expect(draft.canConfirm, isFalse);
    expect(await draft.archiveConfirmed(), isEmpty);
    expect(repository.uploads, isEmpty);
    repository.gate!.complete();
    await recognition;
    expect(draft.groups.single.planId, 'exercise');
    expect(draft.photos.single.recognition!.planId, 'study');
    expect(draft.canConfirm, isTrue);
    draft.dispose();
    await repository.dispose();
  });

  test('multi-photo recognition is capped at four and a failed photo is independently retryable', () async {
    final repository = DraftRepository()
      ..recognitionDelay = const Duration(milliseconds: 20)
      ..failuresRemaining = 1;
    final draft = CheckinDraft(repository: repository, prepare: prepare);
    await Future.wait(List.generate(9, (_) => draft.add(original, 'camera')));
    await draft.startRecognition();
    expect(repository.maxConcurrentRecognitions, 4);
    expect(draft.photos, hasLength(9));
    expect(
      draft.photos.where((photo) => photo.phase == DraftPhotoPhase.ready),
      hasLength(8),
    );
    expect(
      draft.photos.where((photo) => photo.phase == DraftPhotoPhase.pending),
      hasLength(1),
    );
    expect(draft.canConfirm, isTrue);

    repository.failuresRemaining = 0;
    await draft.recognize(
      draft.photos.firstWhere(
        (photo) => photo.phase == DraftPhotoPhase.pending,
      ),
    );
    expect(
      draft.photos.where((photo) => photo.phase == DraftPhotoPhase.ready),
      hasLength(9),
    );
    expect(repository.maxConcurrentRecognitions, 4);
    draft.dispose();
    await repository.dispose();
  });

  test('compression and recognition complete before confirmation', () async {
    final repository = DraftRepository()..gate = Completer<void>();
    final compression = Completer<AnalysisPhoto>();
    final draft = CheckinDraft(
      repository: repository,
      prepare: (_) => compression.future,
    );
    await draft.add(original, 'camera');
    final recognition = draft.startRecognition();
    await Future<void>.delayed(Duration.zero);
    expect(draft.canConfirm, isFalse);
    expect(repository.requests, isEmpty);
    compression.complete(await prepare(originalBytes));
    while (repository.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(draft.canConfirm, isFalse);
    repository.gate!.complete();
    await recognition;
    expect(draft.canConfirm, isTrue);
    expect(repository.uploads, isEmpty);
    draft.dispose();
    await repository.dispose();
  });

  test(
    'switching accounts clears originals and ignores late recognition',
    () async {
      final repository = DraftRepository()..gate = Completer<void>();
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      final request = draft.add(original, 'camera');
      final recognition = draft.startRecognition();
      await Future<void>.delayed(Duration.zero);
      repository.switchUser('another-owner');
      await Future<void>.delayed(Duration.zero);
      expect(draft.photos, isEmpty);
      expect(draft.sessionChanged, true);
      expect(await draft.archiveConfirmed(), isEmpty);
      repository.gate!.complete();
      await Future.wait([request, recognition]);
      await draft.add(original, 'camera');
      expect(draft.photos, isEmpty);
      expect(repository.uploads, isEmpty);
      draft.dispose();
      await repository.dispose();
    },
  );

  test(
    'account change during archive cannot upload remaining originals',
    () async {
      final repository = DraftRepository();
      final draft = CheckinDraft(repository: repository, prepare: prepare);
      await draft.add(original, 'camera');
      await draft.add(original, 'camera');
      await draft.startRecognition();
      repository.uploadGate = Completer<void>();
      final archive = draft.archiveConfirmed();
      await Future<void>.delayed(Duration.zero);
      expect(repository.uploads, hasLength(1));
      repository.switchUser('another-owner');
      repository.uploadGate!.complete();
      expect(await archive, isEmpty);
      expect(repository.uploads, hasLength(1));
      draft.dispose();
      await repository.dispose();
    },
  );
}
