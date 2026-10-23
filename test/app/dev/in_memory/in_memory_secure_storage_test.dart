import 'package:boardroom/app/dev/in_memory/in_memory_secure_storage.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySecureStorage', () {
    test(
      'reads back what was stored, and nothing for an unknown key',
      () async {
        final storage = InMemorySecureStorage();
        final key = SecureStorageKey.session.value;

        expect(await storage.get(key), isNull);
        await storage.set(key, 'value');
        expect(await storage.get(key), equals('value'));
      },
    );

    test('replaces what a key held', () async {
      final storage = InMemorySecureStorage();
      final key = SecureStorageKey.session.value;

      await storage.set(key, 'first');
      await storage.set(key, 'second');

      expect(await storage.get(key), equals('second'));
    });

    test('forgets a key, and forgetting a key that is not there '
        'succeeds', () async {
      final storage = InMemorySecureStorage();
      final key = SecureStorageKey.session.value;
      await storage.set(key, 'value');

      await storage.remove(key);
      await storage.remove(key);

      expect(await storage.get(key), isNull);
    });

    test('keeps the keys apart, and each storage to itself', () async {
      final storage = InMemorySecureStorage();
      final other = InMemorySecureStorage();
      await storage.set(SecureStorageKey.session.value, 'session');
      await storage.set(SecureStorageKey.databaseKey.value, 'key');

      await storage.remove(SecureStorageKey.session.value);

      expect(await storage.get(SecureStorageKey.databaseKey.value), 'key');
      expect(await other.get(SecureStorageKey.databaseKey.value), isNull);
    });
  });
}
