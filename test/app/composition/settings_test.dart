import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:test/test.dart';

import '../../support/builders/builders.dart';

// The scenarios of `config.test.ts` (the defaults of the "Settings" table of
// docs/spec/use-cases.md). The simulated latency is compared with the cap of
// the simulated network in test/app/container/settings_test.dart, which may
// import that part of the app.

const int _millisPerSecond = 1000;

void main() {
  group('the configuration values', () {
    test('are the ones the documents of docs/ and the comments of the module '
        'give', () {
      expect(maxCacheAge, equals(7 * millisPerDay));
      expect(maxVoteDeliveryAttempts, equals(5));
      expect(appLockGracePeriod, equals(30 * _millisPerSecond));
      expect(sessionCheckInterval, equals(30 * _millisPerSecond));
      expect(meetingsPageSize, equals(10));
      expect(devSimulatedLatency, equals(400));
      expect(devSessionLifetime, equals(8 * millisPerHour));
      expect(devStartsSignedIn, isFalse);
      expect(httpRequestTimeout, equals(15 * _millisPerSecond));
      expect(documentDownloadTimeout, equals(60 * _millisPerSecond));
      expect(allowDevicePasscodeFallback, isFalse);
    });

    test('keep the request timeout of the API within the bounds the '
        'configuration accepts', () {
      expect(minHttpRequestTimeout, lessThanOrEqualTo(httpRequestTimeout));
      expect(httpRequestTimeout, lessThanOrEqualTo(maxHttpRequestTimeout));
      expect(documentDownloadTimeout, lessThanOrEqualTo(maxHttpRequestTimeout));
    });

    test('name the file of the database the way the devices already have '
        'it', () {
      // Stored on the device: changing it would leave every installed app with
      // an orphan file.
      expect(databaseName, equals('boardroom.db'));
    });

    test('give a page size that the domain accepts in a page request, below '
        'its maximum', () {
      expect(meetingsPageSize, lessThanOrEqualTo(maxPageLimit));
      expect(
        createPageRequest(limit: meetingsPageSize),
        isA<Ok<Object?, Object?>>(),
      );
    });

    test('keep the app locked for a shorter time than a session lasts, and a '
        'session shorter than a copy kept offline', () {
      expect(appLockGracePeriod, lessThan(devSessionLifetime));
      expect(devSessionLifetime, lessThan(maxCacheAge));
    });

    test('allow more than one attempt to deliver a vote', () {
      expect(maxVoteDeliveryAttempts, greaterThan(1));
    });
  });
}
