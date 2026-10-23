import 'package:boardroom/core/infrastructure/http/status_cause.dart';
import 'package:test/test.dart';

// The cause of an error that comes from a status: the status and nothing else.
// React Native has no test file for it.

void main() {
  group('statusCause', () {
    test('is the status, which is a kind of failure and no more', () {
      expect(statusCause(404), equals('status 404'));
      expect(statusCause(503), equals('status 503'));
    });
  });
}
