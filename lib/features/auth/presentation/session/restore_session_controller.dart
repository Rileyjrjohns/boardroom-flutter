import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_session_controller.g.dart';

/// The cold start of the session: asks `RestoreSession` who was signed in when
/// the app was last used, once, as soon as the app has started. No session
/// sends the user to the sign-in screen; a restored one to the lock screen,
/// always (the use case locks the app, and the access follows its answer). The
/// state is the failure: the only one is a stored session that cannot be read,
/// which can be asked again ([retry]). Watch it once, from the session
/// controller.
@Riverpod(keepAlive: true)
class RestoreSessionController extends _$RestoreSessionController {
  @override
  StorageReadFailedError? build() {
    // Not in the build itself: it must not move another provider.
    unawaited(Future<void>.microtask(_restore));
    return null;
  }

  /// Asks again after a failure.
  void retry() {
    state = null;
    unawaited(_restore());
  }

  Future<void> _restore() async {
    if (ref.read(accessProvider) != Access.starting) {
      return;
    }
    final result = await ref.read(restoreSessionUseCaseProvider).execute();
    if (!ref.mounted) {
      return;
    }
    switch (result) {
      case Ok(:final value):
        state = null;
        ref
            .read(accessControllerProvider.notifier)
            .sessionRestored(value.status);
      case Err(:final error):
        state = error;
    }
  }
}
