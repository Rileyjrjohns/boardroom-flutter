import 'dart:async';
import 'dart:convert';
import 'dart:io' hide HttpClient;
import 'dart:typed_data';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/http/http_client.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/shared/issue_paths.dart';
import 'package:test/test.dart';

import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';

// The client over the adapter dio uses on a device, against a server on this
// machine. The scripted adapter of http_client_test.dart says what the client
// does with what it is given; this says that the platform gives it what the
// client relies on: a redirect that is not followed, a body that is cut off
// when it grows too big (compressed or not), a connection that is dropped when
// nobody waits for it, and the time limit. React Native has no counterpart:
// its tests of the real `fetch` go through MSW.

const String _token = 'a-very-secret-token';
const String _itemBody = '{"id":"a"}';

Result<String, WireFailure> _decodeId(Object? body) =>
    body is Map<String, dynamic> && body['id'] is String
    ? ok(body['id'] as String)
    : err(const WireFailure(rootPath));

HttpRequestSpec<String> _get([String path = '/items']) =>
    HttpRequestSpec<String>(
      method: HttpMethod.get,
      path: path,
      resource: HttpResource.meeting,
      decode: _decodeId,
    );

final class _Tokens implements BearerTokenSource {
  const new();

  @override
  Future<Result<BearerToken?, StorageReadFailedError>> token() =>
      Future.value(ok(BearerToken(token: _token, userId: aUserId())));
}

/// A server that answers with the headers, then sends a chunk over and over in
/// a body that never ends, and says whether the client went away (the client
/// closes its end of the connection) within a few seconds. An `HttpServer`
/// cannot tell: it keeps writing to a connection the client has closed.
final class _RawServer {
  new _(this._server, this.clientLeft);

