import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/application/use_cases/documents/observe_screen_capture.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';
import '../../support/fake_monitoring.dart';

/// Lets the logging that an event started in the background finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

ObserveScreenCapture _observer(Fakes fakes) => ObserveScreenCapture(fakes);

Future<Unsubscribe> _observe(
  Fakes fakes, [
  void Function(ScreenCaptureEvent event) onCapture = _ignore,
]) async {
  final observed = await _observer(fakes)
      .execute(documentId: aDocumentId(), onCapture: onCapture);
  switch (observed) {
    case Ok(:final value):
      return value;
    case Err():
      throw StateError('the observation should have started');
  }
}

void _ignore(ScreenCaptureEvent event) {}

ScreenCaptureEvent _event(ScreenCaptureKind kind) =>
    ScreenCaptureEvent(kind: kind);

void main() {
  group('ObserveScreenCapture', () {
    test('forwards each capture event to the caller', () async {
      final fakes = createFakes();
      final received = <ScreenCaptureEvent>[];
      await _observe(fakes, received.add);

      fakes.screenProtection.emit(_event(ScreenCaptureKind.screenshotTaken));
      fakes.screenProtection.emit(_event(ScreenCaptureKind.recordingStarted));

      expect(
        received,
        equals([
          _event(ScreenCaptureKind.screenshotTaken),
          _event(ScreenCaptureKind.recordingStarted),
        ]),
      );
    });

    test('logs each capture event as a warning, with the document and the '
        'user, as identifiers only', () async {
      final fakes = createFakes();
      await _observe(fakes);

      fakes.screenProtection.emit(_event(ScreenCaptureKind.recordingStopped));
      await _settle();

      expect(
        fakes.monitoring.logs,
        equals([
          LogRecord(
            level: LogLevel.warn,
            event: MonitoringEvent.screenCaptureDetected,
            attributes: {
              LogAttribute.captureKind:
                  ScreenCaptureKind.recordingStopped.value,
              LogAttribute.documentId: aDocumentId(),
              LogAttribute.userId: aUserId(),
            },
          ),
        ]),
      );
      final serialised = fakes.monitoring.logs.toString();
      expect(serialised, isNot(contains(aUser().fullName)));
      expect(serialised, isNot(contains(aUser().email)));
    });

    test('logs the user who is signed in when the event happens, not the one '
        'who started watching', () async {
      final fakes = createFakes();
      await _observe(fakes);
      fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));

      fakes.screenProtection.emit(_event(ScreenCaptureKind.screenshotTaken));
      await _settle();

      expect(
        fakes.monitoring.logs.first.attributes,
        containsPair(LogAttribute.userId, aUserId('user-2')),
      );
    });

    for (final (name, change) in <(String, void Function(Fakes))>[
      ('nobody is signed in', (fakes) => fakes.auth.session = null),
      ('the session expired', (fakes) => fakes.clock.advance(3600000)),
      ('the app is locked', (fakes) => fakes.appLock.lock()),
    ]) {
      test('logs the event without a user when $name', () async {
        final fakes = createFakes();
        final received = <ScreenCaptureEvent>[];
        await _observe(fakes, received.add);
        change(fakes);

        fakes.screenProtection.emit(_event(ScreenCaptureKind.recordingStarted));
        await _settle();

        expect(received, equals([_event(ScreenCaptureKind.recordingStarted)]));
        expect(
          fakes.monitoring.logs,
          equals([
            LogRecord(
              level: LogLevel.warn,
              event: MonitoringEvent.screenCaptureDetected,
              attributes: {
                LogAttribute.captureKind:
                    ScreenCaptureKind.recordingStarted.value,
                LogAttribute.documentId: aDocumentId(),
              },
            ),
          ]),
        );
      });
    }

    test('forwards the event to the caller at once, without waiting for the '
        'session to be read', () async {
      final fakes = createFakes();
      final received = <ScreenCaptureEvent>[];
      await _observe(fakes, received.add);

      fakes.screenProtection.emit(_event(ScreenCaptureKind.screenshotTaken));

      expect(received, hasLength(1));
      expect(fakes.monitoring.logs, isEmpty);
      await _settle();
      expect(fakes.monitoring.logs, hasLength(1));
    });

    test('succeeds with the function that stops the observation', () async {
      final fakes = createFakes();
      final received = <ScreenCaptureEvent>[];
      final unsubscribe = await _observe(fakes, received.add);
      expect(fakes.screenProtection.listenerCount, equals(1));

      unsubscribe();
      fakes.screenProtection.emit(_event(ScreenCaptureKind.screenshotTaken));
      await _settle();

      expect(received, isEmpty);
      expect(fakes.monitoring.logs, isEmpty);
      expect(fakes.screenProtection.listenerCount, equals(0));
    });

    test('requires a valid session: without one nothing is observed', () async {
      final fakes = createFakes();
      fakes.auth.session = null;
      final useCase = _observer(fakes);

      expect(
        await useCase.execute(documentId: aDocumentId(), onCapture: _ignore),
        equals(err(notAuthenticated())),
      );
      fakes.auth.session = aSession(expiresAt: now);
      expect(
        await useCase.execute(documentId: aDocumentId(), onCapture: _ignore),
        equals(err(sessionExpired())),
      );
      fakes.auth.session = aSession();
      fakes.appLock.lock();
      expect(
        await useCase.execute(documentId: aDocumentId(), onCapture: _ignore),
        equals(err(appLocked())),
      );
      expect(fakes.screenProtection.listenerCount, equals(0));
    });
  });
}
