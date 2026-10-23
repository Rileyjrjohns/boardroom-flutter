import 'dart:async';

import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/presentation/session/session_check.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_watch.g.dart';

/// How often the session of the open app is checked.
const Duration sessionCheckInterval = Duration(
  milliseconds: sessionCheckIntervalMillis,
);

/// Checks the session on a timer ([sessionCheckInterval], the
/// `SESSION_CHECK_INTERVAL_MILLIS` of the policy), while the app is open and in
/// the foreground (the privacy cover is down), through the same check as the
/// return from the background (`sessionCheckProvider`). The timer exists only
/// then: it is cancelled when the user leaves the open app and when the app
/// goes away (the return from the background checks, and a timer that runs on
/// in the background wakes the device for nothing). A check that is still under
/// way when the next tick comes is not doubled. Watch it once, from the session
/// controller.
@Riverpod(keepAlive: true)
void sessionWatch(Ref ref) {
  final open = ref.watch(sessionOpenProvider);
  final covered = ref.watch(privacyCoverUpProvider);
  if (!open || covered) {
    return;
  }
  var checking = false;
  final timer = Timer.periodic(sessionCheckInterval, (_) async {
    if (checking) {
      return;
    }
    checking = true;
    try {
      await ref.read(sessionCheckProvider)(
        ref.read(accessControllerProvider).epoch,
      );
    } finally {
      checking = false;
    }
  });
  ref.onDispose(timer.cancel);
}
