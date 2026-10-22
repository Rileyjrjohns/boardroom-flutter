import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:test/test.dart';

void main() {
  group('Duration', () {
    test('accepts a whole, non-negative number of milliseconds', () {
      expect(durationFromMillis(0), equals(ok(0)));
      expect(durationFromMillis(1500), equals(ok(1500)));
    });

    test('rejects a fraction of a millisecond', () {
      expect(
        durationFromMillis(0.5),
        equals(
          err(
            validationError(
              ValidationField.duration,
              ValidationRule.notAnInteger,
            ),
          ),
        ),
      );
    });

    test('rejects a negative or an absurdly long duration', () {
      final outOfRange = err(
        validationError(ValidationField.duration, ValidationRule.outOfRange),
      );

      expect(durationFromMillis(-1), equals(outOfRange));
      expect(durationFromMillis(3153600000001), equals(outOfRange));
    });
  });
}
