import 'dart:async';

import 'package:boardroom/application/ports/meeting_repository.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/instant.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import 'support.dart';

/// What a repository needs to be tested for the contract: a way to make the
/// server hold given meetings, to cut and restore the connection, and to have
/// the caller refused. Each adapter provides it with whatever its own set-up
/// is.
final class MeetingRepositoryHarness {
  /// Creates a harness.
  const new({
    required this.repository,
    required this.now,
    required this.serve,
    required this.forbid,
    required this.recordVote,
    required this.signInAs,
    required this.setOnline,
    required this.refuseCaller,
  });

  /// The adapter under test.
  final MeetingRepository repository;

  /// The instant the server takes for the present. A meeting scheduled after it
  /// is upcoming, any other is past: the server decides, the suite only dates
  /// its meetings from here.
  final Instant now;

  /// Makes the server hold exactly these meetings, all of them visible to the
  /// signed-in user, and forgets the ones it held. They are served in the order
  /// given.
  final FutureOr<void> Function(List<Meeting> meetings) serve;

  /// Makes the server hold this meeting as one the signed-in user may not see
  /// (they are not invited): the meeting exists, and is refused to them.
  final FutureOr<void> Function(Meeting meeting) forbid;

  /// Makes the server hold this vote as recorded, for its voter.
  final FutureOr<void> Function(Vote vote) recordVote;

  /// From now on the requests are authenticated as this user, who is invited to
  /// the served meetings.
  final FutureOr<void> Function(UserId userId) signInAs;

  /// Cuts and restores the connection.
  final void Function({required bool online}) setOnline;

  /// From now on the server refuses the caller: no valid credentials.
  final FutureOr<void> Function() refuseCaller;
}

/// What an implementation of the repository can be asked beyond what any can.
final class MeetingRepositoryContractOptions {
  /// Creates the options.
  const new({required this.projectsRecordedVotes});

  /// Whether the server shows each user their own recorded votes on the
  /// resolutions of a meeting. The scripted server of the fakes returns the
  /// meetings it was given, and cannot.
  final bool projectsRecordedVotes;
}

/// Makes a harness, now or later.
typedef MeetingRepositoryFactory =
    FutureOr<MeetingRepositoryHarness> Function();

final MeetingId _unknownMeeting = aMeetingId('does-not-exist');

