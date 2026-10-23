import 'dart:io';

import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/dev/fixture_server/fixture_server.dart';
import 'package:boardroom/app/device/device_platform.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/builders/builders.dart';
import '../../support/fakes/fake_clock.dart';
import '../../support/fakes/fake_monitoring.dart';
import '../../support/infrastructure/fake_network_state.dart';
import '../../support/infrastructure/fixture_files.dart';
import '../../support/infrastructure/memory_file_volume.dart';
import '../../support/infrastructure/memory_secure_storage.dart';
import '../../support/infrastructure/sleep.dart';
import '../../support/infrastructure/test_files.dart';
import 'container_support.dart';

// Test support, not production code: a device for the real configuration. The
// keychain, the folder of the databases and the files of the documents outlive
// a start of the app, so that a test can start it again; the API is the fixture
// server, reached through the adapter the runtime hands over.

/// The address the tests give to the API. Nothing listens there.
const String testApiBaseUrl = 'https://api.boardroom.example';

/// The biometrics of a test device: they succeed unless the test says
/// otherwise, and remember every prompt.
final class TestLocalAuthentication implements LocalAuthenticationApi {
  /// What the next prompts end with.
  LocalAuthenticationResult outcome =
      const LocalAuthenticationResult.succeeded();

  /// Whether the device has biometric hardware.
  bool hardware = true;

  /// Whether a biometric is enrolled.
  bool enrolled = true;

  /// Every prompt shown, in order.
  final List<AuthenticationPrompt> prompts = [];

  @override
  Future<bool> hasHardware() async => hardware;

  @override
  Future<bool> isEnrolled() async => enrolled;

  @override
  Future<LocalAuthenticationResult> authenticate(
    AuthenticationPrompt prompt,
  ) async {
    prompts.add(prompt);
    return outcome;
  }
}

/// A phone for the tests, and the world the API is in.
final class TestWorld {
  /// Creates the world: [parent] is the directory of the machine the files of
  /// the device live in.
  new _(this.server, this.clock, Directory parent)
    : databases = Directory('${freshDirectory(parent).path}/databases'),
      files = createFileStore(MemoryFileVolume());

  /// The fixture server behind the API.
  final FixtureServer server;

  /// The clock of the server and of the device.
  final FakeClock clock;

  /// The folder of the databases of the device.
  final Directory databases;

  /// The keychain of the device.
  final MemorySecureStorage storage = MemorySecureStorage();

  /// The biometrics of the device.
  final TestLocalAuthentication biometrics = TestLocalAuthentication();

  /// The state of the network, as the device reports it.
  final FakeNetworkState network = FakeNetworkState();

  /// What the adapters report.
  final FakeMonitoring monitoring = FakeMonitoring();

  /// The screen protection of the device.
  final InMemoryScreenProtection screenProtection = InMemoryScreenProtection();

  /// The files of the documents.
  final FileStore files;

  /// The device, as the runtime hands it over.
  DevicePlatform get platform => DevicePlatform(
    databaseOpener: Sqlite3Opener(databases),
    secureStorage: storage,
    randomBytes: secureRandomBytes,
    localAuthentication: biometrics,
    networkState: network,
  );

  /// The runtime of a start of the app on this device.
  ContainerRuntime runtime({
    BiometricPromptText? biometricPromptText,
    FileStore? fileStore,
  }) => ContainerRuntime(
    clock: clock,
    monitoring: monitoring,
    sleep: immediateSleep,
    platform: platform,
    fileStore: fileStore ?? files,
    screenProtection: screenProtection,
    httpAdapter: server.adapter,
    biometricPromptText: biometricPromptText ?? testPromptText,
  );

  /// The real configuration with the settings of the tests.
  HttpConfiguration configuration({bool allowDevicePasscode = false}) =>
      HttpConfiguration(
        baseUrl: testApiBaseUrl,
        requestTimeout: aDuration(5000),
        allowDevicePasscode: allowDevicePasscode,
      );

  /// A start of the app on this device. It is closed when the test is done.
  Future<AppContainer> start({ContainerRuntime? runtime}) async {
    final container = built(
      await createContainer(configuration(), runtime ?? this.runtime()),
    );
    addTearDown(container.dispose);
    return container;
  }
}

/// A world with the fixture server of the project, a clock that stands still
/// and a latency that costs nothing. [parent] is a directory of the machine.
Future<TestWorld> aTestWorld(Directory parent) async {
  final clock = FakeClock();
  final created = await FixtureServer.create(
    clock: clock,
    latency: aDuration(0),
    sleep: immediateSleep,
    files: readFixtureFiles(),
  );
  return TestWorld._(
    switch (created) {
      Ok(:final value) => value,
      Err(:final error) => throw StateError('$error'),
    },
    clock,
    parent,
  );
}
