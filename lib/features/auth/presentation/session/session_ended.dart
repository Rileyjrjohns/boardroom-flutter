import 'dart:async';

import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_ended.g.dart';

/// The failures whose session is forgotten here: the application layer ended
/// the others (`unauthorized` was ended where it met the server's answer, and a
/// lock is not the end of a session: the user unlocks it).
final Set<String> _forgottenHere = Set.unmodifiable({
  AuthenticationErrorCode.notAuthenticated.value,
  AuthenticationErrorCode.sessionExpired.value,
  AuthenticationErrorCode.sessionChanged.value,
});

/// Forgets on the device a session that a failure ended: it expired, nobody was
/// signed in, another user was. The app was sent to the sign-in screen, and a
/// restart must not restore what is no longer valid. `SignOut` does it, and it
/// succeeds when nobody is signed in. Watch it once, from the session
/// controller.
@Riverpod(keepAlive: true)
void signOutEndedSession(Ref ref) {
  ref.listen(accessControllerProvider, (previous, next) {
    final endedBy = next.sessionEndedBy;
    if (endedBy != previous?.sessionEndedBy &&
        endedBy != null &&
        _forgottenHere.contains(endedBy)) {
      unawaited(ref.read(signOutUseCaseProvider).execute());
    }
  });
}
