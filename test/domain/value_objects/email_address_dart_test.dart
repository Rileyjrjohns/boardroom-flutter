import 'package:boardroom/domain/value_objects/email_address.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

// Dart only: `toLowerCase` of Dart and of JavaScript follow different versions
// of Unicode, so they differ on a few hundred rarely used letters (see
// docs/parity/open-questions.md). These are the letters a mailbox can actually
// have, which both give the same lower case.
void main() {
  group('parseEmailAddress lower-casing', () {
    for (final (raw, expected) in [
      ('Alice@Example.COM', 'alice@example.com'),
      ('ÉLODIE@EXEMPLE.FR', 'élodie@exemple.fr'),
      ('JÜRGEN@BEISPIEL.DE', 'jürgen@beispiel.de'),
      ('ÅSA@EXEMPEL.SE', 'åsa@exempel.se'),
      ('ΕΛΈΝΗ@ΠΑΡΆΔΕΙΓΜΑ.ΓΡ', 'ελένη@παράδειγμα.γρ'),
      ('ИВАН@ПРИМЕР.РФ', 'иван@пример.рф'),
    ]) {
      test('gives $expected for $raw', () {
        expect(unwrap(parseEmailAddress(raw)), equals(expected));
      });
    }
  });
}
