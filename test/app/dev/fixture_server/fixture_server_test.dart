import 'package:boardroom/app/dev/fixture_server/fixture_server.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/features/auth/infrastructure/http_auth_session.dart';
import 'package:boardroom/features/auth/infrastructure/session_vault.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/infrastructure/http_meeting_repository.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/infrastructure/dto/vote_dto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_clock.dart';
import '../../../support/fakes/fake_monitoring.dart';
import '../../../support/infrastructure/fixture_files.dart';
import '../../../support/infrastructure/http_world.dart';
import '../../../support/infrastructure/memory_secure_storage.dart';
import '../../../support/infrastructure/sleep.dart';
import '../../../support/infrastructure/test_server.dart';

// The fixture server as the development build builds it, with a real `Dio` in
// front of it: the HTTP adapters of the app run against these files, shifted to
// the clock.

const int _secondsPerHour = 3600;

Future<FixtureServer> _aServer({
  FakeClock? clock,
  String Function()? generateToken,
  RequestLogger? onRequest,
}) async {
  final created = await FixtureServer.create(
    clock: clock ?? FakeClock(),
    sleep: immediateSleep,
    files: readFixtureFiles(),
    generateToken: generateToken ?? randomToken,
    onRequest: onRequest,
  );
  return switch (created) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.detail),
  };
}

Dio _dioOf(FixtureServer server) => Dio(
  BaseOptions(
    baseUrl: 'http://api.boardroom.test',
    validateStatus: (_) => true,
  ),
)..httpClientAdapter = server.adapter;

Future<String> _signIn(Dio dio, FixtureServer server) async {
  final answer = await dio.post<Map<String, dynamic>>(
    Routes.signIn,
    data: {'email': server.accounts.first.user.email, 'password': demoPassword},
  );
  return answer.data!['accessToken'] as String;
}

