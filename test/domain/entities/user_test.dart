import 'package:boardroom/domain/entities/user.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

void main() {
  group('createUser', () {
    test('builds a user with a trimmed name', () {
      expect(
        createUser(
          id: aUserId(),
          fullName: '  Alice Martin ',
          email: anEmail(),
        ),
        equals(
          ok(User(id: aUserId(), fullName: 'Alice Martin', email: anEmail())),
        ),
      );
    });

    test('rejects a blank name and a name that is too long', () {
      expect(
        createUser(id: aUserId(), fullName: ' ', email: anEmail()),
        equals(
          err(
            validationError(ValidationField.fullName, ValidationRule.required),
          ),
        ),
      );
      expect(
        createUser(id: aUserId(), fullName: 'a' * 201, email: anEmail()),
        equals(
          err(
            validationError(ValidationField.fullName, ValidationRule.tooLong),
          ),
        ),
      );
    });
  });
}
