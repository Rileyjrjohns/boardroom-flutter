import 'dart:convert';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

final Map<String, Object?> _wire = toVoteRequestWire(aVote()).toJson();

Result<VoteRequestWire, WireFailure> _parse(Object? json) =>
    decodeWire(json, VoteRequestWire.fromJson);

void main() {
  group('the vote request', () {
    test('writes the vote without its key: the key is derived from '
        'the resolution and the voter', () {
      expect(
        _wire,
        equals({
          'resolutionId': 'resolution-1',
          'meetingId': 'meeting-1',
          'voterId': 'user-1',
          'choice': 'for',
          'castAt': '2030-03-17T17:46:40.000Z',
        }),
      );
    });

    for (final choice in [
      VoteChoice.forChoice,
      VoteChoice.against,
      VoteChoice.abstain,
    ]) {
      test('gives the vote back as it was, for the choice ${choice.value}', () {
        final vote = aVote(choice: choice, castAt: at(1234));

        final parsed = unwrap(
          _parse(jsonDecode(jsonEncode(toVoteRequestWire(vote).toJson()))),
        );

        expect(toVote(parsed), equals(ok(vote)));
      });
    }

    test('ignores the fields it does not know, even an idempotency '
        'key it did not derive', () {
      final parsed = unwrap(
        _parse({..._wire, 'idempotencyKey': 'forged', 'extra': 1}),
      );

      expect(parsed.toJson().containsKey('idempotencyKey'), isFalse);
      expect(
        unwrap(toVote(parsed)).idempotencyKey,
        equals('12.resolution-1.user-1'),
      );
    });

    for (final field in _wire.keys) {
      test('fails when $field is missing', () {
        final rest = {..._wire}..remove(field);

        expect(_parse(rest), isA<Err<Object?, WireFailure>>());
      });
    }

    for (final (field, value) in <(String, Object?)>[
      ('resolutionId', 1),
      ('choice', true),
      ('castAt', 1900000000000),
      ('castAt', 'now'),
    ]) {
      test('fails when $field is ${jsonEncode(value)}', () {
        expect(
          _parse({..._wire, field: value}),
          isA<Err<Object?, WireFailure>>(),
        );
      });
    }

    for (final (name, change, field)
        in <(String, Map<String, Object?>, ValidationField)>[
          (
            'a choice nobody knows',
            {'choice': 'maybe'},
            ValidationField.voteChoice,
          ),
          (
            'a blank resolution',
            {'resolutionId': ''},
            ValidationField.resolutionId,
          ),
          ('a blank meeting', {'meetingId': ' '}, ValidationField.meetingId),
          ('a blank voter', {'voterId': ''}, ValidationField.userId),
        ]) {
      test('refuses $name through the factories of the domain', () {
        final mapped = toVote(unwrap(_parse({..._wire, ...change})));

        expect(
          mapped,
          isA<Err<Object?, ValidationError>>().having(
            (result) => result.error.field,
            'field',
            field,
          ),
        );
      });
    }
  });
}
