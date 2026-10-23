import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_state.g.dart';

// The setters below are methods on purpose: a notifier is written to by name.
// ignore_for_file: use_setters_to_change_properties
// ignore_for_file: avoid_positional_boolean_parameters

// The state of the interface that belongs to no feature, and nothing else.
// Server data is not here (it is in the query providers), and neither is state
// that belongs to one widget (a `State`) or to a feature (where the user
// stands is `auth`'s, which period of the meetings is selected is the
// meetings', what the votes synchronisation did is the votes'). Each is state
// that no query holds, that more than one place reads and that is written from
// outside any widget (the events of the system). The store never holds a name,
// an email or a vote.

/// What the device says about its connection. It is an event, not a request:
/// the offline line of the banner and the trigger of the synchronisation both
/// follow it. Online until the observation says otherwise.
@Riverpod(keepAlive: true)
class ConnectivityState extends _$ConnectivityState {
  @override
  ConnectivityStatus build() => ConnectivityStatus.online;

  /// Records what the device says.
  void set(ConnectivityStatus status) => state = status;
}

/// Whether the content must be hidden, because the app is inactive or in the
/// background (the app switcher takes its snapshot then), or because the lock
/// has not yet been evaluated on the way back.
@Riverpod(keepAlive: true)
class PrivacyCoverUp extends _$PrivacyCoverUp {
  @override
  bool build() => false;

  /// Puts the cover up or takes it down.
  void set(bool covered) => state = covered;
}

/// Whether the user is still to be told that local data was reset (votes
/// waiting on this device may have been lost). Known when the app starts, shown
/// on the screens of the open app, and kept until the user has read it: it is
/// owed to them, not to a session.
@Riverpod(keepAlive: true)
class LocalDataResetNotice extends _$LocalDataResetNotice {
  @override
  bool build() => ref.watch(appNoticesProvider).localDataReset;

  /// The user has read it: forgets it here and tells the startup notices.
  void dismiss() {
    state = false;
    unawaited(ref.read(appNoticesProvider).acknowledgeLocalDataReset());
  }
}
