import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_out_action.g.dart';

/// Signs the user out: the use case empties the caches and forgets the session,
/// and the access moves to signed out, which sends the user to the sign-in
/// screen and drops what the interface holds. The votes waiting in the outbox
/// are kept by the use case. A session that cannot be forgotten is the one
/// failure, and the confirmation says so and can be confirmed again. The use
/// case has already locked the app by then (and emptied the caches), so the
/// interface follows it to the lock screen straight away instead of leaving the
/// screen of the user on display with nothing behind it; signing out is offered
/// there as well.
@riverpod
class SignOutAction extends _$SignOutAction {
  @override
  ActionState build() => const ActionState.idle();

  /// Signs out.
  Future<void> run() => runResultAction<void>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref.read(signOutUseCaseProvider).execute(),
    onSuccess: (_, _) =>
        ref.read(accessControllerProvider.notifier).signedOut(),
    onFailure: (_, startedUnder) =>
        ref.read(accessControllerProvider.notifier).locked(startedUnder),
  );

  /// Forgets the failure.
  void reset() => state = const ActionState.idle();
}
