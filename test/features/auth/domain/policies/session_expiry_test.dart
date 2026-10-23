import 'package:boardroom/features/auth/domain/policies/session_expiry.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

void main() {
  group('isSessionExpired', () {
    final session = aSession(expiresAt: now);

    test('is false before the expiry', () {
      expect(isSessionExpired(session, at(-1)), isFalse);
    });

    test('is true at the expiry instant', () {
      expect(isSessionExpired(session, now), isTrue);
    });

    test('is true after the expiry', () {
      expect(isSessionExpired(session, at(1)), isTrue);
    });
  });
}
