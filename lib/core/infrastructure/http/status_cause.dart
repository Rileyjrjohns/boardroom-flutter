const String _statusCausePrefix = 'status';

/// The `cause` of an `unexpected` error that comes from a status: the status,
/// which is a kind of failure and no more. Never a URL, a path or a part of the
/// body.
String statusCause(int status) => '$_statusCausePrefix $status';
