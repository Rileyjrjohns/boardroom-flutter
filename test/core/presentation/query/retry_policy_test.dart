import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/query/retry_policy.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:flutter_test/flutter_test.dart';

// The scenarios of `retryPolicy.test.ts` and `createQueryClient.test.ts` for
// the retry: at most two retries, 0.5 s then 1 s, only for the codes a second
// try can fix, a session-ending code ends the session and is reported at once.

void main() {
  final ended = <(String, int?)>[];
  late RetryPolicy policy;

  setUp(() {
    ended.clear();
    policy = RetryPolicy(
      catalog: createAppErrorCatalog(),
      isSessionEndingCode: isSessionEndingCode,
      onSessionEnded: (code, startedUnder) => ended.add((code, startedUnder)),
    );
  });

  QueryFailure failure(AppError error, {int? startedUnder}) =>
      QueryFailure(error, startedUnder: startedUnder);

  group('RetryPolicy', () {
    test('retries a network failure twice, after 0.5 s then 1 s', () {
      final error = failure(networkUnavailable());

      expect(policy(0, error), const Duration(milliseconds: 500));
      expect(policy(1, error), const Duration(seconds: 1));
      expect(policy(2, error), isNull);
    });

    test('doubles the wait up to the cap of 4 s', () {
      expect(policy.delayOf(0), retryBaseDelay);
      expect(policy.delayOf(2), const Duration(seconds: 2));
      expect(policy.delayOf(3), retryMaxDelay);
      expect(policy.delayOf(9), retryMaxDelay);
    });

    test('retries every code the catalog calls retryable', () {
      for (final error in <AppError>[
        networkUnavailable(),
        unexpected(),
        storageReadFailed(),
      ]) {
        expect(policy(0, failure(error)), isNotNull, reason: error.code);
      }
    });

    test('reports at once a code a second try cannot fix', () {
      for (final error in <AppError>[
        forbidden(),
        notFound(),
        validationError(ValidationField.email, ValidationRule.required),
        invalidCredentials(),
      ]) {
        expect(policy(0, failure(error)), isNull, reason: error.code);
      }
      expect(ended, isEmpty);
    });

    test(
      'ends the session on a session-ending code, and reports it at once',
      () {
        for (final code in sessionEndingCodes) {
          ended.clear();
          final error = switch (code) {
            'unauthorized' => unauthorized(),
            'notAuthenticated' => notAuthenticated(),
            'sessionExpired' => sessionExpired(),
            'sessionChanged' => sessionChanged(),
            _ => appLocked(),
          };

          expect(policy(0, failure(error, startedUnder: 4)), isNull);
          expect(ended, [(code, 4)]);
        }
      },
    );

    test('reads what is not the failure of a use case as unexpected and '
        'retries it', () {
      expect(policy(0, Exception('a bug')), isNotNull);
      expect(policy(0, 'a string'), isNotNull);
      expect(policy(2, Exception('a bug')), isNull);
    });

    test('reports a programming error at once', () {
      expect(policy(0, UnimplementedError('provider not overridden')), isNull);
    });

    test('reads a code no screen has a text for as unexpected', () {
      final unknown = failure(const _UnknownError());

      expect(policy(0, unknown), isNotNull);
      expect(errorCodeOf(unknown, createAppErrorCatalog()), 'unexpected');
    });

    test('takes the wait from its base delay', () {
      final instant = RetryPolicy(
        catalog: createAppErrorCatalog(),
        isSessionEndingCode: _never,
        baseDelay: Duration.zero,
      );

      expect(instant.delayOf(1), Duration.zero);
    });
  });
}

bool _never(String code) => false;

final class _UnknownError extends AppError {
  const new();

  @override
  String get code => 'somethingNew';
}
