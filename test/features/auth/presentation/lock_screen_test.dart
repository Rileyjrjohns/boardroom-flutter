import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/auth/presentation/screens/lock_screen.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/fake_demo_network.dart';
import '../../../support/presentation/test_app.dart';

// The lock screen, ported from LockScreen.test.tsx of the React Native app.

typedef _Run = ({TestApp app, ProviderContainer providers});

/// The lock screen of an app that has just started: somebody is signed in and
/// the app is locked.
Future<_Run> _pumpLock(
  WidgetTester tester, {
  TestApp? app,
  Access access = Access.locked,
  Locale locale = const Locale('en'),
}) async {
  final theApp = app ?? TestApp(startsLocked: true);
  final providers = await pumpScreen(
    tester,
    const LockScreen(),
    app: theApp,
    access: access,
    locale: locale,
  );
  return (app: theApp, providers: providers);
}

Future<void> _press(WidgetTester tester, String id) async {
  await tester.ensureVisible(byTestId(id));
  await tester.tap(byTestId(id));
  await tester.pumpAndSettle();
}

Finder _inside(String id, Finder matching) =>
    find.descendant(of: byTestId(id), matching: matching);

void main() {
  final en = l10nOf();

  group('LockScreen', () {
    group('what it shows', () {
      testWidgets('says the app is locked and offers to unlock it, and to '
          'sign out', (tester) async {
        await _pumpLock(tester);

        expect(byTestId(AuthTestIds.lockScreen), findsOneWidget);
        expect(find.text(en.authLockTitle), findsOneWidget);
        expect(find.text(en.authLockMessage), findsOneWidget);
        expect(
          _inside(AuthTestIds.lockUnlock, find.text(en.authLockUnlock)),
          findsOneWidget,
        );
        expect(
          _inside(AuthTestIds.lockSignOut, find.text(en.authSignOutAction)),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(find.text(en.authLockTitle)),
          matchesSemantics(label: en.authLockTitle, isHeader: true),
        );
      });

      testWidgets('shows nothing of the user and asks for nothing about '
          'them: no name, no email, no meeting', (tester) async {
        final run = await _pumpLock(tester);
        final user = run.app.fakes.auth.session!.user;

        expect(find.text(user.fullName), findsNothing);
        expect(find.textContaining(user.email), findsNothing);
        expect(run.app.fakes.meetings.listCalls, isEmpty);
        expect(run.app.fakes.meetings.getCalls, isEmpty);
      });

      testWidgets('has buttons at least as tall as the touch target, and a '
          'hint for the unlock', (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpLock(tester);

        expect(
          tester.getSize(byTestId(AuthTestIds.lockUnlock)).height,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester.getSize(byTestId(AuthTestIds.lockSignOut)).height,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester.getSemantics(byTestId(AuthTestIds.lockUnlock)).hint,
          en.authLockUnlockHint,
        );
        handle.dispose();
      });

      testWidgets('says why the app is locked when a failure is what sent '
          'the user here', (tester) async {
        final run = await _pumpLock(tester, access: Access.unlocked);
        run.providers
            .read(accessControllerProvider.notifier)
            .endSession(
              AuthenticationErrorCode.appLocked.value,
              run.providers.read(accessControllerProvider).epoch,
            );
        await tester.pump();

        expect(
          _inside(AuthTestIds.sessionNotice, find.text(en.coreErrorsAppLocked)),
          findsOneWidget,
        );
      });
    });

    group('unlocking', () {
      testWidgets('asks for the biometric proof, once, for the right '
          'reason, and opens the app', (tester) async {
        final run = await _pumpLock(tester);

        await _press(tester, AuthTestIds.lockUnlock);

        expect(run.app.fakes.biometricGate.prompts, [
          BiometricReason.unlockApp,
        ]);
        expect(run.providers.read(accessProvider), Access.unlocked);
      });

      testWidgets('shows the button busy, and asks once however many times '
          'it is pressed', (tester) async {
        final run = await _pumpLock(tester);
        final answer = Completer<void>();
        run.app.fakes.biometricGate.onPrompt = () => answer.future;

        await tester.tap(byTestId(AuthTestIds.lockUnlock));
        await tester.tap(byTestId(AuthTestIds.lockUnlock));
        await tester.pump();
        await tester.tap(byTestId(AuthTestIds.lockUnlock));
        await tester.pump();

        expect(
          _inside(AuthTestIds.lockUnlock, find.text(en.authLockUnlocking)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                _inside(AuthTestIds.lockUnlock, find.byType(FilledButton)),
              )
              .onPressed,
          isNull,
        );
        expect(run.app.fakes.biometricGate.prompts, hasLength(1));
        answer.complete();
        await tester.pumpAndSettle();
      });

      for (final (failure, text)
          in <(BiometricError, String Function(AppLocalizations))>[
            (biometricCancelled(), (l) => l.authUnlockErrorsBiometricCancelled),
            (biometricFailed(), (l) => l.authUnlockErrorsBiometricFailed),
            (biometricLockedOut(), (l) => l.authUnlockErrorsBiometricLockedOut),
          ]) {
        testWidgets('says what happened, and stays locked, when the prompt '
            'ends with ${failure.code}', (tester) async {
          final run = await _pumpLock(tester);
          run.app.fakes.biometricGate.authentication = err(failure);

          await _press(tester, AuthTestIds.lockUnlock);

          expect(
            _inside(AuthTestIds.lockError, find.text(text(en))),
            findsOneWidget,
          );
          expect(run.providers.read(accessProvider), Access.locked);
          expect(
            _inside(AuthTestIds.lockUnlock, find.text(en.authLockUnlock)),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  _inside(AuthTestIds.lockUnlock, find.byType(FilledButton)),
                )
                .onPressed,
            isNotNull,
          );
        });
      }

      for (final (failure, text)
          in <(BiometricAvailabilityError, String Function(AppLocalizations))>[
            (
              biometricUnavailable(),
              (l) => l.authUnlockErrorsBiometricUnavailable,
            ),
            (
              biometricNotEnrolled(),
              (l) => l.authUnlockErrorsBiometricNotEnrolled,
            ),
          ]) {
        testWidgets('says the biometrics cannot be used, without any prompt, '
            'when the device answers ${failure.code}', (tester) async {
          final run = await _pumpLock(tester);
          run.app.fakes.biometricGate.availability = err(failure);

          await _press(tester, AuthTestIds.lockUnlock);

          expect(
            _inside(AuthTestIds.lockError, find.text(text(en))),
            findsOneWidget,
          );
          expect(run.app.fakes.biometricGate.prompts, isEmpty);
          expect(run.providers.read(accessProvider), Access.locked);
        });
      }

      testWidgets('says the biometrics cannot be used every time, and leaves '
          'signing out as the way forward', (tester) async {
        final run = await _pumpLock(tester);
        run.app.fakes.biometricGate.availability = err(biometricNotEnrolled());

        await _press(tester, AuthTestIds.lockUnlock);
        await _press(tester, AuthTestIds.lockUnlock);

        expect(run.providers.read(accessProvider), Access.locked);
        expect(
          tester
              .widget<OutlinedButton>(
                _inside(AuthTestIds.lockSignOut, find.byType(OutlinedButton)),
              )
              .onPressed,
          isNotNull,
        );

        await _press(tester, AuthTestIds.lockSignOut);
        await _press(tester, AuthTestIds.signOutConfirm);

        expect(run.providers.read(accessProvider), Access.signedOut);
      });

      testWidgets('lets the user try again after a failure, and opens the '
          'app when the proof is right', (tester) async {
        final run = await _pumpLock(tester);
        run.app.fakes.biometricGate.authentication = err(biometricFailed());
        await _press(tester, AuthTestIds.lockUnlock);
        expect(byTestId(AuthTestIds.lockError), findsOneWidget);

        run.app.fakes.biometricGate.authentication = ok<void>(null);
        await _press(tester, AuthTestIds.lockUnlock);

        expect(run.providers.read(accessProvider), Access.unlocked);
      });

      testWidgets('does not prompt again by itself, nor on its own when '
          'shown', (tester) async {
        final run = await _pumpLock(tester);
        await tester.pump(const Duration(seconds: 60));

        expect(run.app.fakes.biometricGate.prompts, isEmpty);
        expect(run.app.fakes.biometricGate.availabilityChecks, 0);
      });
    });

    group('signing out from the lock screen', () {
      testWidgets('asks for a confirmation that says, in general terms, that '
          'waiting votes are kept', (tester) async {
        await _pumpLock(tester);

        await _press(tester, AuthTestIds.lockSignOut);

        expect(byTestId(AuthTestIds.signOutDialog), findsOneWidget);
        expect(find.text(en.authSignOutTitle), findsOneWidget);
        expect(find.text(en.authSignOutMessage), findsOneWidget);
        expect(
          _inside(
            AuthTestIds.signOutPending,
            find.text(en.authSignOutPendingUnknown),
          ),
          findsOneWidget,
        );
      });

      testWidgets('signs out when confirmed: the session is forgotten, and '
          'the user goes to the sign-in screen', (tester) async {
        final run = await _pumpLock(tester);

        await _press(tester, AuthTestIds.lockSignOut);
        await _press(tester, AuthTestIds.signOutConfirm);

        expect(run.app.fakes.auth.signOutCalls, 1);
        expect(run.app.fakes.auth.session, isNull);
        expect(run.providers.read(accessProvider), Access.signedOut);
        expect(byTestId(AuthTestIds.signOutDialog), findsNothing);
      });

      testWidgets('does nothing when cancelled', (tester) async {
        final run = await _pumpLock(tester);

        await _press(tester, AuthTestIds.lockSignOut);
        await _press(tester, AuthTestIds.signOutCancel);

        expect(byTestId(AuthTestIds.signOutDialog), findsNothing);
        expect(run.app.fakes.auth.signOutCalls, 0);
        expect(run.providers.read(accessProvider), Access.locked);
      });

      testWidgets('says when the session could not be forgotten, and lets '
          'the user try again', (tester) async {
        final run = await _pumpLock(tester);
        run.app.fakes.auth.signOutFailure = storageWriteFailed();
        await _press(tester, AuthTestIds.lockSignOut);

        await _press(tester, AuthTestIds.signOutConfirm);

        expect(
          _inside(AuthTestIds.signOutError, find.text(en.authSignOutFailed)),
          findsOneWidget,
        );
        expect(run.providers.read(accessProvider), Access.locked);

        run.app.fakes.auth.signOutFailure = null;
        await _press(tester, AuthTestIds.signOutConfirm);
        expect(run.providers.read(accessProvider), Access.signedOut);
      });
    });

    group('a prompt that fails in a way the use case does not know', () {
      testWidgets('says something went wrong instead of crashing, when the '
          'prompt rejects instead of answering', (tester) async {
        final run = await _pumpLock(tester);
        run.app.fakes.biometricGate.onPrompt = () => throw StateError('boom');

        await _press(tester, AuthTestIds.lockUnlock);

        expect(
          _inside(AuthTestIds.lockError, find.text(en.coreErrorsUnexpected)),
          findsOneWidget,
        );
      });
    });

    group('a device that is offline', () {
      testWidgets('says so at the top, and nothing when the connection is '
          'there', (tester) async {
        final run = await _pumpLock(tester);
        expect(byTestId(CoreTestIds.offlineBanner), findsNothing);

        run.providers
            .read(connectivityStateProvider.notifier)
            .set(ConnectivityStatus.offline);
        await tester.pump();
        expect(byTestId(CoreTestIds.offlineBanner), findsOneWidget);
        expect(find.text(en.coreBannerOffline), findsOneWidget);

        run.providers
            .read(connectivityStateProvider.notifier)
            .set(ConnectivityStatus.online);
        await tester.pump();
        expect(byTestId(CoreTestIds.offlineBanner), findsNothing);
      });

      testWidgets('offers the switch of the demo in the dev configuration '
          'only', (tester) async {
        await _pumpLock(
          tester,
          app: TestApp(
            startsLocked: true,
            demoControls: DemoControls(
              network: FakeDemoNetwork(),
              accounts: const [],
            ),
          ),
        );
        expect(byTestId(CoreTestIds.demoOfflineSwitch), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpLock(tester);
        expect(byTestId(CoreTestIds.demoOfflineSwitch), findsNothing);
      });

      testWidgets('keeps the unlock and the sign-out where they were', (
        tester,
      ) async {
        await _pumpLock(
          tester,
          app: TestApp(
            startsLocked: true,
            demoControls: DemoControls(
              network: FakeDemoNetwork(),
              accounts: const [],
            ),
          ),
        );

        expect(byTestId(AuthTestIds.lockUnlock), findsOneWidget);
        expect(byTestId(AuthTestIds.lockSignOut), findsOneWidget);
      });
    });

    group('in each language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        testWidgets('is written in ${locale.languageCode}, failure included', (
          tester,
        ) async {
          final text = l10nOf(locale);
          final run = await _pumpLock(tester, locale: locale);
          run.app.fakes.biometricGate.authentication = err(
            biometricLockedOut(),
          );

          await _press(tester, AuthTestIds.lockUnlock);

          expect(find.text(text.authLockTitle), findsOneWidget);
          expect(find.text(text.authLockMessage), findsOneWidget);
          expect(
            _inside(
              AuthTestIds.lockError,
              find.text(text.authUnlockErrorsBiometricLockedOut),
            ),
            findsOneWidget,
          );
        });
      }

      testWidgets('says in French that the app is locked and how to unlock '
          'it', (tester) async {
        final fr = l10nOf(const Locale('fr'));
        await _pumpLock(tester, locale: const Locale('fr'));

        expect(find.text(fr.authLockTitle), findsOneWidget);
        expect(find.text(fr.authLockUnlock), findsOneWidget);
        expect(find.text(fr.authSignOutAction), findsOneWidget);
        expect(fr.authLockTitle, isNot(en.authLockTitle));
      });
    });
  });
}
