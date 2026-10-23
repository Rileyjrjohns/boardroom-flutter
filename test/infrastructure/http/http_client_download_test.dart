import 'dart:typed_data';

import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/duration.dart';
import 'package:boardroom/infrastructure/http/http_client.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../application/support/fake_monitoring.dart';
import '../../domain/support/builders.dart';
import '../../domain/support/names.dart';
import '../support/scripted_adapter.dart';

// The download of a file by the client, against an adapter that answers what
// the test scripts. The download over the fixture server is exercised by
// http_document_repository_test.dart.

const String _baseUrl = 'https://api.boardroom.example/v1';
const String _token = 'a-very-secret-token';
const String _pdfType = 'application/pdf';
const int _maxBytes = 1000;

Uint8List _bytesOf(int size, [int fill = 7]) =>
    Uint8List(size)..fillRange(0, size, fill);

HttpDownloadSpec _spec({
  Map<String, String> headers = const {},
  DurationMillis? timeout,
}) => HttpDownloadSpec(
  method: HttpMethod.get,
  path: '/files/a',
  resource: HttpResource.documentContent,
  mediaType: _pdfType,
  maxBytes: _maxBytes,
  headers: headers,
  timeout: timeout,
);

enum _Token { signedIn, none, unreadable }

typedef _World = ({HttpClient client, FakeMonitoring monitoring});

_World _aClient(
  HttpClientAdapter adapter, {
  _Token token = _Token.signedIn,
  int timeout = 1000,
}) {
  final monitoring = FakeMonitoring();
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: _baseUrl,
      timeout: aDuration(timeout),
      tokens: _TokenSource(token),
      monitoring: monitoring,
      adapter: adapter,
    ),
  );
  return (client: client, monitoring: monitoring);
}

final class _TokenSource implements BearerTokenSource {
  const new(this._kind);

  final _Token _kind;

  @override
  Future<Result<BearerToken?, StorageReadFailedError>> token() =>
      Future.value(switch (_kind) {
        _Token.unreadable => err(storageReadFailed()),
        _Token.none => ok<BearerToken?>(null),
        _Token.signedIn => ok(BearerToken(token: _token, userId: aUserId())),
      });
}

final Map<String, String> _pdfHeaders = {
  HttpHeader.contentType.value: _pdfType,
  HttpHeader.eTag.value: '"v7"',
};

ScriptedAnswer _pdfAnswer({bool paced = false}) => ScriptedAnswer(
  headers: _pdfHeaders,
  chunks: [_bytesOf(300), _bytesOf(200)],
  paced: paced,
);

RequestFailed _failed(RepositoryError error) => RequestFailed(error);

