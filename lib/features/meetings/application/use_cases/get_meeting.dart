import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/application/session/require_session.dart';
import 'package:boardroom/features/meetings/application/load_meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';

/// What [GetMeeting] needs: what [loadMeeting] needs.
typedef GetMeetingDeps = LoadMeetingDeps;

/// What a meeting request fails with: a [SessionRequiredError], a
/// [SessionChangedError] or a [RepositoryError].
typedef GetMeetingError = AppError;

/// A meeting with its agenda, documents and participants. Requires a valid
/// session, like `ListMeetings`, and follows the same offline policy: fresh
/// from the server, or the cached copy of the signed-in user flagged stale when
/// there is no network. A refusal of the session (`unauthorized`) empties both
/// caches; a refusal of the meeting (`forbidden`, `notFound`) removes the
/// cached copy and the documents it lists. If the user changed while the
/// request was in flight, nothing is written and the answer is
/// `sessionChanged`.
final class GetMeeting {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final GetMeetingDeps _deps;

  /// Gets the meeting [meetingId].
  Future<Result<Loaded<Meeting>, GetMeetingError>> execute({
    required MeetingId meetingId,
  }) async {
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok(:final value):
        return await loadMeeting(_deps, value.user.id, meetingId);
    }
  }
}
