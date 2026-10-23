import 'dart:async';
import 'dart:typed_data';

import 'package:boardroom/infrastructure/fixture_server/api_message.dart';
import 'package:boardroom/infrastructure/fixture_server/mock_api.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:dio/dio.dart';

/// The most a request may carry, in bytes. The biggest body of the API is a
/// vote. A body above it is refused with 413 before the API reads it
/// (docs/api.md).
const int maxRequestBodyBytes = 64 * 1024;

/// Tells that a request was answered, for a console: the method, the path
/// (without the query, which may hold a cursor) and the status. Never the
/// headers nor the body, which hold the token and the passwords.
typedef RequestLogger = void Function(String line);

/// A dio `HttpClientAdapter` that does not touch the network: it hands each
/// request to the simulated API (`MockApi`) and returns its answer. The real
/// HTTP adapters of the app run unchanged against it, in the development build
/// and in the tests, the way they would run against a server that implements
/// docs/api.md over the fixtures.
///
/// It behaves like an adapter for a network: the cancellation of the request
/// ends it with a cancelled exception, and the `receiveTimeout` of the request
/// (or its `connectTimeout`, when there is no other) bounds the whole exchange
/// and ends it with a timeout exception. A server that never answers is
/// therefore a request that times out, not a stuck one.
final class FixtureServerAdapter implements HttpClientAdapter {
  /// Creates an adapter in front of the API. The `logger` is told of each
  /// request once it is answered.
  new(this._api, {this._logger});

  final MockApi _api;
  final RequestLogger? _logger;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final exchange = _exchange(options, requestStream);
    final bounded = boundedByRequest(exchange, options, cancelFuture);
    final response = await bounded;
    _log(options, response.status);
    return ResponseBody(
      Stream.value(response.body),
      response.status,
      headers: {
        for (final entry in response.headers.entries) entry.key: [entry.value],
        if (response.body.isNotEmpty ||
            response.status != HttpStatusCode.noContent.code)
          HttpHeader.contentLength.value: ['${response.body.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  Future<ApiResponse> _exchange(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    final body = await _readBody(requestStream);
    if (body != null && body.length > maxRequestBodyBytes) {
      return _tooLarge();
    }
    final request = ApiRequest(
      method: options.method,
      target: _targetOf(options.uri),
      headers: {
        for (final entry in options.headers.entries)
          entry.key: _headerValue(entry.value),
      },
      body: body,
    );
    try {
      return await _api.handle(request);
    } on Object {
      // The API answers every request; if it fails, the server failed.
      return _failed();
    }
  }

  void _log(RequestOptions options, int status) {
    final logger = _logger;
    if (logger == null) {
      return;
    }
    try {
      logger('${options.method} ${options.uri.path} $status');
    } on Object {
      // A logger that fails must not take the server down.
    }
  }
}

/// Ends [work] the way an adapter for a network ends a request: with a
/// cancelled exception when [cancelFuture] completes first, and with a timeout
/// exception when the `receiveTimeout` of the request (or its `connectTimeout`,
/// when there is no other) elapses first. Without either, [work] decides.
Future<T> boundedByRequest<T>(
  Future<T> work,
  RequestOptions options,
  Future<void>? cancelFuture,
) {
  final racing = <Future<T>>[
    work,
    if (cancelFuture != null)
      cancelFuture.then<T>(
        (_) => throw DioException.requestCancelled(
          requestOptions: options,
          reason: null,
        ),
      ),
  ];
  final limit = options.receiveTimeout ?? options.connectTimeout;
  final answer = Future.any(racing);
  if (limit == null || limit <= Duration.zero) {
    return answer;
  }
  return answer.timeout(
    limit,
    onTimeout: () => throw DioException.receiveTimeout(
      timeout: limit,
      requestOptions: options,
    ),
  );
}

/// What follows the host on the request line: the path and the query, as
/// encoded in the URI.
String _targetOf(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

String _headerValue(Object? value) =>
    value is Iterable ? value.join(', ') : '$value';

/// The body of the request, or `null` when it has none. It stops reading once
/// the body is known to be too big.
Future<Uint8List?> _readBody(Stream<Uint8List>? stream) async {
  if (stream == null) {
    return null;
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    if (builder.length > maxRequestBodyBytes) {
      break;
    }
  }
  return builder.takeBytes();
}

ApiResponse _errorResponse(HttpStatusCode status, ApiErrorCode code) =>
    ApiResponse.text(
      status: status.code,
      text: '{"error":{"code":"${code.value}"}}',
      headers: {
        HttpHeader.contentType.value: mediaTypeJson,
        HttpHeader.cacheControl.value: cacheControlNoStore,
      },
    );

ApiResponse _tooLarge() => _errorResponse(
  HttpStatusCode.requestEntityTooLarge,
  ApiErrorCode.badRequest,
);

ApiResponse _failed() =>
    _errorResponse(HttpStatusCode.internalServerError, ApiErrorCode.unexpected);
