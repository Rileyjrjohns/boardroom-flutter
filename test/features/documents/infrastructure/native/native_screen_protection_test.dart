import 'dart:async';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/infrastructure/native/native_screen_protection.dart';
import 'package:flutter/services.dart';
import 'package:test/test.dart';

import '../../../../support/contracts/screen_protection_contract.dart';
import '../../../../support/fakes/fake_monitoring.dart';
import '../../../../support/infrastructure/fake_screen_protection_module.dart';

const _screenshot = ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken);
const _started = ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted);
const _stopped = ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStopped);

/// Lets what the adapter does in the background (reading the starting point)
/// finish.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

typedef _Adapter = ({
  FakeScreenProtectionModule module,
  FakeMonitoring monitoring,
  NativeScreenProtection protection,
  List<ScreenCaptureEvent> received,
  Unsubscribe Function() listen,
});

_Adapter _anAdapter({int? timeoutMillis}) {
  final module = FakeScreenProtectionModule();
  final monitoring = FakeMonitoring();
  final protection = NativeScreenProtection(
    module: module,
    monitoring: monitoring,
    timeoutMillis: timeoutMillis ?? defaultNativeTimeoutMillis,
  );
  final received = <ScreenCaptureEvent>[];
  return (
    module: module,
    monitoring: monitoring,
    protection: protection,
    received: received,
    listen: () => protection.subscribe(received.add),
  );
}

final Result<void, ScreenProtectionError> _failed = err(
  screenProtectionFailed(),
);

