// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/domain/errors/biometric_error.dart';
import 'package:boardroom/features/auth/presentation/components/restore_failure.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/state/sign_in_action.dart';
import 'package:boardroom/features/auth/presentation/state/sign_out_action.dart';
import 'package:boardroom/features/auth/presentation/state/unlock_action.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes/fake_auth_session.dart';
import '../../../support/presentation/test_app.dart';

// The actions of the session: sign in, unlock and sign out, with the failures
// the screens tell.

void main() {
  group('SignInAction', () {
    test('opens the app and keeps nothing of the sign-in', () async {
      final app = TestApp();
      final providers = app.providers(access: Access.signedOut);
      providers.listen(signInActionProvider, (_, _) {});

      await providers
          .read(signInActionProvider.notifier)
          .run(email: 'alice@example.com', password: defaultPassword);

      expect(providers.read(accessProvider), Access.unlocked);
      expect(providers.read(signInActionProvider), const ActionState.idle());
    });

    test('keeps the failure of the use case and stays signed out', () async {
      final providers = TestApp().providers(access: Access.signedOut);
      providers.listen(signInActionProvider, (_, _) {});

      await providers
          .read(signInActionProvider.notifier)
          .run(email: 'alice@example.com', password: 'wrong');

      expect(
        providers.read(signInActionProvider).failure,
        invalidCredentials(),
      );
      expect(providers.read(accessProvider), Access.signedOut);

      providers.read(signInActionProvider.notifier).reset();
      expect(providers.read(signInActionProvider), const ActionState.idle());
    });

    test('tells the field the domain refuses', () async {
      final providers = TestApp().providers(access: Access.signedOut);
      providers.listen(signInActionProvider, (_, _) {});

      await providers
          .read(signInActionProvider.notifier)
          .run(email: '', password: 'x');

      expect(
        providers.read(signInActionProvider).failure,
        isA<ValidationError>().having(
          (e) => e.field,
          'field',
          ValidationField.email,
        ),
      );
    });
  });

  group('UnlockAction', () {
    test('opens the app once the biometrics succeed', () async {
      final app = TestApp(startsLocked: true);
      final providers = app.providers(access: Access.locked);
      providers.listen(unlockActionProvider, (_, _) {});

      await providers.read(unlockActionProvider.notifier).run();

      expect(providers.read(accessProvider), Access.unlocked);
    });

    test('keeps the failure of the prompt and stays locked', () async {
      final app = TestApp(startsLocked: true);
      app.fakes.biometricGate.authentication = err(biometricCancelled());
      final providers = app.providers(access: Access.locked);
      providers.listen(unlockActionProvider, (_, _) {});

      await providers.read(unlockActionProvider.notifier).run();

      expect(
        providers.read(unlockActionProvider).failure,
        biometricCancelled(),
      );
      expect(providers.read(accessProvider), Access.locked);

      providers.read(unlockActionProvider.notifier).reset();
      expect(providers.read(unlockActionProvider), const ActionState.idle());
    });
  });

  group('SignOutAction', () {
    test('signs out and keeps the votes that wait', () async {
      final app = TestApp();
      final providers = app.providers();
      providers.listen(signOutActionProvider, (_, _) {});

      await providers.read(signOutActionProvider.notifier).run();

      expect(providers.read(accessProvider), Access.signedOut);
      expect(app.fakes.auth.session, isNull);
    });

    test('follows the use case, which has locked the app, to the lock '
        'screen when the session cannot be forgotten', () async {
      final app = TestApp();
      app.fakes.auth.signOutFailure = storageWriteFailed();
      final providers = app.providers();
      providers.listen(signOutActionProvider, (_, _) {});

      await providers.read(signOutActionProvider.notifier).run();

      expect(
        providers.read(signOutActionProvider).failure,
        storageWriteFailed(),
      );
      expect(providers.read(accessProvider), Access.locked);

      providers.read(signOutActionProvider.notifier).reset();
      expect(providers.read(signOutActionProvider), const ActionState.idle());
    });
  });

  group('RestoreFailure', () {
    testWidgets('tells the failure with a way to ask again and a way out', (
      tester,
    ) async {
      var retried = 0;
      final app = TestApp();
      await pumpScreen(
        tester,
        RestoreFailure(error: storageReadFailed(), onRetry: () => retried++),
        app: app,
        access: Access.starting,
      );
      final en = l10nOf();

      expect(byTestId(AuthTestIds.restoreError), findsOneWidget);
      expect(find.text(en.coreErrorsStorageReadFailed), findsOneWidget);
      expect(find.text(en.coreStartupForgetExplanation), findsOneWidget);
      await tester.tap(find.text(en.coreStatesRetry));
      expect(retried, 1);

      await tester.tap(byTestId(AuthTestIds.restoreForget));
      await tester.pumpAndSettle();

      expect(app.fakes.auth.signOutCalls, 1);
    });

    testWidgets('says the sign-out of the escape failed, and can be asked '
        'again', (tester) async {
      final app = TestApp();
      app.fakes.auth.signOutFailure = storageWriteFailed();
      await pumpScreen(
        tester,
        RestoreFailure(error: storageReadFailed(), onRetry: () {}),
        app: app,
        access: Access.starting,
      );

      await tester.tap(byTestId(AuthTestIds.restoreForget));
      await tester.pumpAndSettle();

      expect(byTestId(AuthTestIds.restoreForgetError), findsOneWidget);
      expect(find.text(l10nOf().authSignOutFailed), findsOneWidget);
      expect(find.byType(FilledButton), findsWidgets);
    });
  });
}
