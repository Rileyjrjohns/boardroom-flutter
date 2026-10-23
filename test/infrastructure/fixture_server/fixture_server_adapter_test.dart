import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:boardroom/infrastructure/fixture_server/fixture_server_adapter.dart';
import 'package:boardroom/infrastructure/fixture_server/mock_api.dart';
import 'package:boardroom/infrastructure/http/dto/vote_dto.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/pdf/pdf_signature.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/http_world.dart';
import '../support/test_server.dart';

// The adapter that stands in for the network of dio, with the real `Dio` in
// front of it: what the HTTP adapters of the app go through in the development
// build and in the tests.

/// Holds the simulated network: while a completer is set, a request that enters
/// the network waits for it.
final class _Gate {
  Completer<void>? held;
}

typedef _Setup = ({
  Dio dio,
  HttpServerSide world,
  List<String> lines,
  _Gate gate,
});

/// A `Dio` that talks to the API of a new test server. Every status is an
/// answer, not an exception, so a test reads it.
_Setup _aDio({Duration? receiveTimeout}) {
  final gate = _Gate();
  final world = createHttpServerSide(
    InstalledFixtureServer(),
    TestServerOptions(sleep: (millis) => gate.held?.future ?? Future.value()),
  );
  final lines = <String>[];
  final dio = Dio(
    BaseOptions(
      baseUrl: testApiUrl,
      validateStatus: (status) => true,
      receiveTimeout: receiveTimeout,
    ),
  )..httpClientAdapter = FixtureServerAdapter(world.api, logger: lines.add);
  return (dio: dio, world: world, lines: lines, gate: gate);
}

Future<String> _signIn(Dio dio, String email) async {
  final answer = await dio.post<Map<String, dynamic>>(
    Routes.signIn,
    data: {'email': email, 'password': testPassword},
  );
  return answer.data!['accessToken'] as String;
}

Options _as(String token) =>
    Options(headers: {HttpHeader.authorization.value: 'Bearer $token'});

