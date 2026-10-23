import 'dart:async';

import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/query/query_lifetime.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'meetings_list.g.dart';

/// What the list screen shows of the pages loaded so far.
final class MeetingsListState {
  /// Creates the state.
  const new({
    required this.epoch,
    required this.meetings,
    required this.nextCursor,
    this.staleSince,
    this.loadingMore = false,
    this.nextPageFailure,
  });

  /// The epoch of the access the pages were loaded under. The next pages are
  /// asked, and answered, for that access only (the query itself is dropped
  /// when the epoch moves, see `keepQueryFor`).
  final int epoch;

  /// Every meeting of every page, in the order of the pages.
  final List<MeetingSummary> meetings;

  /// The cursor of the next page, or null when the last page is loaded.
  final PageCursor? nextCursor;

  /// When the oldest saved page was cached, or null when every page comes from
  /// the server. One saved page is enough to say that what is on the screen may
  /// be out of date, and the oldest one says how far.
  final Instant? staleSince;

  /// Whether the next page is being fetched.
  final bool loadingMore;

  /// The code of the failure of the next page, when it failed. The pages loaded
  /// stay: this is a field of the state, not an error of the list.
  final String? nextPageFailure;

  /// Whether there is a page after the last one loaded.
  bool get hasNextPage => nextCursor != null;

  /// A copy with the given fields replaced. [nextPageFailure] is cleared by
  /// passing [clearFailure].
  MeetingsListState copyWith({
    List<MeetingSummary>? meetings,
    PageCursor? nextCursor,
    bool clearCursor = false,
    Instant? staleSince,
    bool? loadingMore,
    String? nextPageFailure,
    bool clearFailure = false,
  }) => MeetingsListState(
    epoch: epoch,
    meetings: meetings ?? this.meetings,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    staleSince: staleSince ?? this.staleSince,
    loadingMore: loadingMore ?? this.loadingMore,
    nextPageFailure: clearFailure
        ? null
        : (nextPageFailure ?? this.nextPageFailure),
  );
}

/// The meetings of a period, a page at a time. The first page is the build of
/// the provider (a failure is thrown as a `QueryFailure`, retried by the
/// policy of the root container); the next pages are appended by [loadMore],
/// and a failure of one is a field of the state. [restart] is what a pull to
/// refresh and a retry call: it starts again from the first page only, never
/// asking again for every page the user has scrolled through.
@riverpod
class MeetingsList extends _$MeetingsList {
  // Bumped at every build, so that the answer of a page asked for before a
  // restart is not appended to the list that replaced it.
  int _generation = 0;

  @override
  Future<MeetingsListState> build(MeetingPeriod period) async {
    ref.keepQueryFor();
    _generation += 1;
    final epoch = ref.read(sessionEpochProvider);
    if (!ref.read(sessionOpenProvider)) {
      // Nothing is asked of the server for a user who is not in the open app.
      return await Completer<MeetingsListState>().future;
    }
    final loaded = await _fetch(null, epoch);
    return MeetingsListState(
      epoch: epoch,
      meetings: loaded.data.items,
      nextCursor: loaded.data.nextCursor,
      staleSince: _staleSinceOf(loaded),
    );
  }

  /// Starts again from the first page: what a pull to refresh and a retry of
  /// the first page or of a refresh call. The rows stay on the screen until the
  /// first page arrives, and stay next to the error if it fails. Completes
  /// when the first page is back, whatever its answer.
  Future<void> restart() async {
    ref.invalidateSelf();
    try {
      await future;
      // The failure is the state of the provider, which the screen reads.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  /// Asks for the next page, when there is one, none is being fetched and the
  /// last one did not fail: after a failed page the user decides when to try
  /// again ([retryNextPage]).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.epoch != ref.read(sessionEpochProvider) ||
        state.isLoading ||
        !current.hasNextPage ||
        current.loadingMore ||
        current.nextPageFailure != null) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final loaded = await _fetch(current.nextCursor, current.epoch);
      if (!_isCurrent(generation)) {
        return;
      }
      final latest = state.requireValue;
      final staleSince = _olderOf(latest.staleSince, _staleSinceOf(loaded));
      state = AsyncData(
        MeetingsListState(
          epoch: latest.epoch,
          meetings: [...latest.meetings, ...loaded.data.items],
          nextCursor: loaded.data.nextCursor,
          staleSince: staleSince,
        ),
      );
    } on Exception catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      final code = errorCodeOf(error, ref.read(errorCatalogProvider));
      // A failure that ends the session ends it for the whole app (the handler
      // ignores the others), as it does for the first page.
      ref.read(sessionEndHandlerProvider)(
        code,
        error is QueryFailure ? error.startedUnder : null,
      );
      state = AsyncData(
        state.requireValue.copyWith(loadingMore: false, nextPageFailure: code),
      );
    }
  }

  /// Asks again for the page that failed.
  Future<void> retryNextPage() async {
    final current = state.value;
    if (current == null || current.nextPageFailure == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearFailure: true));
    await loadMore();
  }

  bool _isCurrent(int generation) =>
      ref.mounted && generation == _generation && state.hasValue;

  Future<Loaded<Page<MeetingSummary>>> _fetch(
    PageCursor? cursor,
    int epoch,
  ) async {
    final limit = ref.read(meetingsPageSizeProvider);
    final Result<Loaded<Page<MeetingSummary>>, AppError> result;
    switch (createPageRequest(limit: limit, cursor: cursor)) {
      case Ok(:final value):
        result = await ref
            .read(listMeetingsUseCaseProvider)
            .execute(period: period, request: value);
      case Err(:final error):
        result = err(error);
    }
    final loaded = unwrapResult(result, startedUnder: epoch);
    return loaded;
  }
}

Instant? _staleSinceOf(Loaded<Page<MeetingSummary>> loaded) =>
    switch (loaded.source) {
      StaleSource(:final cachedAt) => cachedAt,
      FreshSource() => null,
    };

Instant? _olderOf(Instant? first, Instant? second) {
  if (first == null || second == null) {
    return first ?? second;
  }
  return first < second ? first : second;
}