/// The contract of `MeetingRepository`, as a suite any implementation runs: the
/// two lists are ordered as documented and cut to the size asked for, a cursor
/// continues where the page ended, a list holds summaries, an unknown meeting
/// is `notFound`, the failures are `Result`s.
void describeMeetingRepositoryContract(
  String name,
  MeetingRepositoryFactory createHarness,
  MeetingRepositoryContractOptions options,
) {
  group('$name honours the MeetingRepository contract', () {
    late MeetingRepositoryHarness harness;
    late MeetingRepository repository;

    /// A meeting scheduled `days` days from the present of the server.
    Meeting meetingIn(String id, int days) => aMeeting(
      summary: aMeetingSummary(
        id: aMeetingId(id),
        title: 'Meeting $id',
        scheduledAt: unwrap(parseInstant(harness.now + days * millisPerDay)),
      ),
      // Resolution ids are unique across meetings: each meeting has its own.
      agenda: [
        anAgendaItem(
          id: anAgendaItemId('agenda-$id'),
          resolution: aResolution(id: aResolutionId('resolution-$id')),
        ),
      ],
    );

    MeetingSummary summaryOf(Meeting meeting) => aMeetingSummary(
      id: meeting.id,
      title: meeting.title,
      scheduledAt: meeting.scheduledAt,
      location: meeting.location,
    );

    PageRequest request(int limit, [PageCursor? cursor]) =>
        unwrap(createPageRequest(cursor: cursor, limit: limit));

    Future<({List<String> ids, PageCursor? nextCursor})> idsOf(
      MeetingPeriod period,
      int limit, [
      PageCursor? cursor,
    ]) async {
      final page = valueOf(
        await repository.list(period, request(limit, cursor)),
      );
      return (
        ids: <String>[for (final item in page.items) item.id],
        nextCursor: page.nextCursor,
      );
    }

    setUp(() async {
      harness = await createHarness();
      repository = harness.repository;
    });

    group('list', () {
      test('puts upcoming meetings soonest first, '
          'whatever the order the server holds them in', () async {
        await harness.serve([
          meetingIn('u3', 3),
          meetingIn('u1', 1),
          meetingIn('u4', 4),
          meetingIn('u2', 2),
        ]);

        expect(
          (await idsOf(MeetingPeriod.upcoming, 10)).ids,
          equals(['u1', 'u2', 'u3', 'u4']),
        );
      });

      test('puts past meetings latest first, '
          'whatever the order the server holds them in', () async {
        await harness.serve([
          meetingIn('p2', -2),
          meetingIn('p3', -3),
          meetingIn('p1', -1),
        ]);

        expect(
          (await idsOf(MeetingPeriod.past, 10)).ids,
          equals(['p1', 'p2', 'p3']),
        );
      });

      test('lists a meeting under its period only', () async {
        await harness.serve([
          meetingIn('u1', 1),
          meetingIn('p1', -1),
          meetingIn('u2', 2),
        ]);

        expect(
          (await idsOf(MeetingPeriod.upcoming, 10)).ids,
          equals(['u1', 'u2']),
        );
        expect((await idsOf(MeetingPeriod.past, 10)).ids, equals(['p1']));
      });

      test('lists summaries: what a list shows, '
          'and nothing of the agenda, documents or participants', () async {
        final meeting = meetingIn('u1', 1);
        await harness.serve([meeting]);

        final page = valueOf(
          await repository.list(MeetingPeriod.upcoming, request(10)),
        );

        expect(page.items, equals([summaryOf(meeting)]));
      });

      test('gives an empty page, without a cursor, '
          'for a period without meetings', () async {
        await harness.serve([meetingIn('u1', 1)]);

        final page = valueOf(
          await repository.list(MeetingPeriod.past, request(5)),
        );

        expect(page.items, equals(<MeetingSummary>[]));
        expect(page.nextCursor, isNull);
      });

      test('cuts a page to the size asked for, '
          'and gives a cursor only when there is more', () async {
        await harness.serve([
          meetingIn('u1', 1),
          meetingIn('u2', 2),
          meetingIn('u3', 3),
          meetingIn('u4', 4),
        ]);

        final two = await idsOf(MeetingPeriod.upcoming, 2);
        final one = await idsOf(MeetingPeriod.upcoming, 1);
        final exactly = await idsOf(MeetingPeriod.upcoming, 4);
        final more = await idsOf(MeetingPeriod.upcoming, 50);

        expect(two.ids, equals(['u1', 'u2']));
        expect(two.nextCursor, isNotNull);
        expect(one.ids, equals(['u1']));
        expect(one.nextCursor, isNotNull);
        expect(exactly.ids, equals(['u1', 'u2', 'u3', 'u4']));
        expect(exactly.nextCursor, isNull);
        expect(more.ids, equals(['u1', 'u2', 'u3', 'u4']));
        expect(more.nextCursor, isNull);
      });

      for (final limit in [1, 2, 3, 5]) {
        test('walks the whole list with a page size of $limit, '
            'seeing each meeting once and in order', () async {
          final upcoming = [
            for (final day in [1, 2, 3, 4, 5, 6, 7]) meetingIn('u$day', day),
          ];
          final past = [
            for (final day in [1, 2, 3, 4, 5]) meetingIn('p$day', -day),
          ];
          await harness.serve([...upcoming.reversed, ...past]);

          for (final (period, expected) in [
            (MeetingPeriod.upcoming, [for (final m in upcoming) m.id]),
            (MeetingPeriod.past, [for (final m in past) m.id]),
          ]) {
            final seen = <String>[];
            PageCursor? cursor;
            var pages = 0;
            do {
              final page = await idsOf(period, limit, cursor);
              seen.addAll(page.ids);
              cursor = page.nextCursor;
              pages += 1;
            } while (cursor != null && pages <= expected.length);

            expect(seen, equals(expected));
          }
        });
      }

      test('continues a list after the cursor of the page before it, '
          'and ends it with no cursor', () async {
        await harness.serve([
          meetingIn('u1', 1),
          meetingIn('u2', 2),
          meetingIn('u3', 3),
        ]);

        final first = await idsOf(MeetingPeriod.upcoming, 2);
        final second = await idsOf(MeetingPeriod.upcoming, 2, first.nextCursor);

        expect(second.ids, equals(['u3']));
        expect(second.nextCursor, isNull);
      });

      test('answers the same page to the same request', () async {
        await harness.serve([
          meetingIn('u1', 1),
          meetingIn('u2', 2),
          meetingIn('u3', 3),
        ]);

        final first = await idsOf(MeetingPeriod.upcoming, 2);
        final again = await idsOf(MeetingPeriod.upcoming, 2);

        expect(again.ids, equals(first.ids));
        expect(again.nextCursor, equals(first.nextCursor));
      });
    });

    group('get', () {
      test('returns the meeting with its agenda, documents '
          'and participants', () async {
        final meeting = meetingIn('u1', 1);
        await harness.serve([meeting, meetingIn('p1', -1)]);

        expect(await repository.get(meeting.id), equals(ok(meeting)));
      });

      test('answers notFound for a meeting the server does not hold', () async {
        await harness.serve([meetingIn('u1', 1)]);

        expect(await repository.get(_unknownMeeting), equals(err(notFound())));
      });

      test(
        'answers notFound for a meeting the server no longer holds',
        () async {
          await harness.serve([meetingIn('u1', 1)]);
          await harness.serve([]);

          expect(
            await repository.get(aMeetingId('u1')),
            equals(err(notFound())),
          );
        },
      );
    });

    group('what it returns', () {
      test('is a copy: changing a meeting or a page that was returned '
          'changes nothing the next call returns', () async {
        final meeting = meetingIn('u1', 1);
        await harness.serve([meeting]);
        final returned = valueOf(await repository.get(meeting.id));
        final page = valueOf(
          await repository.list(MeetingPeriod.upcoming, request(5)),
        );

        // The values are immutable: only the lists could be changed in place,
        // and they refuse it.
        expectRefused(() => returned.agenda.clear());
        expectRefused(() => returned.participants.clear());
        expectRefused(() => page.items.clear());

        expect(await repository.get(meeting.id), equals(ok(meeting)));
        final again = valueOf(
          await repository.list(MeetingPeriod.upcoming, request(5)),
        );
        expect(again.items, equals([summaryOf(meeting)]));
      });
    });

    // A server that returns what it was given (the fakes) skips these: they
    // show as skipped.
    group('the votes of the user', () {
      final meetingWithVote = aMeeting();
      final vote = aVote();

      test('shows the user the vote they recorded on a resolution', () async {
        await harness.serve([meetingWithVote]);
        await harness.recordVote(vote);

        final returned = valueOf(await repository.get(meetingWithVote.id));

        expect(
          findResolution(returned, vote.resolutionId)?.recordedVote,
          equals(vote.choice),
        );
      });

      test('shows it to nobody else: '
          'another user of the same meeting sees no vote', () async {
        await harness.serve([meetingWithVote]);
        await harness.recordVote(vote);

        await harness.signInAs(aUserId('user-2'));
        final returned = valueOf(await repository.get(meetingWithVote.id));

        expect(
          findResolution(returned, vote.resolutionId)?.recordedVote,
          isNull,
        );
      });

      test('shows no vote on a resolution nobody voted on', () async {
        await harness.serve([meetingWithVote]);

        final returned = valueOf(await repository.get(meetingWithVote.id));

        expect(
          findResolution(returned, vote.resolutionId)?.recordedVote,
          isNull,
        );
      });
    }, skip: !options.projectsRecordedVotes);

    group('a meeting the user may not see', () {
      test('is refused with forbidden: '
          'the session is valid, the item is not theirs', () async {
        final hidden = meetingIn('hidden', 1);
        await harness.serve([meetingIn('u1', 2)]);
        await harness.forbid(hidden);

        expect(await repository.get(hidden.id), equals(err(forbidden())));
      });

      test('is not told apart from the session being refused: '
          'that one is unauthorized', () async {
        final hidden = meetingIn('hidden', 1);
        await harness.serve([]);
        await harness.forbid(hidden);
        await harness.refuseCaller();

        expect(await repository.get(hidden.id), equals(err(unauthorized())));
      });

      test(
        'is not listed, and does not hide the meetings that are theirs',
        () async {
          await harness.serve([meetingIn('u1', 1), meetingIn('u2', 2)]);
          await harness.forbid(meetingIn('hidden', 1));

          expect(
            (await idsOf(MeetingPeriod.upcoming, 10)).ids,
            equals(['u1', 'u2']),
          );
          expect(isOk(await repository.get(aMeetingId('u1'))), isTrue);
        },
      );
    });

    group('failures are results', () {
      setUp(() async {
        await harness.serve([meetingIn('u1', 1)]);
      });

      test('answers networkUnavailable without a connection, '
          'and recovers with it', () async {
        harness.setOnline(online: false);

        expect(
          await repository.list(MeetingPeriod.upcoming, request(5)),
          equals(err(networkUnavailable())),
        );
        expect(
          await repository.get(aMeetingId('u1')),
          equals(err(networkUnavailable())),
        );

        harness.setOnline(online: true);
        expect((await idsOf(MeetingPeriod.upcoming, 5)).ids, equals(['u1']));
        expect(isOk(await repository.get(aMeetingId('u1'))), isTrue);
      });

      test('answers unauthorized when the caller is refused', () async {
        await harness.refuseCaller();

        expect(
          await repository.list(MeetingPeriod.upcoming, request(5)),
          equals(err(unauthorized())),
        );
        expect(
          await repository.get(aMeetingId('u1')),
          equals(err(unauthorized())),
        );
      });
    });
  });
}
