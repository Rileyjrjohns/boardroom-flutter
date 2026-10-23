import 'dart:async';

import 'package:boardroom/core/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

/// Every query that holds data of the user, so that all of them can be dropped
/// at once when the access moves. A query registers itself in
/// [QueryLifetime.keepQueryFor] and leaves when it is disposed.
final class QueryRegistry {
  final Set<KeepAliveLink> _links = {};

  /// How many queries are held in memory.
  int get length => _links.length;

  /// Lets go of every query: the ones nobody listens to are disposed at once,
  /// the data with them. One a screen still listens to is disposed as soon as
  /// that screen goes, and the router removes the screens of a session that
  /// ended; a screen that is built after the move reads a new query.
  void dropAll() {
    for (final link in _links.toList()) {
      link.close();
    }
  }
}

/// The registry of the queries of the container.
final queryRegistryProvider = Provider<QueryRegistry>((ref) => QueryRegistry());

/// Drops every query of [container] each time the epoch of the access moves
/// (the user signed out, the app locked, another user signed in), and returns
/// the subscription, to close it with the container.
///
/// It must be a subscription of the container itself and not one a query makes
/// with `ref.listen`: a provider nobody listens to is paused, and a paused
/// provider is not told of the change, so a second user would be handed what
/// the first one had loaded. The container is always listening, which is the
/// counterpart of the query cache the React Native app clears when a session
/// ends. The app (`StartupGate`) and the test harness both call it.
ProviderSubscription<int> dropQueriesWhenSessionMoves(
  ProviderContainer container,
) => container.listen<int>(sessionEpochProvider, (previous, next) {
  if (previous != next) {
    container.read(queryRegistryProvider).dropAll();
  }
});

/// How long what a query holds counts as current. A screen opened again inside
/// this window shows what it has and asks nothing; after it, the screen shows
/// what it has at once and the query revalidates in the background. The offline
/// policy (the saved copy, how old it may be) is the business of the use cases;
/// this only avoids asking again for what was just asked.
const Duration queryStaleTime = Duration(seconds: 60);

/// How long a query that no screen shows any more stays in memory. The data is
/// confidential, so it must not linger: five minutes cover going back and
/// forth between a list and a meeting.
const Duration queryGcTime = Duration(minutes: 5);

/// The lifetime of the data of a user in memory (the counterpart of the
/// `staleTime` and `gcTime` of the query client of the React Native app).
extension QueryLifetime on Ref {
  /// Call it first in a query that holds data of the user:
  ///
  /// - the data stays in memory [gcTime] after the last screen stopped
  ///   listening (a provider is otherwise disposed at once);
  /// - a screen that listens again after [staleTime] gets the data it has and
  ///   the provider asks again (`invalidateSelf`, which keeps the previous
  ///   value while the new one loads);
  /// - whenever the user leaves the open app (the epoch of the access moves)
  ///   the data is dropped, whether a screen was listening or not, so nothing
  ///   of the previous session stays in memory (see
  ///   [dropQueriesWhenSessionMoves], which the container installs).
  void keepQueryFor({
    Duration staleTime = queryStaleTime,
    Duration gcTime = queryGcTime,
  }) {
    final link = keepAlive();
    final registry = read(queryRegistryProvider);
    registry._links.add(link);
    Timer? gc;
    var stale = false;
    final staleTimer = Timer(staleTime, () => stale = true);

    onCancel(() {
      gc = Timer(gcTime, link.close);
    });
    onResume(() {
      gc?.cancel();
      if (stale) {
        // Not inside the life-cycle callback: a provider cannot invalidate
        // itself from there.
        scheduleMicrotask(() {
          if (mounted) {
            invalidateSelf();
          }
        });
      }
    });
    onDispose(() {
      registry._links.remove(link);
      gc?.cancel();
      staleTimer.cancel();
    });
  }
}
