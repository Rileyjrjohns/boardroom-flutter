import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/policies/voting_state.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/builders/names.dart';

void main() {
  group('getVotingState', () {
    test('is open for an open resolution without a closing instant', () {
      expect(getVotingState(aResolution(), now), equals(VotingState.open));
    });

    test(
      'is open until the closing instant, one millisecond before included',
      () {
        expect(
          getVotingState(aResolution(closesAt: at(1)), now),
          equals(VotingState.open),
        );
      },
    );

    for (final offset in [0, -1, -3600000]) {
      test('is window over when the closing instant is ${formatPretty(offset)} '
          'ms from now, the instant itself included', () {
        expect(
          getVotingState(aResolution(closesAt: at(offset)), now),
          equals(VotingState.windowOver),
        );
      });
    }

    test('is closed for a closed resolution, whatever the closing instant', () {
      const closed = ResolutionStatus.closed;
      expect(
        getVotingState(aResolution(status: closed), now),
        equals(VotingState.closed),
      );
      expect(
        getVotingState(aResolution(status: closed, closesAt: at(1)), now),
        equals(VotingState.closed),
      );
      expect(
        getVotingState(aResolution(status: closed, closesAt: at(-1)), now),
        equals(VotingState.closed),
      );
    });

    test('judges at the instant it is given, not at a clock of its own', () {
      final resolution = aResolution(closesAt: at(1000));
      expect(getVotingState(resolution, at(999)), equals(VotingState.open));
      expect(
        getVotingState(resolution, at(1000)),
        equals(VotingState.windowOver),
      );
    });
  });
}
