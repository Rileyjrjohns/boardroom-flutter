import 'dart:async';

import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/application/screen_protection_coordinator.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_screen_protection.dart';
import '../../../support/fakes/screen_protection_deps.dart';

/// Lets the futures that are ready run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

final DocumentId _a = aDocumentId('document-A');
final DocumentId _b = aDocumentId('document-B');

({
  FakeScreenProtection screenProtection,
  ScreenProtectionCoordinator coordinator,
})
_setup() {
  final screenProtection = FakeScreenProtection();
  return (
    screenProtection: screenProtection,
    coordinator: ScreenProtectionCoordinator(
      ScreenProtectionDeps(screenProtection),
    ),
  );
}

/// What the manual platform was asked for.
enum _Call { enable, disable }

/// A platform whose answers the test gives by hand, one call at a time.
final class _ManualPlatform implements ScreenProtection {
  final List<_Call> calls = [];
  final List<void Function()> _pending = [];

  Future<Result<void, ScreenProtectionError>> _answerLater(_Call call) {
    calls.add(call);
    final answer = Completer<Result<void, ScreenProtectionError>>();
    _pending.add(() => answer.complete(ok<void>(null)));
    return answer.future;
  }

  @override
  Future<Result<void, ScreenProtectionError>> enable() =>
      _answerLater(_Call.enable);

  @override
  Future<Result<void, ScreenProtectionError>> disable() =>
      _answerLater(_Call.disable);

  @override
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener) =>
      () {};

  /// Lets the queue reach the platform, then answers the oldest call it is
  /// waiting for.
  Future<void> settleNext() async {
    await _settle();
    if (_pending.isNotEmpty) {
      _pending.removeAt(0)();
    }
    await _settle();
  }
}

/// A platform whose `enable` gives the answers it was given, in order, and
/// succeeds once they run out.
final class _ScriptedPlatform implements ScreenProtection {
  new(this.answers);

  final List<Result<void, ScreenProtectionError>> answers;
  final List<_Call> calls = [];

  @override
  Future<Result<void, ScreenProtectionError>> enable() {
    calls.add(_Call.enable);
    return Future.value(answers.isEmpty ? ok<void>(null) : answers.removeAt(0));
  }

  @override
  Future<Result<void, ScreenProtectionError>> disable() =>
      Future.value(ok<void>(null));

  @override
  Unsubscribe subscribe(void Function(ScreenCaptureEvent event) listener) =>
      () {};
}

