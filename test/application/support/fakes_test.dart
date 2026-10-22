import 'package:boardroom/application/ports/document_cache.dart';
import 'package:boardroom/application/ports/meeting_cache.dart';
import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/application/ports/types/cache_entry.dart';
import 'package:boardroom/application/ports/vote_outbox.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/outbox_vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/credentials.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:test/test.dart';

import '../../domain/support/builders.dart';
import 'create_fakes.dart';
import 'fake_auth_session.dart';

const _pageKey = MeetingPageKey(period: MeetingPeriod.past, limit: 20);

void main() {
  // The fakes stand in for the adapters in every use case test, so what they
  // promise must match the contract written in the port. These tests check it.

  group('the fake remote sources', () {
    test(
      'fail with networkUnavailable while the network is off, and recover',
      () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        fakes.documents.addDocument(aDocument(), aDocumentLocation());
        fakes.network.goOffline();

        expect(
          await fakes.meetings.get(aMeetingId()),
          equals(err(networkUnavailable())),
        );
        expect(
          await fakes.meetings.list(
            MeetingPeriod.upcoming,
            const PageRequest(limit: 20),
          ),
          equals(err(networkUnavailable())),
        );
        expect(
          await fakes.documents.get(aDocument().id),
          equals(err(networkUnavailable())),
        );
        expect(
          await fakes.documents.fetchContent(aDocument().id),
          equals(err(networkUnavailable())),
        );
        expect(
          await fakes.votes.submit(aVote()),
          equals(err(networkUnavailable())),
        );

        fakes.network.goOnline();
        expect(await fakes.meetings.get(aMeetingId()), equals(ok(aMeeting())));
      },
    );

    test('answer notFound for what they do not hold, '
        'and the scripted failure for everything else', () async {
      final fakes = createFakes();

      expect(await fakes.meetings.get(aMeetingId()), equals(err(notFound())));
      expect(
        await fakes.documents.get(aDocument().id),
        equals(err(notFound())),
      );
      expect(
        await fakes.documents.fetchContent(aDocument().id),
        equals(err(notFound())),
      );

      fakes.meetings.failure = unauthorized();
      fakes.documents.failure = unauthorized();
      expect(
        await fakes.meetings.get(aMeetingId()),
        equals(err(unauthorized())),
      );
      expect(
        await fakes.meetings.list(
          MeetingPeriod.past,
          const PageRequest(limit: 5),
        ),
        equals(err(unauthorized())),
      );
      expect(
        await fakes.documents.get(aDocument().id),
        equals(err(unauthorized())),
      );
    });

    group('the list of meetings', () {
      MeetingSummary upcoming(String id, int days) => aMeetingSummary(
        id: aMeetingId(id),
        scheduledAt: at(days * millisPerDay),
      );
      final u1 = upcoming('u1', 1);
      final u2 = upcoming('u2', 2);
      final u3 = upcoming('u3', 3);
      final u4 = upcoming('u4', 4);
      PageRequest request(int limit, [String? cursor]) => unwrap(
        createPageRequest(
          limit: limit,
          cursor: cursor == null ? null : unwrap(parsePageCursor(cursor)),
        ),
      );
      Future<Object> itemsOf(
        Fakes fakes,
        MeetingPeriod period,
        PageRequest page,
      ) async {
        final result = await fakes.meetings.list(period, page);
        return switch (result) {
          Ok(:final value) => value,
          Err(:final error) => error,
        };
      }

      test('sorts the upcoming meetings soonest first, '
          'whatever order it was given them in', () async {
        final fakes = createFakes();
        fakes.meetings.setMeetings(MeetingPeriod.upcoming, [u3, u1, u4, u2]);

        expect(
          await itemsOf(fakes, MeetingPeriod.upcoming, request(10)),
          equals(createPage([u1, u2, u3, u4])),
        );
      });

      test('sorts the past meetings latest first', () async {
        final fakes = createFakes();
        final p1 = upcoming('p1', -1);
        final p2 = upcoming('p2', -2);
        final p3 = upcoming('p3', -3);
        fakes.meetings.setMeetings(MeetingPeriod.past, [p2, p3, p1]);

        expect(
          await itemsOf(fakes, MeetingPeriod.past, request(10)),
          equals(createPage([p1, p2, p3])),
        );
      });

      test(
        'cuts the list to the size of the page, '
        'and gives the cursor to the next one only when there is more',
        () async {
          final fakes = createFakes();
          fakes.meetings.setMeetings(MeetingPeriod.upcoming, [u1, u2, u3, u4]);

          expect(
            await itemsOf(fakes, MeetingPeriod.upcoming, request(2)),
            equals(createPage([u1, u2], unwrap(parsePageCursor('u2')))),
          );
          expect(
            await itemsOf(fakes, MeetingPeriod.upcoming, request(1)),
            equals(createPage([u1], unwrap(parsePageCursor('u1')))),
          );
          expect(
            await itemsOf(fakes, MeetingPeriod.upcoming, request(4)),
            equals(createPage([u1, u2, u3, u4])),
          );
        },
      );

      test('continues after the cursor', () async {
        final fakes = createFakes();
        fakes.meetings.setMeetings(MeetingPeriod.upcoming, [u1, u2, u3, u4]);

        expect(
          await itemsOf(fakes, MeetingPeriod.upcoming, request(2, 'u2')),
          equals(createPage([u3, u4])),
        );
        expect(
          await itemsOf(fakes, MeetingPeriod.upcoming, request(1, 'u3')),
          equals(createPage([u4])),
        );
      });

      test('gives an empty page for a cursor that matches nothing, '
          'for a period without meetings', () async {
        final fakes = createFakes();
        fakes.meetings.setMeetings(MeetingPeriod.upcoming, [u1, u2]);

        expect(
          await itemsOf(fakes, MeetingPeriod.upcoming, request(2, 'unknown')),
          equals(createPage<MeetingSummary>([])),
        );
        expect(
          await itemsOf(fakes, MeetingPeriod.past, request(2)),
          equals(createPage<MeetingSummary>([])),
        );
      });

      test('records the calls it receives', () async {
        final fakes = createFakes();

        await itemsOf(fakes, MeetingPeriod.past, request(3));

        expect(
          fakes.meetings.listCalls,
          equals([(period: MeetingPeriod.past, request: request(3))]),
        );
      });
    });
  });

  group('the fake auth session', () {
    final session = aSession(
      user: aUser(id: aUserId('user-2'), email: anEmail('bruno@example.com')),
    );

    test(
      'signs in an account the test registered, and opens its session',
      () async {
        final fakes = createFakes();
        fakes.auth.session = null;
        fakes.auth.registerAccount(
          anEmail('bruno@example.com'),
          '  p4ss  ',
          session,
        );

        expect(
          await fakes.auth.signIn(
            Credentials(
              email: anEmail('bruno@example.com'),
              password: '  p4ss  ',
            ),
          ),
          equals(ok(session)),
        );
        expect(fakes.auth.session, equals(session));
      },
    );

    test('knows the default account', () async {
      final fakes = createFakes();

      expect(
        await fakes.auth.signIn(
          Credentials(email: anEmail(), password: defaultPassword),
        ),
        equals(ok(aSession())),
      );
    });

    for (final (name, email, password) in [
      ('a wrong password', anEmail(), 'Secret'),
      ('a password that was trimmed', anEmail(), 'secret '),
      (
        'an email nobody registered',
        anEmail('nobody@example.com'),
        defaultPassword,
      ),
    ]) {
      test('refuses $name, and signs nobody in', () async {
        final fakes = createFakes();
        fakes.auth.session = null;

        expect(
          await fakes.auth.signIn(
            Credentials(email: email, password: password),
          ),
          equals(err(invalidCredentials())),
        );
        expect(fakes.auth.session, isNull);
        expect(
          fakes.auth.signInCalls,
          equals([Credentials(email: email, password: password)]),
        );
      });
    }

    test('fails with the scripted failure, whatever the credentials', () async {
      final fakes = createFakes();
      fakes.auth.signInFailure = networkUnavailable();

      expect(
        await fakes.auth.signIn(
          Credentials(email: anEmail(), password: defaultPassword),
        ),
        equals(err(networkUnavailable())),
      );
    });
  });

  group('the fake vote repository', () {
    test(
      'is idempotent on the key: '
      'the same vote twice is recorded once, both times successfully',
      () async {
        final fakes = createFakes();

        expect(await fakes.votes.submit(aVote()), equals(ok<void>(null)));
        expect(await fakes.votes.submit(aVote()), equals(ok<void>(null)));

        expect(fakes.votes.recordedVotes(), equals([aVote()]));
      },
    );

    test('rejects a different choice under the same key as already voted, '
        'and keeps the first vote', () async {
      final fakes = createFakes();
      // The choice is spelled out: the scenario is about two different choices.
      // ignore: avoid_redundant_argument_values
      await fakes.votes.submit(aVote(choice: VoteChoice.forChoice));

      final second = await fakes.votes.submit(
        aVote(choice: VoteChoice.against),
      );

      expect(
        second,
        equals(
          err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
        ),
      );
      expect(
        fakes.votes.recordedVotes().map((vote) => vote.choice),
        equals([VoteChoice.forChoice]),
      );
    });

    test('answers unauthorized, not a voting error, '
        'to a vote whose voter is not the authenticated user', () async {
      final fakes = createFakes();

      expect(
        await fakes.votes.submit(aVote(voterId: aUserId('user-2'))),
        equals(err(unauthorized())),
      );
      fakes.auth.session = null;
      expect(await fakes.votes.submit(aVote()), equals(err(unauthorized())));
      expect(fakes.votes.recordedVotes(), isEmpty);
    });

    test('records a vote per resolution', () async {
      final fakes = createFakes();

      await fakes.votes.submit(aVote(resolutionId: aResolutionId('r1')));
      await fakes.votes.submit(aVote(resolutionId: aResolutionId('r2')));

      expect(fakes.votes.recordedVotes(), hasLength(2));
    });

    test(
      'plays the scripted answers first, in order, then behaves normally',
      () async {
        final fakes = createFakes();
        fakes.votes
          ..answerNext(err(networkUnavailable()))
          ..answerNext(ok<void>(null));

        expect(
          await fakes.votes.submit(aVote()),
          equals(err(networkUnavailable())),
        );
        expect(fakes.votes.recordedVotes(), isEmpty);
        expect(await fakes.votes.submit(aVote()), equals(ok<void>(null)));
        expect(fakes.votes.recordedVotes(), equals([aVote()]));
        expect(
          await fakes.votes.submit(aVote(resolutionId: aResolutionId('r2'))),
          equals(ok<void>(null)),
        );
        expect(fakes.votes.received, hasLength(3));
      },
    );

    test('calls the hook with each vote before it answers', () async {
      final fakes = createFakes();
      final seen = <String>[];
      fakes.votes.onReceive = (vote) => seen.add(vote.resolutionId);

      await fakes.votes.submit(aVote(resolutionId: aResolutionId('r1')));

      expect(seen, equals(['r1']));
    });
  });

  group('the fake vote outbox', () {
    final first = aPendingVote(
      aVote(resolutionId: aResolutionId('r1')),
      at(-2000),
    );
    final second = aPendingVote(
      aVote(resolutionId: aResolutionId('r2')),
      at(-1000),
    );
    final others = aPendingVote(
      aVote(voterId: aUserId('user-2'), resolutionId: aResolutionId('r1')),
    );

    test('lists the votes in the order they were enqueued, '
        'which no sort of the votes would give', () async {
      final fakes = createFakes();
      // Enqueued in this order, the votes are in decreasing order of instant
      // and in no order of resolution: a sort by instant, by resolution or by
      // key would give another.
      final enqueuedFirst = aPendingVote(
        aVote(resolutionId: aResolutionId('r9')),
        at(5000),
      );
      final enqueuedSecond = aPendingVote(
        aVote(resolutionId: aResolutionId('r1')),
        at(1000),
      );
      final enqueuedThird = aPendingVote(
        aVote(resolutionId: aResolutionId('r5')),
        at(-9000),
      );

      await fakes.outbox.enqueue(enqueuedFirst);
      await fakes.outbox.enqueue(enqueuedSecond);
      await fakes.outbox.enqueue(enqueuedThird);

      expect(
        await fakes.outbox.list(aUserId()),
        equals(
          ok(
            OutboxListing(
              votes: [enqueuedFirst, enqueuedSecond, enqueuedThird],
              unreadable: 0,
            ),
          ),
        ),
      );
      expect(
        await fakes.outbox.findByResolution(aResolutionId('r1'), aUserId()),
        equals(ok([enqueuedSecond])),
      );
    });

    test('only ever returns the votes of the voter it is asked for', () async {
      final fakes = createFakes();
      fakes.outbox.seed([first, others, second]);

      expect(
        await fakes.outbox.list(aUserId()),
        equals(ok(OutboxListing(votes: [first, second], unreadable: 0))),
      );
      expect(
        await fakes.outbox.list(aUserId('user-2')),
        equals(ok(OutboxListing(votes: [others], unreadable: 0))),
      );
      expect(
        await fakes.outbox.list(aUserId('user-3')),
        equals(ok(const OutboxListing(votes: [], unreadable: 0))),
      );
      expect(
        await fakes.outbox.findByResolution(aResolutionId('r1'), aUserId()),
        equals(ok([first])),
      );
      expect(
        await fakes.outbox.findByResolution(
          aResolutionId('r1'),
          aUserId('user-2'),
        ),
        equals(ok([others])),
      );
      expect(
        await fakes.outbox.findByResolution(
          aResolutionId('r2'),
          aUserId('user-2'),
        ),
        equals(ok(<OutboxVote>[])),
      );
    });

    test('says whether it enqueued the vote, '
        'or a vote with the same key was already there', () async {
      final fakes = createFakes();

      expect(
        await fakes.outbox.enqueue(first),
        equals(ok(const EnqueueResult.enqueued())),
      );
      expect(
        await fakes.outbox.enqueue(
          aPendingVote(
            aVote(
              resolutionId: aResolutionId('r1'),
              choice: VoteChoice.against,
            ),
            now,
          ),
        ),
        equals(ok(EnqueueResult.alreadyQueued(existing: first))),
      );

      expect(fakes.outbox.snapshot(), equals([first]));
    });

    test('holds the key of a rejected vote too', () async {
      final fakes = createFakes();
      final rejected = aRejectedVote(aVote(resolutionId: aResolutionId('r1')));
      fakes.outbox.seed([rejected]);

      expect(
        await fakes.outbox.enqueue(first),
        equals(ok(EnqueueResult.alreadyQueued(existing: rejected))),
      );
    });

    test('counts an attempt every time markAttempt is called: '
        'it is not idempotent', () async {
      final fakes = createFakes();
      fakes.outbox.seed([first]);

      await fakes.outbox.markAttempt(first.vote.idempotencyKey);
      await fakes.outbox.markAttempt(first.vote.idempotencyKey);

      expect(fakes.outbox.snapshot(), equals([first.copyWith(attempts: 2)]));
    });

    test('moves a pending vote to the rejected state, once, '
        'and ignores an unknown key', () async {
      final fakes = createFakes();
      fakes.outbox.seed([first, second]);
      const reason = ResolutionClosedError();

      await fakes.outbox.reject(first.vote.idempotencyKey, reason, at(10));
      await fakes.outbox.reject(
        first.vote.idempotencyKey,
        const NoVotingRightsError(),
        at(20),
      );
      await fakes.outbox.reject(
        aVote(resolutionId: aResolutionId('zz')).idempotencyKey,
        reason,
        at(30),
      );

      expect(
        fakes.outbox.snapshot(),
        equals([
          RejectedVote(
            vote: first.vote,
            enqueuedAt: first.enqueuedAt,
            attempts: 0,
            reason: reason,
            rejectedAt: at(10),
          ),
          second,
        ]),
      );
    });

    test('does not count an attempt on a rejected vote', () async {
      final fakes = createFakes();
      final rejected = aRejectedVote();
      fakes.outbox.seed([rejected]);

      await fakes.outbox.markAttempt(rejected.vote.idempotencyKey);

      expect(fakes.outbox.snapshot(), equals([rejected]));
    });

    test(
      'removes a vote, pending or rejected, and ignores an unknown key',
      () async {
        final fakes = createFakes();
        final rejected = aRejectedVote(
          aVote(resolutionId: aResolutionId('r3')),
        );
        fakes.outbox.seed([first, rejected, second]);

        await fakes.outbox.remove(rejected.vote.idempotencyKey);
        await fakes.outbox.remove(rejected.vote.idempotencyKey);
        await fakes.outbox.remove(first.vote.idempotencyKey);

        expect(fakes.outbox.snapshot(), equals([second]));
      },
    );
  });

  group('the fake caches', () {
    final owner = aUserId();
    final other = aUserId('user-2');

    test('return a miss as a value, not as an error', () async {
      final fakes = createFakes();

      expect(
        await fakes.meetingCache.readMeeting(owner, aMeetingId()),
        equals(ok<Object?>(null)),
      );
      expect(
        await fakes.meetingCache.readPage(owner, _pageKey),
        equals(ok<Object?>(null)),
      );
      expect(
        await fakes.documentCache.read(owner, aDocument().id),
        equals(ok<Object?>(null)),
      );
    });

    test(
      'give back what was saved, with the instant it was saved at',
      () async {
        final fakes = createFakes();
        final page = createPage([aMeetingSummary()]);
        final viewable = ViewableDocument(
          document: aDocument(),
          location: aDocumentLocation(),
        );

        await fakes.meetingCache.saveMeeting(owner, aMeeting(), at(10));
        await fakes.meetingCache.savePage(owner, _pageKey, page, at(20));
        await fakes.documentCache.save(owner, viewable, at(30));

        expect(
          await fakes.meetingCache.readMeeting(owner, aMeetingId()),
          equals(ok(CacheEntry(value: aMeeting(), cachedAt: at(10)))),
        );
        expect(
          await fakes.meetingCache.readPage(owner, _pageKey),
          equals(ok(CacheEntry(value: page, cachedAt: at(20)))),
        );
        expect(
          await fakes.documentCache.read(owner, aDocument().id),
          equals(ok(CacheEntry(value: viewable, cachedAt: at(30)))),
        );
      },
    );

    test(
      'keep the entries of each owner apart: another owner reads a miss',
      () async {
        final fakes = createFakes();
        final page = createPage([aMeetingSummary()]);
        final viewable = ViewableDocument(
          document: aDocument(),
          location: aDocumentLocation(),
        );
        await fakes.meetingCache.saveMeeting(owner, aMeeting(), at(10));
        await fakes.meetingCache.savePage(owner, _pageKey, page, at(20));
        await fakes.documentCache.save(owner, viewable, at(30));

        expect(
          await fakes.meetingCache.readMeeting(other, aMeetingId()),
          equals(ok<Object?>(null)),
        );
        expect(
          await fakes.meetingCache.readPage(other, _pageKey),
          equals(ok<Object?>(null)),
        );
        expect(
          await fakes.documentCache.read(other, aDocument().id),
          equals(ok<Object?>(null)),
        );
      },
    );

    test('include the page size in the key of a page', () async {
      final fakes = createFakes();
      await fakes.meetingCache.savePage(
        owner,
        _pageKey,
        createPage<MeetingSummary>([]),
        at(1),
      );

      expect(
        await fakes.meetingCache.readPage(owner, _pageKey.copyWith(limit: 21)),
        equals(ok<Object?>(null)),
      );
    });

    test(
      'remove one entry of one owner, and succeed when it is absent',
      () async {
        final fakes = createFakes();
        final viewable = ViewableDocument(
          document: aDocument(),
          location: aDocumentLocation(),
        );
        await fakes.meetingCache.saveMeeting(owner, aMeeting(), at(10));
        await fakes.meetingCache.saveMeeting(other, aMeeting(), at(10));
        await fakes.meetingCache.savePage(
          owner,
          _pageKey,
          createPage<MeetingSummary>([]),
          at(20),
        );
        await fakes.documentCache.save(owner, viewable, at(30));

        expect(
          await fakes.meetingCache.removeMeeting(owner, aMeetingId()),
          equals(ok<void>(null)),
        );
        expect(
          await fakes.meetingCache.removeMeeting(owner, aMeetingId()),
          equals(ok<void>(null)),
        );
        await fakes.meetingCache.removePage(owner, _pageKey);
        await fakes.documentCache.remove(owner, aDocument().id);

        expect(
          await fakes.meetingCache.readMeeting(owner, aMeetingId()),
          equals(ok<Object?>(null)),
        );
        expect(
          await fakes.meetingCache.readPage(owner, _pageKey),
          equals(ok<Object?>(null)),
        );
        expect(
          await fakes.documentCache.read(owner, aDocument().id),
          equals(ok<Object?>(null)),
        );
        expect(
          await fakes.meetingCache.readMeeting(other, aMeetingId()),
          equals(ok(CacheEntry(value: aMeeting(), cachedAt: at(10)))),
        );
      },
    );

    test('purge every entry of every owner', () async {
      final fakes = createFakes();
      await fakes.meetingCache.saveMeeting(owner, aMeeting(), at(10));
      await fakes.meetingCache.saveMeeting(other, aMeeting(), at(10));
      await fakes.meetingCache.savePage(
        owner,
        _pageKey,
        createPage<MeetingSummary>([]),
        at(20),
      );
      await fakes.documentCache.save(
        other,
        ViewableDocument(document: aDocument(), location: aDocumentLocation()),
        at(30),
      );

      expect(await fakes.meetingCache.purge(), equals(ok<void>(null)));
      expect(await fakes.documentCache.purge(), equals(ok<void>(null)));

      expect(fakes.meetingCache.isEmpty(), isTrue);
      expect(fakes.documentCache.isEmpty(), isTrue);
    });
  });

  group('the fake clock', () {
    test('only moves when it is told to', () {
      final fakes = createFakes();

      expect(fakes.clock.now(), equals(now));
      expect(fakes.clock.now(), equals(now));
      fakes.clock.advance(1500);
      expect(fakes.clock.now(), equals(at(1500)));
      fakes.clock.set(at(-5));
      expect(fakes.clock.now(), equals(at(-5)));
    });
  });

  group('the fake screen protection', () {
    test('stops calling a listener after its unsubscribe, '
        'which can be called twice', () {
      final fakes = createFakes();
      final received = <String>[];
      final unsubscribe = fakes.screenProtection.subscribe(
        (event) => received.add(event.kind.value),
      );

      fakes.screenProtection.emit(
        const ScreenCaptureEvent(kind: ScreenCaptureKind.screenshotTaken),
      );
      unsubscribe();
      unsubscribe();
      fakes.screenProtection.emit(
        const ScreenCaptureEvent(kind: ScreenCaptureKind.recordingStarted),
      );

      expect(received, equals([ScreenCaptureKind.screenshotTaken.value]));
    });
  });
}
