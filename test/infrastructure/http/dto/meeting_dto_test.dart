import 'dart:convert';

import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:boardroom/infrastructure/http/dto/meeting_dto.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/in_memory/fixtures/load_fixtures.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/fixture_files.dart';

/// A value through JSON, the way it travels.
Object? _overTheWire(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value));

final Map<String, Object?> _summary = toMeetingSummaryWire(aMeetingSummary())
    .toJson();
final Map<String, Object?> _meeting = toMeetingWire(aMeetingWithAgenda())
    .toJson();

typedef _Json = Map<String, dynamic>;

/// The wire of a meeting with [change] applied to a copy of it.
Object? _changed(void Function(_Json wire) change) {
  final copy = jsonDecode(jsonEncode(_meeting)) as _Json;
  change(copy);
  return copy;
}

List<_Json> _list(_Json wire, String name) =>
    (wire[name] as List<dynamic>).cast<_Json>();

_Json _item(_Json wire, int position) => _list(wire, 'agenda')[position];

_Json _resolutionOf(_Json item) => item['resolution'] as _Json;

Result<MeetingSummaryWire, WireFailure> _parseSummary(Object? json) =>
    decodeWire(json, MeetingSummaryWire.fromJson);

Result<MeetingWire, WireFailure> _parseMeeting(Object? json) =>
    decodeWire(json, MeetingWire.fromJson);

Result<MeetingPageWire, WireFailure> _parsePage(Object? json) =>
    decodeWire(json, MeetingPageWire.fromJson);

