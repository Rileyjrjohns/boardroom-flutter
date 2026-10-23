import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/core/infrastructure/http/status_cause.dart';

/// What a call that addresses no particular item (a listing, a vote) can fail
/// with. A 403, a 404 or a rejection is not a thing such a call has a name for:
/// it is `unexpected`, with the status as the only cause.
GatewayError asGatewayError(HttpFailure failure) => switch (failure) {
  RequestFailed(:final error) => switch (error) {
    GatewayError() => error,
    ForbiddenError() => unexpected(statusCause(HttpStatusCode.forbidden.code)),
    NotFoundError() => unexpected(statusCause(HttpStatusCode.notFound.code)),
  },
  RequestRejected() => unexpected(
    statusCause(HttpStatusCode.unprocessableContent.code),
  ),
};

/// What a call that addresses one item can fail with. A rejection is not one of
/// them.
RepositoryError asRepositoryError(HttpFailure failure) => switch (failure) {
  RequestFailed(:final error) => error,
  RequestRejected() => asGatewayError(failure),
};
