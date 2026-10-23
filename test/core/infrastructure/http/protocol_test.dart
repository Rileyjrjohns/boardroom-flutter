import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:test/test.dart';

// The constants of the API are shared by the client and by the simulated
// server. React Native has no test file of its own for them (the client and
// the server tests cover them); these tests are listed in
// docs/parity/infrastructure.md.

void main() {
  group('the routes of the API', () {
    test('are the ones of docs/api.md', () {
      expect(Routes.signIn, equals('/auth/sign-in'));
      expect(Routes.meetings, equals('/meetings'));
      expect(Routes.votes, equals('/votes'));
      expect(Routes.meeting('m-1'), equals('/meetings/m-1'));
      expect(Routes.document('d-1'), equals('/documents/d-1'));
      expect(Routes.documentContent('d-1'), equals('/documents/d-1/content'));
    });

    test('percent-encode an identifier, which is opaque and free text', () {
      expect(
        Routes.meeting('a/b c?d#e'),
        equals('/meetings/a%2Fb%20c%3Fd%23e'),
      );
      expect(
        Routes.documentContent('../x'),
        equals('/documents/..%2Fx/content'),
      );
      expect(Routes.document('café'), equals('/documents/caf%C3%A9'));
    });

    test('have as many segments as the server expects', () {
      int segments(String path) =>
          path.split('/').where((s) => s.isNotEmpty).length;

      expect(segments(Routes.meetings), equals(SegmentCount.collection));
      expect(segments(Routes.meeting('m')), equals(SegmentCount.item));
      expect(
        segments(Routes.documentContent('d')),
        equals(SegmentCount.action),
      );
    });
  });

  group('the constants of the protocol', () {
    test('name the headers, the methods and the media types of the API', () {
      expect(
        HttpMethod.values.map((method) => method.value),
        equals(['GET', 'HEAD', 'POST']),
      );
      expect(HttpHeader.eTag.value, equals('ETag'));
      expect(HttpHeader.idempotencyKey.value, equals('Idempotency-Key'));
      expect(mediaTypeJson, equals('application/json'));
      expect(mediaTypePdf, equals('application/pdf'));
      expect(cacheControlNoStore, equals('no-store'));
      expect(bearerPrefix, equals('Bearer '));
    });

    test('limit an answer to 2 MiB and a document to 20 MiB', () {
      expect(maxResponseBytes, equals(2 * 1024 * 1024));
      expect(maxDocumentBytes, equals(20 * 1024 * 1024));
    });

    test('treat the statuses of an outage as a network that failed', () {
      expect(transientStatuses, equals([408, 429, 502, 503, 504]));
    });

    test('keep the numbers of the statuses', () {
      expect(HttpStatusCode.unprocessableContent.code, equals(422));
      expect(HttpStatusCode.ok.code, equals(200));
    });
  });
}