void main() {
  group('the meeting schemas', () {
    group('a summary', () {
      test(
        'reads the wire of a summary, and ignores the fields it does not know',
        () {
          final parsed = unwrap(
            _parseSummary({
              ..._summary,
              'extra': 'ignored',
              'nested': {'a': 1},
            }),
          );

          expect(parsed.id, equals('meeting-1'));
          expect(parsed.title, equals('Board of directors'));
          expect(parsed.scheduledAt, equals(now + 24 * 3600000));
          expect(parsed.location, equals('Room 1'));
        },
      );

      for (final field in _summary.keys) {
        test('fails when $field is missing', () {
          final rest = {..._summary}..remove(field);

          expect(_parseSummary(rest), equals(err(WireFailure(field))));
        });
      }

      for (final (field, value) in <(String, Object?)>[
        ('id', 12),
        ('title', null),
        ('scheduledAt', 1900000000000),
        ('scheduledAt', '2030-03-17'),
        ('location', ['Room 1']),
      ]) {
        test('fails when $field is ${jsonEncode(value)}', () {
          expect(
            _parseSummary({..._summary, field: value}),
            isA<Err<Object?, WireFailure>>(),
          );
        });
      }

      for (final value in <Object?>[null, 'text', 12, <Object?>[]]) {
        test('fails for ${jsonEncode(value)} instead of an object', () {
          expect(_parseSummary(value), isA<Err<Object?, WireFailure>>());
        });
      }

      test('fails for undefined instead of an object', () {
        expect(_parseSummary(null), isA<Err<Object?, WireFailure>>());
      });
    });

    group('a meeting', () {
      test('reads the wire of a meeting with its agenda, its '
          'documents and its participants', () {
        expect(
          _parseMeeting(_overTheWire(_meeting)),
          isA<Ok<Object?, WireFailure>>(),
        );
      });

      for (final field in ['agenda', 'documents', 'participants']) {
        test('fails when $field is missing or not a list', () {
          expect(
            _parseMeeting(_changed((wire) => wire.remove(field))),
            isA<Err<Object?, WireFailure>>(),
          );
          expect(
            _parseMeeting(_changed((wire) => wire[field] = 'none')),
            isA<Err<Object?, WireFailure>>(),
          );
          expect(
            _parseMeeting(_changed((wire) => wire[field] = null)),
            isA<Err<Object?, WireFailure>>(),
          );
        });
      }

      for (final (name, change, path)
          in <(String, void Function(_Json wire), String)>[
            (
              'an agenda item without a title',
              (wire) => _item(wire, 1).remove('title'),
              'agenda.1.title',
            ),
            (
              'an agenda item with a position that is text',
              (wire) => _item(wire, 1)['position'] = '2',
              'agenda.1.position',
            ),
            (
              'a resolution without a status',
              (wire) => _resolutionOf(_item(wire, 1)).remove('status'),
              'agenda.1.resolution.status',
            ),
            (
              'a resolution whose closing time is not an instant',
              (wire) => _resolutionOf(_item(wire, 1))['closesAt'] = 'tomorrow',
              'agenda.1.resolution.closesAt',
            ),
            (
              'a document without a page count',
              (wire) => _list(wire, 'documents')[0].remove('pageCount'),
              'documents.0.pageCount',
            ),
            (
              'a document with a page count that is text',
              (wire) => _list(wire, 'documents')[0]['pageCount'] = '3',
              'documents.0.pageCount',
            ),
            (
              'a participant without a role',
              (wire) => _list(wire, 'participants')[0].remove('role'),
              'participants.0.role',
            ),
            (
              'a participant with no name',
              (wire) => _list(wire, 'participants')[0]['fullName'] = null,
              'participants.0.fullName',
            ),
          ]) {
        test('fails for $name, and names where', () {
          expect(
            _parseMeeting(_changed(change)),
            equals(err(WireFailure(path))),
          );
        });
      }

      test('ignores the fields it does not know at every level', () {
        final wire = _changed((copy) {
          copy['extra'] = true;
          for (final item in _list(copy, 'agenda')) {
            item['extra'] = 1;
          }
          for (final who in _list(copy, 'participants')) {
            who['extra'] = 1;
          }
          for (final document in _list(copy, 'documents')) {
            document['extra'] = 1;
          }
        });

        expect(_parseMeeting(wire), isA<Ok<Object?, WireFailure>>());
      });
    });

    group('a page', () {
      test('reads items with a cursor, and items without one', () {
        expect(
          _parsePage({
            'items': [_summary],
            'nextCursor': 'c',
          }),
          isA<Ok<Object?, WireFailure>>(),
        );
        expect(
          _parsePage({'items': <Object?>[]}),
          isA<Ok<Object?, WireFailure>>(),
        );
      });

      for (final (name, wire) in <(String, Object?)>[
        ('no items', <String, Object?>{}),
        ('items that are not a list', {'items': _summary}),
        (
          'an item that is not a summary',
          {
            'items': [
              {'id': 'a'},
            ],
          },
        ),
        ('a cursor that is a number', {'items': <Object?>[], 'nextCursor': 12}),
        ('a cursor that is null', {'items': <Object?>[], 'nextCursor': null}),
      ]) {
        test('fails for $name', () {
          expect(_parsePage(wire), isA<Err<Object?, WireFailure>>());
        });
      }
    });
  });

  group('the mappers of meetings', () {
    group('from the domain to the wire and back', () {
      for (final (name, meeting) in [
        ('a meeting with one open resolution', aMeeting()),
        ('a meeting with a longer agenda', aMeetingWithAgenda()),
        (
          'a meeting with a resolution that has a closing time and a '
              'recorded vote',
          aMeeting(
            agenda: [
              anAgendaItem(
                description: 'With a description',
                resolution: aResolution(
                  status: ResolutionStatus.closed,
                  closesAt: at(5 * 3600000),
                  recordedVote: VoteChoice.against,
                ),
              ),
            ],
          ),
        ),
      ]) {
        test('gives the meeting back as it was: $name', () {
          final parsed = unwrap(
            _parseMeeting(_overTheWire(toMeetingWire(meeting).toJson())),
          );

          expect(toMeeting(parsed), equals(ok(meeting)));
        });
      }

      test('gives back every meeting of the seed of the simulated '
          'server, as it was', () {
        final seed = unwrap(loadFixtures(readFixtureFiles(), now));

        for (final meeting in seed.content.meetings) {
          final parsed = unwrap(
            _parseMeeting(_overTheWire(toMeetingWire(meeting).toJson())),
          );
          expect(toMeeting(parsed), equals(ok(meeting)));
        }
      });

      test('writes an instant as an ISO 8601 string, and leaves out '
          'what is absent', () {
        final wire = toMeetingWire(aMeeting()).toJson();

        expect(wire['scheduledAt'], equals('2030-03-18T17:46:40.000Z'));
        final agenda = (wire['agenda']! as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final resolution = agenda[0]['resolution']! as Map<String, dynamic>;
        expect(resolution.containsKey('closesAt'), isFalse);
        expect(resolution.containsKey('recordedVote'), isFalse);
        expect(agenda[0].containsKey('description'), isFalse);
      });

      test('gives a summary back as it was', () {
        final summary = aMeetingSummary();

        expect(
          toMeetingSummary(
            unwrap(
              _parseSummary(
                _overTheWire(toMeetingSummaryWire(summary).toJson()),
              ),
            ),
          ),
          equals(ok(summary)),
        );
      });

      test('gives a page back as it was, with its cursor or without one', () {
        final pages = <Page<MeetingSummary>>[
          createPage([aMeetingSummary()], unwrap(parsePageCursor('next'))),
          createPage([aMeetingSummary(), aMeetingSummary()]),
          createPage(<MeetingSummary>[]),
        ];

        for (final page in pages) {
          final parsed = unwrap(
            _parsePage(_overTheWire(toMeetingPageWire(page).toJson())),
          );
          expect(toMeetingPage(parsed), equals(ok(page)));
        }
      });
    });

    group('through the factories of the domain', () {
      void rejects(
        void Function(_Json wire) change,
        ValidationField field, [
        ValidationRule? rule,
      ]) {
        final parsed = unwrap(_parseMeeting(_changed(change)));
        final mapped = toMeeting(parsed);

        expect(mapped, isA<Err<Object?, ValidationError>>());
        final error = (mapped as Err<Object?, ValidationError>).error;
        expect(error.field, equals(field));
        if (rule != null) {
          expect(error.rule, equals(rule));
        }
      }

      test('refuses a blank title and a title that is too long', () {
        rejects(
          (wire) => wire['title'] = '   ',
          ValidationField.title,
          ValidationRule.required,
        );
        rejects(
          (wire) => wire['title'] = 'x' * 301,
          ValidationField.title,
          ValidationRule.tooLong,
        );
      });

      test('refuses an id that is blank', () {
        rejects(
          (wire) => wire['id'] = ' ',
          ValidationField.meetingId,
          ValidationRule.required,
        );
      });

      test('refuses a status nobody knows', () {
        rejects(
          (wire) => _resolutionOf(_item(wire, 1))['status'] = 'archived',
          ValidationField.resolutionStatus,
          ValidationRule.unknownValue,
        );
      });

      test('refuses a vote choice nobody knows', () {
        rejects(
          (wire) => _resolutionOf(_item(wire, 1))['recordedVote'] = 'maybe',
          ValidationField.voteChoice,
          ValidationRule.unknownValue,
        );
      });

      test('refuses a role and a confidentiality level nobody knows', () {
        rejects(
          (wire) => _list(wire, 'participants')[0]['role'] = 'owner',
          ValidationField.participantRole,
        );
        rejects(
          (wire) => _list(wire, 'documents')[0]['confidentiality'] = 'secret',
          ValidationField.confidentialityLevel,
        );
      });

      test('refuses a position that is not a whole number and a page '
          'count out of range', () {
        rejects(
          (wire) => _item(wire, 1)['position'] = 1.5,
          ValidationField.position,
          ValidationRule.notAnInteger,
        );
        rejects(
          (wire) => _list(wire, 'documents')[0]['pageCount'] = 0,
          ValidationField.pageCount,
          ValidationRule.outOfRange,
        );
      });

      test(
        'refuses a closing time and a scheduled time the domain cannot hold',
        () {
          rejects(
            (wire) => wire['scheduledAt'] = '-000001-01-01T00:00:00.000Z',
            ValidationField.instant,
          );
        },
      );

      test('refuses two agenda items with the same position, and two '
          'participants with the same id', () {
        rejects(
          (wire) => _item(wire, 2)['position'] = 2,
          ValidationField.agenda,
          ValidationRule.duplicate,
        );
        rejects(
          (wire) {
            final people = _list(wire, 'participants');
            people[1]['userId'] = people[0]['userId'];
          },
          ValidationField.participants,
          ValidationRule.duplicate,
        );
      });

      test('refuses a page whose item or cursor the domain refuses', () {
        final blankCursor = unwrap(
          _parsePage({'items': <Object?>[], 'nextCursor': '  '}),
        );
        final blankItem = unwrap(
          _parsePage({
            'items': [
              {..._summary, 'title': ' '},
            ],
          }),
        );

        expect(
          toMeetingPage(blankCursor),
          isA<Err<Object?, ValidationError>>(),
        );
        expect(toMeetingPage(blankItem), isA<Err<Object?, ValidationError>>());
      });
    });
  });
}
