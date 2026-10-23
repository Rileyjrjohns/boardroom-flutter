import 'dart:async';

import 'package:boardroom/infrastructure/clock/sleep.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('timerSleep', () {
    test('resolves once the delay has passed, and not before', () {
      fakeAsync((async) {
        var settled = 0;

        unawaited(timerSleep(500).then((_) => settled += 1));
        async.elapse(const Duration(milliseconds: 499));
        expect(settled, equals(0));

        async.elapse(const Duration(milliseconds: 1));
        expect(settled, equals(1));
      });
    });
  });
}
