// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The transitions of the access (docs/spec/screens.md "ACCESS"): each starts
// from the access it makes sense from and does nothing from any other, and the
// epoch goes up every time the access changes.

void main() {
  late ProviderContainer providers;
  late AccessController access;

  AccessState state() => providers.read(accessControllerProvider);

  void startAt(Access at) => access.startAt(at);

  setUp(() {
    providers = ProviderContainer();
    addTearDown(providers.dispose);
    access = providers.read(accessControllerProvider.notifier);
  });

  test('starts, with no epoch and no reason', () {
    expect(state().access, Access.starting);
    expect(state().epoch, 0);
    expect(state().sessionEndedBy, isNull);
  });

  test(
    'a restore with no session signs the user out, a restored one locks',
    () {
      access.sessionRestored(SessionRestore.none);
      expect(state().access, Access.signedOut);

      startAt(Access.starting);
      access.sessionRestored(SessionRestore.unlockRequired);
      expect(state().access, Access.locked);
    },
  );

  test('a restore answers once, from starting only', () {
    startAt(Access.unlocked);

    access.sessionRestored(SessionRestore.none);

    expect(state().access, Access.unlocked);
  });

  test('signing in opens the app from signed out only', () {
    startAt(Access.locked);
    access.signedIn();
    expect(state().access, Access.locked);

    startAt(Access.signedOut);
    access.signedIn();
    expect(state().access, Access.unlocked);
  });

  test('unlocking opens the app from locked only', () {
    startAt(Access.signedOut);
    access.unlocked();
    expect(state().access, Access.signedOut);

    startAt(Access.locked);
    access.unlocked();
    expect(state().access, Access.unlocked);
  });

  test('locking needs an open app and the epoch the check started under', () {
    startAt(Access.unlocked);
    access.locked(5);
    expect(state().access, Access.unlocked);

    access.locked(state().epoch);
    expect(state().access, Access.locked);
  });

  test('signing out moves to signed out from any other access, once', () {
    for (final from in [Access.starting, Access.locked, Access.unlocked]) {
      startAt(from);
      final epoch = state().epoch;

      access.signedOut();

      expect(state().access, Access.signedOut);
      expect(state().epoch, epoch + 1);
    }
    final epoch = state().epoch;
    access.signedOut();
    expect(state().epoch, epoch);
  });

  test('a failure that ends the session sends the user to sign-in with the '
      'reason, or to the lock for appLocked', () {
    for (final (code, to) in [
      ('sessionExpired', Access.signedOut),
      ('unauthorized', Access.signedOut),
      ('appLocked', Access.locked),
    ]) {
      startAt(Access.unlocked);

      access.endSession(code, state().epoch);

      expect(state().access, to, reason: code);
      expect(state().sessionEndedBy, code);
    }
  });

  test('the answer of a user who left is ignored', () {
    startAt(Access.unlocked);
    final epoch = state().epoch;
    access
      ..signedOut()
      ..signedIn();

    access.endSession(AuthenticationErrorCode.sessionChanged.value, epoch);

    expect(state().access, Access.unlocked);
  });

  test('a session that is not open has nothing to end', () {
    startAt(Access.locked);

    access.endSession('sessionExpired', state().epoch);

    expect(state().access, Access.locked);
  });

  test('the reason is forgotten when the access changes again', () {
    startAt(Access.unlocked);
    access.endSession('sessionExpired', state().epoch);
    access.signedIn();

    expect(state().sessionEndedBy, isNull);
  });

  test('the selectors follow the access', () {
    startAt(Access.unlocked);
    expect(providers.read(accessProvider), Access.unlocked);
    expect(providers.read(sessionOpenProvider), isTrue);

    access.signedOut();

    expect(providers.read(sessionOpenProvider), isFalse);
    expect(
      const AccessState(access: Access.locked),
      const AccessState(access: Access.locked),
    );
    expect(Access.values.map((a) => a.value), [
      'starting',
      'signedOut',
      'locked',
      'unlocked',
    ]);
  });
}
