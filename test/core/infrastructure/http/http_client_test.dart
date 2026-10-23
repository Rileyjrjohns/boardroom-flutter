import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/invalid_response.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/core/infrastructure/http/well_formed.dart';
import 'package:boardroom/core/infrastructure/shared/issue_paths.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/http_adapters_world.dart';
import '../../../support/infrastructure/http_world.dart';
import '../../../support/infrastructure/scripted_adapter.dart';

const String _baseUrl = 'https://api.boardroom.example/v1';
const String _token = 'a-very-secret-token';
const String _itemBody = '{"id":"a","count":1}';

typedef _Item = ({String id, int count});

/// The token of the signed-in user, which says whose it is.
Result<BearerToken?, StorageReadFailedError> _signedInAs([
  UserId? userId,
  String token = _token,
]) => ok(BearerToken(token: token, userId: userId ?? aUserId()));

/// Reads `{"id": string, "count": number}`, as the schema of the React Native
/// tests does, and says where it broke it.
Result<_Item, WireFailure> _decodeItem(Object? body) {
  if (body is! Map<String, dynamic>) {
    return err(const WireFailure(rootPath));
  }
  final id = body['id'];
  final count = body['count'];
  if (id is String && count is num) {
    return ok((id: id, count: count.toInt()));
  }
  return err(
    WireFailure(
      issuePathsOf([
        if (id is! String) const ['id'],
        if (count is! num) const ['count'],
      ]),
    ),
  );
}

/// Reads `{"rows": [{"inner": {"n": number}}]}` and says where it broke it.
Result<int, WireFailure> _decodeRows(Object? body) {
  if (body is! Map<String, dynamic>) {
    return err(const WireFailure(rootPath));
  }
  final rows = body['rows'];
  if (rows is! List<dynamic>) {
    return err(
      WireFailure(
        issuePathsOf([
          const ['rows'],
        ]),
      ),
    );
  }
  final flaws = <List<Object>>[];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final inner = row is Map<String, dynamic> ? row['inner'] : null;
    final n = inner is Map<String, dynamic> ? inner['n'] : null;
    if (n is! num) {
      flaws.add(['rows', index, 'inner', 'n']);
    }
  }
  return flaws.isEmpty
      ? ok(rows.length)
      : err(WireFailure(issuePathsOf(flaws)));
}

HttpRequestSpec<_Item> _get({
  String path = '/items',
  HttpMethod method = HttpMethod.get,
  Map<String, Object?> query = const {},
  Object? body,
  Map<String, String> headers = const {},
  bool authenticated = true,
  UserId? forUser,
}) => HttpRequestSpec<_Item>(
  method: method,
  path: path,
  resource: HttpResource.meeting,
  decode: _decodeItem,
  query: query,
  body: body,
  headers: headers,
  authenticated: authenticated,
  forUser: forUser,
);

/// Answers whatever the token source is told to, and counts the reads.
final class _Tokens implements BearerTokenSource {
  new(this._read);

  final Result<BearerToken?, StorageReadFailedError> Function() _read;
  int calls = 0;

  @override
  Future<Result<BearerToken?, StorageReadFailedError>> token() async {
    calls += 1;
    return _read();
  }
}

typedef _World = ({
  HttpClient client,
  FakeMonitoring monitoring,
  _Tokens tokens,
});

_World _aClient(
  HttpClientAdapter adapter, {
  Result<BearerToken?, StorageReadFailedError> Function()? token,
  int timeout = 1000,
}) {
  final monitoring = FakeMonitoring();
  final tokens = _Tokens(token ?? _signedInAs);
  final client = HttpClient(
    HttpClientOptions(
      baseUrl: _baseUrl,
      timeout: aDuration(timeout),
      tokens: tokens,
      monitoring: monitoring,
      adapter: adapter,
    ),
  );
  return (client: client, monitoring: monitoring, tokens: tokens);
}

/// A request that nothing answers until the test says so.
final class _HeldAdapter implements HttpClientAdapter {
  final List<RequestOptions> sent = [];
  final List<Completer<ResponseBody>> _waiting = [];