void main() {
  group('HttpClient, downloading a file', () {
    group('the request', () {
      test('is a GET that accepts the media type it asks for, is not to be '
          'stored, and carries the token', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter);

        await world.client.download(_spec);

        expect(adapter.sent, hasLength(1));
        final sent = adapter.sent.single;
        expect(sent.url, equals('$_baseUrl/files/a'));
        expect(sent.method, equals('GET'));
        expect(sent.options.followRedirects, isFalse);
        expect(sent.options.maxRedirects, equals(0));
        expect(sent.header(HttpHeader.accept.value), equals(_pdfType));
        expect(
          sent.header(HttpHeader.cacheControl.value),
          equals(cacheControlNoStore),
        );
        expect(
          sent.header(HttpHeader.authorization.value),
          equals('Bearer $_token'),
        );
        expect(sent.header(HttpHeader.contentType.value), isNull);
      });

      test('lets the caller say more headers, which win over the ones it '
          'sets', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter);

        await world.client.download(
          () =>
              _spec(headers: {HttpHeader.accept.value: 'application/x-other'}),
        );

        expect(
          adapter.sent.single.header(HttpHeader.accept.value),
          equals('application/x-other'),
        );
      });

      test('is not sent, and is unauthorized, when nobody is signed '
          'in', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter, token: _Token.none);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(unauthorized()))),
        );
        expect(adapter.sent, isEmpty);
      });

      test('is not sent, and is unexpected, when the token cannot be '
          'read', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter, token: _Token.unreadable);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(unexpected('credentials unreadable')))),
        );
        expect(adapter.sent, isEmpty);
      });

      test('is not sent, and is unexpected, when the path cannot be '
          'built', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter);

        final failed = await world.client.download(
          () => throw Exception('a secret path'),
        );

        expect(
          failed,
          equals(err(_failed(unexpected('request could not be built')))),
        );
        expect(adapter.sent, isEmpty);
      });
    });

    group('the answer', () {
      test('gives the bytes, the version it was given, and the user whose '
          'token the request carried', () async {
        final adapter = ScriptedAdapter([_pdfAnswer()]);
        final world = _aClient(adapter);

        final downloaded = (await world.client.download(_spec)) as Ok;

        final value = downloaded.value as Downloaded;
        expect(value.bytes, equals([..._bytesOf(300), ..._bytesOf(200)]));
        expect(value.etag, equals('"v7"'));
        expect(value.userId, equals(aUserId()));
      });

      test('gives no version when the server gave none', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            headers: {HttpHeader.contentType.value: _pdfType},
            chunks: [_bytesOf(10)],
          ),
        ]);
        final world = _aClient(adapter);

        final downloaded = (await world.client.download(_spec)) as Ok;

        expect((downloaded.value as Downloaded).etag, isNull);
      });

      test('accepts an empty file: judging what is in it is for the '
          'caller', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(headers: _pdfHeaders, chunks: const []),
        ]);
        final world = _aClient(adapter);

        final downloaded = (await world.client.download(_spec)) as Ok;

        expect((downloaded.value as Downloaded).bytes, isEmpty);
      });

      for (final (name, contentType) in [
        ('with parameters', 'application/pdf; charset=binary'),
        ('in upper case', 'APPLICATION/PDF'),
        ('with spaces', '  application/pdf  ;q=1'),
      ]) {
        test('accepts the media type $name', () async {
          final adapter = ScriptedAdapter([
            ScriptedAnswer(
              headers: {HttpHeader.contentType.value: contentType},
              chunks: [_bytesOf(10)],
            ),
          ]);
          final world = _aClient(adapter);

          expect(
            await world.client.download(_spec),
            isA<Ok<Downloaded, HttpFailure>>(),
          );
        });
      }
    });

    group('the media type', () {
      for (final contentType in [
        'text/html',
        'application/json',
        'application/octet-stream',
        '',
      ]) {
        test('refuses ${formatJson(contentType)} before a byte is '
            'read', () async {
          final adapter = ScriptedAdapter([
            ScriptedAnswer(
              headers: contentType.isEmpty
                  ? const {}
                  : {HttpHeader.contentType.value: contentType},
              chunks: [_bytesOf(10)],
              paced: true,
            ),
          ]);
          final world = _aClient(adapter);

          expect(
            await world.client.download(_spec),
            equals(err(_failed(unexpected('unexpected media type')))),
          );
          expect(adapter.reading.chunksRead, equals(0));
        });
      }
    });

    group('the size', () {
      test('refuses a file that declares more than the maximum, '
          'unread', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            headers: {
              ..._pdfHeaders,
              HttpHeader.contentLength.value: '${_maxBytes + 1}',
            },
            chunks: [_bytesOf(10)],
            paced: true,
          ),
        ]);
        final world = _aClient(adapter);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(unexpected('response too large')))),
        );
        expect(adapter.reading.chunksRead, equals(0));
      });

      test('stops reading, and cancels the stream, once the body grows past '
          'the maximum', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            headers: _pdfHeaders,
            chunks: [_bytesOf(600), _bytesOf(600), _bytesOf(600)],
            paced: true,
          ),
        ]);
        final world = _aClient(adapter);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(unexpected('response too large')))),
        );
        await Future<void>.delayed(Duration.zero);
        expect(adapter.reading.chunksRead, equals(2));
        expect(adapter.reading.cancelled, isTrue);
      });

      test('accepts a file of exactly the maximum', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            headers: {
              ..._pdfHeaders,
              HttpHeader.contentLength.value: '$_maxBytes',
            },
            chunks: [_bytesOf(_maxBytes)],
          ),
        ]);
        final world = _aClient(adapter);

        expect(
          await world.client.download(_spec),
          isA<Ok<Downloaded, HttpFailure>>(),
        );
      });

      test('ignores a length that is not a number', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            headers: {..._pdfHeaders, HttpHeader.contentLength.value: 'many'},
            chunks: [_bytesOf(10)],
          ),
        ]);
        final world = _aClient(adapter);

        expect(
          await world.client.download(_spec),
          isA<Ok<Downloaded, HttpFailure>>(),
        );
      });
    });

    group('a refusal', () {
      for (final (status, error) in <(int, RepositoryError)>[
        (HttpStatusCode.unauthorized.code, unauthorized()),
        (HttpStatusCode.forbidden.code, forbidden()),
        (HttpStatusCode.notFound.code, notFound()),
        (HttpStatusCode.requestTimeout.code, networkUnavailable()),
        (HttpStatusCode.tooManyRequests.code, networkUnavailable()),
        (HttpStatusCode.badGateway.code, networkUnavailable()),
        (HttpStatusCode.serviceUnavailable.code, networkUnavailable()),
        (HttpStatusCode.gatewayTimeout.code, networkUnavailable()),
        (HttpStatusCode.badRequest.code, unexpected('status 400')),
        (HttpStatusCode.internalServerError.code, unexpected('status 500')),
        (HttpStatusCode.unprocessableContent.code, unexpected('status 422')),
        (302, unexpected('status 302')),
      ]) {
        test('with the status $status is the error the other requests '
            'answer, and its body is not read', () async {
          final adapter = ScriptedAdapter([
            ScriptedAnswer(
              status: status,
              headers: {HttpHeader.contentType.value: 'application/json'},
              chunks: [_bytesOf(10)],
              paced: true,
            ),
          ]);
          final world = _aClient(adapter);

          expect(
            await world.client.download(_spec),
            equals(err(_failed(error))),
          );
          expect(adapter.reading.chunksRead, equals(0));
          // What was left unread is dropped with the connection.
          await Future<void>.delayed(Duration.zero);
          expect(adapter.sent.single.cancelled, isTrue);
        });
      }
    });

    group('time and failure', () {
      test('is a network that failed when the request does not go '
          'through', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer.fails(
            StateError('Network request failed: https://secret.example'),
          ),
        ]);
        final world = _aClient(adapter);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(networkUnavailable()))),
        );
      });

      test('is a network that failed when the server never answers, at the '
          'timeout of the client', () async {
        final adapter = ScriptedAdapter([const ScriptedAnswer.never()]);
        final world = _aClient(adapter, timeout: 40);

        expect(
          await world.client.download(_spec),
          equals(err(_failed(networkUnavailable()))),
        );
        await Future<void>.delayed(Duration.zero);
        expect(adapter.sent.single.cancelled, isTrue);
      });

      test('takes the timeout of the download when it has one, and not the '
          'one of the client', () async {
        final adapter = ScriptedAdapter([const ScriptedAnswer.never()]);
        final world = _aClient(adapter, timeout: 5000);

        final failed = await world.client.download(
          () => _spec(timeout: aDuration(30)),
        );

        expect(failed, equals(err(_failed(networkUnavailable()))));
        await Future<void>.delayed(Duration.zero);
        expect(adapter.sent.single.cancelled, isTrue);
      });

      test('puts no address, token or path in anything it answers', () async {
        final failures = [
          ScriptedAdapter([
            ScriptedAnswer.fails(
              StateError('Network request failed: $_baseUrl'),
            ),
          ]),
          ScriptedAdapter([
            ScriptedAnswer(status: HttpStatusCode.internalServerError.code),
          ]),
          ScriptedAdapter([
            ScriptedAnswer(
              headers: {HttpHeader.contentType.value: 'text/html'},
              chunks: const [],
            ),
          ]),
          ScriptedAdapter([
            ScriptedAnswer(
              headers: _pdfHeaders,
              chunks: [_bytesOf(_maxBytes + 1)],
            ),
          ]),
        ];

        final answers = await Future.wait([
          for (final adapter in failures)
            _aClient(adapter).client.download(_spec),
        ]);

        expect(
          '$answers',
          isNot(
            matches(RegExp(r'boardroom\.example|a-very-secret-token|files/a')),
          ),
        );
      });
    });
  });
}
