import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/infrastructure/http/gateway_errors.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:test/test.dart';

// What a failure of the client becomes for a call that addresses no item (a
// listing, a vote) and for one that addresses an item. React Native has no test
// file for it: the repositories' tests go through it.

void main() {
  group('asGatewayError', () {
    for (final error in <GatewayError>[
      networkUnavailable(),
      unauthorized(),
      unexpected('status 500'),
    ]) {
      test('keeps ${error.code}', () {
        expect(asGatewayError(RequestFailed(error)), equals(error));
      });
    }

    test('turns a 403 into unexpected, with the status as its only cause', () {
      expect(
        asGatewayError(RequestFailed(forbidden())),
        equals(unexpected('status 403')),
      );
    });

    test('turns a 404 into unexpected, with the status as its only cause', () {
      expect(
        asGatewayError(RequestFailed(notFound())),
        equals(unexpected('status 404')),
      );
    });

    test('turns a rejection into unexpected, with the status as its only '
        'cause', () {
      expect(
        asGatewayError(const RequestRejected({'code': 'resolutionClosed'})),
        equals(unexpected('status 422')),
      );
    });
  });

  group('asRepositoryError', () {
    for (final error in <RepositoryError>[
      forbidden(),
      notFound(),
      networkUnavailable(),
      unauthorized(),
      unexpected('status 500'),
    ]) {
      test('keeps ${error.code}', () {
        expect(asRepositoryError(RequestFailed(error)), equals(error));
      });
    }

    test('turns a rejection into unexpected, with the status as its only '
        'cause', () {
      expect(
        asRepositoryError(const RequestRejected(null)),
        equals(unexpected('status 422')),
      );
    });
  });
}
