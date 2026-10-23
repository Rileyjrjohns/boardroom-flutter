// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/features/votes/presentation/state/pending_votes.dart';
import 'package:boardroom/features/votes/presentation/state/sync_summary.dart';
import 'package:boardroom/features/votes/presentation/state/vote_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/create_fakes.dart';
import '../../../support/presentation/test_app.dart';
import 'votes_presentation_support.dart';

// The one place that decides when the votes that wait are sent. The use case
// does the sending; these tests are about the conditions under which the
// interface asks, what it tells the user, and what it refreshes afterwards.

final ResolutionId _r1 = aResolutionId('r1');
final ResolutionId _r2 = aResolutionId('r2');

typedef _Sync = ({
  Fakes fakes,
  ProviderContainer providers,
  RequestVoteSync request,
});

_Sync _renderSync({
  Fakes? fakes,
  Access access = Access.unlocked,
  HoldingVotes? holding,
  bool startsLocked = false,
}) {
  final theFakes = fakes ?? createFakes();
  final providers = TestApp(
    fakes: theFakes,
    startsLocked: startsLocked,
    adaptPorts: holding == null ? null : (ports) => withVotes(ports, holding),
  ).providers(access: access);
  providers.listen(syncSummaryStateProvider, (_, _) {});
  return (
    fakes: theFakes,
    providers: providers,
    request: providers.read(requestVoteSyncProvider),
  );
}

Future<void> _sync(_Sync rendered) async {
  rendered.request();
  await pumpEventQueue();
}

SyncSummary? _summaryOf(_Sync rendered) =>
    rendered.providers.read(syncSummaryStateProvider);

Access _accessOf(_Sync rendered) => rendered.providers.read(accessProvider);

String? _endedBy(_Sync rendered) =>
    rendered.providers.read(accessControllerProvider).sessionEndedBy;

int _epochOf(_Sync rendered) =>
    rendered.providers.read(accessControllerProvider).epoch;

HoldingVotes _holdServer(Fakes fakes) => HoldingVotes(fakes.votes);

// How many times the use case ran: each run, however it ends, is logged once.
int _runsOf(Fakes fakes) => fakes.monitoring.logs
    .where(
      (record) =>
          record.event == MonitoringEvent.voteSyncCompleted ||
          record.event == MonitoringEvent.voteSyncInterrupted,
    )
    .length;

