import 'dart:convert';

import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/infrastructure/http/dto/wire.dart';
import 'package:boardroom/infrastructure/in_memory/fixtures/fixture_schemas.dart';
import 'package:boardroom/infrastructure/in_memory/fixtures/load_fixtures.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/fixture_files.dart';

typedef _Json = Map<String, dynamic>;

Instant _instant(int millis) => unwrap(parseInstant(millis));

const int _millisPerHour = 3600000;
const int _millisPerDay = 24 * _millisPerHour;

/// The password of the demo accounts: it protects nothing, and is the one of
/// `accounts.json`.
const String _demoPassword = 'boardroom-demo';

final int _reference = referenceDateOnDisk();

/// The instants the app may start at, before and after the reference date of
/// the files.
final List<(String, int)> _nows = [
  ('the reference date', _reference),
  ('a millisecond after the reference date', _reference + 1),
  ('a millisecond before the reference date', _reference - 1),
  ('a day before the reference date', _reference - _millisPerDay),
  (
    'a day less a millisecond after the reference date',
    _reference + _millisPerDay - 1,
  ),
  ('a day after the reference date', _reference + _millisPerDay),
  ('the instant of the tests', now),
  ('the year 2096', 4000000000000),
];

/// The shift the files must get at `millis`: the complete days since the
/// reference date, rounded down.
int _expectedShift(int millis) =>
    ((millis - _reference) / _millisPerDay).floor() * _millisPerDay;

List<_Json> _meetingsOf(DecodedFixtures files) =>
    ((files.meetings! as _Json)['meetings'] as List<dynamic>).cast<_Json>();

List<_Json> _votesOf(DecodedFixtures files) =>
    ((files.recordedVotes! as _Json)['recordedVotes'] as List<dynamic>)
        .cast<_Json>();

List<_Json> _accountsOf(DecodedFixtures files) =>
    ((files.accounts! as _Json)['accounts'] as List<dynamic>).cast<_Json>();

_Json _firstMeeting(DecodedFixtures files) => _meetingsOf(files).first;

int _parseDate(Object? text) => readInstantMillis(text! as String);

SeedData _loaded(FixtureFiles files, int millis) {
  final loaded = loadFixtures(files, _instant(millis));
  return switch (loaded) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.detail),
  };
}

