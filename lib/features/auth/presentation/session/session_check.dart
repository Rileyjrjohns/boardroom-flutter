import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_check.g.dart';

/// Asks whether the session of the open app is still good, and ends it if it is
/// not. The provider gives `check(epoch)`, where `epoch` is the access the
/// caller is checking (the epoch of the access when it decided to check).
///
/// The question goes to a use case (`GetCurrentUser`, through the session
/// guard), which is what knows the session: an expired one is found out and the
/// caches are emptied by the guard, and the screen is sent to the sign-in
/// screen with the reason (`sessionExpired`, `notAuthenticated`,
/// `unauthorized`...), or to the lock screen if the app is locked. A question
/// that cannot be answered (the stored session cannot be read) fails closed,
/// with the lock screen: nothing says the content may stay. The answer is
/// applied only if the access is still the one `epoch` names, so a check that
/// outlives its user does not touch the next one.
///
/// Two things ask: the return from the background when no lock is required (the
/// app lifecycle), which keeps the privacy cover up until the answer, and the
/// timer of an app that stays open (`sessionWatchProvider`).
@Riverpod(keepAlive: true)
Future<void> Function(int epoch) sessionCheck(Ref ref) => (epoch) async {
  final access = ref.read(accessControllerProvider.notifier);
  if (ref.read(accessProvider) != Access.unlocked) {
    return;
  }
  switch (await ref.read(getCurrentUserUseCaseProvider).execute()) {
    case Ok():
      return;
    case Err(:final error):
      if (isSessionEndingCode(error.code)) {
        access.endSession(error.code, epoch);
      } else {
        access.locked(epoch);
      }
  }
};
