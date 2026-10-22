import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';

/// The remote source of truth for meetings. Read only.
///
/// Contract: no method throws, and every method settles in bounded time. Every
/// failure is an error `Result`:
///
/// - `networkUnavailable` when the server cannot be reached (a request that
///   times out included);
/// - `unauthorized` when the SESSION is no longer valid (expired, revoked,
///   signed out elsewhere): it concerns everything the caller holds, and the
///   application empties both caches;
/// - `forbidden` when the session is valid but this user may not see THIS item
///   (removed from the meeting): it concerns one item, and the application
///   drops it, and what hangs off it, from the caches. A server that prefers
///   not to reveal that an item exists answers `notFound` instead, which the
///   application treats the same way;
/// - `notFound` when an item does not exist;
/// - `unexpected` for anything else. Its free-text `cause` is a status code or
///   a kind of failure: never a path, a URL, the location of a document or its
///   title, a name, an email, an id taken from a query, nor a vote choice.
///
/// A request carries the identity that was read when it was created (the token
/// of the user who was signed in then): a request in flight is answered for
/// that user, never for one who signed in while it was on its way. The
/// application checks again, when the answer arrives, that the same user is
/// still signed in.
abstract interface class MeetingRepository {
  /// One page of the meetings of a period: upcoming ones soonest first, past
  /// ones latest first.
  Future<Result<Page<MeetingSummary>, GatewayError>> list(
    MeetingPeriod period,
    PageRequest request,
  );

  /// A meeting with its agenda, documents and participants.
  Future<Result<Meeting, RepositoryError>> get(MeetingId id);
}
