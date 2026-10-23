import 'dart:async';

import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes/create_fakes.dart';
import '../../../support/fakes/fake_auth_session.dart';
import '../../../support/presentation/fake_demo_network.dart';
import '../../../support/presentation/test_app.dart';

// The reference widget test of a screen: the use cases are the real ones over
// the fakes, the providers are overridden like the app does, the texts are read
// from the generated localizations and the elements are found by test id.

Future<void> _type(WidgetTester tester, String id, String text) async {
  await tester.enterText(byTestId(id), text);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(byTestId(AuthTestIds.signInSubmit));
  await tester.pump();
}

void main() {
  final en = l10nOf();

  group('SignInScreen', () {
    testWidgets('shows the form in the idle state', (tester) async {
      await pumpScreen(tester, const SignInScreen(), access: Access.signedOut);

      expect(byTestId(AuthTestIds.signInScreen), findsOneWidget);
      expect(find.text(en.authSignInTitle), findsOneWidget);
      expect(find.text(en.authSignInMessage), findsOneWidget);
      expect(byTestId(AuthTestIds.signInEmail), findsOneWidget);
      expect(byTestId(AuthTestIds.signInPassword), findsOneWidget);
      expect(byTestId(AuthTestIds.signInSubmit), findsOneWidget);
      expect(byTestId(AuthTestIds.signInEmailError), findsNothing);
      expect(byTestId(AuthTestIds.signInError), findsNothing);
      expect(byTestId(AuthTestIds.sessionNotice), findsNothing);
      expect(byTestId(CoreTestIds.demoPanel), findsNothing);
      expect(byTestId(CoreTestIds.statusBanner), findsNothing);
    });

    testWidgets('speaks French when the device does', (tester) async {
      await pumpScreen(
        tester,
        const SignInScreen(),
        access: Access.signedOut,
        locale: const Locale('fr'),
      );

      expect(find.text(l10nOf(const Locale('fr')).authSignInTitle), findsOne);
    });

    testWidgets('tells an empty email next to its field and calls nothing', (
      tester,
    ) async {
      final app = TestApp();
      await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );

      await _submit(tester);

      expect(find.text(en.authSignInEmailRequired), findsOneWidget);
      expect(byTestId(AuthTestIds.signInEmailError), findsOneWidget);
      expect(app.fakes.auth.signInCalls, isEmpty);
    });

    testWidgets('tells a malformed email, then clears it on typing', (
      tester,
    ) async {
      await pumpScreen(tester, const SignInScreen(), access: Access.signedOut);
      await _type(tester, AuthTestIds.signInEmail, 'not an email');
      await _type(tester, AuthTestIds.signInPassword, 'secret');

      await _submit(tester);
      expect(find.text(en.authSignInEmailInvalid), findsOneWidget);

      await _type(tester, AuthTestIds.signInEmail, 'a@b.co');
      expect(byTestId(AuthTestIds.signInEmailError), findsNothing);
    });

    testWidgets('tells an empty password next to its field', (tester) async {
      await pumpScreen(tester, const SignInScreen(), access: Access.signedOut);
      await _type(tester, AuthTestIds.signInEmail, validCredentials.email);

      await _submit(tester);

      expect(find.text(en.authSignInPasswordRequired), findsOneWidget);
      expect(byTestId(AuthTestIds.signInPasswordError), findsOneWidget);
    });

    testWidgets('signs in, opens the app and empties the password', (
      tester,
    ) async {
      final app = TestApp();
      final providers = await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );
      await _type(tester, AuthTestIds.signInEmail, validCredentials.email);
      await _type(
        tester,
        AuthTestIds.signInPassword,
        validCredentials.password,
      );

      await _submit(tester);
      await tester.pumpAndSettle();

      expect(app.fakes.auth.signInCalls, hasLength(1));
      expect(providers.read(accessControllerProvider).access, Access.unlocked);
      final password = tester.widget<TextField>(
        find.descendant(
          of: byTestId(AuthTestIds.signInPassword),
          matching: find.byType(TextField),
        ),
      );
      expect(password.controller!.text, isEmpty);
    });

    testWidgets('shows the busy state and ignores a second press while the '
        'request is under way', (tester) async {
      final gate = Completer<void>();
      final fakes = createFakes();
      final app = TestApp(
        fakes: fakes,
        adaptPorts: (ports) => Ports(
          clock: ports.clock,
          monitoring: ports.monitoring,
          auth: _HeldAuth(fakes.auth, gate.future),
          biometricGate: ports.biometricGate,
          connectivity: ports.connectivity,
          screenProtection: ports.screenProtection,
          meetings: ports.meetings,
          meetingCache: ports.meetingCache,
          documents: ports.documents,
          documentCache: ports.documentCache,
          votes: ports.votes,
          outbox: ports.outbox,
        ),
      );
      await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );
      await _type(tester, AuthTestIds.signInEmail, validCredentials.email);
      await _type(
        tester,
        AuthTestIds.signInPassword,
        validCredentials.password,
      );

      await tester.tap(byTestId(AuthTestIds.signInSubmit));
      await tester.pump();
      expect(find.text(en.authSignInSubmitting), findsOneWidget);
      await tester.tap(byTestId(AuthTestIds.signInSubmit));
      gate.complete();
      await tester.pumpAndSettle();

      expect(app.fakes.auth.signInCalls, hasLength(1));
    });

    testWidgets('tells refused credentials above the button and stays', (
      tester,
    ) async {
      final providers = await pumpScreen(
        tester,
        const SignInScreen(),
        access: Access.signedOut,
      );
      await _type(tester, AuthTestIds.signInEmail, validCredentials.email);
      await _type(tester, AuthTestIds.signInPassword, 'wrong');

      await _submit(tester);
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.signInError), findsOneWidget);
      expect(find.text(en.coreErrorsInvalidCredentials), findsOneWidget);
      expect(providers.read(accessControllerProvider).access, Access.signedOut);
    });

    testWidgets('tells a server out of reach as a form error', (tester) async {
      final app = TestApp()..fakes.auth.signInFailure = networkUnavailable();
      await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );
      await _type(tester, AuthTestIds.signInEmail, validCredentials.email);
      await _type(
        tester,
        AuthTestIds.signInPassword,
        validCredentials.password,
      );

      await _submit(tester);
      await tester.pumpAndSettle();

      expect(find.text(en.coreErrorsNetworkUnavailable), findsOneWidget);
    });

    testWidgets('explains why the user was sent back by a failure', (
      tester,
    ) async {
      final providers = await pumpScreen(tester, const SignInScreen());
      providers
          .read(accessControllerProvider.notifier)
          .endSession(
            AuthenticationErrorCode.sessionExpired.value,
            providers.read(accessControllerProvider).epoch,
          );
      await tester.pump();

      expect(byTestId(AuthTestIds.sessionNotice), findsOneWidget);
      expect(find.text(en.coreErrorsSessionExpired), findsOneWidget);
    });

    testWidgets('says the device is offline in the connection banner', (
      tester,
    ) async {
      final providers = await pumpScreen(
        tester,
        const SignInScreen(),
        access: Access.signedOut,
      );
      providers
          .read(connectivityStateProvider.notifier)
          .set(ConnectivityStatus.offline);
      await tester.pump();

      expect(byTestId(CoreTestIds.statusBanner), findsOneWidget);
      expect(byTestId(CoreTestIds.offlineBanner), findsOneWidget);
    });
  });

  group('SignInScreen in the dev configuration', () {
    testWidgets('offers the demo accounts, which fill the form without '
        'submitting', (tester) async {
      final network = FakeDemoNetwork();
      final app = TestApp(
        demoControls: DemoControls(
          network: network,
          accounts: const [
            DemoAccountHint(
              fullName: 'Alice',
              email: 'alice@example.com',
              password: 'secret',
            ),
          ],
        ),
      );
      await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );
      expect(byTestId(CoreTestIds.demoPanel), findsOneWidget);
      expect(byTestId(CoreTestIds.demoAccounts), findsOneWidget);

      await tester.ensureVisible(
        byTestId(demoAccountTestId('alice@example.com')),
      );
      await tester.tap(byTestId(demoAccountTestId('alice@example.com')));
      await tester.pump();

      expect(find.text('alice@example.com'), findsOneWidget);
      expect(app.fakes.auth.signInCalls, isEmpty);
    });

    testWidgets('has an offline switch that cuts the simulated network', (
      tester,
    ) async {
      final network = FakeDemoNetwork();
      final app = TestApp(
        demoControls: DemoControls(network: network, accounts: const []),
      );
      await pumpScreen(
        tester,
        const SignInScreen(),
        app: app,
        access: Access.signedOut,
      );

      await tester.tap(byTestId(CoreTestIds.demoOfflineSwitch));
      await tester.pump();

      expect(network.online, isFalse);
    });
  });

  test('the sign-in route is the one of the specification', () {
    expect(AppRoutes.signIn.path, '/sign-in');
  });
}

/// A session store that waits for the test before it answers a sign-in.
final class _HeldAuth implements AuthSession {
  new(this._inner, this._gate);

  final FakeAuthSession _inner;
  final Future<void> _gate;

  @override
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials) async {
    await _gate;
    return await _inner.signIn(credentials);
  }

  @override
  Future<Result<Session?, StorageReadFailedError>> current() =>
      _inner.current();

  @override
  Future<Result<void, StorageWriteFailedError>> signOut() => _inner.signOut();
}
