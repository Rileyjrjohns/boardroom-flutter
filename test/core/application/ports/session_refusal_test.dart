import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:test/test.dart';

// Dart only: the refusal is the plain answer of the `SessionGate` port, which
// core declares so that it needs no session type of auth.

void main() {
  group('SessionRefusal', () {
    test(
      'is equal to another one with the same error and the same verdict',
      () {
        expect(
          SessionRefusal(error: appLocked(), sessionKept: true),
          equals(SessionRefusal(error: appLocked(), sessionKept: true)),
        );
        expect(
          SessionRefusal(error: appLocked(), sessionKept: true).hashCode,
          equals(
            SessionRefusal(error: appLocked(), sessionKept: true).hashCode,
          ),
        );
      },
    );

    test('differs by its error or by its verdict', () {
      expect(
        SessionRefusal(error: appLocked(), sessionKept: true),
        isNot(equals(SessionRefusal(error: appLocked(), sessionKept: false))),
      );
      expect(
        SessionRefusal(error: appLocked(), sessionKept: true),
        isNot(
          equals(SessionRefusal(error: sessionChanged(), sessionKept: true)),
        ),
      );
    });

    test('prints its error and its verdict', () {
      expect(
        SessionRefusal(error: appLocked(), sessionKept: true).toString(),
        equals(
          'SessionRefusal(error: AppError(code: appLocked), sessionKept: true)',
        ),
      );
    });
  });
}
