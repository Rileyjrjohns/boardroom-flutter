import 'package:boardroom/domain/entities/participant.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

void main() {
  group('createParticipant', () {
    test('builds a participant with a trimmed name', () {
      expect(
        createParticipant(
          userId: aUserId(),
          fullName: ' Alice Martin ',
          role: ParticipantRole.chair,
        ),
        equals(
          ok(
            Participant(
              userId: aUserId(),
              fullName: 'Alice Martin',
              role: ParticipantRole.chair,
            ),
          ),
        ),
      );
    });

    test('rejects a blank name', () {
      expect(
        createParticipant(
          userId: aUserId(),
          fullName: '',
          role: ParticipantRole.member,
        ),
        equals(
          err(
            validationError(ValidationField.fullName, ValidationRule.required),
          ),
        ),
      );
    });
  });

  group('hasVotingRights', () {
    for (final (role, expected) in <(ParticipantRole, bool)>[
      (ParticipantRole.chair, true),
      (ParticipantRole.member, true),
      (ParticipantRole.secretary, false),
      (ParticipantRole.guest, false),
    ]) {
      test('is decided by the role: ${role.value} -> $expected', () {
        expect(hasVotingRights(aParticipant(role: role)), equals(expected));
      });
    }
  });

  group('parseParticipantRole', () {
    for (final role in ParticipantRole.values) {
      test('parses ${role.value}', () {
        expect(parseParticipantRole(role.value), equals(ok(role)));
      });
    }

    test('rejects an unknown role', () {
      expect(
        parseParticipantRole('owner'),
        equals(
          err(
            validationError(
              ValidationField.participantRole,
              ValidationRule.unknownValue,
            ),
          ),
        ),
      );
    });
  });
}
