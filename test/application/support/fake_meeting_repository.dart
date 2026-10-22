import 'dart:async';
import 'dart:math';

import 'package:boardroom/application/ports/meeting_repository.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';

import '../../domain/support/builders.dart';
import 'copy_plain.dart';
import 'fake_network.dart';

/// A call of `list`: the period asked for and the request.
typedef ListCall = ({MeetingPeriod period, PageRequest request});

/// The remote meetings of a test. It behaves like the server the port
/// describes: a list is sorted as documented (upcoming meetings soonest first,
/// past ones latest first), cut to the page size of the request, and continued
/// from the cursor, which here is the id of the last meeting of the previous
/// page. A wrong request (another period, another size, another cursor) is
/// therefore visible in what comes back, not only in the calls recorded. A
/// cursor that matches nothing gives an empty page.
class FakeMeetingRepository implements MeetingRepository {
  /// Creates a repository that goes down with [_network].
  new(this._network);

  final FakeNetwork _network;

  /// Makes every call fail with this error while set (an `unauthorized` server,
  /// say).
  GatewayError? failure;

  /// Called when a request arrives, before the server answers: a test uses it
  /// to change the world while the request is in flight (another user signs
  /// in, say). The answer is the one of the world after the hook has run.
  FutureOr<void> Function()? onRequest;

  /// Every call of `list`, in order.
  final List<ListCall> listCalls = [];

  /// The id of every call of `get`, in order.
  final List<MeetingId> getCalls = [];

  final Map<MeetingPeriod, List<MeetingSummary>> _summaries = {};
  final Map<MeetingId, Meeting> _meetings = {};
  final Set<MeetingId> _forbiddenIds = {};

  /// The meetings of a period, in any order.
  void setMeetings(MeetingPeriod period, List<MeetingSummary> summaries) {
    _summaries[period] = List.of(summaries);
  }

  /// Adds a meeting the server holds.
  void addMeeting(Meeting meeting) {
    _meetings[meeting.id] = meeting;
  }

  /// The server no longer has the meeting.
  void removeMeeting(MeetingId id) {
    _meetings.remove(id);
    _forbiddenIds.remove(id);
  }

  /// The server has the meeting but refuses the caller: it answers `forbidden`.
  void forbid(MeetingId id) {
    _forbiddenIds.add(id);
  }

  @override
  Future<Result<Page<MeetingSummary>, GatewayError>> list(
    MeetingPeriod period,
    PageRequest request,
  ) async {
    listCalls.add((period: period, request: request));
    await onRequest?.call();
    if (!_network.online) {
      return err(networkUnavailable());
    }
    final failure = this.failure;
    if (failure != null) {
      return err(failure);
    }

    final sorted = _sorted(period);
    final String? after = request.cursor;
    final afterIndex = sorted.indexWhere((summary) => summary.id == after);
    // No cursor: from the start. A cursor that matches nothing: past the end.
    final start = after == null
        ? 0
        : afterIndex == -1
        ? sorted.length
        : afterIndex + 1;
    final end = min(start + request.limit, sorted.length);
    final items = sorted.sublist(start, end);
    final hasMore = start + request.limit < sorted.length;

    return ok(
      copyPlain(
        hasMore && items.isNotEmpty
            ? createPage(items, unwrap(parsePageCursor(items.last.id)))
            : createPage(items),
      ),
    );
  }

  @override
  Future<Result<Meeting, RepositoryError>> get(MeetingId id) async {
    getCalls.add(id);
    await onRequest?.call();
    if (!_network.online) {
      return err(networkUnavailable());
    }
    final failure = this.failure;
    if (failure != null) {
      return err(failure);
    }
    if (_forbiddenIds.contains(id)) {
      return err(forbidden());
    }
    final meeting = _meetings[id];
    if (meeting == null) {
      return err(notFound());
    }
    return ok(copyPlain(meeting));
  }

  // Meetings with the same instant keep the order they were given in, as the
  // sort of a list does in the server this fake stands for: `List.sort` of
  // Dart is not stable, so the position is the tie-break.
  List<MeetingSummary> _sorted(MeetingPeriod period) {
    final indexed =
        (_summaries[period] ?? const <MeetingSummary>[]).indexed.toList()
          ..sort((first, second) {
            final byTime = period == MeetingPeriod.upcoming
                ? first.$2.scheduledAt - second.$2.scheduledAt
                : second.$2.scheduledAt - first.$2.scheduledAt;
            return byTime != 0 ? byTime : first.$1 - second.$1;
          });
    return [for (final (_, summary) in indexed) summary];
  }
}
