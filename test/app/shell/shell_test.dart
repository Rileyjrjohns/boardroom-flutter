// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:boardroom/app/app.dart';
import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/shell/app_lifecycle.dart';
import 'package:boardroom/app/shell/connectivity_observer.dart';
import 'package:boardroom/app/shell/session_controller.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/features/votes/presentation/state/vote_sync.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation/fake_demo_network.dart';
import '../../support/presentation/test_app.dart';

// The shell: what the app does as it goes to the background and comes back, the
// connection of the device, the session controller and the start of the app.

void main() {
  group('AppLifecycleHandler', () {
    late TestApp app;
    late ProviderContainer providers;
    late AppLifecycleHandler handler;
    late int syncs;

    void setUpApp([Access access = Access.unlocked]) {
      syncs = 0;
      app = TestApp();
      providers = app.providers(
        access: access,
        extra: [requestVoteSyncProvider.overrideWithValue(() => syncs++)],
      );
      handler = providers.read(appLifecycleHandlerProvider)
        ..start(AppLifecycleState.resumed);
    }

    bool covered() => providers.read(privacyCoverUpProvider);

    test('covers the content as soon as the app is inactive and uncovers it '
        'when it is back, without judging the lock', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.inactive);
        expect(covered(), isTrue);
        handler.onChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(covered(), isFalse);
        expect(providers.read(accessProvider), Access.unlocked);
        expect(syncs, 0);
      });
    });

    test('starts covered when the app starts in the background', () {
      setUpApp();

      handler.start(AppLifecycleState.paused);

      expect(covered(), isTrue);
      handler.start(null);
      expect(covered(), isFalse);
    });

    test('keeps the app open when it was away less than the grace period, '
        'checks the session and asks for the votes', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.hidden);
        handler.onChanged(AppLifecycleState.paused);
        app.fakes.clock.advance(10000);
        handler.onChanged(AppLifecycleState.inactive);
        handler.onChanged(AppLifecycleState.resumed);
        expect(covered(), isTrue);
        async.flushMicrotasks();

        expect(covered(), isFalse);
        expect(providers.read(accessProvider), Access.unlocked);
        expect(syncs, 1);
      });
    });

    test('locks the app when it was away past the grace period', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.paused);
        app.fakes.clock.advance(appLockGracePeriod + 1);
        handler.onChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
        expect(covered(), isFalse);
        expect(syncs, 0);
      });
    });

    test('ends the session when it expired while the app was away', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.paused);
        app.fakes.auth.session = null;
        handler.onChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.signedOut);
        expect(
          providers.read(accessControllerProvider).sessionEndedBy,
          AuthenticationErrorCode.notAuthenticated.value,
        );
      });
    });

    test('fails closed when the lock cannot be judged', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.paused);
        app.fakes.auth.readFailure = storageReadFailed();
        handler.onChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(providers.read(accessProvider), Access.locked);
      });
    });

    test('stays covered when the app goes away again while the lock is being '
        'judged', () {
      fakeAsync((async) {
        setUpApp();

        handler.onChanged(AppLifecycleState.paused);
        handler.onChanged(AppLifecycleState.resumed);
        handler.onChanged(AppLifecycleState.inactive);
        async.flushMicrotasks();

        expect(covered(), isTrue);
        expect(syncs, 0);
      });
    });

    test('judges nothing when nobody is signed in', () {
      fakeAsync((async) {
        setUpApp(Access.signedOut);

        handler.onChanged(AppLifecycleState.paused);
        handler.onChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(covered(), isFalse);
        expect(providers.read(accessProvider), Access.signedOut);
        expect(syncs, 0);
      });
    });

    test('tells the background from the inactive states', () {
      expect(isHidden(AppLifecycleState.resumed), isFalse);
      expect(isHidden(AppLifecycleState.inactive), isTrue);
      expect(isBackground(AppLifecycleState.inactive), isFalse);
      expect(isBackground(AppLifecycleState.hidden), isTrue);
      expect(isBackground(AppLifecycleState.paused), isTrue);
    });
  });

  group('connectivityObserver', () {
    test('follows the connection, and asks for the votes when it is back', () {
      fakeAsync((async) {
        final app = TestApp();
        var syncs = 0;
        final providers = app.providers(
          extra: [requestVoteSyncProvider.overrideWithValue(() => syncs++)],
        );
        final subscription = providers.listen(
          connectivityObserverProvider,
          (_, _) {},
        );
        async.flushMicrotasks();
        expect(
          providers.read(connectivityStateProvider),
          ConnectivityStatus.online,
        );

        app.fakes.connectivity.emit(ConnectivityStatus.offline);
        expect(
          providers.read(connectivityStateProvider),
          ConnectivityStatus.offline,
        );
        expect(syncs, 0);
        app.fakes.connectivity.emit(ConnectivityStatus.online);

        expect(
          providers.read(connectivityStateProvider),
          ConnectivityStatus.online,
        );
        expect(syncs, 1);
        subscription.close();
      });
    });

    test('starts offline when the device is', () {
      fakeAsync((async) {
        final app = TestApp();
        app.fakes.connectivity.emit(ConnectivityStatus.offline);
        final providers = app.providers();

        providers.listen(connectivityObserverProvider, (_, _) {});
        async.flushMicrotasks();

        expect(
          providers.read(connectivityStateProvider),
          ConnectivityStatus.offline,
        );
      });
    });
  });

  group('the app', () {
    Future<void> pumpApp(
      WidgetTester tester,
      TestApp app, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        BoardroomApp(start: (_) async => ok(app.container), locale: locale),
      );
    }

    testWidgets('shows the loading state while it starts, then restores the '
        'session', (tester) async {
      final app = TestApp()..fakes.auth.session = null;
      final gate = Completer<void>();
      await tester.pumpWidget(
        BoardroomApp(
          start: (_) async {
            await gate.future;
            return ok(app.container);
          },
        ),
      );

      expect(byTestId(CoreTestIds.startupLoading), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      expect(byTestId(CoreTestIds.startupLoading), findsNothing);
      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
    });

    testWidgets('a stored session locks the app at the start', (tester) async {
      await pumpApp(tester, TestApp());
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.lockScreen), findsOneWidget);
    });

    testWidgets('the loading state is translated', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        BoardroomApp(
          locale: const Locale('fr'),
          start: (_) async {
            await gate.future;
            return ok(TestApp().container);
          },
        ),
      );

      expect(
        find.bySemanticsLabel(l10nOf(const Locale('fr')).coreStartupLoading),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a restore that fails says so, with a way to ask again and a '
        'way out', (tester) async {
      final app = TestApp()..fakes.auth.readFailure = storageReadFailed();
      await pumpApp(tester, app);
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.restoreError), findsOneWidget);
      expect(byTestId(AuthTestIds.restoreForget), findsOneWidget);

      app.fakes.auth.readFailure = null;
      await tester.tap(byTestId(CoreTestIds.retryButton));
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.lockScreen), findsOneWidget);
    });

    testWidgets('the way out of a restore that fails signs out and goes to '
        'sign-in', (tester) async {
      final app = TestApp()..fakes.auth.readFailure = storageReadFailed();
      await pumpApp(tester, app);
      await tester.pumpAndSettle();

      await tester.tap(byTestId(AuthTestIds.restoreForget));
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
    });

    testWidgets('shows the privacy cover when the app goes inactive, over '
        'the screen', (tester) async {
      await pumpApp(tester, TestApp()..fakes.auth.session = null);
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(byTestId(CoreTestIds.privacyCover), findsOneWidget);
      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(byTestId(CoreTestIds.privacyCover), findsNothing);
    });

    testWidgets('requests the vote synchronisation when the app opens', (
      tester,
    ) async {
      // The shell asks as soon as the access is unlocked.
      var syncs = 0;
      final app = TestApp();
      final providers = app.providers(
        extra: [requestVoteSyncProvider.overrideWithValue(() => syncs++)],
      );
      await tester.pumpWidget(
        testHost(providers, const SessionController(child: SizedBox.shrink())),
      );
      await tester.pump();

      expect(syncs, greaterThanOrEqualTo(1));
      // The session watch has a timer: stop it before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
      providers.dispose();
      expect(byTestId(MeetingsTestIds.meetingsList), findsNothing);
    });
  });

  group('the start fails', () {
    testWidgets('says why, with the technical code and nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(
        BoardroomApp(start: (_) async => err(const MissingApiBaseUrlError())),
      );
      await tester.pumpAndSettle();
      final en = l10nOf();

      expect(byTestId(CoreTestIds.startupFailure), findsOneWidget);
      expect(find.text(en.coreStartupTitle), findsOneWidget);
      expect(
        find.text(en.coreStartupCode('missingApiBaseUrl')),
        findsOneWidget,
      );
    });

    testWidgets('gives the code startupAborted when the start itself throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        BoardroomApp(start: (_) async => throw StateError('a bug')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10nOf().coreStartupCode(startupAbortedCode)),
        findsOneWidget,
      );
    });

    testWidgets('speaks French', (tester) async {
      await tester.pumpWidget(
        BoardroomApp(
          locale: const Locale('fr'),
          start: (_) async => err(const MissingApiBaseUrlError()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10nOf(const Locale('fr')).coreStartupTitle),
        findsOneWidget,
      );
    });
  });

  test('a demo network keeps its listeners apart', () {
    final network = FakeDemoNetwork();
    final seen = <bool>[];
    final stop = network.subscribe(({required online}) => seen.add(online));

    network.setOnline(online: false);
    stop();
    network.setOnline(online: true);

    expect(seen, [false]);
  });
}