  static Future<_RawServer> start({
    required int status,
    required Map<String, String> headers,
    required Uint8List chunk,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final left = Completer<bool>();
    server.listen((socket) {
      var answered = false;
      socket.listen(
        (_) {
          if (answered) {
            return;
          }
          answered = true;
          socket.add(
            utf8.encode(
              'HTTP/1.1 $status Answer\r\n'
              '${headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()}'
              'transfer-encoding: chunked\r\n\r\n',
            ),
          );
          unawaited(_sendForever(socket, chunk));
        },
        onDone: () {
          if (!left.isCompleted) {
            left.complete(true);
          }
        },
        onError: (Object _) {
          if (!left.isCompleted) {
            left.complete(true);
          }
        },
        cancelOnError: true,
      );
    });
    final result = left.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    return _RawServer._(server, result);
  }

  final ServerSocket _server;

  /// Whether the client closed the connection.
  final Future<bool> clientLeft;

  String get address => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() async {
    await _server.close();
  }
}

Future<void> _sendForever(Socket socket, Uint8List chunk) async {
  final head = utf8.encode('${chunk.length.toRadixString(16)}\r\n');
  final tail = utf8.encode('\r\n');
  try {
    for (var sent = 0; sent < 1000; sent++) {
      socket
        ..add(head)
        ..add(chunk)
        ..add(tail);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  } on Object {
    // The client went away.
  }
}

void main() {
  late HttpServer server;
  late FakeMonitoring monitoring;
  var asked = <String>[];
  var seen = <HttpHeaders>[];

  /// What the server does with a request, set by each test.
  late FutureOr<void> Function(HttpRequest request) handler;

  HttpClient aClient({int timeout = 2000, String? baseUrl}) => HttpClient(
    HttpClientOptions(
      baseUrl: baseUrl ?? 'http://${server.address.host}:${server.port}',
      timeout: aDuration(timeout),
      tokens: const _Tokens(),
      monitoring: monitoring,
    ),
  );

  setUp(() async {
    asked = [];
    seen = [];
    monitoring = FakeMonitoring();
    final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    bound.listen((request) async {
      asked.add(request.uri.path);
      seen.add(request.headers);
      await handler(request);
    });
    server = bound;
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<void> sendJson(HttpRequest request, String body) async {
    request.response
      ..headers.contentType = ContentType.json
      ..write(body);
    await request.response.close();
  }

  group('HttpClient, over the network of the machine', () {
    test('carries the token, asks for JSON and for nothing to be stored, and '
        'reads the answer', () async {
      handler = (request) => sendJson(request, _itemBody);

      final answer = await aClient().request(_get);

      expect(answer, equals(ok('a')));
      final headers = seen.single;
      expect(
        headers.value(HttpHeader.authorization.value),
        equals('Bearer $_token'),
      );
      expect(headers.value(HttpHeader.accept.value), equals(mediaTypeJson));
      expect(
        headers.value(HttpHeader.cacheControl.value),
        equals(cacheControlNoStore),
      );
    });

    test('does not follow a redirect: it is unexpected, and the address it '
        'points to is never asked', () async {
      handler = (request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/elsewhere');
        await request.response.close();
      };

      final answer = await aClient().request(_get);

      expect(answer, equals(err(RequestFailed(unexpected('status 302')))));
      expect(asked, equals(['/items']));
    });

    test('sends a body as JSON, with the key of a vote in a header', () async {
      final body = Completer<String>();
      handler = (request) async {
        body.complete(await utf8.decoder.bind(request).join());
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      };

      final answer = await aClient().perform(
        () => HttpActionSpec(
          method: HttpMethod.post,
          path: Routes.votes,
          body: const {'choice': 'for'},
          headers: {HttpHeader.idempotencyKey.value: '12.r.u'},
          resource: HttpResource.vote,
        ),
      );

      expect(answer, equals(ok<void>(null)));
      expect(await body.future, equals('{"choice":"for"}'));
      final headers = seen.single;
      expect(headers.contentType?.mimeType, equals(mediaTypeJson));
      expect(headers.value(HttpHeader.idempotencyKey.value), equals('12.r.u'));
    });

    test('drops the connection of a success whose body nobody wants', () async {
      final raw = await _RawServer.start(
        status: HttpStatus.created,
        headers: const {'content-type': 'text/plain'},
        chunk: Uint8List.fromList(utf8.encode('created')),
      );
      addTearDown(raw.close);

      final answer = await aClient(baseUrl: raw.address).perform(
        () => const HttpActionSpec(
          method: HttpMethod.post,
          path: '/votes',
          resource: HttpResource.vote,
        ),
      );

      expect(answer, equals(ok<void>(null)));
      expect(await raw.clientLeft, isTrue);
    });

    test('drops the connection of a refusal whose file nobody reads', () async {
      final raw = await _RawServer.start(
        status: HttpStatus.forbidden,
        headers: const {'content-type': 'application/pdf'},
        chunk: Uint8List(1024),
      );
      addTearDown(raw.close);

      final answer = await aClient(baseUrl: raw.address).download(
        () => const HttpDownloadSpec(
          method: HttpMethod.get,
          path: '/files/a',
          resource: HttpResource.documentContent,
          mediaType: mediaTypePdf,
          maxBytes: 1000,
        ),
      );

      expect(answer, equals(err(RequestFailed(forbidden()))));
      expect(await raw.clientLeft, isTrue);
    });

    test('refuses a body that grows past the maximum though it declares no '
        'length, and drops the connection', () async {
      final raw = await _RawServer.start(
        status: HttpStatus.ok,
        headers: const {'content-type': 'application/json'},
        chunk: Uint8List(maxResponseBytes ~/ 2 + 1),
      );
      addTearDown(raw.close);

      final answer = await aClient(baseUrl: raw.address).request(_get);

      expect(
        answer,
        equals(err(RequestFailed(unexpected('response too large')))),
      );
      expect(await raw.clientLeft, isTrue);
    });

    test('refuses an answer that declares more than the maximum, without '
        'waiting for it', () async {
      final release = Completer<void>();
      handler = (request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..contentLength = maxResponseBytes + 1
          ..add(utf8.encode(_itemBody));
        await request.response.flush();
        await release.future;
      };
      addTearDown(release.complete);

      final answer = await aClient().request(_get);

      expect(
        answer,
        equals(err(RequestFailed(unexpected('response too large')))),
      );
    });

    test('refuses an answer that is small compressed and grows past the '
        'maximum once it is uncompressed', () async {
      handler = (request) async {
        final compressed = gzip.encode(Uint8List(maxResponseBytes + 1));
        request.response
          ..headers.contentType = ContentType.json
          ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
          ..headers.set(HttpHeaders.contentLengthHeader, compressed.length)
          ..add(compressed);
        await request.response.close();
      };

      final answer = await aClient().request(_get);

      expect(
        answer,
        equals(err(RequestFailed(unexpected('response too large')))),
      );
    });

    test('is networkUnavailable, within the timeout, when the server never '
        'answers', () async {
      final release = Completer<void>();
      handler = (request) => release.future;
      addTearDown(release.complete);

      final started = DateTime.now();
      final answer = await aClient(timeout: 150).request(_get);

      expect(answer, equals(err(RequestFailed(networkUnavailable()))));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
      );
    });

    test('is networkUnavailable, within the timeout, when the body never '
        'ends', () async {
      final release = Completer<void>();
      handler = (request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"id":');
        await request.response.flush();
        await release.future;
      };
      addTearDown(release.complete);

      final started = DateTime.now();
      final answer = await aClient(timeout: 150).request(_get);

      expect(answer, equals(err(RequestFailed(networkUnavailable()))));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
      );
    });

    test('is networkUnavailable when nothing listens at the address', () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final address = 'http://${closed.address.host}:${closed.port}';
      await closed.close(force: true);

      final answer = await aClient(baseUrl: address).request(_get);

      expect(answer, equals(err(RequestFailed(networkUnavailable()))));
    });

    test('downloads a file with the version the server gave it', () async {
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 content'));
      handler = (request) async {
        request.response
          ..headers.contentType = ContentType('application', 'pdf')
          ..headers.set(HttpHeaders.etagHeader, '"v7"')
          ..add(pdf);
        await request.response.close();
      };

      final answer = await aClient().download(
        () => const HttpDownloadSpec(
          method: HttpMethod.get,
          path: '/files/a',
          resource: HttpResource.documentContent,
          mediaType: mediaTypePdf,
          maxBytes: 1000,
        ),
      );

      expect(answer, isA<Ok<Downloaded, HttpFailure>>());
      final downloaded = (answer as Ok<Downloaded, HttpFailure>).value;
      expect(downloaded.bytes, equals(pdf));
      expect(downloaded.etag, equals('"v7"'));
      expect(seen.single.value(HttpHeader.accept.value), equals(mediaTypePdf));
    });

    test('reports nothing about the address in what it logs', () async {
      handler = (request) => sendJson(request, '{"id":1}');

      final answer = await aClient().request(_get);

      expect(
        answer,
        equals(err(RequestFailed(unexpected('invalid response')))),
      );
      expect('${monitoring.errors}', isNot(contains('127.0.0.1')));
      expect(
        monitoring.errors.single.attributes?[LogAttribute.issuePaths],
        equals(rootPath),
      );
    });
  });
}
