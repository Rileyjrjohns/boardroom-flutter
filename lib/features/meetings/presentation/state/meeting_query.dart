import 'dart:async';

import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/query/query_lifetime.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/presentation/providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'meeting_query.g.dart';

/// One meeting with its agenda, documents and participants, and where it comes
/// from (the server, or the copy saved on the device). Calls the `GetMeeting`
/// use case and throws a `QueryFailure` for a failure, the way the query layer
/// says. It runs only while the app is open.
@riverpod
Future<Loaded<Meeting>> meetingQuery(Ref ref, MeetingId id) async {
  ref.keepQueryFor();
  // The access this answer is for; the query itself is dropped when it moves
  // (see `keepQueryFor`), so a second user never sees the first one's meeting.
  final epoch = ref.read(sessionEpochProvider);
  if (!ref.read(sessionOpenProvider)) {
    // Nothing is asked of the server for a user who is not in the open app.
    return await Completer<Loaded<Meeting>>().future;
  }
  final result = await ref
      .read(getMeetingUseCaseProvider)
      .execute(meetingId: id);
  final loaded = unwrapResult(result, startedUnder: epoch);
  return loaded;
}
