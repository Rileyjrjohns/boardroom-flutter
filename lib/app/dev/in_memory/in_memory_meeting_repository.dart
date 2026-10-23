import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';

/// The meetings of the simulated server. A thin window on the backend it shares
/// with the others.
final class InMemoryMeetingRepository implements MeetingRepository {
  /// Creates the repository over `backend`.
  const new(this._backend);

  final InMemoryBackend _backend;

  @override
  Future<Result<Page<MeetingSummary>, GatewayError>> list(
    MeetingPeriod period,
    PageRequest request,
  ) => _backend.listMeetings(period, request);

  @override
  Future<Result<Meeting, RepositoryError>> get(MeetingId id) =>
      _backend.getMeeting(id);
}
