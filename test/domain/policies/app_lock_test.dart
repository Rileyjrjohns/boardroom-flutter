import 'package:boardroom/domain/policies/app_lock.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:test/test.dart';

import '../support/builders.dart';

void main() {
  final grace = aDuration(30000);

  group('isUnlockRequired', () {
    AppLockInput input({
      required Instant current,
      bool hasSession = true,
      DurationMillis? gracePeriod,
    }) => AppLockInput(
      backgroundedAt: now,
      now: current,
      gracePeriod: gracePeriod ?? grace,
      hasSession: hasSession,
    );

    test('is false when the app comes back within the grace period', () {
      expect(isUnlockRequired(input(current: at(29999))), isFalse);
      expect(isUnlockRequired(input(current: now)), isFalse);
    });

    test(
      'is true once the grace period has elapsed, the boundary included',
      () {
        expect(isUnlockRequired(input(current: at(30000))), isTrue);
        expect(isUnlockRequired(input(current: at(millisPerMinute))), isTrue);
      },
    );

    test('locks every time when the grace period is zero', () {
      expect(
        isUnlockRequired(input(gracePeriod: aDuration(0), current: now)),
        isTrue,
      );
    });

    test('is false without a session, whatever the time spent away', () {
      expect(
        isUnlockRequired(
          input(hasSession: false, current: at(millisPerMinute)),
        ),
        isFalse,
      );
    });

    test('fails closed when the clock has been set back', () {
      expect(isUnlockRequired(input(current: at(-1))), isTrue);
    });
  });
}
