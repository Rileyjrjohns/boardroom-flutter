import 'dart:async';

import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/features/votes/presentation/state/vote_sync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_observer.g.dart';

/// Follows the connection of the device through the `ObserveConnectivity` use
/// case, from the start of the app (it needs no session) and until the app is
/// gone: the status goes to `connectivityStateProvider`, where the offline line
/// of the banner reads it (on the screens of the open app, and on the sign-in
/// and lock screens), and the votes are requested each time the connection
/// comes back, which is when the votes that wait are sent. The device saying it
/// is online is a hint, not a promise: the synchronisation is what finds out.
/// Watch it once, from the session controller.
@Riverpod(keepAlive: true)
void connectivityObserver(Ref ref) {
  final useCase = ref.watch(observeConnectivityUseCaseProvider);
  final connectivity = ref.read(connectivityStateProvider.notifier);
  var active = true;
  Unsubscribe? stop;

  unawaited(
    useCase
        .execute((status) {
          connectivity.set(status);
          if (status == ConnectivityStatus.online) {
            ref.read(requestVoteSyncProvider)();
          }
        })
        .then((observation) {
          if (!active) {
            observation.unsubscribe();
            return;
          }
          stop = observation.unsubscribe;
          connectivity.set(observation.status);
        }),
  );

  ref.onDispose(() {
    active = false;
    stop?.call();
  });
}
