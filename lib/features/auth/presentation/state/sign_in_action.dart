import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_in_action.g.dart';

/// Signs in with what the user typed. On success the app is open (the access
/// moves to unlocked), and nothing of the sign-in stays behind: the answer (the
/// session, with a name and an email) is dropped, and the password is only an
/// argument of [run], never kept in the state.
///
/// Failures are the errors of `SignIn`: a field the domain refuses
/// (`validation`, with the field and the rule), the credentials refused, the
/// server unreachable, a fault of the server or of the storage. None is
/// retried, and a second call while one is under way is ignored.
@riverpod
class SignInAction extends _$SignInAction {
  @override
  ActionState build() => const ActionState.idle();

  /// Signs in.
  Future<void> run({required String email, required String password}) =>
      runResultAction<void>(
        ref: ref,
        current: () => state,
        emit: (next) => state = next,
        execute: () async {
          final result = await ref
              .read(signInUseCaseProvider)
              .execute(email: email, password: password);
          return map(result, (_) {});
        },
        onSuccess: (_, _) =>
            ref.read(accessControllerProvider.notifier).signedIn(),
      );

  /// Forgets the failure.
  void reset() => state = const ActionState.idle();
}
