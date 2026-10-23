import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_auth_session.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import 'http_world.dart';
import 'test_server.dart';

// The support code of the HTTP tests behaves the way the tests that use it rely
// on: it records what the server received, cuts the network, delays or stops
// the answers, and forgets all of it after each test.

void main() {
  final installed = installFixtureServer();
  final dio = Dio(
    BaseOptions(baseUrl: testApiUrl, validateStatus: (status) => true),
  )..httpClientAdapter = installed;

  Future<Response<Map<String, dynamic>>> signIn(HttpServerSide world) =>
      dio.post<Map<String, dynamic>>(
        Routes.signIn,
        data: {
          'email': world.accounts.first.user.email,
          'password': testPassword,
        },
      );

  group('installFixtureServer', () {
    test('answers for the API of the world created last', () async {
      final world = createHttpServerSide(installed);

      final answer = await signIn(world);

      expect(answer.statusCode, equals(HttpStatusCode.ok.code));
      expect(answer.data!['accessToken'], equals('token-1'));
    });

    test('records the requests it received, and their headers', () async {
      final world = createHttpServerSide(installed);

      await signIn(world);

      expect(installed.received, equals(['POST $testApiUrl${Routes.signIn}']));
      expect(
        installed.receivedHeader(0, 'content-type'),
        contains('application/json'),
      );
    });

    test('forgets what it recorded after each test', () {
      expect(installed.received, isEmpty);
      expect(installed.receivedHeaders, isEmpty);
    });

    test('fails the way a request without a network does when the device '
        'is offline', () async {
      final world = createHttpServerSide(installed);
      installed.conditions.online = false;

      await expectLater(
        signIn(world),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.connectionError,
          ),
        ),
      );
    });

    test('is back online after each test', () {
      expect(installed.conditions.online, isTrue);
    });

    test('fails the same way before any world exists', () async {
      installed.api = null;

      await expectLater(
        dio.get<Object?>(Routes.meetings),
        throwsA(isA<DioException>()),
      );
    });

    test('waits the delay it is told to before it answers', () async {
      final world = createHttpServerSide(installed);
      installed.conditions.delayMillis = 30;
      final watch = Stopwatch()..start();

      await signIn(world);

      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(25));
    });

    test(
      'never answers when it is told to, and the timeout ends the request',
      () async {
        final world = createHttpServerSide(installed);
        installed.conditions.neverAnswers = true;

        await expectLater(
          dio.post<Object?>(
            Routes.signIn,
            data: {
              'email': world.accounts.first.user.email,
              'password': testPassword,
            },
            options: Options(receiveTimeout: const Duration(milliseconds: 20)),
          ),
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.receiveTimeout,
            ),
          ),
        );
      },
    );

    test('sends what the test makes it send instead of the API', () async {
      createHttpServerSide(installed);
      installed.answerWith = (options) => ResponseBody.fromString(
        'not a PDF',
        HttpStatusCode.ok.code,
        headers: {
          HttpHeader.contentType.value: [mediaTypePdf],
        },
      );

      final answer = await dio.get<String>(
        Routes.documentContent('document-1'),
      );

      expect(answer.data, equals('not a PDF'));
    });

    test('refuses a request to anywhere else, so that nothing reaches a real '
        'network by mistake', () {
      expect(
        () => installed.fetch(
          RequestOptions(path: 'https://example.com/'),
          null,
          null,
        ),
        throwsStateError,
      );
    });
  });

  group('createHttpServerSide', () {
    test('has nobody signed in, and the two accounts of the test server', () {
      final world = createHttpServerSide(installed);

      expect(world.accounts.map((account) => account.user.id), [
        'user-1',
        'user-2',
      ]);
      expect(world.server.auth, isA<InMemoryAuthSession>());
    });

    test('grants tokens that are numbered, one per sign-in', () async {
      final world = createHttpServerSide(installed);

      await signIn(world);
      final second = await signIn(world);

      expect(second.data!['accessToken'], equals('token-2'));
    });

    test('lets a test add an account the server then knows', () async {
      final world = createHttpServerSide(installed);
      world.accounts.add(
        DemoAccount(
          user: aUser(id: aUserId('user-7'), email: anEmail('u7@example.com')),
          password: testPassword,
        ),
      );

      final answer = await dio.post<Map<String, dynamic>>(
        Routes.signIn,
        data: {'email': 'u7@example.com', 'password': testPassword},
      );

      expect(answer.statusCode, equals(HttpStatusCode.ok.code));
      expect(
        (answer.data!['user'] as Map<String, dynamic>)['id'],
        equals('user-7'),
      );
    });
  });
}
