import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/constants.dart';

/// What the server answered, for the logs: the resource, never a value of it.
enum HttpResource implements StableValue {
  /// The session a sign-in gives.
  session('session'),

  /// A page of meetings.
  meetingPage('meetingPage'),

  /// A meeting.
  meeting('meeting'),

  /// The metadata of a document.
  document('document'),

  /// The content of a document.
  documentContent('documentContent'),

  /// A vote.
  vote('vote');

  new(this.value);

  @override
  final String value;
}

/// The `cause` of the error an answer that does not have the shape of the API
/// becomes.
const String invalidResponseCause = 'invalid response';

/// An answer that breaks the schema of the API becomes `unexpected`, and the
/// places where it broke go to the monitoring: the paths of the fields, never
/// what they held.
UnexpectedError schemaViolation(
  Monitoring monitoring,
  HttpResource resource,
  String issuePaths,
) {
  final error = unexpected(invalidResponseCause);
  monitoring.captureError(MonitoringEvent.responseInvalid, error, {
    LogAttribute.resource: resource.value,
    LogAttribute.issuePaths: issuePaths,
  });
  return error;
}

/// An answer that has the shape of the API but breaks a rule of the domain (a
/// blank title, a status nobody knows) becomes `unexpected` too. The error of
/// the domain names a field and a rule, not the value, so it can go to the
/// monitoring as it is.
UnexpectedError domainViolation(
  Monitoring monitoring,
  HttpResource resource,
  ValidationError violation,
) {
  monitoring.captureError(MonitoringEvent.responseInvalid, violation, {
    LogAttribute.resource: resource.value,
  });
  return unexpected(invalidResponseCause);
}

/// Why the file an answer carried was refused, for the logs.
enum ContentViolation implements StableValue {
  /// It does not start with the signature of the kind of file it was said to
  /// be.
  wrongSignature('wrongSignature'),

  /// The answer gave no version, or one that is not a usable `ETag`.
  noVersion('noVersion');

  new(this.value);

  @override
  final String value;
}

/// Why an answer that is well formed was refused, for the logs.
enum IdentityViolation implements StableValue {
  /// It describes another item than the one that was asked for.
  otherItem('otherItem');

  new(this.value);

  @override
  final String value;
}

UnexpectedError _refusedFor(
  Monitoring monitoring,
  HttpResource resource,
  String reason,
) {
  final error = unexpected(invalidResponseCause);
  monitoring.captureError(MonitoringEvent.responseInvalid, error, {
    LogAttribute.resource: resource.value,
    LogAttribute.reason: reason,
  });
  return error;
}

/// A file that does not have the shape of the API (it is not the kind of file
/// the server said, or it comes without a version) becomes `unexpected`, and
/// the monitoring is told which of the two it was, and nothing of the file.
UnexpectedError contentViolation(
  Monitoring monitoring,
  HttpResource resource,
  ContentViolation violation,
) => _refusedFor(monitoring, resource, violation.value);

/// An answer that has the shape of the API but is about another item than the
/// one that was asked for (a server, a proxy or a cache that mixes up two
/// requests) becomes `unexpected`. It is not trusted: the metadata of one
/// document must never be shown for another, nor saved under its identifier.
/// The monitoring is told which rule was broken, and neither identifier.
UnexpectedError identityViolation(
  Monitoring monitoring,
  HttpResource resource,
  IdentityViolation violation,
) => _refusedFor(monitoring, resource, violation.value);
