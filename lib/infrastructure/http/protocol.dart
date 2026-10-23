import 'package:boardroom/domain/shared/constants.dart';

// The constants of the API, shared by the client and by the simulated server,
// so that the two cannot disagree about a route, a header or a status.
// docs/api.md describes them for people.

/// The methods the API uses.
enum HttpMethod implements StableValue {
  /// Reads.
  get('GET'),

  /// Reads the headers only.
  head('HEAD'),

  /// Sends.
  post('POST');

  new(this.value);

  @override
  final String value;
}

/// The headers the client and the server read and write.
enum HttpHeader implements StableValue {
  /// The token of the caller.
  authorization('Authorization'),

  /// The kind of content the caller accepts.
  accept('Accept'),

  /// The kind of content of the body.
  contentType('Content-Type'),

  /// What may be stored of the message.
  cacheControl('Cache-Control'),

  /// The size of the body, in bytes.
  contentLength('Content-Length'),

  /// The version of what was sent: it changes when the content does.
  eTag('ETag'),

  /// The key of a vote (`idempotencyKeyOf`), percent-encoded: a retry carries
  /// the same value.
  idempotencyKey('Idempotency-Key');

  new(this.value);

  @override
  final String value;
}

/// The media type of the JSON bodies.
const String mediaTypeJson = 'application/json';

/// The media type of the content of a document.
const String mediaTypePdf = 'application/pdf';

/// What every request and every answer says about caching: nothing of the API
/// is stored by an intermediary or by the HTTP cache of the platform. The
/// answers are confidential.
const String cacheControlNoStore = 'no-store';

/// How big an answer may be, in bytes. A page of fifty meetings is a few tens
/// of kilobytes and a meeting with its agenda and its participants some
/// hundreds: two megabytes is far above any answer the API gives, and far below
/// what a hostile or broken server could make the app hold.
const int maxResponseBytes = 2 * 1024 * 1024;

/// How big the content of a document may be, in bytes. A board pack of a few
/// hundred pages is some megabytes; twenty is far above any document the API
/// serves, and far below what a hostile or broken server could make the app
/// write to the device.
const int maxDocumentBytes = 20 * 1024 * 1024;

/// The only kind of token the API issues, and the scheme of the `Authorization`
/// header.
const String bearerTokenType = 'Bearer';

/// The scheme of the `Authorization` header, with the space that separates it
/// from the token.
const String bearerPrefix = '$bearerTokenType ';

/// The statuses of the API.
enum HttpStatusCode {
  /// The request succeeded.
  ok(200),

  /// The request succeeded and the answer has no body.
  noContent(204),

  /// The request could not be understood.
  badRequest(400),

  /// The caller is not authenticated.
  unauthorized(401),

  /// The caller may not do this.
  forbidden(403),

  /// There is no such thing.
  notFound(404),

  /// The server gave up waiting for the request.
  requestTimeout(408),

  /// The body of the request is bigger than the server accepts.
  requestEntityTooLarge(413),

  /// The request was understood and refused by a business rule: the body says
  /// which.
  unprocessableContent(422),

  /// Too many requests: the server asks the client to come back later.
  tooManyRequests(429),

  /// The server failed.
  internalServerError(500),

  /// The gateway got a bad answer.
  badGateway(502),

  /// The service cannot take the request now.
  serviceUnavailable(503),

  /// The gateway gave up waiting for the service.
  gatewayTimeout(504);

  new(this.code);

  /// The number of the status.
  final int code;
}

/// The statuses that say nothing about the request but that the service cannot
/// take it right now: the server gave up waiting for it (408), asks to be given
/// time (429), or the service behind the gateway cannot be reached (502, 503,
/// 504). The client treats them like a network that failed, so that the saved
/// copy is served and a queue of votes is not given up during an outage.
final List<int> transientStatuses = [
  HttpStatusCode.requestTimeout.code,
  HttpStatusCode.tooManyRequests.code,
  HttpStatusCode.badGateway.code,
  HttpStatusCode.serviceUnavailable.code,
  HttpStatusCode.gatewayTimeout.code,
];

/// The names of the query parameters.
enum QueryParameter implements StableValue {
  /// Upcoming or past meetings.
  period('period'),

  /// The size of a page.
  limit('limit'),

  /// Where the next page starts.
  cursor('cursor');

  new(this.value);

  @override
  final String value;
}

/// The first segment of each route.
enum RouteRoot implements StableValue {
  /// Authentication.
  auth('auth'),

  /// Meetings.
  meetings('meetings'),

  /// Documents.
  documents('documents'),

  /// Votes.
  votes('votes');

  new(this.value);

  @override
  final String value;
}

/// The last segment of the routes that have one.
enum RouteAction implements StableValue {
  /// Signing in.
  signIn('sign-in'),

  /// The content of a document.
  content('content');

  new(this.value);

  @override
  final String value;
}

const String _separator = '/';

/// A path from its segments. A segment that is an identifier is
/// percent-encoded by the caller.
String _path(List<String> segments) => ['', ...segments].join(_separator);

/// The routes of the API. An identifier is opaque and free text, so it is
/// percent-encoded.
abstract final class Routes {
  /// `POST /auth/sign-in`.
  static final String signIn = _path([
    RouteRoot.auth.value,
    RouteAction.signIn.value,
  ]);

  /// `GET /meetings`.
  static final String meetings = _path([RouteRoot.meetings.value]);

  /// `GET /meetings/{id}`.
  static String meeting(String id) =>
      _path([RouteRoot.meetings.value, Uri.encodeComponent(id)]);

  /// `GET /documents/{id}`.
  static String document(String id) =>
      _path([RouteRoot.documents.value, Uri.encodeComponent(id)]);

  /// `GET /documents/{id}/content`.
  static String documentContent(String id) => _path([
    RouteRoot.documents.value,
    Uri.encodeComponent(id),
    RouteAction.content.value,
  ]);

  /// `POST /votes`.
  static final String votes = _path([RouteRoot.votes.value]);
}

/// How many segments each route has, for the server to tell them apart.
abstract final class SegmentCount {
  /// `/meetings`.
  static const int collection = 1;

  /// `/meetings/{id}`.
  static const int item = 2;

  /// `/documents/{id}/content`.
  static const int action = 3;
}