void main() {
  group('FixtureServerAdapter', () {
    test(
      'serves the routes of the API to a dio client, JSON included',
      () async {
        final (:dio, :world, lines: _, gate: _) = _aDio();
        final token = await _signIn(dio, world.accounts.first.user.email);

        final answer = await dio.get<Map<String, dynamic>>(
          Routes.meetings,
          queryParameters: {'period': 'upcoming', 'limit': 5},
          options: _as(token),
        );

        expect(answer.statusCode, equals(HttpStatusCode.ok.code));
        expect(
          answer.headers.value(HttpHeader.contentType.value),
          contains('json'),
        );
        expect(
          (answer.data!['items'] as List<dynamic>).map((item) {
            return (item as Map<String, dynamic>)['id'];
          }),
          equals(['meeting-1']),
        );
      },
    );

    test('sends the body and the headers of the request to the API', () async {
      final (:dio, :world, lines: _, gate: _) = _aDio();
      final token = await _signIn(dio, world.accounts.first.user.email);
      final vote = aVote(choice: VoteChoice.against);

      final answer = await dio.post<Object?>(
        Routes.votes,
        data: toVoteRequestWire(vote).toJson(),
        options: Options(
          headers: {
            HttpHeader.authorization.value: 'Bearer $token',
            HttpHeader.idempotencyKey.value: Uri.encodeComponent(
              vote.idempotencyKey,
            ),
          },
        ),
      );

      expect(answer.statusCode, equals(HttpStatusCode.noContent.code));
      expect(world.backend.recordedVotes().single.choice, VoteChoice.against);
    });

    test(
      'hands the answer an error body and its status, like a server',
      () async {
        final (:dio, world: _, lines: _, gate: _) = _aDio();

        final answer = await dio.get<Map<String, dynamic>>(
          Routes.meeting('meeting-1'),
        );

        expect(answer.statusCode, equals(HttpStatusCode.unauthorized.code));
        expect(
          answer.data,
          equals({
            'error': {'code': 'unauthorized'},
          }),
        );
        expect(
          answer.headers.value(HttpHeader.cacheControl.value),
          equals('no-store'),
        );
      },
    );

    test(
      'hands the content of a document over as bytes, with its ETag',
      () async {
        final (:dio, :world, lines: _, gate: _) = _aDio();
        final token = await _signIn(dio, world.accounts.first.user.email);

        final answer = await dio.get<List<int>>(
          Routes.documentContent('document-1'),
          options: _as(token).copyWith(responseType: ResponseType.bytes),
        );

        expect(answer.statusCode, equals(HttpStatusCode.ok.code));
        expect(
          answer.headers.value(HttpHeader.contentType.value),
          equals('application/pdf'),
        );
        expect(
          answer.headers.value(HttpHeader.eTag.value),
          matches(r'^"[^"]+"$'),
        );
        expect(
          answer.headers.value(HttpHeader.contentLength.value),
          equals('${answer.data!.length}'),
        );
        expect(hasPdfSignature(Uint8List.fromList(answer.data!)), isTrue);
      },
    );

    test('says no content length for an answer that has no body', () async {
      final (:dio, :world, lines: _, gate: _) = _aDio();
      final token = await _signIn(dio, world.accounts.first.user.email);
      final vote = aVote();

      final answer = await dio.post<Object?>(
        Routes.votes,
        data: toVoteRequestWire(vote).toJson(),
        options: Options(
          headers: {
            HttpHeader.authorization.value: 'Bearer $token',
            HttpHeader.idempotencyKey.value: Uri.encodeComponent(
              vote.idempotencyKey,
            ),
          },
        ),
      );

      expect(answer.statusCode, equals(HttpStatusCode.noContent.code));
      expect(answer.headers.value(HttpHeader.contentLength.value), isNull);
    });

    test('reads an identifier that dio sends percent-encoded', () async {
      final (:dio, :world, lines: _, gate: _) = _aDio();
      world.load(
        ServerContent(
          meetings: [aMeetingWithAgenda().copyWith(id: aMeetingId('a/b c'))],
          recordedVotes: const [],
        ),
      );
      final token = await _signIn(dio, world.accounts.first.user.email);

      final answer = await dio.get<Map<String, dynamic>>(
        Routes.meeting('a/b c'),
        options: _as(token),
      );

      expect(answer.statusCode, equals(HttpStatusCode.ok.code));
      expect(answer.data!['id'], equals('a/b c'));
    });

    test(
      'hands a cursor with special characters back as it was written',
      () async {
        final (:dio, :world, lines: _, gate: _) = _aDio();
        final ids = ['a:b', 'c/d', 'e%20f', 'g h'];
        world.load(
          ServerContent(
            meetings: [
              for (final (index, id) in ids.indexed)
                aMeetingWithAgenda().copyWith(
                  id: aMeetingId(id),
                  agenda: [],
                  scheduledAt: at((index + 1) * millisPerDay),
                ),
            ],
            recordedVotes: const [],
          ),
        );
        final token = await _signIn(dio, world.accounts.first.user.email);

        final seen = <String>[];
        String? cursor;
        do {
          final page = await dio.get<Map<String, dynamic>>(
            Routes.meetings,
            queryParameters: {
              'period': 'upcoming',
              'limit': 1,
              'cursor': ?cursor,
            },
            options: _as(token),
          );
          seen.addAll([
            for (final item in page.data!['items'] as List<dynamic>)
              (item as Map<String, dynamic>)['id'] as String,
          ]);
          cursor = page.data!['nextCursor'] as String?;
        } while (cursor != null);

        expect(seen, equals(ids));
      },
    );

    test(
      'refuses a body above 64 KiB with 413, before the API reads it',
      () async {
        final (:dio, :world, lines: _, gate: _) = _aDio();

        final answer = await dio.post<Map<String, dynamic>>(
          Routes.signIn,
          data: {
            'email': world.accounts.first.user.email,
            'password': 'x' * (maxRequestBodyBytes + 1),
          },
        );

        expect(
          answer.statusCode,
          equals(HttpStatusCode.requestEntityTooLarge.code),
        );
        expect(
          answer.data,
          equals({
            'error': {'code': 'badRequest'},
          }),
        );
      },
    );

    test('accepts a body of exactly the size limit', () async {
      final (:dio, :world, lines: _, gate: _) = _aDio();
      final overhead = utf8
          .encode(
            jsonEncode({
              'email': world.accounts.first.user.email,
              'password': '',
            }),
          )
          .length;

      final answer = await dio.post<Map<String, dynamic>>(
        Routes.signIn,
        data: {
          'email': world.accounts.first.user.email,
          'password': 'x' * (maxRequestBodyBytes - overhead),
        },
      );

      // The body is read and refused for its credentials, not for its size.
      expect(answer.statusCode, equals(HttpStatusCode.unauthorized.code));
    });

    test(
      'ends a request the client cancels with a cancelled exception',
      () async {
        final (:dio, :world, lines: _, :gate) = _aDio();
        final token = await _signIn(dio, world.accounts.first.user.email);
        gate.held = Completer<void>();
        final cancel = CancelToken();

        final request = dio.get<Object?>(
          Routes.meeting('meeting-1'),
          options: _as(token),
          cancelToken: cancel,
        );
        await Future<void>.delayed(Duration.zero);
        cancel.cancel();

        await expectLater(
          request,
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        gate.held!.complete();
      },
    );

    test('ends a request that takes more than the receive timeout '
        'with a timeout exception', () async {
      final (:dio, :world, lines: _, :gate) = _aDio(
        receiveTimeout: const Duration(milliseconds: 20),
      );
      final token = await _signIn(dio, world.accounts.first.user.email);
      gate.held = Completer<void>();

      await expectLater(
        dio.get<Object?>(Routes.meeting('meeting-1'), options: _as(token)),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.receiveTimeout,
          ),
        ),
      );
      gate.held!.complete();
    });

    test('tells its logger the method, the path and the status of each '
        'request, without the query, the headers or the body', () async {
      final (:dio, :world, :lines, gate: _) = _aDio();
      final token = await _signIn(dio, world.accounts.first.user.email);

      await dio.get<Object?>(
        Routes.meetings,
        queryParameters: {'period': 'past', 'limit': 5, 'cursor': 'secret'},
        options: _as(token),
      );

      expect(lines, equals(['POST /auth/sign-in 200', 'GET /meetings 400']));
      expect(lines.join(' '), isNot(contains(token)));
    });

    test('keeps serving when its logger fails', () async {
      final world = createHttpServerSide(InstalledFixtureServer());
      final dio = Dio(BaseOptions(baseUrl: testApiUrl))
        ..httpClientAdapter = FixtureServerAdapter(
          world.api,
          logger: (line) => throw StateError('a logger that fails'),
        );

      final token = await _signIn(dio, world.accounts.first.user.email);

      expect(token, isNotEmpty);
    });

    test(
      'answers 500 when the API itself fails, instead of throwing',
      () async {
        final world = createHttpServerSide(InstalledFixtureServer());
        final failing = MockApi(
          MockApiOptions(
            backend: world.backend,
            clock: world.clock,
            accounts: world.accounts,
            sessionLifetime: aDuration(millisPerHour),
            generateToken: () => throw StateError('no randomness'),
          ),
        );
        final dio = Dio(
          BaseOptions(baseUrl: testApiUrl, validateStatus: (status) => true),
        )..httpClientAdapter = FixtureServerAdapter(failing);

        final answer = await dio.post<Map<String, dynamic>>(
          Routes.signIn,
          data: {
            'email': world.accounts.first.user.email,
            'password': testPassword,
          },
        );

        expect(
          answer.statusCode,
          equals(HttpStatusCode.internalServerError.code),
        );
        expect(
          answer.data,
          equals({
            'error': {'code': 'unexpected'},
          }),
        );
      },
    );

    test('is closed without effect', () {
      final world = createHttpServerSide(InstalledFixtureServer());

      expect(
        () => FixtureServerAdapter(world.api).close(force: true),
        returnsNormally,
      );
    });
  });
}
