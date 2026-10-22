import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

// Dart only: the TypeScript object is plain data, a Dart object can be printed
// by a log or a failing test, and the password must not appear in it.
void main() {
  group('Credentials', () {
    test('does not print the password', () {
      final credentials = Credentials(email: anEmail(), password: 's3cret');

      expect(credentials.toString(), isNot(contains('s3cret')));
      expect(credentials.toString(), contains('alice@example.com'));
    });
  });
}
