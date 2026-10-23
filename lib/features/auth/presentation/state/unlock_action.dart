import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'unlock_action.g.dart';

/// Unlocks the app with the biometrics. On success the access moves to
/// unlocked and the router shows the meetings. The prompt is not started on its
/// own: the user touches Unlock. A failure is one of the codes of
/// `unlockErrorMessages`; none is retried, the user touches Unlock again.
@riverpod
class UnlockAction extends _$UnlockAction {
  @override
  ActionState build() => const ActionState.idle();

  /// Asks for the biometric proof.
  Future<void> run() => runResultAction<void>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref.read(unlockAppUseCaseProvider).execute(),
    onSuccess: (_, _) => ref.read(accessControllerProvider.notifier).unlocked(),
  );

  /// Forgets the failure.
  void reset() => state = const ActionState.idle();
}
