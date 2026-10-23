import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/http/gateway_errors.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/invalid_response.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/core/infrastructure/http/well_formed.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/infrastructure/dto/meeting_dto.dart';

/// The meetings of the API (`GET /meetings`, `GET /meetings/{id}`). The request
/// is given to the client as a function, so that the route, which is made of an
/// identifier, is built where the client can catch a failure: an adapter never
/// throws.
final class HttpMeetingRepository implements MeetingRepository {
  /// Creates the repository over `client`.
  const new(this._client, this._monitoring);

  final HttpClient _client;
  final Monitoring _monitoring;

  @override
  Future<Result<Page<MeetingSummary>, GatewayError>> list(
    MeetingPeriod period,
    PageRequest request,
  ) async {
    final answer = await _client.request(
      () => HttpRequestSpec<MeetingPageWire>(
        method: HttpMethod.get,
        path: Routes.meetings,
        query: {
          QueryParameter.period.value: period.value,
          QueryParameter.limit.value: request.limit,
          QueryParameter.cursor.value: request.cursor,
        },
        resource: HttpResource.meetingPage,
        decode: (json) => decodeWire(json, MeetingPageWire.fromJson),
      ),
    );
    final MeetingPageWire wire;
    switch (answer) {
      case Err(:final error):
        return err(asGatewayError(error));
      case Ok(:final value):
        wire = value;
    }

    switch (toMeetingPage(wire)) {
      case Ok(:final value):
        return ok(value);
      case Err(:final error):
        return err(
          domainViolation(_monitoring, HttpResource.meetingPage, error),
        );
    }
  }

  @override
  Future<Result<Meeting, RepositoryError>> get(MeetingId id) async {
    final answer = await _client.request(
      () => HttpRequestSpec<MeetingWire>(
        method: HttpMethod.get,
        path: Routes.meeting(requireWellFormed(id)),
        resource: HttpResource.meeting,
        decode: (json) => decodeWire(json, MeetingWire.fromJson),
      ),
    );
    final MeetingWire wire;
    switch (answer) {
      case Err(:final error):
        return err(asRepositoryError(error));
      case Ok(:final value):
        wire = value;
    }

    switch (toMeeting(wire)) {
      case Ok(:final value):
        return ok(value);
      case Err(:final error):
        return err(domainViolation(_monitoring, HttpResource.meeting, error));
    }
  }
}
