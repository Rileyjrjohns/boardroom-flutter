import 'package:boardroom/domain/value_objects/watermark.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

void main() {
  group('createWatermark', () {
    test('carries the name and the email of the reader '
        'and the instant of the viewing, unformatted', () {
      final reader = aUser();

      expect(
        createWatermark(reader, now),
        equals(
          Watermark(
            fullName: reader.fullName,
            email: reader.email,
            viewedAt: now,
          ),
        ),
      );
    });

    test('keeps nothing else of the reader', () {
      expect(
        createWatermark(aUser(), now).toString(),
        equals(
          'Watermark(fullName: Alice Martin, email: alice@example.com, '
          'viewedAt: 1900000000000)',
        ),
      );
    });
  });
}
