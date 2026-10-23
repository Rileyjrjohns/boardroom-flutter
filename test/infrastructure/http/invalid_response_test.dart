import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/infrastructure/http/invalid_response.dart';
import 'package:test/test.dart';

import '../../application/support/fake_monitoring.dart';

// How an answer that does not have the shape of the API is reported: React
// Native has no test file for it, the client and the repositories go through
// it.

void main() {
  group('schemaViolation', () {
    test('is unexpected, and tells the monitoring where the body broke the '
        'schema', () {
      final monitoring = FakeMonitoring();

      final error = schemaViolation(
        monitoring,
        HttpResource.meetingPage,
        'agenda.0.status',
      );

      expect(error, equals(unexpected('invalid response')));
      expect(
        monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.responseInvalid,
            error: unexpected('invalid response'),
            attributes: {
              LogAttribute.resource: 'meetingPage',
              LogAttribute.issuePaths: 'agenda.0.status',
            },
          ),
        ]),
      );
    });
  });

  group('domainViolation', () {
    test('is unexpected, and tells the monitoring the rule that was broken, '
        'not the value', () {
      final monitoring = FakeMonitoring();
      final violation = validationError(
        ValidationField.title,
        ValidationRule.required,
      );

      final error = domainViolation(
        monitoring,
        HttpResource.session,
        violation,
      );

      expect(error, equals(unexpected('invalid response')));
      expect(
        monitoring.errors,
        equals([
          ErrorRecord(
            event: MonitoringEvent.responseInvalid,
            error: violation,
            attributes: {LogAttribute.resource: 'session'},
          ),
        ]),
      );
    });
  });

  group('contentViolation and identityViolation', () {
    for (final violation in ContentViolation.values) {
      test(
        'tell the monitoring why a file was refused: ${violation.value}',
        () {
          final monitoring = FakeMonitoring();

          final error = contentViolation(
            monitoring,
            HttpResource.documentContent,
            violation,
          );

          expect(error, equals(unexpected('invalid response')));
          expect(
            monitoring.errors.single.attributes,
            equals({
              LogAttribute.resource: 'documentContent',
              LogAttribute.reason: violation.value,
            }),
          );
        },
      );
    }

    test('tell the monitoring which rule an answer broke, and neither '
        'identifier', () {
      final monitoring = FakeMonitoring();

      final error = identityViolation(
        monitoring,
        HttpResource.document,
        IdentityViolation.otherItem,
      );

      expect(error, equals(unexpected('invalid response')));
      expect(
        monitoring.errors.single.attributes,
        equals({
          LogAttribute.resource: 'document',
          LogAttribute.reason: 'otherItem',
        }),
      );
    });
  });

  group('HttpResource', () {
    test('has the stable names of the logs', () {
      expect(
        [for (final resource in HttpResource.values) resource.value],
        equals([
          'session',
          'meetingPage',
          'meeting',
          'document',
          'documentContent',
          'vote',
        ]),
      );
    });
  });
}