void main() {
  // The contract of the port, against the adapter over a stand-in of the native
  // side. The stand-in turns the protection on later than it turns it off, so
  // the order of the calls is really tested.
  describeScreenProtectionContract('NativeScreenProtection', () {
    final module = FakeScreenProtectionModule();
    return ScreenProtectionHarness(
      protection: NativeScreenProtection(
        module: module,
        monitoring: FakeMonitoring(),
      ),
      isEnabled: () => module.enabled,
      emit: (event) {
        switch (event.kind) {
          case ScreenCaptureKind.screenshotTaken:
            module.emitScreenshot();
          case ScreenCaptureKind.recordingStarted:
            module.emitCapture(captured: true);
          case ScreenCaptureKind.recordingStopped:
            module.emitCapture(captured: false);
        }
      },
    );
  });

  group('NativeScreenProtection, turning the protection on and off', () {
    test('asks the module for each call, with the state wanted', () async {
      final a = _anAdapter();

      await a.protection.enable();
      await a.protection.enable();
      await a.protection.disable();

      expect(a.module.calls, equals([true, true, false]));
    });

    test('gives the calls to the module one at a time, '
        'in the order they were issued', () async {
      final a = _anAdapter();

      await Future.wait([
        a.protection.enable(),
        a.protection.disable(),
        a.protection.enable(),
      ]);

      expect(a.module.calls, equals([true, false, true]));
      expect(a.module.enabled, isTrue);
    });

    group('when the module fails', () {
      for (final (name, fail) in <(String, void Function(_Adapter))>[
        ('rejects', (a) => a.module.failure = StateError('boom')),
        ('throws', (a) => a.module.throwsSynchronously = true),
      ]) {
        test('answers an error, never throws, when it $name, '
            'and works again after', () async {
          final a = _anAdapter();
          fail(a);

          final enabled = await a.protection.enable();
          final disabled = await a.protection.disable();

          expect(enabled, equals(_failed));
          expect(disabled, equals(_failed));
          expect(
            a.monitoring.capturedEvents(),
            equals([
              MonitoringEvent.screenProtectionNativeFailed,
              MonitoringEvent.screenProtectionNativeFailed,
            ]),
          );

          a.module
            ..failure = null
            ..throwsSynchronously = false;
          expect(await a.protection.enable(), equals(ok<void>(null)));
          expect(a.module.enabled, isTrue);
        });
      }

      test('reports a kind of failure and nothing the failure said', () async {
        final a = _anAdapter();
        a.module.failure = PlatformException(
          code: 'ERR_ACTIVITY',
          message: '/private/var/mobile/secret.pdf',
        );

        await a.protection.enable();

        expect(a.monitoring.errors, hasLength(1));
        final record = a.monitoring.errors.single;
        expect(record.event, MonitoringEvent.screenProtectionNativeFailed);
        expect(record.error, equals(screenProtectionFailed()));
        expect(
          record.attributes,
          equals({LogAttribute.reason: 'ERR_ACTIVITY'}),
        );
      });

      test('settles when the module never answers, '
          'and the calls after it still go through', () async {
        final a = _anAdapter(timeoutMillis: 20);
        a.module.hanging = true;

        final stuck = await a.protection.enable();
        a.module.hanging = false;
        final next = await a.protection.disable();

        expect(stuck, equals(_failed));
        expect(next, equals(ok<void>(null)));
        expect(a.module.calls, equals([true, false]));
      });
    });

    group('when the build has no native module', () {
      NativeScreenProtection noModule() =>
          NativeScreenProtection(module: null, monitoring: FakeMonitoring());

      test('cannot protect the screen: enabling is refused, '
          'so a document is not shown unprotected', () async {
        expect(
          await noModule().enable(),
          equals(err(screenProtectionUnsupported())),
        );
      });

      test('has nothing to turn off: disabling succeeds', () async {
        expect(await noModule().disable(), equals(ok<void>(null)));
      });

      test('delivers no event, and unsubscribing works', () {
        final unsubscribe = noModule().subscribe((_) {});

        expect(() {
          unsubscribe();
          unsubscribe();
        }, returnsNormally);
      });
    });
  });

  group('NativeScreenProtection, the events', () {
    test('listens to the module only while someone is subscribed, '
        'once for everybody', () {
      final a = _anAdapter();
      expect(a.module.listenerCount, equals(0));

      final first = a.listen();
      final second = a.listen();
      expect(a.module.listenerCount, equals(1));

      first();
      expect(a.module.listenerCount, equals(1));
      second();
      expect(a.module.listenerCount, equals(0));
    });

    test('listens again when someone subscribes after everybody left', () {
      final a = _anAdapter();
      a.listen()();

      a.listen();
      a.module.emitScreenshot();

      expect(a.module.listenerCount, equals(1));
      expect(a.received, equals([_screenshot]));
    });

    test('maps a screenshot, and a recording that starts and stops', () async {
      final a = _anAdapter();
      a.listen();
      await _settle();

      a.module
        ..emitScreenshot()
        ..emitCapture(captured: true)
        ..emitCapture(captured: false);

      expect(a.received, equals([_screenshot, _started, _stopped]));
    });

    test('tells a change once: '
        'a report of the state that is already known is dropped', () async {
      final a = _anAdapter();
      a.listen();
      await _settle();

      a.module
        ..emitCapture(captured: true)
        ..emitCapture(captured: true)
        ..emitCapture(captured: false)
        ..emitCapture(captured: false);

      expect(a.received, equals([_started, _stopped]));
    });

    test('tells nobody after the last subscriber left, '
        'even if the module still reports', () {
      final a = _anAdapter();
      final listener = a.module;
      a.listen()();

      listener
        ..emitScreenshot()
        ..emitCapture(captured: true);

      expect(a.received, isEmpty);
    });

    group('a recording that is already running', () {
      test('is told to the first subscriber, as a start', () async {
        final a = _anAdapter();
        a.module.captured = true;

        a.listen();
        await _settle();

        expect(a.received, equals([_started]));
      });

      test(
        'is told to a subscriber who comes later, and only to them',
        () async {
          final a = _anAdapter();
          a.module.captured = true;
          a.listen();
          await _settle();
          final later = <ScreenCaptureEvent>[];

          a.protection.subscribe(later.add);
          await _settle();

          expect(later, equals([_started]));
          expect(a.received, equals([_started]));
        },
      );

      test('is not told to a subscriber who has already left', () async {
        final a = _anAdapter();
        a.module.captured = true;
        a.listen();
        await _settle();
        final later = <ScreenCaptureEvent>[];

        a.protection.subscribe(later.add)();
        await _settle();

        expect(later, isEmpty);
      });

      test('is not told when the screen is not being recorded', () async {
        final a = _anAdapter();

        a.listen();
        await _settle();

        expect(a.received, isEmpty);
      });

      test('gives way to a change that came first: '
          'the answer of the module is then out of date', () async {
        final a = _anAdapter();
        a.module.captured = true;
        final release = a.module.holdNextCaptureQuery();
        a.listen();

        a.module.emitCapture(captured: false);
        release();
        await _settle();

        expect(a.received, equals([_stopped]));
      });

      test(
        'is not told by an answer that comes after everybody left',
        () async {
          final a = _anAdapter();
          a.module.captured = true;
          final release = a.module.holdNextCaptureQuery();
          a.listen()();

          release();
          await _settle();

          expect(a.received, isEmpty);
        },
      );

      test('is not told by an answer to an earlier listening, '
          'once someone listens again', () async {
        final a = _anAdapter();
        a.module.captured = true;
        final release = a.module.holdNextCaptureQuery();
        a.listen()();
        a.module.captured = false;
        a.listen();

        release();
        await _settle();

        expect(a.received, isEmpty);
      });

      test('is simply not known when the module cannot say, '
          'and the changes still come', () async {
        final a = _anAdapter();
        a.module.captureFailure = StateError('x');

        a.listen();
        await _settle();
        a.module.emitCapture(captured: true);

        expect(a.received, equals([_started]));
      });
    });

    group('when something goes wrong', () {
      test('does not throw when the module cannot be listened to, '
          'and says so', () {
        final a = _anAdapter();
        a.module.addFailure = StateError('no emitter');

        expect(a.listen, returnsNormally);

        expect(a.received, isEmpty);
        expect(
          a.monitoring.capturedEvents(),
          equals([MonitoringEvent.screenProtectionNativeFailed]),
        );
      });

      test('says so when the stream of events fails, '
          'and the events that follow still come', () async {
        final a = _anAdapter();
        a.listen();
        await _settle();

        a.module
          ..emitError(StateError('stream'))
          ..emitScreenshot();

        expect(a.received, equals([_screenshot]));
        expect(
          a.monitoring.capturedEvents(),
          equals([MonitoringEvent.screenProtectionNativeFailed]),
        );
      });

      test('does not let a listener that throws stop the others, '
          'nor escape, and says so', () {
        final a = _anAdapter();
        final heard = <ScreenCaptureEvent>[];
        a.protection
          ..subscribe((_) => throw StateError('listener'))
          ..subscribe(heard.add);

        expect(a.module.emitScreenshot, returnsNormally);

        expect(heard, equals([_screenshot]));
        expect(
          a.monitoring.capturedEvents(),
          equals([MonitoringEvent.screenProtectionListenerFailed]),
        );
      });

      test('does not let a late listener that throws escape', () async {
        final a = _anAdapter();
        a.module.captured = true;
        a.listen();
        await _settle();

        a.protection.subscribe((_) => throw StateError('listener'));
        await _settle();

        expect(
          a.monitoring.capturedEvents(),
          equals([MonitoringEvent.screenProtectionListenerFailed]),
        );
      });

      test('does not throw when a native listener cannot be removed, '
          'and says so', () {
        final a = _anAdapter();
        final stop = a.listen();
        a.module.removeFailure = StateError('gone');

        expect(stop, returnsNormally);

        expect(
          a.monitoring.capturedEvents(),
          equals([MonitoringEvent.screenProtectionNativeFailed]),
        );
      });
    });
  });
}
