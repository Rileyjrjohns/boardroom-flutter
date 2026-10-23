import 'dart:ui';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/error_messages.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';

// The domain and the application speak in codes. These tests check that every
// code of a family has a text in both languages, each its own, and that the
// texts depend on where a vote already cast is.

const List<Locale> _locales = [Locale('en'), Locale('fr')];

AppLocalizations _l10n(Locale locale) => lookupAppLocalizations(locale);

void _checkTotal(
  String name,
  Map<String, ErrorMessage> messages,
  Iterable<String> codes,
) {
  group(name, () {
    test('has an entry for every code of its family, and for nothing else', () {
      expect(messages.keys.toSet(), codes.toSet());
    });

    for (final locale in _locales) {
      test('has a text in ${locale.languageCode} for every code', () {
        final l10n = _l10n(locale);
        for (final code in codes) {
          expect(messages[code]!(l10n), isNotEmpty, reason: code);
        }
      });
    }
  });
}

void main() {
  _checkTotal('castVoteErrorMessages', castVoteErrorMessages, [
    ...RepositoryErrorCode.values.map((code) => code.value),
    ...VotingErrorCode.values.map((code) => code.value),
    ...BiometricErrorCode.values.map((code) => code.value),
    AuthenticationErrorCode.notAuthenticated.value,
    AuthenticationErrorCode.sessionExpired.value,
    AuthenticationErrorCode.appLocked.value,
    AuthenticationErrorCode.sessionChanged.value,
    ...StorageErrorCode.values.map((code) => code.value),
    VoteDeliveryErrorCode.inProgress.value,
    VoteDeliveryErrorCode.previouslyRejected.value,
  ]);

  _checkTotal('acknowledgeErrorMessages', acknowledgeErrorMessages, [
    AuthenticationErrorCode.notAuthenticated.value,
    AuthenticationErrorCode.sessionExpired.value,
    AuthenticationErrorCode.appLocked.value,
    AuthenticationErrorCode.sessionChanged.value,
    ...StorageErrorCode.values.map((code) => code.value),
    VoteDeliveryErrorCode.notRejected.value,
    RepositoryErrorCode.unexpected.value,
  ]);

  _checkTotal('discardErrorMessages', discardErrorMessages, [
    AuthenticationErrorCode.notAuthenticated.value,
    AuthenticationErrorCode.sessionExpired.value,
    AuthenticationErrorCode.appLocked.value,
    AuthenticationErrorCode.sessionChanged.value,
    ...StorageErrorCode.values.map((code) => code.value),
    RepositoryErrorCode.unexpected.value,
  ]);

  group('votingReasonText', () {
    for (final locale in _locales) {
      test('tells every rule of the vote in ${locale.languageCode}, '
          'each with its own text', () {
        final l10n = _l10n(locale);
        final texts = [
          votingReasonMessage(
            l10n,
            ResolutionNotFoundError(resolutionId: aResolutionId()),
          ),
          votingReasonMessage(l10n, const NotAParticipantError()),
          votingReasonMessage(l10n, const NoVotingRightsError()),
          votingReasonMessage(l10n, const ResolutionClosedError()),
          votingReasonMessage(l10n, const VotingWindowOverError()),
          votingReasonMessage(
            l10n,
            const AlreadyVotedError(source: AlreadyVotedSource.recorded),
          ),
          votingReasonMessage(
            l10n,
            const AlreadyVotedError(source: AlreadyVotedSource.queued),
          ),
        ];

        expect(texts.toSet().length, texts.length);
      });
    }

    test('tells a vote already cast differently when it waits to be sent', () {
      final en = _l10n(const Locale('en'));

      expect(
        votingReasonMessage(
          en,
          const AlreadyVotedError(source: AlreadyVotedSource.queued),
        ),
        en.votesVotingReasonAlreadyVotedQueued,
      );
    });
  });

  group('rejectionReasonText', () {
    test('tells a rule of the vote the way the rules are told', () {
      final en = _l10n(const Locale('en'));

      expect(
        rejectionReasonMessage(en, const ResolutionClosedError()),
        en.votesVotingReasonResolutionClosed,
      );
    });

    for (final (locale, attempts) in [
      (const Locale('en'), 1),
      (const Locale('en'), 5),
      (const Locale('fr'), 1),
      (const Locale('fr'), 5),
    ]) {
      test('counts the attempts of a vote that was given up, '
          'in ${locale.languageCode}: $attempts', () {
        final l10n = _l10n(locale);

        expect(
          rejectionReasonMessage(l10n, voteUndeliverable(attempts)),
          l10n.votesVotingReasonVoteUndeliverable(attempts),
        );
        expect(
          rejectionReasonMessage(l10n, voteUndeliverable(attempts)),
          contains('$attempts'),
        );
      });
    }

    test('writes one attempt and several attempts differently', () {
      final en = _l10n(const Locale('en'));

      expect(
        rejectionReasonMessage(en, voteUndeliverable(1)),
        isNot(rejectionReasonMessage(en, voteUndeliverable(5))),
      );
    });
  });

  group('castVoteErrorText', () {
    for (final locale in _locales) {
      test('has a text in ${locale.languageCode} for every biometric '
          'outcome, each its own', () {
        final l10n = _l10n(locale);
        final texts = [
          for (final code in BiometricErrorCode.values)
            castVoteErrorMessage(l10n, _error(code.value)),
        ];

        expect(texts.toSet().length, texts.length);
      });
    }

    test('tells a vote already cast by where it is', () {
      final en = _l10n(const Locale('en'));

      expect(
        castVoteErrorMessage(
          en,
          const AlreadyVotedError(source: AlreadyVotedSource.queued),
        ),
        en.votesVotingReasonAlreadyVotedQueued,
      );
      expect(
        castVoteErrorMessage(
          en,
          const AlreadyVotedError(source: AlreadyVotedSource.recorded),
        ),
        en.votesVotingReasonAlreadyVotedRecorded,
      );
    });

    test('tells a vote in progress and a vote that was rejected before', () {
      final en = _l10n(const Locale('en'));

      expect(
        castVoteErrorMessage(en, voteInProgress()),
        en.votesVotingFailureVoteInProgress,
      );
      expect(
        castVoteErrorMessage(
          en,
          votePreviouslyRejected(const ResolutionClosedError()),
        ),
        en.votesVotingFailureVotePreviouslyRejected,
      );
    });

    test('falls back to the unexpected text for a code it does not know', () {
      final en = _l10n(const Locale('en'));

      expect(
        castVoteErrorMessage(en, _error('somethingNew')),
        en.coreErrorsUnexpected,
      );
    });
  });

  group('CAST_OUTCOME_KEYS', () {
    test('tells a recorded vote with a message, and a vote that '
        'waits with none: the resolution says that', () {
      final en = _l10n(const Locale('en'));

      expect(
        castOutcomeMessage(en, CastVoteStatus.submitted),
        en.votesVotingSubmitted,
      );
      expect(castOutcomeMessage(en, CastVoteStatus.queued), isNull);
    });

    for (final locale in _locales) {
      test('has the translation of the message in ${locale.languageCode}', () {
        expect(
          castOutcomeMessage(_l10n(locale), CastVoteStatus.submitted),
          isNotEmpty,
        );
      });
    }
  });
}

final class _CodeError extends AppError {
  const new(this.code);

  @override
  final String code;
}

AppError _error(String code) => _CodeError(code);
