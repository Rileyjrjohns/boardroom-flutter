import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

void main() {
  group('createCredentials', () {
    test('validates the email and keeps the password exactly as typed', () {
      expect(
        createCredentials(' Alice@Example.com ', '  secret  '),
        equals(ok(Credentials(email: anEmail(), password: '  secret  '))),
      );
    });

    test('rejects a bad email', () {
      expect(
        createCredentials('alice', 'secret'),
        equals(
          err(
            validationError(
              ValidationField.email,
              ValidationRule.invalidFormat,
            ),
          ),
        ),
      );
    });

    test('rejects an empty password', () {
      expect(
        createCredentials('alice@example.com', ''),
        equals(
          err(
            validationError(ValidationField.password, ValidationRule.required),
          ),
        ),
      );
    });

    test('reports the email first when both are wrong', () {
      expect(
        createCredentials('', ''),
        equals(
          err(validationError(ValidationField.email, ValidationRule.required)),
        ),
      );
    });
  });
}
