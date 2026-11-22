import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_controller.dart';
import 'checkin_draft.dart';

typedef CheckinDraftKey = ({
  String? planId,
  String? redoOf,
  String? targetDate,
});

/// A draft survives navigation and ordinary app suspension. Account changes
/// clear its originals; confirmed records use the persistent archived AI queue.
final checkinDraftProvider = Provider.family<CheckinDraft, CheckinDraftKey>((
  ref,
  key,
) {
  final draft = CheckinDraft(
    repository: ref.watch(repositoryProvider),
    selectedPlanId: key.planId,
  );
  ref.onDispose(draft.dispose);
  ref.listen(authStateProvider, (_, _) {
    if (draft.sessionChanged) ref.invalidateSelf();
  });
  return draft;
});
