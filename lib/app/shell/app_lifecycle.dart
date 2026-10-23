import 'dart:async';

import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/session/session_check.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/presentation/state/vote_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the system may take a snapshot of the app, or show it to nobody: the
/// app is anything but resumed. (The React Native states are `inactive` and
/// `background`; Flutter's `hidden` and `paused` are the background.)
bool isHidden(AppLifecycleState state) => state != AppLifecycleState.resumed;

/// Whether the app is in the background, as opposed to merely inactive (the
/// system biometric prompt, a pulled-down control centre).
bool isBackground(AppLifecycleState state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;

/// What the app does as it goes to the background and comes back, from the
/// events of the lifecycle of the system (`useAppLifecycle` of the React Native
/// app):
///
/// - **The privacy cover.** The content is covered as soon as the app is no
///   longer active (the app switcher takes its snapshot as the app goes
///   inactive, and nothing confidential must be in it), and uncovered only when
///   it is active again and, if it had been in the background, the lock has
///   been evaluated.
/// - **The lock.** The instant the app went to the background is recorded from
///   the clock of the use cases (not when it merely became inactive: the
///   system's biometric prompt makes it inactive, and unlocking must not count
///   as having been away). On the way back, `EvaluateAppLock` judges it against
///   the grace period, before the content is shown: when the unlock is
///   required, or the answer cannot be known, the access moves to locked, which
///   drops the data and removes the screens. Failing to judge fails closed.
/// - **The session.** When no lock is required, the session is still checked
///   before anything is uncovered (`sessionCheckProvider`): an app that was
///   away past the expiry of its session would otherwise show the previous
///   content until the first request found out. The cover stays up until the
///   answer.
/// - **The synchronisation.** Once the lock has been judged, the session
///   checked and the app is still open, the votes that wait are requested.
///
/// A return from inactive that never went to the background only uncovers the
/// content.
class AppLifecycleHandler {
  /// Creates the handler over [_ref].
  new(this._ref);

  final Ref _ref;
  AppLifecycleState _current = AppLifecycleState.resumed;
  Instant? _backgroundedAt;

  /// Starts from the state the app is in now (null when the binding does not
  /// say, which is a resumed app).
  void start(AppLifecycleState? initial) {
    _current = initial ?? AppLifecycleState.resumed;
    _ref.read(privacyCoverUpProvider.notifier).set(isHidden(_current));
  }

  /// The system said the app moved to [next].
  void onChanged(AppLifecycleState next) {
    _current = next;
    final cover = _ref.read(privacyCoverUpProvider.notifier);
    if (isHidden(next)) {
      cover.set(true);
      if (isBackground(next) && _backgroundedAt == null) {
        _backgroundedAt = _ref.read(clockProvider).now();
      }
      return;
    }
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) {
      cover.set(false);
      return;
    }
    unawaited(_resume(since));
  }

  Future<void> _resume(Instant since) async {
    final access = _ref.read(accessControllerProvider.notifier);
    final epoch = _ref.read(accessControllerProvider).epoch;
    if (_ref.read(accessProvider) == Access.unlocked) {
      final required = await _ref
          .read(evaluateAppLockUseCaseProvider)
          .execute(backgroundedAt: since);
      if (required case Ok(:final value) when !value) {
        await _ref.read(sessionCheckProvider)(epoch);
      } else {
        access.locked(epoch);
      }
    }
    // The app may have gone away again while the lock was being judged: it
    // stays covered then.
    if (!isHidden(_current)) {
      _ref.read(privacyCoverUpProvider.notifier).set(false);
      if (_ref.read(accessProvider) == Access.unlocked) {
        _ref.read(requestVoteSyncProvider)();
      }
    }
  }
}

/// The handler of the lifecycle of the app, one for the whole app.
final appLifecycleHandlerProvider = Provider<AppLifecycleHandler>(
  AppLifecycleHandler.new,
);
