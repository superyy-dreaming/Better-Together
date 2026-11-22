import 'package:better_together/domain/invitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes short codes and preserves old invitations', () {
    expect(invitationToken(' abcd-23ef '), 'ABCD23EF');
    expect(invitationToken('bettertogether://invite/ABCD23EF'), 'ABCD23EF');
    expect(
      invitationToken('bettertogether://invite?token=ABCD23EF'),
      'ABCD23EF',
    );
    expect(invitationToken('ab' * 24), 'ab' * 24);
    expect(invitationToken('bettertogether://invite/${'ab' * 24}'), 'ab' * 24);
    expect(displayInvitationCode('ABCD23EF'), 'ABCD 23EF');
  });
  test('scanned links are constrained to the application', () {
    expect(invitationToken('https://evil.example/invite/ABCD23EF'), isNull);
    expect(
      invitationToken(
        'https://trusted.example/invite/ABCD23EF',
        linkHost: 'trusted.example',
      ),
      'ABCD23EF',
    );
    expect(
      invitationToken(
        'https://evil@trusted.example/invite/ABCD23EF',
        linkHost: 'trusted.example',
      ),
      isNull,
    );
    expect(invitationToken('bettertogether://auth/ABCD23EF'), isNull);
    expect(invitationToken('bettertogether://invite/extra/ABCD23EF'), isNull);
    expect(invitationToken('0123IOAB'), isNull);
    expect(invitationToken(''), isNull);
    expect(invitationToken('A' * 2000), isNull);
  });
}
