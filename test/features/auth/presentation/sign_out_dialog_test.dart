import 'dart:async';

import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/presentation/components/sign_out_dialog.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/create_fakes.dart';
import '../../../support/fakes/fake_auth_session.dart';
import '../../../support/presentation/test_app.dart';

// The confirmation of a sign-out, ported from SignOutDialog.test.tsx of the
// React Native app. The dialog is mounted as it is (not through
// showSignOutDialog) so that a test sees what the screen that opens it passes.

Future<_Run> _pump(
  WidgetTester tester, {
  int? pendingCount = 0,
  VoidCallback? onDismiss,
  TestApp? app,
  Locale locale = const Locale('en'),
}) async {
  final theApp = app ?? TestApp();
  final providers = await pumpScreen(
    tester,
    SignOutDialog(pendingCount: pendingCount, onDismiss: onDismiss ?? () {}),
    app: theApp,
    locale: locale,
  );
  return (providers: providers, app: theApp);
}

typedef _Run = ({ProviderContainer providers, TestApp app});

void main() {
  final en = l10nOf();

  group('SignOutDialog', () {
    testWidgets('says what signing out means, and nothing about votes when '
        'none waits', (tester) async {
      await _pump(tester);

      expect(find.text(en.authSignOutTitle), findsOneWidget);
      expect(find.text(en.authSignOutMessage), findsOneWidget);
      expect(byTestId(AuthTestIds.signOutPending), findsNothing);
    });

    for (final (count, language) in [
      (1, 'en'),
      (3, 'en'),
      (1, 'fr'),
      (2, 'fr'),
    ]) {
      testWidgets(
        'says how many votes wait and that they are kept, for $count in '
        '$language',
        (tester) async {
          final locale = Locale(language);
          await _pump(tester, pendingCount: count, locale: locale);

          expect(
            find.descendant(
              of: byTestId(AuthTestIds.signOutPending),
              matching: find.text(l10nOf(locale).authSignOutPending(count)),
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('says it in general terms when the screen cannot know how '
        'many wait', (tester) async {
      await _pump(tester, pendingCount: null);

      expect(
        find.descendant(
          of: byTestId(AuthTestIds.signOutPending),
          matching: find.text(en.authSignOutPendingUnknown),
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps the votes that wait when the user signs out, and '
        'empties the rest', (tester) async {
      final app = TestApp()..fakes.outbox.seed([aPendingVote()]);
      final run = await _pump(tester, pendingCount: 1, app: app);

      await tester.tap(byTestId(AuthTestIds.signOutConfirm));
      await tester.pumpAndSettle();

      expect(run.providers.read(accessProvider), Access.signedOut);
      expect(app.fakes.outbox.snapshot(), hasLength(1));
      expect(app.fakes.auth.session, isNull);
    });

    testWidgets('asks to be closed by its cancel button and by the back '
        'button, and signs nobody out', (tester) async {
      var dismissed = 0;
      final run = await _pump(tester, onDismiss: () => dismissed += 1);

      await tester.tap(byTestId(AuthTestIds.signOutCancel));
      await tester.pump();
      expect(dismissed, 1);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(dismissed, 2);
      expect(run.app.fakes.auth.signOutCalls, 0);
    });

    testWidgets('makes the destructive action look like one, and puts the '
        'safe one first', (tester) async {
      await _pump(tester);

      final cancel = tester.getTopLeft(byTestId(AuthTestIds.signOutCancel));
      final confirm = tester.getTopLeft(byTestId(AuthTestIds.signOutConfirm));

      expect(cancel.dy, lessThan(confirm.dy));
      expect(
        find.descendant(
          of: byTestId(AuthTestIds.signOutConfirm),
          matching: find.text(en.authSignOutAction),
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: byTestId(AuthTestIds.signOutConfirm),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.style?.backgroundColor?.resolve({}), isNotNull);
    });

    group('while the sign-out is under way', () {
      Future<(TestApp, Completer<void>)> hold(WidgetTester tester) async {
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
        return (app, gate);
      }

      testWidgets('cannot be closed with the back button, nor with the '
          'cancel button', (tester) async {
        final (app, gate) = await hold(tester);
        var dismissed = 0;
        await _pump(tester, app: app, onDismiss: () => dismissed += 1);
        await tester.tap(byTestId(AuthTestIds.signOutConfirm));
        await tester.pump();
        expect(find.text(en.authSignOutSigningOut), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.tap(byTestId(AuthTestIds.signOutCancel));
        await tester.pump();

        expect(dismissed, 0);
        gate.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('can be closed again once it has ended', (tester) async {
        final app = TestApp()..fakes.auth.signOutFailure = storageWriteFailed();
        var dismissed = 0;
        await _pump(tester, app: app, onDismiss: () => dismissed += 1);
        await tester.tap(byTestId(AuthTestIds.signOutConfirm));
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(dismissed, 1);
      });
    });

    group('when the session cannot be forgotten', () {
      testWidgets('follows the use case, which has locked the app, to the '
          'lock screen', (tester) async {
        final app = TestApp()..fakes.auth.signOutFailure = storageWriteFailed();
        final run = await _pump(tester, app: app);

        await tester.tap(byTestId(AuthTestIds.signOutConfirm));
        await tester.pumpAndSettle();

        expect(run.providers.read(accessProvider), Access.locked);
        expect(find.text(en.authSignOutFailed), findsOneWidget);
        expect(byTestId(AuthTestIds.signOutError), findsOneWidget);
      });
    });
  });
}

/// A session store that waits for the test before it forgets the session.
final class _HeldAuth implements AuthSession {
  new(this._inner, this._gate);

  final FakeAuthSession _inner;
  final Future<void> _gate;

  @override
  Future<Result<Session, SignInFailure>> signIn(Credentials credentials) =>
      _inner.signIn(credentials);

  @override
  Future<Result<Session?, StorageReadFailedError>> current() =>
      _inner.current();

  @override
  Future<Result<void, StorageWriteFailedError>> signOut() async {
    await _gate;
    return await _inner.signOut();
  }
}
