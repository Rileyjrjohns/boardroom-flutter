import 'dart:convert';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/infrastructure/rejection_schemas.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';

/// A value through JSON, the way it travels.
Object? _overTheWire(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value));

String _json(Object? value) => jsonEncode(value);

final List<VotingError> _votingErrors = [
  ResolutionNotFoundError(resolutionId: aResolutionId('gone')),
  const NotAParticipantError(),
  const NoVotingRightsError(),
  const ResolutionClosedError(),
  const VotingWindowOverError(),
  const AlreadyVotedError(source: AlreadyVotedSource.recorded),
  const AlreadyVotedError(source: AlreadyVotedSource.queued),
];

Result<VotingErrorWire, WireFailure> _votingErrorOf(Object? json) =>
    decodeWire(json, votingErrorWireFromJson);

Result<RejectionReasonWire, WireFailure> _rejectionReasonOf(Object? json) =>
    decodeWire(json, rejectionReasonWireFromJson);

void main() {
  group('the schemas of a rejected vote', () {
    for (final error in _votingErrors) {
      test('give a voting error back as it was: '
          '${_json(toVotingErrorWire(error).toJson())}', () {
        final parsed = _votingErrorOf(
          _overTheWire(toVotingErrorWire(error).toJson()),
        );

        expect(switch (parsed) {
          Ok(:final value) => toVotingError(value),
          Err() => null,
        }, equals(ok(error)));
      });
    }

    for (final reason in [..._votingErrors, voteUndeliverable(4)]) {
      test('give a rejection reason back as it was: '
          '${_json(toRejectionReasonWire(reason).toJson())}', () {
        final parsed = _rejectionReasonOf(
          _overTheWire(toRejectionReasonWire(reason).toJson()),
        );

        expect(switch (parsed) {
          Ok(:final value) => toRejectionReason(value),
          Err() => null,
        }, equals(ok(reason)));
      });
    }

    test('keeps the voting errors apart from the giving up of a vote', () {
      const undeliverable = {'code': 'voteUndeliverable', 'attempts': 3};

      expect(_votingErrorOf(undeliverable), isA<Err<Object?, WireFailure>>());
      expect(
        _rejectionReasonOf(undeliverable),
        isA<Ok<Object?, WireFailure>>(),
      );
    });

    for (final wire in <Object?>[
      <String, Object?>{},
      {'code': 'somethingElse'},
      {'code': 'resolutionNotFound'},
      {'code': 'resolutionNotFound', 'resolutionId': 12},
      {'code': 'alreadyVoted'},
      {'code': 'alreadyVoted', 'source': 'elsewhere'},
      {'code': 'voteUndeliverable', 'attempts': -1},
      {'code': 'voteUndeliverable', 'attempts': 1.5},
      {'code': 'voteUndeliverable'},
      'resolutionClosed',
      null,
    ]) {
      test('refuse ${_json(wire)}', () {
        expect(_rejectionReasonOf(wire), isA<Err<Object?, WireFailure>>());
      });
    }

    test('ignore the fields they do not know', () {
      final parsed = _votingErrorOf({
        'code': 'resolutionClosed',
        'detail': 'ignored',
      });

      expect(switch (parsed) {
        Ok(:final value) => value.toJson(),
        Err() => null,
      }, equals({'code': 'resolutionClosed'}));
    });

    test(
      'refuse a resolution id that is blank through the factory of the domain',
      () {
        final parsed = unwrap(
          _votingErrorOf({'code': 'resolutionNotFound', 'resolutionId': ' '}),
        );

        expect(toVotingError(parsed), isA<Err<Object?, ValidationError>>());
        expect(toRejectionReason(parsed), isA<Err<Object?, ValidationError>>());
      },
    );

    test('name the place of the flaw and no value', () {
      expect(
        _rejectionReasonOf({'code': 'alreadyVoted', 'source': 'elsewhere'}),
        equals(err(const WireFailure('source'))),
      );
    });
  });
}
