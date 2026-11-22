import 'models.dart';

/// Resolve only objects in the authorized snapshot, never an arbitrary push URL.
String notificationRoute(String kind, String? targetId, AppSnapshot? snapshot) {
  if (snapshot == null) return '/notifications';
  final report = snapshot.reports.where((r) => r.id == targetId).firstOrNull;
  if (report != null) {
    return report.kind == 'personal' && report.userId != snapshot.profile.id
        ? '/team'
        : '/reports';
  }
  if (targetId != null && snapshot.checkins.any((c) => c.id == targetId)) {
    return '/memo/${Uri.encodeComponent(targetId)}';
  }
  final overdue = snapshot.overdue.where((o) => o.id == targetId).firstOrNull;
  if (overdue != null) {
    return overdue.userId == snapshot.profile.id && overdue.status == 'open'
        ? '/checkin?plan=${Uri.encodeComponent(overdue.planId)}'
        : '/team';
  }
  if (kind == 'reminder' && snapshot.plans.any((p) => p.id == targetId)) {
    return '/checkin?plan=${Uri.encodeComponent(targetId!)}';
  }
  if (kind == 'report' && targetId == null) return '/reports';
  return '/notifications';
}
