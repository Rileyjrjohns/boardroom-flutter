import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/infrastructure/persistence/local_data_reset.dart';
import 'package:boardroom/infrastructure/secure_storage/secure_storage.dart';
import 'package:test/test.dart';

import '../../application/support/fake_monitoring.dart';
import '../support/memory_secure_storage.dart';

const int _timeout = 50;

void main() {
  group('the record that local data was reset', () {
    test('is absent at first', () async {
      expect(
        await hasLocalDataReset(
          MemorySecureStorage(),
          FakeMonitoring(),
          _timeout,
        ),
        isFalse,
      );
    });

    test('is written with the reason and nothing else, then read, '
        'then cleared', () async {
      final storage = MemorySecureStorage();
      final monitoring = FakeMonitoring();

      expect(
        await markLocalDataReset(storage, ResetReason.keyLost, _timeout),
        isTrue,
      );
      expect(
        storage.snapshot(),
        equals({
          SecureStorageKey.localDataReset.value: ResetReason.keyLost.value,
        }),
      );
      expect(await hasLocalDataReset(storage, monitoring, _timeout), isTrue);

      expect(await clearLocalDataReset(storage, _timeout), isTrue);
      expect(storage.snapshot(), isEmpty);
      expect(await hasLocalDataReset(storage, monitoring, _timeout), isFalse);
    });

    test('says it was not written when the keychain refuses, '
        'and when it does not answer', () async {
      final refusing = MemorySecureStorage()..failNext();
      final silent = MemorySecureStorage()..hang();

      expect(
        await markLocalDataReset(refusing, ResetReason.keyLost, _timeout),
        isFalse,
      );
      expect(
        await markLocalDataReset(silent, ResetReason.keyLost, _timeout),
        isFalse,
      );
    });

    test('counts a keychain that cannot be read as no record, '
        'and captures it', () async {
      final storage = MemorySecureStorage()
        ..seed(SecureStorageKey.localDataReset.value, ResetReason.keyLost.value)
        ..failNext();
      final monitoring = FakeMonitoring();

      expect(await hasLocalDataReset(storage, monitoring, _timeout), isFalse);

      expect(monitoring.errors, hasLength(1));
      expect(
        monitoring.errors.single,
        equals(
          ErrorRecord(
            event: MonitoringEvent.resetNoticeUnreadable,
            error: storageReadFailed('unknown failure'),
            attributes: null,
          ),
        ),
      );
    });

    test('says when it could not be cleared', () async {
      final storage = MemorySecureStorage()..failNext();

      expect(await clearLocalDataReset(storage, _timeout), isFalse);
    });
  });

  group('the notice of a reset', () {
    test(
      'is not pending when nothing was reset, and has nothing to clear',
      () async {
        final storage = MemorySecureStorage();

        final notice = await readLocalDataResetNotice(
          storage,
          FakeMonitoring(),
          _timeout,
        );
        await notice.acknowledge();

        expect(notice.pending, isFalse);
        expect(storage.snapshot(), isEmpty);
      },
    );

    test('is pending while the record is there, '
        'and acknowledging clears the record', () async {
      final storage = MemorySecureStorage();
      await markLocalDataReset(storage, ResetReason.keyRejected, _timeout);

      final notice = await readLocalDataResetNotice(
        storage,
        FakeMonitoring(),
        _timeout,
      );
      expect(notice.pending, isTrue);
      await notice.acknowledge();

      expect(storage.snapshot(), isEmpty);
      expect(
        (await readLocalDataResetNotice(
          storage,
          FakeMonitoring(),
          _timeout,
        )).pending,
        isFalse,
      );
    });

    test('captures a record that cannot be cleared, and does not reject: '
        'the user will be told again', () async {
      final storage = MemorySecureStorage();
      await markLocalDataReset(storage, ResetReason.keyLost, _timeout);
      final monitoring = FakeMonitoring();
      final notice = await readLocalDataResetNotice(
        storage,
        monitoring,
        _timeout,
      );
      storage.failNext();

      await expectLater(notice.acknowledge(), completes);

      expect(
        monitoring.errors.single,
        equals(
          ErrorRecord(
            event: MonitoringEvent.resetNoticeNotCleared,
            error: storageWriteFailed(),
            attributes: null,
          ),
        ),
      );
      expect(
        (await readLocalDataResetNotice(
          storage,
          FakeMonitoring(),
          _timeout,
        )).pending,
        isTrue,
      );
    });

    test('is the default notice when the time is not given', () async {
      final storage = MemorySecureStorage();
      await markLocalDataReset(storage, ResetReason.keyLost, _timeout);

      final notice = await readLocalDataResetNotice(storage, FakeMonitoring());

      expect(notice.pending, isTrue);
    });
  });
}
