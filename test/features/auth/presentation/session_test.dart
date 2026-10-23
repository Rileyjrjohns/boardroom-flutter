// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/presentation/session/restore_session_controller.dart';
import 'package:boardroom/features/auth/presentation/session/session_check.dart';
import 'package:boardroom/features/auth/presentation/session/session_ended.dart';
import 'package:boardroom/features/auth/presentation/session/session_watch.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// The session life of the open app: the restore at the start, the check of the
// session, the timer that repeats it, and the session a failure ended.

void main() {
  group('RestoreSessionController', () {
    test('no stored session sends the user to sign-in', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.session = null;
        final providers = app.providers(access: Access.starting);

        providers.read(restoreSessionControllerProvider);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.signedOut);
        expect(providers.read(restoreSessionControllerProvider), isNull);
      });
    });

    test('a stored session locks the app', () {
      fakeAsync((async) {
        final providers = TestApp().providers(access: Access.starting);

        providers.read(restoreSessionControllerProvider);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
      });
    });

    test('keeps the failure of a session that cannot be read, and asks '
        'again', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.readFailure = storageReadFailed();
        final providers = app.providers(access: Access.starting);
        providers.listen(restoreSessionControllerProvider, (_, _) {});

        async.flushMicrotasks();
        expect(
          providers.read(restoreSessionControllerProvider),
          storageReadFailed(),
        );
        expect(providers.read(accessProvider), Access.starting);

        app.fakes.auth.readFailure = null;
        providers.read(restoreSessionControllerProvider.notifier).retry();
        async.flushMicrotasks();

        expect(providers.read(restoreSessionControllerProvider), isNull);
        expect(providers.read(accessProvider), Access.locked);
      });
    });

    test('does not restore once the app is past the start', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.session = null;
        final providers = app.providers();

        providers.read(restoreSessionControllerProvider);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.unlocked);
      });
    });
  });

  group('sessionCheck', () {
    test('keeps an open app whose session is good', () {
      fakeAsync((async) {
        final providers = TestApp().providers();

        unawaited(
          providers.read(sessionCheckProvider)(
            providers.read(accessControllerProvider).epoch,
          ),
        );
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.unlocked);
      });
    });

    test('ends a session that is over, with the reason', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.session = null;
        final providers = app.providers();

        unawaited(
          providers.read(sessionCheckProvider)(
            providers.read(accessControllerProvider).epoch,
          ),
        );
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.signedOut);
        expect(
          providers.read(accessControllerProvider).sessionEndedBy,
          AuthenticationErrorCode.notAuthenticated.value,
        );
      });
    });

    test('fails closed, with the lock, when the session cannot be read', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.readFailure = storageReadFailed();
        final providers = app.providers();

        unawaited(
          providers.read(sessionCheckProvider)(
            providers.read(accessControllerProvider).epoch,
          ),
        );
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
      });
    });

    test('locks when the app is locked meanwhile', () {
      fakeAsync((async) {
        final app = TestApp(startsLocked: true);
        final providers = app.providers();

        unawaited(
          providers.read(sessionCheckProvider)(
            providers.read(accessControllerProvider).epoch,
          ),
        );
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
        expect(
          providers.read(accessControllerProvider).sessionEndedBy,
          AuthenticationErrorCode.appLocked.value,
        );
      });
    });

    test('does nothing unless the app is open', () {
      fakeAsync((async) {
        final app = TestApp()..fakes.auth.session = null;
        final providers = app.providers(access: Access.locked);

        unawaited(providers.read(sessionCheckProvider)(0));
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
      });
    });
  });

  group('sessionWatch', () {
    test('checks the session every interval while the app is open and in the '
        'foreground', () {
      fakeAsync((async) {
        final app = TestApp();
        final providers = app.providers();
        providers.listen(sessionWatchProvider, (_, _) {});
        app.fakes.auth.session = null;

        async.elapse(sessionCheckInterval - const Duration(seconds: 1));
        expect(providers.read(accessProvider), Access.unlocked);

        async.elapse(const Duration(seconds: 1));
        expect(providers.read(accessProvider), Access.signedOut);
      });
    });

    test('has no timer while the cover is up, nor once the app is closed', () {
      fakeAsync((async) {
        final app = TestApp();
        final providers = app.providers();
        providers.listen(sessionWatchProvider, (_, _) {});
        providers.read(privacyCoverUpProvider.notifier).set(true);
        app.fakes.auth.session = null;

        async.elapse(sessionCheckInterval * 3);

        expect(providers.read(accessProvider), Access.unlocked);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('does not double a check that is still under way', () {
      fakeAsync((async) {
        final app = TestApp();
        final providers = app.providers();
        providers.listen(sessionWatchProvider, (_, _) {});

        async.elapse(sessionCheckInterval * 3);

        expect(providers.read(accessProvider), Access.unlocked);
      });
    });
  });

  group('signOutEndedSession', () {
    test('forgets on the device the session a failure ended', () {
      fakeAsync((async) {
        final app = TestApp();
        final providers = app.providers();
        providers.listen(signOutEndedSessionProvider, (_, _) {});

        providers
            .read(accessControllerProvider.notifier)
            .endSession('sessionExpired', 0);
        async.flushMicrotasks();

        expect(app.fakes.auth.signOutCalls, 1);
      });
    });

    test('leaves alone a lock and a session the application already ended', () {
      fakeAsync((async) {
        final app = TestApp();
        final providers = app.providers();
        providers.listen(signOutEndedSessionProvider, (_, _) {});
        final access = providers.read(accessControllerProvider.notifier);

        access.endSession('appLocked', 0);
        async.flushMicrotasks();
        access
          ..startAt(Access.unlocked)
          ..endSession('unauthorized', 0);
        async.flushMicrotasks();

        expect(app.fakes.auth.signOutCalls, 0);
      });
    });
  });
}