void main() {
  group('ScreenProtectionCoordinator', () {
    test(
      'turns the protection on when a confidential document is opened',
      () async {
        final (:screenProtection, :coordinator) = _setup();

        expect(await coordinator.acquire(_a), equals(ok<void>(null)));
        expect(screenProtection.enabled, isTrue);
      },
    );

    test(
      'turns the protection off when the only open document is closed',
      () async {
        final (:screenProtection, :coordinator) = _setup();
        await coordinator.acquire(_a);

        expect(await coordinator.release(_a), equals(ok<void>(null)));
        expect(screenProtection.enabled, isFalse);
      },
    );

    test('keeps the protection on while another confidential document is still '
        'open', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      await coordinator.acquire(_b);

      await coordinator.release(_b);

      expect(screenProtection.enabled, isTrue);
      expect(screenProtection.disableCalls, equals(0));

      await coordinator.release(_a);

      expect(screenProtection.enabled, isFalse);
      expect(screenProtection.disableCalls, equals(1));
    });

    test(
      'does not depend on the order in which the documents are closed',
      () async {
        final (:screenProtection, :coordinator) = _setup();
        await coordinator.acquire(_a);
        await coordinator.acquire(_b);

        await coordinator.release(_a);
        expect(screenProtection.enabled, isTrue);
        await coordinator.release(_b);

        expect(screenProtection.enabled, isFalse);
      },
    );

    test('ignores the closing of an unknown document: nothing is switched, it '
        'succeeds', () async {
      final (:screenProtection, :coordinator) = _setup();

      expect(await coordinator.release(_a), equals(ok<void>(null)));
      expect(screenProtection.disableCalls, equals(0));

      await coordinator.acquire(_b);
      expect(await coordinator.release(_a), equals(ok<void>(null)));
      expect(screenProtection.enabled, isTrue);
    });

    test('ignores the closing of a document that is already closed', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      await coordinator.acquire(_b);
      await coordinator.release(_a);

      await coordinator.release(_a);

      expect(screenProtection.enabled, isTrue);
      expect(screenProtection.disableCalls, equals(0));
    });

    test('counts the views of a document: closing one of two leaves the other '
        'protected', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      await coordinator.acquire(_a);

      await coordinator.release(_a);

      expect(screenProtection.enabled, isTrue);
      expect(screenProtection.disableCalls, equals(0));

      await coordinator.release(_a);

      expect(screenProtection.enabled, isFalse);
      expect(screenProtection.disableCalls, equals(1));
    });

    test('counts the views of every document together: the last view of all '
        'turns the protection off', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      await coordinator.acquire(_a);
      await coordinator.acquire(_b);

      await coordinator.release(_a);
      await coordinator.release(_b);
      expect(screenProtection.enabled, isTrue);

      await coordinator.release(_a);
      expect(screenProtection.enabled, isFalse);
    });

    test('does not count a view twice for one close: a document with no view '
        'left is ignored', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      await coordinator.acquire(_b);

      await coordinator.release(_a);
      await coordinator.release(_a);

      expect(screenProtection.enabled, isTrue);
    });

    test(
      'does not register a document whose protection could not be turned on',
      () async {
        final (:screenProtection, :coordinator) = _setup();
        screenProtection.enableFailure = screenProtectionUnsupported();

        expect(
          await coordinator.acquire(_a),
          equals(err(screenProtectionUnsupported())),
        );

        screenProtection.enableFailure = null;
        await coordinator.acquire(_b);
        await coordinator.release(_b);
        expect(screenProtection.enabled, isFalse);
        // A was never registered: closing it again does not touch the
        // protection.
        expect(await coordinator.release(_a), equals(ok<void>(null)));
        expect(screenProtection.disableCalls, equals(1));
      },
    );

    test('does not keep counting a view whose protection could not be turned '
        'off', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      screenProtection.disableFailure = screenProtectionFailed();

      expect(
        await coordinator.release(_a),
        equals(err(screenProtectionFailed())),
      );
      expect(screenProtection.enabled, isTrue);

      // The view is gone whatever the platform said: the next document that
      // is opened and closed finds no view of A left, and turns the
      // protection off for good.
      screenProtection.disableFailure = null;
      await coordinator.acquire(_b);
      expect(await coordinator.release(_b), equals(ok<void>(null)));
      expect(screenProtection.enabled, isFalse);
    });

    test('retries the disable that failed on the next release that leaves no '
        'view', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      screenProtection.disableFailure = screenProtectionFailed();
      await coordinator.release(_a);
      screenProtection.disableFailure = null;

      // The same document closed again: it has no view, and there is none
      // at all.
      expect(await coordinator.release(_a), equals(ok<void>(null)));

      expect(screenProtection.enabled, isFalse);
      expect(screenProtection.disableCalls, equals(2));
      // Once it went through, nothing is pending any more.
      await coordinator.release(_a);
      expect(screenProtection.disableCalls, equals(2));
    });

    test('keeps the protection on, and does not retry the disable, while a '
        'view is open', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      screenProtection.disableFailure = screenProtectionFailed();
      await coordinator.release(_a);
      screenProtection.disableFailure = null;

      await coordinator.acquire(_b);
      await coordinator.release(_a);

      expect(screenProtection.enabled, isTrue);
      expect(screenProtection.disableCalls, equals(1));

      await coordinator.release(_b);

      expect(screenProtection.enabled, isFalse);
    });

    test('ends with the protection off after A fails to close, then B is '
        'opened and closed', () async {
      final (:screenProtection, :coordinator) = _setup();
      await coordinator.acquire(_a);
      screenProtection.disableFailure = screenProtectionFailed();
      await coordinator.release(_a);
      screenProtection.disableFailure = null;

      await coordinator.acquire(_b);
      await coordinator.release(_b);

      expect(screenProtection.enabled, isFalse);
    });

    test('keeps no memory of its own between two instances', () async {
      final screenProtection = FakeScreenProtection();
      final deps = ScreenProtectionDeps(screenProtection);
      final first = ScreenProtectionCoordinator(deps);
      final second = ScreenProtectionCoordinator(deps);
      await first.acquire(_a);

      await second.release(_a);

      expect(screenProtection.enabled, isTrue);
    });

    group('the calls to the platform', () {
      test('are issued in the order they were asked for, each one after the '
          'previous has settled', () async {
        final platform = _ManualPlatform();
        final coordinator = ScreenProtectionCoordinator(
          ScreenProtectionDeps(platform),
        );

        final opening = coordinator.acquire(_a);
        await platform.settleNext();
        await opening;
        // A is closed while B is being opened: the slow disable of A must
        // not land after the enable of B.
        final closing = coordinator.release(_a);
        final nextOpening = coordinator.acquire(_b);
        await _settle();

        expect(platform.calls, equals([_Call.enable, _Call.disable]));

        await platform.settleNext();
        await closing;
        expect(
          platform.calls,
          equals([_Call.enable, _Call.disable, _Call.enable]),
        );

        await platform.settleNext();
        await nextOpening;
      });

      test('end with the protection on when the last call asked for it, '
          'whatever the speed of the platform', () async {
        final screenProtection = FakeScreenProtection();
        final coordinator = ScreenProtectionCoordinator(
          ScreenProtectionDeps(screenProtection),
        );
        await coordinator.acquire(_a);

        await Future.wait([
          coordinator.release(_a),
          coordinator.acquire(_b),
          coordinator.acquire(_a),
        ]);

        expect(screenProtection.enabled, isTrue);
        expect(await coordinator.release(_b), equals(ok<void>(null)));
        expect(screenProtection.enabled, isTrue);
      });

      test('go on after a call that failed: one failure does not block the '
          'queue', () async {
        final platform = _ScriptedPlatform([
          err(screenProtectionFailed()),
          ok<void>(null),
        ]);
        final coordinator = ScreenProtectionCoordinator(
          ScreenProtectionDeps(platform),
        );

        final results = await Future.wait([
          coordinator.acquire(_a),
          coordinator.acquire(_b),
        ]);

        expect(results[0], equals(err(screenProtectionFailed())));
        expect(results[1], equals(ok<void>(null)));
        expect(platform.calls, equals([_Call.enable, _Call.enable]));
      });
    });
  });
}
