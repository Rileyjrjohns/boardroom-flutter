import 'dart:io';

import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/infrastructure/test_files.dart';
import 'container_support.dart';
import 'http_support.dart';

// The scenarios of `createContainer.http.test.ts`: the real configuration over
// the encrypted database, the keychain, the biometrics and the network of a
// device, with the fixture server standing in for the API.

void main() {
  final parent = temporaryDirectory();

  Future<void> signInAlice(AppContainer container) async {
    valueOf(
      await container.useCases.signIn.execute(
        email: aliceEmail,
        password: demoAccountPassword,
      ),
    );
  }

  group('createContainer, http configuration, end to end', () {
    test('builds a container of the http kind, with all the use cases and the '
        'settings of the screens', () async {
      final world = await aTestWorld(parent);

      final container = await world.start();

      expect(container.kind, equals(AdaptersKind.http));
      expect(container.settings.meetingsPageSize, equals(meetingsPageSize));
      expect(container.demoControls, isNull);
      expect(container.clock, same(world.clock));
      expect(container.screenProtection, same(world.screenProtection));
      expect(container.notices.localDataReset, isFalse);
    });

    test('runs the whole journey: sign in, list, detail, vote, offline, '
        'queued vote, back online, sync, restart', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      await signInAlice(container);

      final listed = await firstMeetingOf(container, MeetingPeriod.upcoming);
      final detail = valueOf(
        await container.useCases.getMeeting.execute(meetingId: listed.id),
      );
      expect(detail.source, isA<FreshSource>());

      final (:meeting, :resolution) = await anOpenResolution(container);
      final submitted = valueOf(
        await container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.forChoice,
        ),
      );
      expect(submitted.status, equals(CastVoteStatus.submitted));
      expect(
        world.server.backend.recordedVotes().any(
          (vote) => vote.resolutionId == resolution.id,
        ),
        isTrue,
      );

      // Offline: the same meeting is served from the database, and the next
      // vote is queued.
      world.server.backend.network.setOnline(online: false);
      final stale = valueOf(
        await container.useCases.getMeeting.execute(meetingId: listed.id),
      );
      expect(stale.source, isA<StaleSource>());

      // Back online.
      world.server.backend.network.setOnline(online: true);
      final sync = valueOf(await container.useCases.syncPendingVotes.execute());
      expect(sync.outcome, equals(SyncOutcome.completed));

      // Restart: the session is kept in the keychain, and the app is locked.
      await container.dispose();
      final restarted = await world.start();
      final restored = valueOf(
        await restarted.useCases.restoreSession.execute(),
      );
      expect(restored.status, equals(SessionRestore.unlockRequired));
      valueOf(await restarted.useCases.unlockApp.execute());
      expect(
        valueOf(await restarted.useCases.getCurrentUser.execute()).email,
        equals(aliceEmail),
      );
    });

    test('keeps the database encrypted with a key that only the secure '
        'storage holds', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      await signInAlice(container);
      await firstMeetingOf(container, MeetingPeriod.upcoming);
      await container.dispose();

      final files = world.databases.listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        final header = file.readAsBytesSync().take(15).toList();
        expect(String.fromCharCodes(header), isNot(equals('SQLite format 3')));
      }
      expect(
        world.storage.snapshot().keys,
        contains(SecureStorageKey.databaseKey.value),
      );
    });

    test('queues the vote of a device that is offline, and sends it when the '
        'connection comes back', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      await signInAlice(container);
      final (:meeting, :resolution) = await anOpenResolution(container);
      world.server.backend.network.setOnline(online: false);

      final cast = valueOf(
        await container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.abstain,
        ),
      );
      expect(cast.status, equals(CastVoteStatus.queued));

      // The queue is in the database: it survives a restart of the app.
      await container.dispose();
      final restarted = await world.start();
      valueOf(await restarted.useCases.restoreSession.execute());
      valueOf(await restarted.useCases.unlockApp.execute());
      expect(
        valueOf(await restarted.useCases.listPendingVotes.execute()).pending,
        hasLength(1),
      );

      world.server.backend.network.setOnline(online: true);
      final sync = valueOf(await restarted.useCases.syncPendingVotes.execute());
      expect(sync.outcome, equals(SyncOutcome.completed));
      expect(
        valueOf(await restarted.useCases.listPendingVotes.execute()).pending,
        isEmpty,
      );
    });

    test(
      'refuses a vote the biometrics do not confirm, and keeps nothing',
      () async {
        final world = await aTestWorld(parent);
        final container = await world.start();
        await signInAlice(container);
        final (:meeting, :resolution) = await anOpenResolution(container);
        world.biometrics.outcome = const LocalAuthenticationResult.failed(
          'user_cancel',
        );

        final cancelled = await container.useCases.castVote.execute(
          meetingId: meeting.id,
          resolutionId: resolution.id,
          choice: VoteChoice.forChoice,
        );

        expect(
          cancelled,
          isA<Err<Object?, AppError>>().having(
            (err) => err.error.code,
            'code',
            'biometricCancelled',
          ),
        );
        expect(
          world.server.backend.recordedVotes().where(
            (vote) => vote.resolutionId == resolution.id,
          ),
          isEmpty,
        );
        expect(
          valueOf(await container.useCases.listPendingVotes.execute()).pending,
          isEmpty,
        );
      },
    );

    test('ends the session when the server no longer knows the token: it is '
        'forgotten on the device', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      await signInAlice(container);
      await firstMeetingOf(container, MeetingPeriod.upcoming);
      world.server.api.revokeSessions();

      final refused = await container.useCases.listMeetings.execute(
        period: MeetingPeriod.past,
        request: firstPage(),
      );

      expect(
        refused,
        isA<Err<Object?, AppError>>().having(
          (err) => err.error.code,
          'code',
          'unauthorized',
        ),
      );
      expect(
        await container.useCases.getCurrentUser.execute(),
        isA<Err<Object?, AppError>>(),
      );
    });

    test('follows the network state of the device', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      final changes = <ConnectivityStatus>[];

      final observation = await container.useCases.observeConnectivity.execute(
        changes.add,
      );
      world.network.change(
        const NetworkSnapshot(isConnected: false, isInternetReachable: false),
      );
      await Future<void>.delayed(Duration.zero);

      expect(observation.status, equals(ConnectivityStatus.online));
      expect(changes, [ConnectivityStatus.offline]);
      observation.unsubscribe();
    });
  });

  group('startContainer, http configuration, when it cannot start', () {
    for (final (name, settings, code) in [
      (
        'no address of the API',
        const RawSettings(adapters: 'http'),
        'missingApiBaseUrl',
      ),
      (
        'an address that is not one',
        const RawSettings(adapters: 'http', apiBaseUrl: 'api'),
        'invalidApiBaseUrl',
      ),
      (
        'a clear address in a release build',
        const RawSettings(adapters: 'http', apiBaseUrl: 'http://api.example'),
        'insecureApiBaseUrl',
      ),
      (
        'a timeout out of bounds',
        const RawSettings(
          adapters: 'http',
          apiBaseUrl: testApiBaseUrl,
          requestTimeoutMillis: 5,
        ),
        'invalidRequestTimeout',
      ),
      (
        'a passcode setting that is not a yes or a no',
        const RawSettings(
          adapters: 'http',
          apiBaseUrl: testApiBaseUrl,
          allowDevicePasscode: 'yes',
        ),
        'invalidBiometricFallback',
      ),
    ]) {
      test('says $code for $name, before it touches the device', () async {
        final world = await aTestWorld(parent);

        final started = await startContainer(
          settings,
          world.runtime(),
          development: false,
        );

        expect(
          started,
          isA<Err<Object?, ContainerError>>().having(
            (err) => err.error.code,
            'code',
            code,
          ),
        );
        expect(world.storage.getCalls, equals(0));
        expect(world.databases.existsSync(), isFalse);
      });
    }

    test('says the storage is unavailable when the keychain cannot be read, '
        'and starts nothing', () async {
      final world = await aTestWorld(parent);
      world.storage.failNext(100);

      final started = await createContainer(
        world.configuration(),
        world.runtime(),
      );

      expect(
        started,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error,
          'error',
          storageUnavailable(DatabaseFailureReason.keyStorage),
        ),
      );
    });

    test('answers with an error of its own instead of throwing, whatever the '
        'device throws', () async {
      final world = await aTestWorld(parent);
      // No folder for the files is handed over, and the plugin that finds one
      // is not there in a test: the device fails to provide it.
      final started = await createContainer(
        world.configuration(),
        ContainerRuntime(
          clock: world.clock,
          monitoring: world.monitoring,
          platform: world.platform,
          screenProtection: world.screenProtection,
          httpAdapter: world.server.adapter,
        ),
      );

      expect(
        started,
        isA<Err<Object?, ContainerError>>().having(
          (err) => err.error,
          'error',
          platformUnavailable(),
        ),
      );
      expect(
        world.databases.existsSync() ? world.databases.listSync() : <Object>[],
        isEmpty,
      );
    });
  });

  group('startContainer, http configuration, the settings reach the '
      'adapters', () {
    test('refuses the passcode by default', () async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      await signInAlice(container);
      await container.useCases.restoreSession.execute();

      await container.useCases.unlockApp.execute();

      expect(world.biometrics.prompts.single.disableDeviceFallback, isTrue);
    });

    test('accepts the passcode when the configuration says so', () async {
      final world = await aTestWorld(parent);
      final created = built(
        await createContainer(
          world.configuration(allowDevicePasscode: true),
          world.runtime(),
        ),
      );
      addTearDown(created.dispose);

      await created.useCases.restoreSession.execute();
      await created.useCases.unlockApp.execute();

      expect(world.biometrics.prompts.single.disableDeviceFallback, isFalse);
    });

    test('asks for strong biometrics, with the cancel label of the language, '
        'for the reason it was given', () async {
      final world = await aTestWorld(parent);
      final container = await world.start(
        runtime: world.runtime(
          biometricPromptText: (reason) => PromptText(
            message: 'message for ${reason.value}',
            cancelLabel: 'annuler',
          ),
        ),
      );

      await container.useCases.restoreSession.execute();
      await container.useCases.unlockApp.execute();

      final prompt = world.biometrics.prompts.single;
      expect(
        prompt.biometricsSecurityLevel,
        equals(BiometricsSecurityLevel.strong),
      );
      expect(prompt.cancelLabel, equals('annuler'));
      expect(
        prompt.promptMessage,
        equals('message for ${BiometricReason.unlockApp.value}'),
      );
    });
  });

  group('startContainer, http configuration, when local data cannot be '
      'read', () {
    /// Starts the app once, then loses the key of the database, as a cleared
    /// keychain does.
    Future<TestWorld> aDeviceThatLostItsKey() async {
      final world = await aTestWorld(parent);
      final first = await world.start();
      await first.dispose();
      await world.storage.remove(SecureStorageKey.databaseKey.value);
      return world;
    }

    test('starts on a new database, tells the notice once, and keeps the old '
        'file', () async {
      final world = await aDeviceThatLostItsKey();
      final filesBefore = world.databases.listSync().length;

      final container = await world.start();

      expect(container.notices.localDataReset, isTrue);
      expect(world.databases.listSync().length, greaterThan(filesBefore));
    });

    test('tells the notice again at the next start until it is acknowledged, '
        'and not after', () async {
      final world = await aDeviceThatLostItsKey();
      final first = await world.start();
      expect(first.notices.localDataReset, isTrue);
      await first.dispose();

      final second = await world.start();
      expect(second.notices.localDataReset, isTrue);
      await second.notices.acknowledgeLocalDataReset();
      await second.dispose();

      final third = await world.start();
      expect(third.notices.localDataReset, isFalse);
    });

    test('has nothing to tell on a start where nothing was lost', () async {
      final world = await aTestWorld(parent);
      final first = await world.start();
      await first.dispose();

      final second = await world.start();

      expect(second.notices.localDataReset, isFalse);
    });
  });
}
