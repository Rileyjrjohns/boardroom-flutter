import 'dart:async';

import 'package:boardroom/core/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  ///   the data is dropped as soon as nobody listens, so nothing of the
  ///   previous session stays in memory.
  void keepQueryFor({
    Duration staleTime = queryStaleTime,
    Duration gcTime = queryGcTime,
  }) {
    final link = keepAlive();
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
      gc?.cancel();
      staleTimer.cancel();
    });
    listen<int>(sessionEpochProvider, (previous, next) {
      if (previous != next) {
        link.close();
      }
    });
  }
}
