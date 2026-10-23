import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:test/test.dart';

void main() {
  group('AppLock', () {
    test('starts locked: a process that has proven nothing fails closed', () {
      expect(AppLock().isLocked(), isTrue);
    });

    test('can be made to start unlocked', () {
      expect(AppLock(locked: false).isLocked(), isFalse);
    });

    test('opens and closes', () {
      final lock = AppLock()..unlock();
      expect(lock.isLocked(), isFalse);

      lock.lock();
      expect(lock.isLocked(), isTrue);
    });

    test('is idempotent in both directions', () {
      final lock = AppLock(locked: false)
        ..unlock()
        ..unlock();
      expect(lock.isLocked(), isFalse);

      lock
        ..lock()
        ..lock();
      expect(lock.isLocked(), isTrue);
    });

    test('keeps its state to itself: two locks do not share it', () {
      final first = AppLock();
      final second = AppLock();

      first.unlock();

      expect(second.isLocked(), isTrue);
    });
  });
}
