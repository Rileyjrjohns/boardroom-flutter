import 'package:test/test.dart';

import 'sleep.dart';

void main() {
  group('the sleeps of the tests', () {
    test('do not wait', () async {
      await expectLater(immediateSleep(60000), completes);
    });

    test('remember the delays they were asked for, in order', () async {
      final (:sleep, :requested) = recordingSleep();

      await sleep(300);
      await sleep(0);

      expect(requested, equals([300, 0]));
    });
  });
}
