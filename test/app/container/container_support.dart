import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/app/device/device_platform.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:boardroom/core/infrastructure/clock/sleep.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/fake_clock.dart';
import '../../support/fakes/fake_monitoring.dart';
import '../../support/infrastructure/fixture_files.dart';
import '../../support/infrastructure/memory_file_volume.dart';
import '../../support/infrastructure/sleep.dart';

// Test support, not production code: the runtime and the helpers the tests of
// the container share (the counterpart of `silentRuntime`, `aContainer` and
// friends of `createContainer.test.ts`).

/// The email of the first account of the simulation.
const String aliceEmail = 'alice.martin@boardroom.example';

/// The email of the second account of the simulation.
const String brunoEmail = 'bruno.durand@boardroom.example';

/// The password of the accounts of the simulation.
const String demoAccountPassword = 'boardroom-demo';

/// The prompt text the tests hand over: the reason and a fixed cancel label.
PromptText testPromptText(BiometricReason reason) =>
    PromptText(message: reason.value, cancelLabel: 'cancel');

/// What the container reads from the outside, replaced: a clock that stands
/// still, a network that does not wait, a monitoring that writes nowhere, the
/// fixtures from the files of the project and the files in memory. The other
/// arguments replace what a test controls.
({ContainerRuntime runtime, FakeClock clock, FakeMonitoring monitoring})
silentRuntime({
  FakeClock? clock,
  FakeMonitoring? monitoring,
  FileStore? fileStore,
  Sleep? sleep,
  FixtureFiles? fixtureFiles,
  ScreenProtection? screenProtection,
  DevicePlatform? platform,
  HttpClientAdapter? httpAdapter,
  BiometricPromptText? biometricPromptText,
}) {
  final theClock = clock ?? FakeClock();
  final theMonitoring = monitoring ?? FakeMonitoring();
  return (
    runtime: ContainerRuntime(
      clock: theClock,
      sleep: sleep ?? immediateSleep,
      monitoring: theMonitoring,
      fileStore: fileStore ?? createFileStore(MemoryFileVolume()),
      fixtureFiles: fixtureFiles ?? readFixtureFiles(),
      screenProtection: screenProtection,
      platform: platform,
      httpAdapter: httpAdapter,
      biometricPromptText: biometricPromptText ?? testPromptText,
    ),
    clock: theClock,
    monitoring: theMonitoring,
  );
}

/// The development configuration the tests use: signed in as the first account
/// at start unless it says otherwise, and no latency.
DevConfiguration dev({bool startSignedIn = true}) =>
    DevConfiguration(startSignedIn: startSignedIn, latency: aDuration(0));

/// The container that was built, or the failure of the test.
AppContainer built(Result<AppContainer, Object?> created) => switch (created) {
  Ok(:final value) => value,
  Err(:final error) => throw TestFailure('The container was not built: $error'),
};

/// A development container that does not wait and whose clock stands still.
Future<({AppContainer container, FakeClock clock, FakeMonitoring monitoring})>
aDevContainer({DevConfiguration? configuration}) async {
  final world = silentRuntime();
  final container = built(
    await createContainer(configuration ?? dev(), world.runtime),
  );
  addTearDown(container.dispose);
  return (
    container: container,
    clock: world.clock,
    monitoring: world.monitoring,
  );
}

/// The first page of the list, as the screens ask for it.
PageRequest firstPage() => unwrap(createPageRequest(limit: meetingsPageSize));

/// The value of a success, or the failure of the test.
T valueOf<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw TestFailure('Expected a success, got $error'),
};

/// The first meeting of a period for the signed-in user.
Future<MeetingSummary> firstMeetingOf(
  AppContainer container,
  MeetingPeriod period,
) async {
  final listed = valueOf(
    await container.useCases.listMeetings.execute(
      period: period,
      request: firstPage(),
    ),
  );
  return listed.data.items.first;
}

/// A meeting of the first page of the upcoming ones that has an open
/// resolution nobody voted on.
Future<({Meeting meeting, Resolution resolution})> anOpenResolution(
  AppContainer container,
) async {
  final upcoming = await firstMeetingOf(container, MeetingPeriod.upcoming);
  final meeting = valueOf(
    await container.useCases.getMeeting.execute(meetingId: upcoming.id),
  ).data;
  final resolution = meeting.agenda
      .map((item) => item.resolution)
      .whereType<Resolution>()
      .firstWhere(
        (candidate) =>
            candidate.status == ResolutionStatus.open &&
            candidate.recordedVote == null,
      );
  return (meeting: meeting, resolution: resolution);
}
