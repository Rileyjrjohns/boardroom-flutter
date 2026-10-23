import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';

void main() {
  group('createSession', () {
    test('holds the user and the expiry', () {
      final user = aUser();

      expect(
        createSession(user: user, expiresAt: at(millisPerHour)),
        equals(Session(user: user, expiresAt: at(millisPerHour))),
      );
    });
  });
}