void main() {
  group('the fixtures of docs/spec/fixtures', () {
    final names = fixtureFileNamesOnDisk();

    test('are the three files the app reads, and no other JSON file', () {
      expect(
        names,
        equals([for (final file in FixtureFile.values) file.value]..sort()),
      );
    });

    for (final (name, parse)
        in <(String, Result<Object, WireFailure> Function(Object?))>[
          (
            FixtureFile.accounts.value,
            (json) => decodeWire<Object>(json, AccountsFileWire.fromJson),
          ),
          (
            FixtureFile.meetings.value,
            (json) => decodeWire<Object>(json, MeetingsFileWire.fromJson),
          ),
          (
            FixtureFile.recordedVotes.value,
            (json) => decodeWire<Object>(json, RecordedVotesFileWire.fromJson),
          ),
        ]) {
      group(name, () {
        final content = readFixtureFile(name)! as _Json;

        test('has the shape its schema describes', () {
          expect(parse(content), isA<Ok<Object, WireFailure>>());
        });

        test('declares its reference date first, '
            'as an ISO 8601 instant with a zone', () {
          expect(content.keys.first, equals('referenceDate'));
          expect(
            content['referenceDate'],
            matches(
              RegExp(
                r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
              ),
            ),
          );
        });
      });
    }

    test('share one reference date', () {
      final dates = [
        for (final name in names)
          (readFixtureFile(name)! as _Json)['referenceDate'],
      ];

      expect(dates.toSet(), hasLength(1));
      expect(_parseDate(dates.first), isA<int>());
    });

    test(
      'keep their keys in alphabetical order, so that the files stay stable',
      () {
        bool sorted(Object? value) {
          if (value is List<dynamic>) {
            return value.every(sorted);
          }
          if (value is! Map<String, dynamic>) {
            return true;
          }
          final keys = value.keys
              .where((key) => key != 'referenceDate')
              .toList();
          return keys.join(',') == (List.of(keys)..sort()).join(',') &&
              value.values.every(sorted);
        }

        for (final name in names) {
          expect(sorted(readFixtureFile(name)), isTrue);
        }
      },
    );

    group('titles', () {
      final meetings =
          ((readFixtureFile(FixtureFile.meetings.value)! as _Json)['meetings']
                  as List<dynamic>)
              .cast<_Json>();

      test('name no month and no year anywhere in the text, which the '
          'shift does not move', () {
        final months = RegExp(
          r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\b',
        );
        final years = RegExp(r'\b(?:19|20)\d{2}\b');
        // The instants are read as numbers, not as text: leave their keys out.
        Object? withoutInstants(Object? value) => switch (value) {
          final List<dynamic> list => list.map(withoutInstants).toList(),
          final Map<String, dynamic> map => {
            for (final MapEntry(:key, :value) in map.entries)
              if (key != 'scheduledAt' && key != 'closesAt')
                key: withoutInstants(value),
          },
          _ => value,
        };
        final texts = RegExp('"[^"]*"')
            .allMatches(jsonEncode(withoutInstants(meetings)))
            .map((match) => match.group(0)!);

        expect(
          texts.where((text) => months.hasMatch(text) || years.hasMatch(text)),
          isEmpty,
        );
      });

      test('are a committee, a subject and a session number, which is '
          'distinct for every meeting', () {
        final titles = [
          for (final meeting in meetings) meeting['title']! as String,
        ];

        expect(
          titles.every(
            (title) => RegExp(r'^[^:]+: .+, session [1-9]\d*$').hasMatch(title),
          ),
          isTrue,
        );
        expect(titles.toSet(), hasLength(titles.length));
      });

      test('number the sessions of each committee from 1, oldest '
          'first, with no gap', () {
        final byCommittee = <String, List<int>>{};
        final oldestFirst = List.of(meetings)
          ..sort(
            (first, second) =>
                _parseDate(first['scheduledAt'])
                    .compareTo(_parseDate(second['scheduledAt'])),
          );
        for (final meeting in oldestFirst) {
          final title = meeting['title']! as String;
          final committee = title.split(':').first;
          final session = int.parse(
            RegExp(r'session (\d+)$').firstMatch(title)![1]!,
          );
          byCommittee.putIfAbsent(committee, () => []).add(session);
        }

        expect(byCommittee.length, greaterThan(1));
        for (final sessions in byCommittee.values) {
          expect(
            sessions,
            equals([
              for (var index = 0; index < sessions.length; index++) index + 1,
            ]),
          );
        }
      });
    });

    test('keep the votes already recorded out of the meetings: the '
        'API gives a user their own', () {
      final meetings =
          ((readFixtureFile(FixtureFile.meetings.value)! as _Json)['meetings']
                  as List<dynamic>)
              .cast<_Json>();

      final recorded = [
        for (final meeting in meetings)
          for (final item
              in (meeting['agenda']! as List<dynamic>).cast<_Json>())
            if ((item['resolution'] as _Json?)?['recordedVote'] != null) item,
      ];

      expect(recorded, isEmpty);
    });
  });

  group('loading the fixtures', () {
    for (final (name, millis) in _nows) {
      group('at $name', () {
        final now = _instant(millis);
        final delta = _expectedShift(millis);
        final raw = DecodedFixtures();
        final loaded = loadFixtures(raw.encode(), now);

        test('loads', () {
          expect(loaded, isA<Ok<SeedData, FixtureError>>());
        });

        test(
          'moves every date of every file by the same whole number of days',
          () {
            final content = unwrap(loaded).content;
            final meetings = _meetingsOf(raw);
            final recordedVotes = _votesOf(raw);

            expect(content.meetings, hasLength(meetings.length));
            for (final (index, wire) in meetings.indexed) {
              final meeting = content.meetings[index];
              expect(meeting.id, equals(wire['id']));
              expect(
                meeting.scheduledAt,
                equals(_parseDate(wire['scheduledAt']) + delta),
              );
              for (final item
                  in (wire['agenda']! as List<dynamic>).cast<_Json>()) {
                final resolutionWire = item['resolution'] as _Json?;
                if (resolutionWire == null) {
                  continue;
                }
                final resolution = findResolution(
                  meeting,
                  aResolutionId(resolutionWire['id']! as String),
                );
                expect(
                  resolution?.closesAt,
                  equals(
                    resolutionWire['closesAt'] == null
                        ? null
                        : _parseDate(resolutionWire['closesAt']) + delta,
                  ),
                );
              }
            }
            expect(content.recordedVotes, hasLength(recordedVotes.length));
            for (final (index, wire) in recordedVotes.indexed) {
              expect(
                content.recordedVotes[index].castAt,
                equals(_parseDate(wire['castAt']) + delta),
              );
            }
          },
        );

        test('keeps the distance between any two dates of the files', () {
          final meetings = _meetingsOf(raw);
          final shifted = unwrap(loaded).content.meetings;

          expect(
            shifted.first.scheduledAt - shifted.last.scheduledAt,
            equals(
              _parseDate(meetings.first['scheduledAt']) -
                  _parseDate(meetings.last['scheduledAt']),
            ),
          );
        });

        test(
          'keeps the time of day of every meeting, in UTC, on a round hour',
          () {
            final meetings = _meetingsOf(raw);

            for (final (index, wire) in meetings.indexed) {
              final written = DateTime.fromMillisecondsSinceEpoch(
                _parseDate(wire['scheduledAt']),
                isUtc: true,
              );
              final shifted = DateTime.fromMillisecondsSinceEpoch(
                unwrap(loaded).content.meetings[index].scheduledAt,
                isUtc: true,
              );
              expect(shifted.hour, equals(written.hour));
              expect(shifted.minute, equals(0));
              expect(shifted.second + shifted.millisecond, equals(0));
            }
          },
        );

        test(
          'does not change what it reads, and gives a new copy each time',
          () {
            final files = raw.encode();
            final before = (
              files.accounts,
              files.meetings,
              files.recordedVotes,
            );
            final again = loadFixtures(files, now);

            expect((
              files.accounts,
              files.meetings,
              files.recordedVotes,
            ), equals(before));
            expect(again, equals(loaded));
            expect(
              identical(
                unwrap(again).content.meetings.first,
                unwrap(loaded).content.meetings.first,
              ),
              isFalse,
            );
          },
        );
      });
    }

    test('puts the same meetings upcoming as the files did, at the '
        'reference date itself', () {
      final loaded = _loaded(readFixtureFiles(), _reference);
      final meetings = _meetingsOf(DecodedFixtures());

      final upcoming = loaded.content.meetings.where(
        (meeting) => meeting.scheduledAt > _reference,
      );

      expect(
        upcoming.map((meeting) => meeting.id),
        equals(
          meetings
              .where(
                (meeting) => _parseDate(meeting['scheduledAt']) > _reference,
              )
              .map((meeting) => meeting['id']),
        ),
      );
    });

    test(
      'reads dates written with an offset as the instants they stand for',
      () {
        final files = DecodedFixtures();
        final first = _firstMeeting(files);
        final original = _parseDate(first['scheduledAt']);
        final written = DateTime.fromMillisecondsSinceEpoch(
          original + 3600000,
          isUtc: true,
        ).toIso8601String();
        first['scheduledAt'] = '${written.replaceFirst('Z', '')}+01:00';

        final loaded = loadFixtures(files.encode(), _instant(_reference));

        expect(
          unwrap(loaded).content.meetings.first.scheduledAt,
          equals(original),
        );
      },
    );

    group('the shift', () {
      int firstScheduledAt(int millis) => _loaded(
        readFixtureFiles(),
        millis,
      ).content.meetings.first.scheduledAt;

      for (final (name, millis, days) in [
        ('at the reference date', _reference, 0),
        (
          'until the last millisecond of the first day',
          _reference + _millisPerDay - 1,
          0,
        ),
        (
          'from a whole day after the reference date',
          _reference + _millisPerDay,
          1,
        ),
        (
          'for the days that follow',
          _reference + 400 * _millisPerDay + 5 * _millisPerHour,
          400,
        ),
        (
          'a millisecond before the reference date, rounded to the earlier day',
          _reference - 1,
          -1,
        ),
        (
          'exactly a day before the reference date',
          _reference - _millisPerDay,
          -1,
        ),
        (
          'a millisecond more than a day before, rounded to the earlier day',
          _reference - _millisPerDay - 1,
          -2,
        ),
        (
          'for the days before',
          _reference - 9 * _millisPerDay - 3 * _millisPerHour,
          -10,
        ),
      ]) {
        test('is a whole number of days $name: $days days', () {
          final written = _parseDate(
            _firstMeeting(DecodedFixtures())['scheduledAt'],
          );

          expect(
            firstScheduledAt(millis) - written,
            equals(days * _millisPerDay),
          );
        });
      }
    });

    test('chooses the demo user the file names, not the first account', () {
      final files = DecodedFixtures();
      (files.accounts! as _Json)['demoUserId'] = 'user-bruno';

      final loaded = loadFixtures(files.encode(), _instant(now));

      expect(unwrap(loaded).demoUser.fullName, equals('Bruno Durand'));
    });
  });

  group('a broken fixture', () {
    FixtureError errorOf(void Function(DecodedFixtures files) breakIt) {
      final files = DecodedFixtures();
      breakIt(files);
      final loaded = loadFixtures(files.encode(), _instant(now));
      return switch (loaded) {
        Ok() => throw StateError('The broken fixtures were accepted.'),
        Err(:final error) => error,
      };
    }

    _Json firstResolution(DecodedFixtures files) {
      for (final item
          in (_firstMeeting(files)['agenda']! as List<dynamic>).cast<_Json>()) {
        if (item['resolution'] != null) {
          return item['resolution']! as _Json;
        }
      }
      throw StateError('no resolution');
    }

    _Json agendaResolution(DecodedFixtures files, int position) =>
        ((_firstMeeting(files)['agenda']! as List<dynamic>)[position]
                as _Json)['resolution']!
            as _Json;

    final readCount = _votesOf(DecodedFixtures()).length;

    for (final (name, breakIt, code, file, place)
        in <
          (
            String,
            void Function(DecodedFixtures),
            FixtureErrorCode,
            FixtureFile,
            String,
          )
        >[
          (
            'a date that is a number',
            (files) => _firstMeeting(files)['scheduledAt'] = 1790000000000,
            FixtureErrorCode.invalidShape,
            FixtureFile.meetings,
            'meetings.0.scheduledAt',
          ),
          (
            'a date with no zone',
            (files) =>
                _firstMeeting(files)['scheduledAt'] = '2026-10-03T09:00:00',
            FixtureErrorCode.invalidShape,
            FixtureFile.meetings,
            'meetings.0.scheduledAt',
          ),
          (
            'a missing title',
            (files) => _firstMeeting(files).remove('title'),
            FixtureErrorCode.invalidShape,
            FixtureFile.meetings,
            'meetings.0.title',
          ),
          (
            'a list that is not a list',
            (files) => (files.meetings! as _Json)['meetings'] = 'none',
            FixtureErrorCode.invalidShape,
            FixtureFile.meetings,
            'meetings',
          ),
          (
            'a missing reference date',
            (files) => (files.accounts! as _Json).remove('referenceDate'),
            FixtureErrorCode.invalidShape,
            FixtureFile.accounts,
            'referenceDate',
          ),
          (
            'a vote with a choice that is not text',
            (files) => _votesOf(files)[3]['choice'] = 1,
            FixtureErrorCode.invalidShape,
            FixtureFile.recordedVotes,
            'recordedVotes.3.choice',
          ),
          (
            'an account with no password',
            (files) => _accountsOf(files)[0].remove('password'),
            FixtureErrorCode.invalidShape,
            FixtureFile.accounts,
            'accounts.0.password',
          ),
          (
            'a file that is not an object',
            (files) => files.recordedVotes = null,
            FixtureErrorCode.invalidShape,
            FixtureFile.recordedVotes,
            r'$',
          ),
          (
            'a blank title',
            (files) => _firstMeeting(files)['title'] = '   ',
            FixtureErrorCode.invalidValue,
            FixtureFile.meetings,
            'meetings.0 (title required)',
          ),
          (
            'a status nobody knows',
            (files) => firstResolution(files)['status'] = 'archived',
            FixtureErrorCode.invalidValue,
            FixtureFile.meetings,
            'meetings.0 (resolutionStatus unknownValue)',
          ),
          (
            'a vote that nobody can cast',
            (files) => _votesOf(files)[0]['choice'] = 'maybe',
            FixtureErrorCode.invalidValue,
            FixtureFile.recordedVotes,
            'recordedVotes.0 (voteChoice unknownValue)',
          ),
          (
            'an email that is not one',
            (files) => (_accountsOf(files)[1]['user']! as _Json)['email'] =
                'not an email',
            FixtureErrorCode.invalidValue,
            FixtureFile.accounts,
            'accounts.1 (email invalidFormat)',
          ),
          (
            'a reference date that differs between files',
            (files) => (files.meetings! as _Json)['referenceDate'] =
                '2026-10-02T08:00:00.000Z',
            FixtureErrorCode.referenceDateMismatch,
            FixtureFile.meetings,
            'referenceDate',
          ),
          (
            'a vote on a resolution that does not exist',
            (files) =>
                _votesOf(files)[2]['resolutionId'] = 'resolution-nobody-wrote',
            FixtureErrorCode.unknownReference,
            FixtureFile.recordedVotes,
            'recordedVotes.2.resolutionId',
          ),
          (
            'a vote that names another meeting than the one of its resolution',
            (files) => _votesOf(files)[2]['meetingId'] = 'meeting-066',
            FixtureErrorCode.unknownReference,
            FixtureFile.recordedVotes,
            'recordedVotes.2.meetingId',
          ),
          (
            'a vote of someone who is not in the meeting',
            (files) => _votesOf(files)[2]['voterId'] = 'user-nobody',
            FixtureErrorCode.unknownReference,
            FixtureFile.recordedVotes,
            'recordedVotes.2.voterId',
          ),
          (
            'a demo user that is not an account',
            (files) => (files.accounts! as _Json)['demoUserId'] = 'user-nobody',
            FixtureErrorCode.unknownReference,
            FixtureFile.accounts,
            'demoUserId',
          ),
          (
            'a meeting less than a day after the reference date',
            (files) => _firstMeeting(files)['scheduledAt'] = writeInstantMillis(
              _reference + _millisPerDay - 1,
            ),
            FixtureErrorCode.timelineMargin,
            FixtureFile.meetings,
            'meetings.0.scheduledAt',
          ),
          (
            'a meeting less than a day before the reference date',
            (files) => _firstMeeting(files)['scheduledAt'] = writeInstantMillis(
              _reference - _millisPerDay + 1,
            ),
            FixtureErrorCode.timelineMargin,
            FixtureFile.meetings,
            'meetings.0.scheduledAt',
          ),
          (
            'a closing time less than a day after the reference date',
            (files) => agendaResolution(files, 1)['closesAt'] =
                writeInstantMillis(_reference + _millisPerHour),
            FixtureErrorCode.timelineMargin,
            FixtureFile.meetings,
            'meetings.0.agenda.1.resolution.closesAt',
          ),
          (
            'a closing time less than a day before the reference date',
            (files) => agendaResolution(files, 1)['closesAt'] =
                writeInstantMillis(_reference - _millisPerHour),
            FixtureErrorCode.timelineMargin,
            FixtureFile.meetings,
            'meetings.0.agenda.1.resolution.closesAt',
          ),
          (
            'a vote cast after the reference date',
            (files) => _votesOf(files)[4]['castAt'] = writeInstantMillis(
              _reference + 1,
            ),
            FixtureErrorCode.timelineMargin,
            FixtureFile.recordedVotes,
            'recordedVotes.4.castAt',
          ),
          (
            'two meetings with the same id',
            (files) => _meetingsOf(files)[1]['id'] = _firstMeeting(files)['id'],
            FixtureErrorCode.duplicate,
            FixtureFile.meetings,
            'meetings.1.id',
          ),
          (
            'a document listed by two meetings',
            (files) =>
                (_meetingsOf(files)[1]['documents']! as List<dynamic>)[0] =
                    (_firstMeeting(files)['documents']! as List<dynamic>)[0],
            FixtureErrorCode.duplicate,
            FixtureFile.meetings,
            'meetings.1.documents',
          ),
          (
            'the same vote twice',
            (files) => _votesOf(files).add({..._votesOf(files)[0]}),
            FixtureErrorCode.duplicate,
            FixtureFile.recordedVotes,
            'recordedVotes.$readCount',
          ),
          (
            'two accounts with the same email',
            (files) {
              final accounts = _accountsOf(files);
              (accounts[1]['user']! as _Json)['email'] =
                  (accounts[0]['user']! as _Json)['email'];
            },
            FixtureErrorCode.duplicate,
            FixtureFile.accounts,
            'accounts.1',
          ),
        ]) {
      group('with $name', () {
        test('is reported as an error of the right kind, in the right '
            'file and place', () {
          final error = errorOf(breakIt);

          expect(error.code, equals(code));
          expect(error.file, equals(file));
          expect(error.detail, equals('${file.value}: $place'));
        });

        test('is not thrown, and says nothing of the values of the files', () {
          final files = DecodedFixtures();
          breakIt(files);

          final loaded = loadFixtures(files.encode(), _instant(now));

          expect(loaded, isA<Err<SeedData, FixtureError>>());
          final error = (loaded as Err<SeedData, FixtureError>).error;
          expect(error.detail, isNot(contains(_demoPassword)));
          expect(error.detail, isNot(contains('@boardroom.example')));
        });
      });
    }

    test('is reported as an error when the instant leaves no room '
        'for the past meetings', () {
      final loaded = loadFixtures(readFixtureFiles(), _instant(1000));

      expect(loaded, isA<Err<SeedData, FixtureError>>());
      final error = (loaded as Err<SeedData, FixtureError>).error;
      expect(error.code, equals(FixtureErrorCode.invalidValue));
      expect(
        error.detail,
        matches(
          RegExp(r'^meetings\.json: meetings\.\d+ \(instant outOfRange\)$'),
        ),
      );
    });

    test('is reported as an error when a file is missing altogether', () {
      final loaded = loadFixtures(
        const FixtureFiles(accounts: '', meetings: '', recordedVotes: ''),
        _instant(now),
      );

      expect(
        loaded,
        equals(
          err(
            const FixtureError(
              code: FixtureErrorCode.invalidShape,
              file: FixtureFile.accounts,
              detail: r'accounts.json: $',
            ),
          ),
        ),
      );
    });

    for (final (name, millis) in [
      ('exactly a day after the reference date', _reference + _millisPerDay),
      ('exactly a day before the reference date', _reference - _millisPerDay),
    ]) {
      test(
        'accepts a meeting and a closing time $name: the margin is a whole day',
        () {
          final files = DecodedFixtures();
          _firstMeeting(files)['scheduledAt'] = writeInstantMillis(millis);
          agendaResolution(files, 1)['closesAt'] = writeInstantMillis(millis);
          _votesOf(files)[0]['castAt'] = writeInstantMillis(_reference);

          expect(
            loadFixtures(files.encode(), _instant(now)),
            isA<Ok<SeedData, FixtureError>>(),
          );
        },
      );
    }

    test('is found before the files are read, in the order '
        'accounts, meetings, votes', () {
      final files = DecodedFixtures();
      (files.meetings! as _Json)['meetings'] = 1;
      (files.recordedVotes! as _Json)['recordedVotes'] = 1;

      final loaded = loadFixtures(files.encode(), _instant(now));

      expect(
        (loaded as Err<SeedData, FixtureError>).error.file,
        equals(FixtureFile.meetings),
      );
    });
  });

  group('the loader of the fixtures, in Dart', () {
    test('is reported as an invalid shape when a file is not JSON', () {
      final files = readFixtureFiles();

      final loaded = loadFixtures(
        FixtureFiles(
          accounts: files.accounts,
          meetings: '{"referenceDate": ',
          recordedVotes: files.recordedVotes,
        ),
        _instant(now),
      );

      expect(
        loaded,
        equals(
          err(
            const FixtureError(
              code: FixtureErrorCode.invalidShape,
              file: FixtureFile.meetings,
              detail: r'meetings.json: $',
            ),
          ),
        ),
      );
    });

    test('prints neither the accounts nor their passwords', () {
      final seed = _loaded(readFixtureFiles(), now);

      expect('$seed ${seed.accounts.first}', isNot(contains(_demoPassword)));
    });
  });
}