void main() {
  group('useVoteSync', () {
    group('what it sends', () {
      test('sends the votes that wait, oldest first, and '
          'records them with the server', () async {
        final fakes = createFakes();
        fakes.outbox.seed([
          aPendingVote(aVote(resolutionId: _r1)),
          aPendingVote(aVote(resolutionId: _r2)),
        ]);
        final rendered = _renderSync(fakes: fakes);

        await _sync(rendered);

        expect(fakes.votes.received.map((vote) => vote.resolutionId), [
          _r1,
          _r2,
        ]);
        expect(fakes.outbox.snapshot(), isEmpty);
      });

      test(
        'tells how many were sent, in the banner, when something was',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([
            aPendingVote(aVote(resolutionId: _r1)),
            aPendingVote(aVote(resolutionId: _r2)),
          ]);
          final rendered = _renderSync(fakes: fakes);

          await _sync(rendered);

          expect(
            _summaryOf(rendered),
            const SyncSummary(synced: 2, rejected: 0),
          );
        },
      );

      test(
        'tells how many were rejected when the server refused some',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([
            aPendingVote(aVote(resolutionId: _r1)),
            aPendingVote(aVote(resolutionId: _r2)),
          ]);
          fakes.votes.answerNext(err(const NoVotingRightsError()));
          final rendered = _renderSync(fakes: fakes);

          await _sync(rendered);

          expect(
            _summaryOf(rendered),
            const SyncSummary(synced: 1, rejected: 1),
          );
        },
      );

      test('says nothing when nothing waited, nothing was '
          'sent and nothing was rejected', () async {
        final rendered = _renderSync();

        await _sync(rendered);

        expect(_summaryOf(rendered), isNull);
      });

      test('says nothing when the network is down: the votes '
          'stay, and no attempt is counted', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        fakes.network.goOffline();
        final rendered = _renderSync(fakes: fakes);

        await _sync(rendered);

        expect(_summaryOf(rendered), isNull);
        expect(fakes.outbox.snapshot(), hasLength(1));
        expect((fakes.outbox.snapshot().single as PendingVote).attempts, 0);
        expect(_accessOf(rendered), Access.unlocked);
      });

      test('says nothing when the server fails in a way '
          'that says nothing about the vote', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        fakes.votes.answerNext(err(const UnexpectedError()));
        final rendered = _renderSync(fakes: fakes);

        await _sync(rendered);

        expect(_summaryOf(rendered), isNull);
        expect(fakes.outbox.snapshot(), hasLength(1));
      });
    });

    group('what it refreshes afterwards', () {
      test('asks again for the outbox and for the '
          'meetings, when something was sent', () async {
        final fakes = createFakes();
        fakes.meetings.addMeeting(aMeeting());
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        final rendered = _renderSync(fakes: fakes);
        final providers = rendered.providers;
        final outboxes = <OutboxContent>[];
        final meetingLoads = <Object?>[];
        providers.listen(
          pendingVotesProvider,
          (_, next) => outboxes.add(next.requireValue),
        );
        providers.listen(
          meetingQueryProvider(aVote().meetingId),
          (_, next) => meetingLoads.add(next.value),
        );
        await providers.read(pendingVotesProvider.future);
        await providers.read(meetingQueryProvider(aVote().meetingId).future);
        final before = meetingLoads.length;

        await _sync(rendered);

        expect(outboxes.last.pending, isEmpty);
        expect(meetingLoads.length, greaterThan(before));
      });

      test('leaves the queries alone when nothing changed', () async {
        final rendered = _renderSync();
        final outboxes = <OutboxContent>[];
        rendered.providers.listen(
          pendingVotesProvider,
          (_, next) => outboxes.add(next.requireValue),
        );
        await rendered.providers.read(pendingVotesProvider.future);
        final before = outboxes.length;

        await _sync(rendered);

        expect(outboxes.length, before);
      });
    });

    group('when it does not send', () {
      for (final access in [Access.locked, Access.signedOut, Access.starting]) {
        test(
          'does not ask the use case at all while the state is ${access.value}',
          () async {
            final fakes = createFakes();
            fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
            final rendered = _renderSync(fakes: fakes, access: access);

            await _sync(rendered);

            expect(fakes.votes.received, isEmpty);
            expect(fakes.outbox.snapshot(), hasLength(1));
          },
        );
      }

      test(
        'sends once the app is open again, when it is asked again',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
          final rendered = _renderSync(fakes: fakes, access: Access.locked);
          await _sync(rendered);
          expect(fakes.votes.received, isEmpty);

          rendered.providers.read(accessControllerProvider.notifier).unlocked();
          await _sync(rendered);

          expect(fakes.votes.received, hasLength(1));
        },
      );
    });

    group('never two runs at once', () {
      test('answers a request that comes during a run with one '
          'more run after it, not a concurrent one', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        final server = _holdServer(fakes);
        final rendered = _renderSync(fakes: fakes, holding: server);

        rendered.request();
        rendered.request();
        rendered.request();
        await pumpEventQueue();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r2))]);
        server.release();
        await pumpEventQueue();

        expect(server.overlapped, isFalse);
        expect(fakes.votes.recordedVotes().map((vote) => vote.resolutionId), [
          _r1,
          _r2,
        ]);
        expect(server.calls, 2);
      });

      test('asks again later: the guard is released when a run ends', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        final rendered = _renderSync(fakes: fakes);
        await _sync(rendered);

        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r2))]);
        await _sync(rendered);

        expect(fakes.votes.received.map((vote) => vote.resolutionId), [
          _r1,
          _r2,
        ]);
      });

      test(
        'does not run again after the user left the open app during a run',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
          final server = _holdServer(fakes);
          final rendered = _renderSync(fakes: fakes, holding: server);
          rendered.request();
          rendered.request();
          await pumpEventQueue();

          rendered.providers
              .read(accessControllerProvider.notifier)
              .locked(_epochOf(rendered));
          server.release();
          await pumpEventQueue();

          expect(fakes.votes.received, hasLength(1));
          expect(_runsOf(fakes), 1);
        },
      );
    });

    group('when the run meets the end of the session', () {
      test(
        'ends it for the whole app when the server refuses the session',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
          fakes.votes.answerNext(err(unauthorized()));
          final rendered = _renderSync(fakes: fakes);

          await _sync(rendered);

          expect(_accessOf(rendered), Access.signedOut);
          expect(_endedBy(rendered), 'unauthorized');
          expect(_summaryOf(rendered), isNull);
        },
      );

      test(
        'sends the user to the lock screen when the app is locked under it',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
          final rendered = _renderSync(fakes: fakes, startsLocked: true);

          await _sync(rendered);

          expect(_accessOf(rendered), Access.locked);
          expect(fakes.votes.received, isEmpty);
        },
      );

      test(
        'sends the user to the sign-in screen when somebody else signs in '
        'during the run, and the server refuses the vote of the first',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([
            aPendingVote(aVote(resolutionId: _r1)),
            aPendingVote(aVote(resolutionId: _r2)),
          ]);
          fakes.votes.onReceive = (_) {
            fakes.auth.session = aSession(user: aUser(id: aUserId('user-2')));
          };
          final rendered = _renderSync(fakes: fakes);

          await _sync(rendered);

          expect(_accessOf(rendered), Access.signedOut);
          expect(_endedBy(rendered), 'unauthorized');
          expect(_summaryOf(rendered), isNull);
        },
      );

      test(
        'sends the user to the sign-in screen when nobody is signed in',
        () async {
          final fakes = createFakes();
          fakes.auth.session = null;
          final rendered = _renderSync(fakes: fakes);

          await _sync(rendered);

          expect(_endedBy(rendered), 'notAuthenticated');
        },
      );

      test('does not end the session for a connection that is down', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        fakes.votes.answerNext(err(networkUnavailable()));
        final rendered = _renderSync(fakes: fakes);

        await _sync(rendered);

        expect(_accessOf(rendered), Access.unlocked);
      });

      test('does not end the session for an outbox that cannot be read: '
          'a fault of the device is not the end of it', () async {
        final fakes = createFakes();
        fakes.outbox.listFailure = storageReadFailed();
        final rendered = _renderSync(fakes: fakes);

        await _sync(rendered);

        expect(_accessOf(rendered), Access.unlocked);
      });
    });

    group('the summary the runs leave', () {
      test('adds up what the runs sent, until the user dismisses it', () async {
        final fakes = createFakes();
        final rendered = _renderSync(fakes: fakes);
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        await _sync(rendered);
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r2))]);
        fakes.votes.answerNext(err(const NoVotingRightsError()));

        await _sync(rendered);

        expect(_summaryOf(rendered), const SyncSummary(synced: 1, rejected: 1));

        rendered.providers.read(syncSummaryStateProvider.notifier).dismiss();
        fakes.outbox.seed([
          aPendingVote(aVote(resolutionId: aResolutionId('r3'))),
        ]);
        await _sync(rendered);

        expect(_summaryOf(rendered), const SyncSummary(synced: 1, rejected: 0));
      });
    });

    group('a run that outlives the user who started it', () {
      // The user of the run leaves, and somebody else signs in, while the
      // server is answering.
      void swapUsers(_Sync rendered) {
        final access = rendered.providers.read(
          accessControllerProvider.notifier,
        );
        access.signedOut();
        access.signedIn();
      }

      test(
        'does not show what it sent to the user who signed in after',
        () async {
          final fakes = createFakes();
          fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
          final server = _holdServer(fakes);
          final rendered = _renderSync(fakes: fakes, holding: server);
          rendered.request();
          await pumpEventQueue();

          swapUsers(rendered);
          server.release();
          await pumpEventQueue();

          expect(fakes.votes.received, hasLength(1));
          expect(_summaryOf(rendered), isNull);
          expect(_accessOf(rendered), Access.unlocked);
        },
      );

      for (final (code, script) in <(String, void Function(Fakes))>[
        (
          'unauthorized',
          (fakes) => fakes.votes.answerNext(err(unauthorized())),
        ),
        (
          'notAuthenticated',
          (fakes) => fakes.votes.onReceive = (_) => fakes.auth.session = null,
        ),
      ]) {
        test(
          'does not sign the user who signed in after out when it meets $code',
          () async {
            final fakes = createFakes();
            fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
            script(fakes);
            final server = _holdServer(fakes);
            final rendered = _renderSync(fakes: fakes, holding: server);
            rendered.request();
            await pumpEventQueue();

            swapUsers(rendered);
            server.release();
            await pumpEventQueue();

            expect(_accessOf(rendered), Access.unlocked);
            expect(_endedBy(rendered), isNull);
          },
        );
      }

      test('is followed by a run of its own for the user who '
          'signed in after, when they asked for one', () async {
        final fakes = createFakes();
        fakes.outbox.seed([aPendingVote(aVote(resolutionId: _r1))]);
        final server = _holdServer(fakes);
        final rendered = _renderSync(fakes: fakes, holding: server);
        rendered.request();
        await pumpEventQueue();

        swapUsers(rendered);
        rendered.request();
        server.release();
        await pumpEventQueue();

        // Two runs: the one that outlived its user, then the one asked for
        // by the user who came after.
        expect(_runsOf(fakes), 2);
      });
    });
  });
}
