import 'package:better_together/data/demo_repository.dart';
import 'package:better_together/domain/models.dart';
import 'package:better_together/domain/notification_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'notification targets resolve within the current authorized snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = DemoRepository();
      addTearDown(repository.dispose);
      final snapshot = await repository.bootstrap();
      final mine = snapshot.reports.firstWhere(
        (r) => r.userId == snapshot.profile.id,
      );
      expect(notificationRoute('interaction', mine.id, snapshot), '/reports');
      final card = snapshot.checkins.first;
      expect(notificationRoute('stamp', card.id, snapshot), '/memo/${card.id}');
      expect(
        notificationRoute('interaction', card.id, snapshot),
        '/memo/${card.id}',
      );
      expect(notificationRoute('report', null, snapshot), '/reports');
      expect(
        notificationRoute('challenge', 'unknown', snapshot),
        '/notifications',
      );
      expect(
        notificationRoute('challenge', 'https://example.com', snapshot),
        '/notifications',
      );
      expect(notificationRoute('report', mine.id, null), '/notifications');
      final plan = snapshot.plans.first;
      expect(
        notificationRoute('reminder', plan.id, snapshot),
        '/checkin?plan=${plan.id}',
      );
    },
  );

  test('a teammate report notification leads to the shared team feed', () {
    final snapshot = AppSnapshot.fromJson({
      'profile': {'id': 'me'},
      'reports': [
        {
          'id': 'friend-report',
          'user_id': 'friend',
          'kind': 'personal',
          'shared': true,
        },
      ],
    });
    expect(notificationRoute('report', 'friend-report', snapshot), '/team');
    expect(
      notificationRoute('interaction', 'friend-report', snapshot),
      '/team',
    );
  });
}
