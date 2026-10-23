import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';
import 'package:test/test.dart';

void main() {
  group('NetworkSnapshot', () {
    test('compares by the two flags the platform reports', () {
      const snapshot = NetworkSnapshot(
        isConnected: true,
        isInternetReachable: false,
      );

      expect(
        snapshot,
        equals(
          const NetworkSnapshot(isConnected: true, isInternetReachable: false),
        ),
      );
      expect(
        snapshot.hashCode,
        equals(
          const NetworkSnapshot(
            isConnected: true,
            isInternetReachable: false,
          ).hashCode,
        ),
      );
      expect(snapshot, isNot(equals(const NetworkSnapshot(isConnected: true))));
      expect(
        snapshot,
        isNot(
          equals(
            const NetworkSnapshot(
              isConnected: false,
              isInternetReachable: false,
            ),
          ),
        ),
      );
    });

    test('prints the flags, a flag that is not set as null', () {
      expect(
        const NetworkSnapshot(isConnected: true).toString(),
        equals('NetworkSnapshot(isConnected: true, isInternetReachable: null)'),
      );
    });
  });
}