  /// Waits until a request reaches the adapter.
  Future<void> arrival() async {
    while (sent.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void respond(int status, String text) {
    _waiting.removeAt(0).complete(ResponseBody.fromString(text, status));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    sent.add(options);
    final waiting = Completer<ResponseBody>();
    _waiting.add(waiting);
    return waiting.future;
  }

  @override
  void close({bool force = false}) {}
}

/// An adapter that throws instead of returning a future.
final class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw StateError('synchronous');

  @override
  void close({bool force = false}) {}
}

RequestFailed _failed(RepositoryError error) => RequestFailed(error);

void main() {
  const illFormed = '\uD800';

  group('HttpClient, the request', () {
    test('sends a GET to the base URL and the path with the token of the user, '
        'asking for JSON', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(adapter);

      await world.client.request(() => _get(path: '/items/a'));

      expect(adapter.sent, hasLength(1));
      final sent = adapter.sent.single;
      expect(sent.url, equals('$_baseUrl/items/a'));
      expect(sent.method, equals('GET'));
      expect(
        sent.headers,
        containsPair(HttpHeader.accept.value.toLowerCase(), 'application/json'),
      );
      expect(
        sent.headers,
        containsPair(HttpHeader.cacheControl.value.toLowerCase(), 'no-store'),
      );
      expect(
        sent.headers,
        containsPair(
          HttpHeader.authorization.value.toLowerCase(),
          'Bearer $_token',
        ),
      );
      expect(
        sent.headers.keys,
        isNot(contains(HttpHeader.contentType.value.toLowerCase())),
      );
      expect(sent.body, isNull);
      expect(sent.options.cancelToken, isNotNull);
    });

    test('puts the query after the path, every name and value '
        'percent-encoded, and leaves out what is undefined', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(adapter);

      await world.client.request(
        () => _get(
          query: {
            'period': 'past',
            'limit': 10,
            'cursor': 'a b&c=d/é',
            'skipped': null,
          },
        ),
      );

      expect(
        adapter.sent.single.url,
        equals(
          '$_baseUrl/items?period=past&limit=10&cursor=a%20b%26c%3Dd%2F%C3%A9',
        ),
      );
    });

    test('sends no query mark for an empty query', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      await world.client.request(() => _get(query: {'nothing': null}));

      expect(adapter.sent.single.url, equals('$_baseUrl/items'));
    });