Options _as(String token) =>
    Options(headers: {HttpHeader.authorization.value: 'Bearer $token'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the fixture server', () {
    test('lets the demo user sign in with the password of the simulation, '
        'for the lifetime of a working day', () async {
      final server = await _aServer();
      final dio = _dioOf(server);

      final answer = await dio.post<Map<String, dynamic>>(
        Routes.signIn,
        data: {
          'email': server.accounts.first.user.email,
          'password': demoPassword,
        },
      );

      expect(answer.statusCode, equals(HttpStatusCode.ok.code));
      expect(answer.data!['tokenType'], equals('Bearer'));
      expect(answer.data!['expiresIn'], equals(8 * _secondsPerHour));
      expect(
        (answer.data!['user'] as Map<String, dynamic>)['email'],
        equals(server.accounts.first.user.email),
      );
    });

    test('refuses another password', () async {
      final server = await _aServer();

      final answer = await _dioOf(server).post<Map<String, dynamic>>(
        Routes.signIn,
        data: {
          'email': server.accounts.first.user.email,
          'password': 'not-the-password',
        },
      );

      expect(answer.statusCode, equals(HttpStatusCode.unauthorized.code));
    });

    test('serves the 24 upcoming meetings of the fixtures, soonest first, '
        'and the 42 past ones, latest first, a page at a time', () async {
      final server = await _aServer();
      final dio = _dioOf(server);
      final token = await _signIn(dio, server);

      Future<List<Map<String, dynamic>>> every(String period) async {
        final items = <Map<String, dynamic>>[];
        String? cursor;
        do {
          final page = await dio.get<Map<String, dynamic>>(
            Routes.meetings,
            queryParameters: {'period': period, 'limit': 10, 'cursor': ?cursor},
            options: _as(token),
          );
          items.addAll(
            (page.data!['items'] as List<dynamic>).cast<Map<String, dynamic>>(),
          );
          cursor = page.data!['nextCursor'] as String?;
        } while (cursor != null);
        return items;
      }

      final upcoming = await every('upcoming');
      final past = await every('past');

      expect(upcoming, hasLength(24));
      expect(past, hasLength(42));
      final upcomingTimes = [
        for (final item in upcoming)
          DateTime.parse(item['scheduledAt'] as String),
      ];
      final soonestFirst = List.of(upcomingTimes)..sort();
      expect(upcomingTimes, orderedEquals(soonestFirst));
      final pastTimes = [
        for (final item in past) DateTime.parse(item['scheduledAt'] as String),
      ];
      final latestFirst = List.of(pastTimes)
        ..sort((first, second) => second.compareTo(first));
      expect(pastTimes, orderedEquals(latestFirst));
    });

    test(
      'serves a meeting of the demo user with the votes they cast',
      () async {
        final server = await _aServer();
        final dio = _dioOf(server);
        final token = await _signIn(dio, server);

        final answer = await dio.get<Map<String, dynamic>>(
          Routes.meeting('meeting-001'),
          options: _as(token),
        );

        final agenda = (answer.data!['agenda'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(answer.statusCode, equals(HttpStatusCode.ok.code));
        expect(
          agenda.any(
            (item) =>
                (item['resolution']
                    as Map<String, dynamic>?)?['recordedVote'] !=
                null,
          ),
          isTrue,
        );
      },
    );

    test('records a vote once, as the API says: 204 again for the same vote, '
        'and 422 alreadyVoted for another choice', () async {
      final server = await _aServer();
      final dio = _dioOf(server);
      final token = await _signIn(dio, server);
      final meeting = (await dio.get<Map<String, dynamic>>(
        Routes.meeting('meeting-001'),
        options: _as(token),
      )).data!;
      final open = (meeting['agenda'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((item) => item['resolution'] as Map<String, dynamic>?)
          .firstWhere(
            (resolution) =>
                resolution != null &&
                resolution['status'] == 'open' &&
                resolution['recordedVote'] == null,
          )!;
      final userId = server.accounts.first.user.id;

      Future<Response<Map<String, dynamic>>> cast(VoteChoice choice) {
        final vote = aVote(
          resolutionId: aResolutionId(open['id'] as String),
          meetingId: aMeetingId('meeting-001'),
          voterId: userId,
          choice: choice,
        );
        return dio.post<Map<String, dynamic>>(
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
      }

      expect(
        (await cast(VoteChoice.forChoice)).statusCode,
        equals(HttpStatusCode.noContent.code),
      );
      expect(
        (await cast(VoteChoice.forChoice)).statusCode,
        equals(HttpStatusCode.noContent.code),
      );
      final other = await cast(VoteChoice.against);
      expect(
        other.statusCode,
        equals(HttpStatusCode.unprocessableContent.code),
      );
      expect(
        other.data,
        equals({
          'error': {
            'code': VotingErrorCode.alreadyVoted.value,
            'source': 'recorded',
          },
        }),
      );
    });

    test('serves the content of a document as a PDF', () async {
      final server = await _aServer();
      final dio = _dioOf(server);
      final token = await _signIn(dio, server);
      final meeting = (await dio.get<Map<String, dynamic>>(
        Routes.meeting('meeting-001'),
        options: _as(token),
      )).data!;
      final document =
          (meeting['documents'] as List<dynamic>).first as Map<String, dynamic>;

      final content = await dio.get<List<int>>(
        Routes.documentContent(document['id'] as String),
        options: _as(token).copyWith(responseType: ResponseType.bytes),
      );

      expect(content.statusCode, equals(HttpStatusCode.ok.code));
      expect(
        content.headers.value(HttpHeader.contentType.value),
        equals('application/pdf'),
      );
      expect(String.fromCharCodes(content.data!.take(5)), equals('%PDF-'));
    });

    test(
      'answers 503 to everything while its simulated network is cut',
      () async {
        final server = await _aServer();
        final dio = _dioOf(server);
        final token = await _signIn(dio, server);
        server.backend.network.setOnline(online: false);

        final answer = await dio.get<Map<String, dynamic>>(
          Routes.meeting('meeting-001'),
          options: _as(token),
        );

        expect(
          answer.statusCode,
          equals(HttpStatusCode.serviceUnavailable.code),
        );
      },
    );

    test(
      'ends the session of a token when its lifetime is over on the clock',
      () async {
        final clock = FakeClock();
        final server = await _aServer(clock: clock);
        final dio = _dioOf(server);
        final token = await _signIn(dio, server);

        clock.advance(8 * millisPerHour);

        final answer = await dio.get<Map<String, dynamic>>(
          Routes.meeting('meeting-001'),
          options: _as(token),
        );
        expect(answer.statusCode, equals(HttpStatusCode.unauthorized.code));
      },
    );

    test('shifts the fixtures to the clock it is built with', () async {
      final clock = FakeClock(at(400 * millisPerDay));
      final server = await _aServer(clock: clock);
      final dio = _dioOf(server);
      final token = await _signIn(dio, server);

      final answer = await dio.get<Map<String, dynamic>>(
        Routes.meetings,
        queryParameters: {'period': 'upcoming', 'limit': 50},
        options: _as(token),
      );

      expect((answer.data!['items'] as List<dynamic>).length, equals(24));
    });

    test(
      'logs each request without the token, and keeps the password out',
      () async {
        final lines = <String>[];
        final server = await _aServer(onRequest: lines.add);
        final dio = _dioOf(server);

        final token = await _signIn(dio, server);
        await dio.get<Object?>(
          Routes.meeting('meeting-001'),
          options: _as(token),
        );

        expect(
          lines,
          equals(['POST /auth/sign-in 200', 'GET /meetings/meeting-001 200']),
        );
        expect(lines.join(), isNot(contains(token)));
        expect(lines.join(), isNot(contains(demoPassword)));
      },
    );
  });

  group('FixtureServer.create', () {
    test(
      'reads the fixtures bundled with the app when it is given none',
      () async {
        final created = await FixtureServer.create(
          clock: FakeClock(),
          sleep: immediateSleep,
        );

        expect(created, isA<Ok<FixtureServer, FixtureServerError>>());
        expect(
          (created as Ok<FixtureServer, FixtureServerError>).value.accounts,
          hasLength(2),
        );
      },
    );

    test('serves the HTTP adapters of the app, composed as the development '
        'build composes them, with the bundled fixtures shifted to the clock '
        'and the simulated latency not waited for', () async {
      final clock = FakeClock(at(400 * millisPerDay));
      final created = await FixtureServer.create(
        clock: clock,
        sleep: immediateSleep,
      );
      final server = (created as Ok<FixtureServer, FixtureServerError>).value;
      final monitoring = FakeMonitoring();
      final vault = SessionVault(
        storage: MemorySecureStorage(),
        monitoring: monitoring,
      );
      final client = HttpClient(
        HttpClientOptions(
          baseUrl: testApiUrl,
          timeout: aDuration(5000),
          tokens: vault,
          monitoring: monitoring,
          adapter: server.adapter,
        ),
      );
      final auth = HttpAuthSession(
        HttpAuthSessionOptions(
          client: client,
          vault: vault,
          clock: clock,
          monitoring: monitoring,
        ),
      );
      final meetings = HttpMeetingRepository(client, monitoring);

      final signedIn = await auth.signIn(credentialsOf(server.accounts.first));
      final upcoming = await meetings.list(
        MeetingPeriod.upcoming,
        unwrap(createPageRequest(limit: 50)),
      );
      final past = await meetings.list(
        MeetingPeriod.past,
        unwrap(createPageRequest(limit: 50)),
      );

      expect(
        unwrap(signedIn).user.email,
        equals(server.accounts.first.user.email),
      );
      final upcomingItems = unwrap(upcoming).items;
      final pastItems = unwrap(past).items;
      expect(upcomingItems, hasLength(24));
      expect(pastItems, hasLength(42));
      expect(
        upcomingItems.every((meeting) => meeting.scheduledAt > clock.now()),
        isTrue,
      );
      expect(
        pastItems.every((meeting) => meeting.scheduledAt <= clock.now()),
        isTrue,
      );
      expect(monitoring.errors, isEmpty);
    });

    test('says why it cannot be built when the clock leaves no room '
        'for the past meetings', () async {
      final created = await FixtureServer.create(
        clock: FakeClock(at(-now + 1000)),
        sleep: immediateSleep,
        files: readFixtureFiles(),
      );

      expect(created, isA<Err<FixtureServer, FixtureServerError>>());
      expect(
        (created as Err<FixtureServer, FixtureServerError>).error.detail,
        contains('meetings.json'),
      );
    });

    test('waits 200 milliseconds for each request by default', () async {
      final (:sleep, :requested) = recordingSleep();
      final created = await FixtureServer.create(
        clock: FakeClock(),
        sleep: sleep,
        files: readFixtureFiles(),
      );
      final server = (created as Ok<FixtureServer, FixtureServerError>).value;
      final dio = _dioOf(server);

      await _signIn(dio, server);

      expect(requested, equals([200]));
      expect(defaultLatency, equals(200));
    });

    test('takes the latency and the lifetime it is given', () async {
      final (:sleep, :requested) = recordingSleep();
      final created = await FixtureServer.create(
        clock: FakeClock(),
        sleep: sleep,
        files: readFixtureFiles(),
        latency: aDuration(750),
        sessionLifetime: aDuration(90 * 1000),
      );
      final server = (created as Ok<FixtureServer, FixtureServerError>).value;
      final dio = _dioOf(server);

      final answer = await dio.post<Map<String, dynamic>>(
        Routes.signIn,
        data: {
          'email': server.accounts.first.user.email,
          'password': demoPassword,
        },
      );

      expect(requested, equals([750]));
      expect(answer.data!['expiresIn'], equals(90));
    });

    test('grants the tokens it is given', () async {
      final server = await _aServer(generateToken: () => 'a-token');
      final dio = _dioOf(server);

      expect(await _signIn(dio, server), equals('a-token'));
    });

    test('has a session lifetime of a working day', () {
      expect(defaultSessionLifetime, equals(8 * millisPerHour));
    });
  });

  group('randomToken', () {
    test(
      'is made of visible ASCII characters only, so it can go in a header',
      () {
        final token = randomToken();

        expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      },
    );

    test('is not the same twice', () {
      expect(randomToken(), isNot(equals(randomToken())));
    });
  });
}
