import 'dart:io';

import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/infrastructure/test_files.dart';
import 'container_support.dart';
import 'http_support.dart';

// Which biometrics the development configuration uses: those of the device
// when it has some enrolled, so that a demo on a phone asks for them, else the
// ones in memory, which always recognise the user, so that a simulator, an
// emulator without enrolment or a test can still sign in, unlock and vote.

void main() {
  final parent = temporaryDirectory();

  Future<({TestWorld world, AppContainer container})> start(
    Directory parent, {
    bool hardware = true,
    bool enrolled = true,
    LocalAuthenticationResult? outcome,
  }) async {
    final world = await aTestWorld(parent);
    world.biometrics
      ..hardware = hardware
      ..enrolled = enrolled;
    if (outcome != null) {
      world.biometrics.outcome = outcome;
    }
    final container = built(
      await createContainer(
        dev(),
        silentRuntime(platform: world.platform).runtime,
      ),
    );
    addTearDown(container.dispose);
    return (world: world, container: container);
  }

  Future<Result<CastVoteOutcome, AppError>> castOne(AppContainer container) {
    return anOpenResolution(container).then(
      (target) => container.useCases.castVote.execute(
        meetingId: target.meeting.id,
        resolutionId: target.resolution.id,
        choice: VoteChoice.forChoice,
      ),
    );
  }

  group('createContainer, development configuration, biometrics', () {
    test('asks the device to confirm a vote and to unlock the app when the '
        'device has biometrics enrolled', () async {
      final (:world, :container) = await start(parent);

      valueOf(await container.useCases.unlockApp.execute());
      final cast = await castOne(container);

      expect(valueOf(cast).status, equals(CastVoteStatus.submitted));
      expect(
        world.biometrics.prompts.map((prompt) => prompt.promptMessage),
        equals([
          BiometricReason.unlockApp.value,
          BiometricReason.confirmVote.value,
        ]),
      );
    });

    test('refuses the vote when the user does not pass the prompt of the '
        'device', () async {
      final (:world, :container) = await start(
        parent,
        outcome: const LocalAuthenticationResult.failed('user_cancel'),
      );

      final cast = await castOne(container);

      expect(
        cast,
        isA<Err<Object?, AppError>>().having(
          (err) => err.error.code,
          'code',
          'biometricCancelled',
        ),
      );
      expect(world.biometrics.prompts, hasLength(1));
    });

    test('uses the gate in memory, without a prompt, when the device has no '
        'biometric hardware', () async {
      final (:world, :container) = await start(parent, hardware: false);

      final cast = await castOne(container);

      expect(valueOf(cast).status, equals(CastVoteStatus.submitted));
      expect(world.biometrics.prompts, isEmpty);
    });

    test('uses the gate in memory, without a prompt, when the device has '
        'nothing enrolled', () async {
      final (:world, :container) = await start(parent, enrolled: false);

      valueOf(await container.useCases.unlockApp.execute());
      final cast = await castOne(container);

      expect(valueOf(cast).status, equals(CastVoteStatus.submitted));
      expect(world.biometrics.prompts, isEmpty);
    });

    test('uses the gate in memory when the platform cannot be asked (no '
        'plugin, as in a test or on a bare simulator)', () async {
      final container = built(
        await createContainer(dev(), silentRuntime().runtime),
      );
      addTearDown(container.dispose);

      final cast = await castOne(container);

      expect(valueOf(cast).status, equals(CastVoteStatus.submitted));
    });
  });
}