    test('sends a body as JSON with its content type, next to the headers '
        'the caller adds', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(adapter);

      await world.client.request(
        () => _get(
          path: '/votes',
          method: HttpMethod.post,
          body: {
            'choice': 'for',
            'nested': {'n': 1},
          },
          headers: {HttpHeader.idempotencyKey.value: '12.r.u'},
        ),
      );

      final sent = adapter.sent.single;
      expect(sent.method, equals('POST'));
      expect(sent.body, equals('{"choice":"for","nested":{"n":1}}'));
      expect(sent.header(HttpHeader.accept.value), equals('application/json'));
      expect(sent.header(HttpHeader.cacheControl.value), equals('no-store'));
      expect(
        sent.header(HttpHeader.authorization.value),
        equals('Bearer $_token'),
      );
      expect(
        sent.header(HttpHeader.contentType.value),
        equals('application/json'),
      );
      expect(sent.header(HttpHeader.idempotencyKey.value), equals('12.r.u'));
    });

    test('carries no token, and does not ask for one, when the request is '
        'not authenticated', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      await world.client.request(
        () => _get(path: '/auth/sign-in', authenticated: false),
      );

      expect(
        adapter.sent.single.headers.keys,
        isNot(contains(HttpHeader.authorization.value.toLowerCase())),
      );
      expect(world.tokens.calls, equals(0));
    });

    test('is unauthorized, without sending anything, when nobody is signed '
        'in', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter, token: () => ok<BearerToken?>(null));

      expect(
        await world.client.request(_get),
        equals(err(_failed(unauthorized()))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('is unexpected, not unauthorized, and sends nothing, when the token '
        'cannot be read', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter, token: () => err(storageReadFailed()));

      expect(
        await world.client.request(_get),
        equals(err(_failed(unexpected('credentials unreadable')))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('attaches the token read when the request was created, not one '
        'that arrives while it is on its way', () async {
      var current = 'token-of-alice';
      final adapter = _HeldAdapter();
      final world = _aClient(adapter, token: () => _signedInAs(null, current));

      final pending = world.client.request(_get);
      await adapter.arrival();
      current = 'token-of-bruno';
      adapter.respond(200, _itemBody);
      await pending;

      expect(
        adapter.sent.single.headers[HttpHeader.authorization.value],
        equals('Bearer token-of-alice'),
      );
    });

    test('answers unexpected, and sends nothing, for a body that has no JSON '
        'form', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);
      final circular = <String, Object?>{};
      circular['self'] = circular;

      expect(
        await world.client.request(
          () => _get(method: HttpMethod.post, body: circular),
        ),
        equals(err(_failed(unexpected('request could not be built')))),
      );
      expect(
        await world.client.request(
          () => _get(method: HttpMethod.post, body: {'n': BigInt.one}),
        ),
        isA<Err<_Item, HttpFailure>>(),
      );
      expect(adapter.sent, isEmpty);
    });
  });

  group('HttpClient, the answer', () {
    test('gives the body of a success, read through the schema', () async {
      final adapter = ScriptedAdapter([
        const ScriptedAnswer(text: '{"id":"a","count":3,"ignored":true}'),
      ]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(ok<_Item>((id: 'a', count: 3))),
      );
    });

    for (final status in [200, 201, 202, 299]) {
      test('reads a body from a success with status $status', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: '{"id":"a","count":3}'),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          isA<Ok<_Item, HttpFailure>>(),
        );
      });
    }

    test('reads an empty body as undefined, for the schema of a call that '
        'returns nothing', () async {
      final adapter = ScriptedAdapter([
        ScriptedAnswer(status: HttpStatusCode.noContent.code),
      ]);
      final world = _aClient(adapter);

      expect(
        await world.client.request(
          () => HttpRequestSpec<void>(
            method: HttpMethod.get,
            path: '/items',
            resource: HttpResource.meeting,
            decode: (body) => body == null
                ? ok<void>(null)
                : err(const WireFailure(rootPath)),
          ),
        ),
        equals(ok<void>(null)),
      );
    });

    for (final status in [200, 201, 204, 299]) {
      test('takes the status $status for a success', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: _itemBody),
        ]);

        expect(
          await _aClient(adapter).client.request(
            () => const HttpRequestSpec<Object?>(
              method: HttpMethod.get,
              path: '/items',
              resource: HttpResource.meeting,
              decode: ok,
            ),
          ),
          isA<Ok<Object?, HttpFailure>>(),
        );
      });
    }

    for (final (status, error) in <(int, RepositoryError)>[
      (HttpStatusCode.unauthorized.code, unauthorized()),
      (HttpStatusCode.forbidden.code, forbidden()),
      (HttpStatusCode.notFound.code, notFound()),
      (HttpStatusCode.badGateway.code, networkUnavailable()),
      (HttpStatusCode.serviceUnavailable.code, networkUnavailable()),
      (HttpStatusCode.gatewayTimeout.code, networkUnavailable()),
    ]) {
      test('turns the status $status into ${error.code}', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: '{"error":{"code":"whatever"}}'),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(err(_failed(error))),
        );
      });
    }

    for (final status in [
      400,
      405,
      409,
      418,
      500,
      501,
      300,
      301,
      304,
      199,
      100,
    ]) {
      test('turns the status $status into unexpected, with the status as the '
          'only cause', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: 'secret-looking text'),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(err(_failed(unexpected('status $status')))),
        );
      });
    }

    group('a business rejection, status 422', () {
      test(
        'gives the description the server sent, for the caller to read',
        () async {
          final adapter = ScriptedAdapter([
            ScriptedAnswer(
              status: HttpStatusCode.unprocessableContent.code,
              text: '{"error":{"code":"resolutionClosed"}}',
            ),
          ]);

          expect(
            await _aClient(adapter).client.request(_get),
            equals(err(const RequestRejected({'code': 'resolutionClosed'}))),
          );
        },
      );

      for (final (name, body) in [
        ('a body that is not JSON', 'oops'),
        ('an empty body', ''),
        ('JSON without an error', '{"message":"no"}'),
        ('JSON that is not an object', '12'),
        ('JSON that is null', 'null'),
      ]) {
        test('is unexpected, with the status, for $name', () async {
          final adapter = ScriptedAdapter([
            ScriptedAnswer(
              status: HttpStatusCode.unprocessableContent.code,
              text: body,
            ),
          ]);

          expect(
            await _aClient(adapter).client.request(_get),
            equals(err(_failed(unexpected('status 422')))),
          );
        });
      }
    });

    group('a success that does not have the shape of the API', () {
      for (final (name, body, paths) in [
        ('text that is not JSON', 'not json', r'$'),
        ('an empty body', '', r'$'),
        ('JSON of another type', '[]', r'$'),
        ('a missing field', '{"id":"a"}', 'count'),
        ('a mistyped field', '{"id":"a","count":"3"}', 'count'),
        (
          'several flaws, listed once each, sorted',
          '{"id":1,"count":"x"}',
          'count,id',
        ),
      ]) {
        test('is unexpected for $name, and reports where it broke the '
            'schema', () async {
          final adapter = ScriptedAdapter([ScriptedAnswer(text: body)]);
          final world = _aClient(adapter);

          expect(
            await world.client.request(_get),
            equals(err(_failed(unexpected('invalid response')))),
          );

          expect(
            world.monitoring.errors,
            equals([
              ErrorRecord(
                event: MonitoringEvent.responseInvalid,
                error: unexpected('invalid response'),
                attributes: {
                  LogAttribute.resource: HttpResource.meeting.value,
                  LogAttribute.issuePaths: paths,
                },
              ),
            ]),
          );
        });
      }

      test('reports the position in a list and the path of a nested field, '
          'never the values', () async {
        final adapter = ScriptedAdapter([
          const ScriptedAnswer(
            text: '{"rows":[{"inner":{"n":"SECRET-VALUE"}},{"inner":{"n":1}}]}',
          ),
        ]);
        final world = _aClient(adapter);

        await world.client.request(
          () => const HttpRequestSpec<int>(
            method: HttpMethod.get,
            path: '/items',
            resource: HttpResource.meeting,
            decode: _decodeRows,
          ),
        );

        expect(
          world.monitoring.errors.first.attributes?[LogAttribute.issuePaths],
          equals('rows.0.inner.n'),
        );
        expect('${world.monitoring.errors}', isNot(contains('SECRET-VALUE')));
      });
    });
  });

  group('HttpClient, when the network fails', () {
    test('is networkUnavailable when the request cannot be made', () async {
      final adapter = ScriptedAdapter([
        ScriptedAnswer.fails(StateError('Network request failed')),
      ]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(err(_failed(networkUnavailable()))),
      );
    });

    test('is networkUnavailable when the answer is cut off while it is being '
        'read', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer.brokenBody()]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(err(_failed(networkUnavailable()))),
      );
    });

    test('is networkUnavailable, and aborts the request, when the answer '
        'takes longer than the timeout', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer.never()]);
      final world = _aClient(adapter, timeout: 30);

      final started = DateTime.now();
      final answer = await world.client.request(_get);
      await Future<void>.delayed(Duration.zero);

      expect(answer, equals(err(_failed(networkUnavailable()))));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 1)),
      );
      expect(adapter.sent.single.cancelled, isTrue);
    });

    test('settles within the timeout even when the platform ignores the '
        'abort', () async {
      // The adapter never settles, cancelled or not: the answer must not
      // depend on it.
      final adapter = ScriptedAdapter([const ScriptedAnswer.never()]);
      final world = _aClient(adapter, timeout: 20);

      final started = DateTime.now();
      expect(await world.client.request(_get), isA<Err<_Item, HttpFailure>>());

      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('waits for the timeout it was given, and not for less: a slow '
        'answer inside it is an answer', () async {
      final adapter = _HeldAdapter();
      final world = _aClient(adapter, timeout: 2000);

      final pending = world.client.request(_get);
      await adapter.arrival();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      adapter.respond(200, _itemBody);

      expect(await pending, isA<Ok<_Item, HttpFailure>>());
    });

    test('does not leave its timer running once the answer is in', () {
      fakeAsync((async) {
        final adapter = ScriptedAdapter([
          const ScriptedAnswer(text: _itemBody),
        ]);
        final world = _aClient(adapter, timeout: 5000);
        Result<_Item, HttpFailure>? answer;

        unawaited(world.client.request(_get).then((value) => answer = value));
        async.elapse(const Duration(milliseconds: 1));

        expect(answer, isNotNull);
        expect(async.nonPeriodicTimerCount, equals(0));
      });
    });

    test('does not leave its timer running after a failure either', () {
      fakeAsync((async) {
        final adapter = ScriptedAdapter([
          ScriptedAnswer.fails(StateError('offline')),
        ]);
        final world = _aClient(adapter, timeout: 5000);
        Result<_Item, HttpFailure>? answer;

        unawaited(world.client.request(_get).then((value) => answer = value));
        async.elapse(const Duration(milliseconds: 1));

        expect(answer, isNotNull);
        expect(async.nonPeriodicTimerCount, equals(0));
      });
    });
  });

  group('HttpClient, whatever goes wrong', () {
    final failures = <(String, ScriptedAnswer)>[
      (
        'a network error',
        ScriptedAnswer.fails(
          StateError(
            'failed to fetch https://api.boardroom.example/v1/items?q=secret',
          ),
        ),
      ),
      (
        'a status',
        const ScriptedAnswer(
          status: 500,
          text: '{"detail":"$_token /var/secret/path"}',
        ),
      ),
      (
        'a rejection that cannot be read',
        const ScriptedAnswer(status: 422, text: 'user alice@example.com'),
      ),
      ('a body that is not JSON', const ScriptedAnswer(text: 'leak $_token')),
      (
        'a body of the wrong shape',
        const ScriptedAnswer(
          text: '{"id":"$_token","count":"alice@example.com"}',
        ),
      ),
    ];

    for (final (name, answer) in failures) {
      test('puts no URL, path, token, email or body in the error for '
          '$name', () async {
        final adapter = ScriptedAdapter([answer]);
        final world = _aClient(adapter);

        final result = await world.client.request(
          () => _get(path: '/items/secret-id?q=secret'),
        );

        final reported =
            '$result ${world.monitoring.logs} ${world.monitoring.errors}';
        for (final secret in [
          'api.boardroom.example',
          'secret-id',
          'q=secret',
          _token,
          'alice@example.com',
          '/var/secret',
        ]) {
          expect(reported, isNot(contains(secret)));
        }
      });
    }

    test('never rejects: a function that throws instead of returning a '
        'promise is a network failure too', () async {
      final world = _aClient(_ThrowingAdapter());

      expect(
        await world.client.request(_get),
        equals(err(_failed(networkUnavailable()))),
      );
    });
  });

  // The same client over the adapter that serves the fixtures, which the
  // scripted adapter above cannot say: a connection that fails, a server that
  // never answers and a request that is cancelled are what the network layer
  // really does.
  group('HttpClient, over the global fetch and MSW', () {
    final installed = installFixtureServer();

    Future<HttpWorld> aWorldClient([int timeout = 2000]) async {
      final world = createHttpWorld(
        installed,
        HttpWorldOptions(clientTimeout: aDuration(timeout)),
      );
      await world.signInAs(aUserId());
      return world;
    }

    Future<Result<dynamic, RepositoryError>> listUpcoming(HttpWorld world) =>
        world.meetings.list(
          MeetingPeriod.upcoming,
          unwrap(createPageRequest(limit: 5)),
        );

    test('reaches the server through the global fetch, with the token of '
        'the signed-in user', () async {
      final world = await aWorldClient();

      final listed = await listUpcoming(world);

      expect(listed, isA<Ok<dynamic, RepositoryError>>());
      expect(
        installed.received,
        contains(startsWith('GET $testApiUrl/meetings?')),
      );
      expect(
        installed.receivedHeader(
          installed.received.length - 1,
          HttpHeader.authorization.value,
        ),
        startsWith('Bearer token-'),
      );
    });

    test('is networkUnavailable when the connection fails', () async {
      final world = await aWorldClient();
      installed.conditions.online = false;

      expect(await listUpcoming(world), equals(err(networkUnavailable())));
    });

    test('is networkUnavailable, within the timeout, when the server never '
        'answers', () async {
      final world = await aWorldClient(50);
      installed.conditions.neverAnswers = true;

      final started = DateTime.now();
      final answer = await listUpcoming(world);

      expect(answer, equals(err(networkUnavailable())));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
      );
    });

    test('is networkUnavailable when the simulated server is unreachable and '
        'answers 503', () async {
      final world = await aWorldClient();
      world.network.setOnline(online: false);

      expect(await listUpcoming(world), equals(err(networkUnavailable())));
    });
  });

  group('HttpClient, a request that cannot be built', () {
    test('answers unexpected, and sends nothing, when the path cannot be '
        'built', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      final answer = await world.client.request(
        () => _get(path: '/items/${encodeUriComponent(illFormed)}'),
      );

      expect(
        answer,
        equals(err(_failed(unexpected('request could not be built')))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('answers unexpected, and sends nothing, when the query cannot be '
        'encoded', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      final answer = await world.client.request(
        () => _get(query: {'cursor': illFormed}),
      );

      expect(
        answer,
        equals(err(_failed(unexpected('request could not be built')))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('answers unexpected, and sends nothing, when a header cannot be '
        'built', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      final answer = await world.client.request(
        () => _get(
          headers: {
            HttpHeader.idempotencyKey.value: encodeUriComponent(illFormed),
          },
        ),
      );

      expect(
        answer,
        equals(err(_failed(unexpected('request could not be built')))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('leaks nothing of what could not be encoded', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter);

      final answer = await world.client.request<_Item>(
        () => throw const FormatException(
          'malformed $_token https://api.boardroom.example/secret',
        ),
      );

      final reported =
          '$answer ${world.monitoring.errors} ${world.monitoring.logs}';
      expect(reported, isNot(contains(_token)));
      expect(reported, isNot(contains('api.boardroom.example')));
    });
  });

  group('HttpClient, a request made for a user', () {
    test('is sent when the token is the one of that user', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(adapter);

      final answer = await world.client.request(() => _get(forUser: aUserId()));

      expect(answer, isA<Ok<_Item, HttpFailure>>());
      expect(adapter.sent, hasLength(1));
    });

    test('is unauthorized, without being sent, when the token is the one of '
        'another user', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(
        adapter,
        token: () => _signedInAs(aUserId('user-2'), 'token-of-bruno'),
      );

      final answer = await world.client.request(() => _get(forUser: aUserId()));

      expect(answer, equals(err(_failed(unauthorized()))));
      expect(adapter.sent, isEmpty);
    });

    test('decides on the token and the user it reads together, not on two '
        'reads', () async {
      // The user who is signed in changes at once after the token is read: the
      // request already carries the token of the first, and it is for the
      // first. Only a pair read in one go can say so.
      var current = _signedInAs(aUserId(), 'token-of-alice');
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(
        adapter,
        token: () {
          final read = current;
          current = _signedInAs(aUserId('user-2'), 'token-of-bruno');
          return read;
        },
      );

      final answer = await world.client.request(() => _get(forUser: aUserId()));

      expect(answer, isA<Ok<_Item, HttpFailure>>());
      expect(
        adapter.sent.single.header(HttpHeader.authorization.value),
        equals('Bearer token-of-alice'),
      );
    });

    test('is unauthorized, without being sent, when nobody is signed '
        'in', () async {
      final adapter = ScriptedAdapter();
      final world = _aClient(adapter, token: () => ok<BearerToken?>(null));

      expect(
        await world.client.request(() => _get(forUser: aUserId())),
        equals(err(_failed(unauthorized()))),
      );
      expect(adapter.sent, isEmpty);
    });

    test('does not ask who the token belongs to when the request is not made '
        'for anyone', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(
        adapter,
        token: () => _signedInAs(aUserId('user-2')),
      );

      expect(await world.client.request(_get), isA<Ok<_Item, HttpFailure>>());
      expect(adapter.sent, hasLength(1));
    });
  });

  group('HttpClient, the statuses that say to come back later', () {
    for (final status in [
      HttpStatusCode.requestTimeout.code,
      HttpStatusCode.tooManyRequests.code,
    ]) {
      test('turns the status $status into networkUnavailable: nothing is said '
          'of the request', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: '{"error":{"code":"later"}}'),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(err(_failed(networkUnavailable()))),
        );
      });
    }

    for (final status in [300, 301, 302, 304, 307, 308]) {
      test('does not take the status $status for a success: a redirect is '
          'not an answer', () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: _itemBody),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(err(_failed(unexpected('status $status')))),
        );
      });
    }

    test('takes the first and the last status of the successes for '
        'successes', () async {
      for (final status in [200, 299]) {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(status: status, text: _itemBody),
        ]);
        expect(
          await _aClient(adapter).client.request(_get),
          isA<Ok<_Item, HttpFailure>>(),
        );
      }
    });
  });

  group('HttpClient, what every request says', () {
    test('refuses a redirect and asks for nothing to be stored', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);

      await _aClient(adapter).client.request(_get);

      final sent = adapter.sent.single;
      expect(sent.options.followRedirects, isFalse);
      expect(sent.options.maxRedirects, equals(0));
      expect(
        sent.header(HttpHeader.cacheControl.value),
        equals(cacheControlNoStore),
      );
    });

    test('says it also for a request that carries no token', () async {
      final adapter = ScriptedAdapter();

      await _aClient(adapter).client.request(() => _get(authenticated: false));

      final sent = adapter.sent.single;
      expect(sent.options.followRedirects, isFalse);
      expect(sent.options.maxRedirects, equals(0));
      expect(
        sent.header(HttpHeader.cacheControl.value),
        equals(cacheControlNoStore),
      );
    });
  });

  group('HttpClient, the size of an answer', () {
    const max = maxResponseBytes;

    ScriptedAnswer declaring(Object bytes) => ScriptedAnswer(
      text: _itemBody,
      paced: true,
      headers: {HttpHeader.contentLength.value: '$bytes'},
    );

    test('refuses an answer that declares more than the maximum, without '
        'reading it', () async {
      final adapter = ScriptedAdapter([declaring(max + 1)]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(err(_failed(unexpected('response too large')))),
      );
      expect(adapter.reading.chunksRead, equals(0));
    });

    test('accepts an answer that declares exactly the maximum, and one that '
        'declares nothing usable', () async {
      for (final declared in [max, 'nonsense', '', '-5']) {
        final adapter = ScriptedAdapter([declaring(declared)]);
        expect(
          await _aClient(adapter).client.request(_get),
          isA<Ok<_Item, HttpFailure>>(),
        );
      }
    });

    test('stops reading a body that grows past the maximum, and cancels '
        'it', () async {
      final chunk = Uint8List(max ~/ 2 + 1)..fillRange(0, max ~/ 2 + 1, 0x20);
      final adapter = ScriptedAdapter([
        ScriptedAnswer(chunks: [chunk, chunk, chunk], paced: true),
      ]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(err(_failed(unexpected('response too large')))),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.reading.chunksRead, equals(2));
      expect(adapter.reading.cancelled, isTrue);
    });

    test('reads a body that arrives in pieces, and puts it back '
        'together', () async {
      final adapter = ScriptedAdapter([
        ScriptedAnswer(
          chunks: [
            Uint8List.fromList(utf8.encode('{"id":"a",')),
            Uint8List.fromList(utf8.encode('"count":1}')),
          ],
        ),
      ]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(ok<_Item>((id: 'a', count: 1))),
      );
    });

    test('is networkUnavailable when the stream breaks', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer.brokenBody()]);

      expect(
        await _aClient(adapter).client.request(_get),
        equals(err(_failed(networkUnavailable()))),
      );
    });
  });

  group('HttpClient, an action whose answer holds nothing to read', () {
    HttpActionSpec action({HttpMethod method = HttpMethod.get}) =>
        HttpActionSpec(
          method: method,
          path: '/items',
          resource: HttpResource.meeting,
        );

    test('succeeds on a success whatever the body is, and does not read '
        'it', () async {
      for (final body in ['', 'not json', '{"anything":1}', '<html>']) {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(text: body, paced: true),
        ]);
        final client = _aClient(adapter).client;

        expect(
          await client.perform(() => action(method: HttpMethod.post)),
          equals(ok<void>(null)),
        );
        expect(adapter.reading.chunksRead, equals(0));
      }
    });

    test('reads the description of a rejection, like any request', () async {
      final adapter = ScriptedAdapter([
        ScriptedAnswer(
          status: HttpStatusCode.unprocessableContent.code,
          text: '{"error":{"code":"resolutionClosed"}}',
        ),
      ]);

      expect(
        await _aClient(adapter).client.perform(action),
        equals(err(const RequestRejected({'code': 'resolutionClosed'}))),
      );
    });

    test('fails like any request on the statuses that are not a '
        'success', () async {
      final adapter = ScriptedAdapter([
        const ScriptedAnswer(status: 401),
        const ScriptedAnswer(status: 500),
        ScriptedAnswer.fails(StateError('offline')),
      ]);
      final client = _aClient(adapter).client;

      expect(
        await client.perform(action),
        equals(err(_failed(unauthorized()))),
      );
      expect(
        await client.perform(action),
        equals(err(_failed(unexpected('status 500')))),
      );
      expect(
        await client.perform(action),
        equals(err(_failed(networkUnavailable()))),
      );
    });
  });

  // What exists only in Dart: the client of the React Native app is built over
  // `fetch`, this one over dio.
  group('HttpClient, over dio', () {
    test('does not retry a request that failed: what asks again is the '
        'synchronisation of the votes, not the client', () async {
      final adapter = ScriptedAdapter([
        ScriptedAnswer(status: HttpStatusCode.serviceUnavailable.code),
        const ScriptedAnswer(text: _itemBody),
      ]);

      final answer = await _aClient(adapter).client.request(_get);

      expect(answer, equals(err(_failed(networkUnavailable()))));
      expect(adapter.sent, hasLength(1));
    });

    test('drops the connection of a success whose body nobody wants', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: 'created')]);

      await _aClient(adapter).client.perform(
        () => const HttpActionSpec(
          method: HttpMethod.post,
          path: '/votes',
          resource: HttpResource.vote,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(adapter.sent.single.cancelled, isTrue);
    });

    test(
      'does not drop the connection of a success it has read to the end',
      () async {
        final adapter = ScriptedAdapter([
          const ScriptedAnswer(text: _itemBody),
        ]);

        await _aClient(adapter).client.request(_get);
        await Future<void>.delayed(Duration.zero);

        expect(adapter.sent.single.cancelled, isFalse);
      },
    );

    test(
      'reads a length that is written as a whole number in any form',
      () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            text: _itemBody,
            paced: true,
            headers: {
              HttpHeader.contentLength.value: '${maxResponseBytes + 1}.0',
            },
          ),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(err(_failed(unexpected('response too large')))),
        );
        expect(adapter.reading.chunksRead, equals(0));
      },
    );

    test(
      'reads a body that is not UTF-8 with the replacement character',
      () async {
        final adapter = ScriptedAdapter([
          ScriptedAnswer(
            chunks: [
              Uint8List.fromList([
                ...utf8.encode('{"id":"'),
                0xff,
                ...utf8.encode('","count":1}'),
              ]),
            ],
          ),
        ]);

        expect(
          await _aClient(adapter).client.request(_get),
          equals(ok<_Item>((id: '�', count: 1))),
        );
      },
    );

    test('lets go of its adapter when it is closed, and fails like a '
        'network that is not there after that', () async {
      final adapter = ScriptedAdapter([const ScriptedAnswer(text: _itemBody)]);
      final world = _aClient(adapter)..client.close();

      expect(adapter.closed, isTrue);
      expect(
        await world.client.request(_get),
        equals(err(_failed(networkUnavailable()))),
      );
    });

    test('never prints the token of a user', () {
      final bearer = BearerToken(token: _token, userId: aUserId());

      expect('$bearer', isNot(contains(_token)));
      expect(bearer, equals(BearerToken(token: _token, userId: aUserId())));
      expect(
        bearer.hashCode,
        equals(BearerToken(token: _token, userId: aUserId()).hashCode),
      );
    });

    test('tells two failures by what they hold', () {
      expect(_failed(notFound()), isNot(equals(_failed(forbidden()))));
      expect(
        const RequestRejected({'code': 'a'}),
        equals(const RequestRejected({'code': 'a'})),
      );
      expect(
        const RequestRejected({'code': 'a'}).hashCode,
        equals(const RequestRejected({'code': 'a'}).hashCode),
      );
      expect(
        const RequestRejected({'code': 'a'}),
        isNot(equals(const RequestRejected({'code': 'b'}))),
      );
      expect('${_failed(notFound())}', contains('notFound'));
      expect('${const RequestRejected(1)}', equals('RequestRejected(1)'));
    });
  });
}
