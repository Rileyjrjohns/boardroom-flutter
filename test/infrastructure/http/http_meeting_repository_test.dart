import 'dart:convert';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/infrastructure/http/protocol.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import '../support/http_adapters_world.dart';
import '../support/http_world.dart';

// The two things the contract suite of MeetingRepository does not say about
// the HTTP adapter: what it sends, and what it makes of an answer that has the
// shape of the API but breaks a rule of the domain. React Native has no test
// file for the repository; its contract suite and the client tests go through
// it.

void main() {
  final installed = installFixtureServer();

  /// The server sends [body] as JSON with the [status], whatever the request.
  void serverSends(Object body, {int status = 200}) {
    installed.answerWith = (_) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        HttpHeader.contentType.value: [mediaTypeJson],
      },
    );
  }

  group('HttpMeetingRepository, what it sends', () {
    test('asks for a page of a period with the limit, and for the next one '
        'with the cursor it was given', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();

      await world.meetings.list(
        MeetingPeriod.past,
        const PageRequest(limit: 5, cursor: '1:meeting a/b' as PageCursor),
      );
      await world.meetings.list(
        MeetingPeriod.upcoming,
        unwrap(createPageRequest(limit: 7)),
      );

      expect(
        installed.received,
        equals([
          'GET $testApiUrl/meetings?period=past&limit=5&cursor=1%3Ameeting%20a%2Fb',
          'GET $testApiUrl/meetings?period=upcoming&limit=7',
        ]),
      );
    });

    test('asks for a meeting by its percent-encoded id', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      installed.received.clear();

      await world.meetings.get(aMeetingId('meeting 1/a'));

      expect(
        installed.received,
        equals(['GET $testApiUrl/meetings/meeting%201%2Fa']),
      );
    });
  });

  group('HttpMeetingRepository, an answer that is not what the API '
      'promises', () {
    test('a page of the wrong shape is unexpected, and the monitoring is told '
        'where it broke the schema', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends({'items': 'none'});

      final answer = await world.meetings.list(
        MeetingPeriod.upcoming,
        unwrap(createPageRequest(limit: 5)),
      );

      expect(answer, equals(err(unexpected('invalid response'))));
      expect(
        world.monitoring.errors.single.attributes,
        equals({
          LogAttribute.resource: 'meetingPage',
          LogAttribute.issuePaths: 'items',
        }),
      );
    });

    test('a page that breaks a rule of the domain is unexpected, and the '
        'monitoring is told the rule, not the value', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends({
        'items': [
          {
            'id': 'meeting-1',
            'title': '   ',
            'scheduledAt': '2030-01-01T00:00:00.000Z',
            'location': 'Boardroom',
          },
        ],
      });

      final answer = await world.meetings.list(
        MeetingPeriod.upcoming,
        unwrap(createPageRequest(limit: 5)),
      );

      expect(answer, equals(err(unexpected('invalid response'))));
      expect(
        world.monitoring.errors.single.error,
        equals(validationError(ValidationField.title, ValidationRule.required)),
      );
      expect(
        world.monitoring.errors.single.attributes,
        equals({LogAttribute.resource: 'meetingPage'}),
      );
    });

    test('a meeting of the wrong shape is unexpected, and the monitoring is '
        'told where it broke the schema', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends({'id': 'meeting-1'});

      final answer = await world.meetings.get(aMeetingId());

      expect(answer, equals(err(unexpected('invalid response'))));
      expect(
        world.monitoring.errors.single.attributes?[LogAttribute.resource],
        equals('meeting'),
      );
    });

    test('a meeting that breaks a rule of the domain is unexpected', () async {
      final world = createHttpWorld(installed);
      await world.signInAs(aUserId());
      serverSends({
        'id': 'meeting-1',
        'title': '   ',
        'scheduledAt': '2030-01-01T00:00:00.000Z',
        'location': 'Boardroom',
        'agenda': <Object>[],
        'documents': <Object>[],
        'participants': <Object>[],
      });

      final answer = await world.meetings.get(aMeetingId());

      expect(answer, equals(err(unexpected('invalid response'))));
      expect(
        world.monitoring.capturedEvents(),
        equals([MonitoringEvent.responseInvalid]),
      );
    });
  });
}
