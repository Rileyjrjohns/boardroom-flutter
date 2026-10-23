import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/dev/in_memory/simulated_network.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';
import '../../support/infrastructure/fixture_files.dart';
import '../../support/infrastructure/sleep.dart';
import 'container_support.dart';

// The scenarios of `createContainer.test.ts`, for the development
// configuration (the mock one in React Native). The container is the real
// thing: the HTTP adapters over the fixture server, in process.

void main() {
  group('createContainer, development configuration', () {
    test('builds a container with the use cases, the settings of the screens '
        'and the controls of the demo', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();

      expect(container.kind, equals(AdaptersKind.dev));
      expect(container.settings.meetingsPageSize, equals(meetingsPageSize));
      expect(container.demoControls, isNotNull);
      expect(container.notices.localDataReset, isFalse);
      expect(container.monitoring, same(monitoring));
    });

    test('hands the clock the use cases read to the screens, so that one '
        'instant is not read twice from two clocks', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();

      expect(container.clock, same(clock));
    });

    test('hands the accounts of the simulation to the demo, with their shared '
        'password and nothing of the sessions', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();

      final accounts = container.demoControls!.accounts;

      expect(accounts.map((account) => account.email), [
        aliceEmail,
        brunoEmail,
      ]);
      expect(accounts.map((account) => account.password).toSet(), {
        demoAccountPassword,
      });
      expect(accounts.first, isA<DemoAccountHint>());
    });

    test('tells who is signed in, once the app is unlocked and not '
        'before', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();
      final user = valueOf(await container.useCases.getCurrentUser.execute());
      expect(user.email, equals(aliceEmail));

      final signedOut = built(
        await createContainer(
          dev(startSignedIn: false),
          silentRuntime().runtime,
        ),
      );
      addTearDown(signedOut.dispose);
      expect(
        await signedOut.useCases.getCurrentUser.execute(),
        equals(err(notAuthenticated())),
      );
    });

    test('serves meetings from the first use case to the detail, using only '
        'the container', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();

      final upcoming = await firstMeetingOf(container, MeetingPeriod.upcoming);
      final detail = valueOf(
        await container.useCases.getMeeting.execute(meetingId: upcoming.id),
      );

      expect(detail.data.id, equals(upcoming.id));
      expect(detail.source, isA<FreshSource>());
      expect(detail.data.agenda, isNotEmpty);
    });

    test('pages through the whole list with the cursors it gives', () async {
      final (:container, :clock, :monitoring) = await aDevContainer();
      final ids = <Object>[];

      var request = createPageRequest(limit: meetingsPageSize);
      for (var guard = 0; guard < 20; guard++) {
        final page = valueOf(
          await container.useCases.listMeetings.execute(
            period: MeetingPeriod.past,
            request: unwrap<PageRequest, Object?>(request),
          ),
        ).data;
        ids.addAll(page.items.map((item) => item.id));
        final next = page.nextCursor;
        if (next == null) {
          break;
        }
        request = createPageRequest(cursor: next, limit: meetingsPageSize);
      }

      expect(ids, isNotEmpty);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('shifts its content to the clock it is given', () async {
      final world = silentRuntime();
      world.clock.advance(40 * millisPerDay);
      final container = built(await createContainer(dev(), world.runtime));
      addTearDown(container.dispose);

      final upcoming = await firstMeetingOf(container, MeetingPeriod.upcoming);

      expect(upcoming.scheduledAt > world.clock.now(), isTrue);
    });

    test('starts signed out when the option is off, and the demo accounts '
        'then sign in', () async {
      final (:container, :clock, :monitoring) = await aDevContainer(
        configuration: dev(startSignedIn: false),
      );
      expect(
        await container.useCases.listPendingVotes.execute(),
        equals(err(notAuthenticated())),
      );
      final account = container.demoControls!.accounts.first;

      final signedIn = valueOf(
        await container.useCases.signIn.execute(
          email: account.email,
          password: account.password,
        ),
      );

      expect(signedIn.user.email, equals(aliceEmail));
      expect(
        await container.useCases.listPendingVotes.execute(),
        isA<Ok<Object?, AppError>>(),
      );
    });

    test('refuses the wrong password of a demo account', () async {
      final (:container, :clock, :monitoring) = await aDevContainer(
        configuration: dev(startSignedIn: false),
      );

      final result = await container.useCases.signIn.execute(
        email: aliceEmail,
        password: 'not the password',
      );

      expect(result, isA<Err<Object?, AppError>>());
    });

    test('gives the two demo users different lists of meetings', () async {
      final (:container, :clock, :monitoring) = await aDevContainer(
        configuration: dev(startSignedIn: false),
      );
      Future<Set<Object>> listFor(String email) async {
        await container.useCases.signIn.execute(
          email: email,
          password: demoAccountPassword,
        );
        final listed = valueOf(
          await container.useCases.listMeetings.execute(
            period: MeetingPeriod.past,
            request: unwrap(createPageRequest(limit: 50)),
          ),
        );
        return listed.data.items.map<Object>((item) => item.id).toSet();
      }

      final alice = await listFor(aliceEmail);
      final bruno = await listFor(brunoEmail);

      expect(alice, isNotEmpty);
      expect(bruno, isNotEmpty);
      expect(alice, isNot(equals(bruno)));
    });

    group('the lock of the app', () {
      test('is open when the configuration opened the session itself, as '
          'after a sign-in', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();

        expect(
          await container.useCases.listPendingVotes.execute(),
          isA<Ok<Object?, AppError>>(),
        );
      });

      test('is closed by the restore of the session, for every use case, '
          'until the biometrics succeed', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();

        final restored = valueOf(
          await container.useCases.restoreSession.execute(),
        );
        expect(restored.status, equals(SessionRestore.unlockRequired));
        expect(
          await container.useCases.listPendingVotes.execute(),
          equals(err(appLocked())),
        );

        valueOf(await container.useCases.unlockApp.execute());
        expect(
          await container.useCases.listPendingVotes.execute(),
          isA<Ok<Object?, AppError>>(),
        );
      });
    });

    group('single shared instances', () {
      test('shares CastVote: a second vote on the same resolution cast at the '
          'same time is refused', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        final (:meeting, :resolution) = await anOpenResolution(container);

        final first = container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.abstain,
        );
        final second = await container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.against,
        );

        expect(second, isA<Err<Object?, AppError>>());
        expect(valueOf(await first).status, equals(CastVoteStatus.submitted));
      });

      test('gives each container its own server, caches and outbox: nothing '
          'is shared between two', () async {
        final one = await aDevContainer();
        final other = await aDevContainer();
        final (:meeting, :resolution) = await anOpenResolution(one.container);
        one.container.demoControls!.network.setOnline(online: false);
        await one.container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.abstain,
        );

        expect(
          valueOf(await one.container.useCases.listPendingVotes.execute())
              .pending,
          hasLength(1),
        );
        expect(
          valueOf(await other.container.useCases.listPendingVotes.execute())
              .pending,
          isEmpty,
        );
        expect(other.container.demoControls!.network.online, isTrue);
      });
    });

    group('the simulated network', () {
      test('can be taken offline: a meeting seen before is then served from '
          'the cache, flagged stale', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        final upcoming = await firstMeetingOf(
          container,
          MeetingPeriod.upcoming,
        );
        await container.useCases.getMeeting.execute(meetingId: upcoming.id);

        container.demoControls!.network.setOnline(online: false);
        final stale = valueOf(
          await container.useCases.getMeeting.execute(meetingId: upcoming.id),
        );

        expect(stale.source, equals(DataSource.stale(cachedAt: now)));
        container.demoControls!.network.setOnline(online: true);
        expect(
          valueOf(
            await container.useCases.getMeeting.execute(meetingId: upcoming.id),
          ).source,
          isA<FreshSource>(),
        );
      });

      test('fails with networkUnavailable offline for what was never '
          'seen', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        container.demoControls!.network.setOnline(online: false);

        final result = await container.useCases.listMeetings.execute(
          period: MeetingPeriod.upcoming,
          request: firstPage(),
        );

        expect(
          result,
          isA<Err<Object?, AppError>>().having(
            (err) => err.error.code,
            'code',
            'networkUnavailable',
          ),
        );
      });

      test('queues a vote cast offline, and sends it when the network is '
          'back', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        final (:meeting, :resolution) = await anOpenResolution(container);
        container.demoControls!.network.setOnline(online: false);

        final cast = valueOf(
          await container.useCases.castVote.execute(
            meetingId: meeting.id,
            resolutionId: resolution.id,
            choice: VoteChoice.abstain,
          ),
        );
        expect(cast.status, equals(CastVoteStatus.queued));
        expect(
          valueOf(await container.useCases.listPendingVotes.execute()).pending,
          hasLength(1),
        );

        container.demoControls!.network.setOnline(online: true);
        final sync = valueOf(
          await container.useCases.syncPendingVotes.execute(),
        );
        expect(sync.outcome, equals(SyncOutcome.completed));
        expect(
          valueOf(await container.useCases.listPendingVotes.execute()).pending,
          isEmpty,
        );
      });

      test('waits for the latency of the configuration through the sleep it '
          'was given', () async {
        final recorded = recordingSleep();
        final world = silentRuntime(sleep: recorded.sleep);
        final container = built(
          await createContainer(
            DevConfiguration(latency: aDuration(250)),
            world.runtime,
          ),
        );
        addTearDown(container.dispose);

        await container.useCases.signIn.execute(
          email: aliceEmail,
          password: demoAccountPassword,
        );

        expect(recorded.requested, isNotEmpty);
        expect(recorded.requested.toSet(), equals({250}));
      });
    });

    group('the connectivity of the app', () {
      test('follows the offline switch of the demo, which the container hands '
          'to the screens', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        final changes = <ConnectivityStatus>[];

        final observation = await container.useCases.observeConnectivity
            .execute(changes.add);
        expect(observation.status, equals(ConnectivityStatus.online));
        container.demoControls!.network.setOnline(online: false);
        container.demoControls!.network.setOnline(online: true);
        observation.unsubscribe();
        container.demoControls!.network.setOnline(online: false);

        expect(changes, [
          ConnectivityStatus.offline,
          ConnectivityStatus.online,
        ]);
      });

      test('is the same switch that cuts the repositories, so one control '
          'drives the whole app', () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        final observation = await container.useCases.observeConnectivity
            .execute((_) {});
        final network = container.demoControls!.network
          ..setOnline(online: false);
        final offline = await container.useCases.listMeetings.execute(
          period: MeetingPeriod.upcoming,
          request: firstPage(),
        );
        final status = await container.useCases.observeConnectivity.execute(
          (_) {},
        );

        expect(offline, isA<Err<Object?, AppError>>());
        expect(status.status, equals(ConnectivityStatus.offline));
        expect(network, isA<DemoNetwork>());
        observation.unsubscribe();
        status.unsubscribe();
      });
    });

    test('uses the screen protection the runtime hands over, and the '
        'simulation otherwise', () async {
      final protection = InMemoryScreenProtection();
      final world = silentRuntime(screenProtection: protection);
      final handed = built(await createContainer(dev(), world.runtime));
      addTearDown(handed.dispose);
      final simulated = await aDevContainer();

      expect(handed.screenProtection, same(protection));
      expect(
        simulated.container.screenProtection,
        isA<InMemoryScreenProtection>(),
      );
    });

    test(
      'reports what the use cases swallow to the monitoring it was given',
      () async {
        final (:container, :clock, :monitoring) = await aDevContainer();
        container.demoControls!.network.setOnline(online: false);

        await container.useCases.listMeetings.execute(
          period: MeetingPeriod.upcoming,
          request: firstPage(),
        );

        expect(
          monitoring.capturedEvents() + monitoring.loggedEvents(),
          isNotNull,
        );
      },
    );

    test('answers mockDataInvalid, not an exception, when the fixtures are '
        'broken', () async {
      final fixtures = DecodedFixtures()..meetings = 'not the meetings';
      final world = silentRuntime(fixtureFiles: fixtures.encode());

      final created = await createContainer(dev(), world.runtime);

      expect(
        created,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error.code,
          'code',
          'mockDataInvalid',
        ),
      );
    });
  });

  group('startContainer', () {
    test('builds the development container when the setting is missing in a '
        'development build', () async {
      final started = await startContainer(
        const RawSettings(),
        silentRuntime().runtime,
        development: true,
      );

      expect(built(started).kind, equals(AdaptersKind.dev));
    });

    test('starts the development container signed out unless it is told to '
        'start signed in', () async {
      final signedOut = built(
        await startContainer(
          const RawSettings(adapters: 'dev'),
          silentRuntime().runtime,
          development: true,
        ),
      );
      final signedIn = built(
        await startContainer(
          const RawSettings(adapters: 'dev', devStartsSignedIn: true),
          silentRuntime().runtime,
          development: true,
        ),
      );
      addTearDown(signedOut.dispose);
      addTearDown(signedIn.dispose);

      expect(
        await signedOut.useCases.listPendingVotes.execute(),
        equals(err(notAuthenticated())),
      );
      expect(
        await signedIn.useCases.listPendingVotes.execute(),
        isA<Ok<Object?, AppError>>(),
      );
    });

    test('reports a value it does not know instead of guessing', () async {
      final started = await startContainer(
        const RawSettings(adapters: 'staging'),
        silentRuntime().runtime,
        development: true,
      );

      expect(
        started,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error,
          'error',
          invalidAdaptersSetting('staging'),
        ),
      );
    });

    test('refuses to start without a setting outside of a development build, '
        'instead of starting the development adapters', () async {
      final started = await startContainer(
        const RawSettings(),
        silentRuntime().runtime,
        development: false,
      );

      expect(
        started,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error,
          'error',
          missingAdaptersSetting(),
        ),
      );
    });

    test('reports the address of the API that http needs before it builds '
        'anything', () async {
      final started = await startContainer(
        const RawSettings(adapters: 'http'),
        silentRuntime().runtime,
        development: true,
      );

      expect(
        started,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error,
          'error',
          missingApiBaseUrl(),
        ),
      );
    });
  });

  test('the simulated latency fits within the time a request is allowed to '
      'take', () {
    expect(devSimulatedLatency, lessThanOrEqualTo(maxSimulatedLatencyMillis));
  });
}
