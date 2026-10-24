import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/app/device/device_platform.dart';
import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/infrastructure/clock/sleep.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/monitoring/sentry_monitoring.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

/// The text of the system prompt that asks for a biometric proof, for a reason,
/// in the language of the user: what it says, and the label of its cancel
/// button. The adapters cannot import the translations, so the app hands over a
/// function that reads them, and that reads the current language each time it
/// is called.
typedef BiometricPromptText = PromptText Function(BiometricReason reason);

/// What the container reads from the outside world. Everything has a default:
/// the clock of the device, the console, a real timer, a phone, the folder of
/// the app for the files and the screens of the bundled fixtures. A test
/// replaces what it needs to control time, to run without waiting and without a
/// phone. It is a parameter of the factory and not a global: nothing here is
/// read from a library.
@immutable
final class ContainerRuntime {
  /// Creates the runtime. Every argument is an override.
  const new({
    this.clock,
    this.monitoring,
    this.sentrySdk,
    this.sleep,
    this.biometricPromptText,
    this.platform,
    this.screenProtection,
    this.fileStore,
    this.httpAdapter,
    this.fixtureFiles,
  });

  /// The clock of the device by default.
  final Clock? clock;

  /// Where the events go, in place of the monitoring `createMonitoring`
  /// chooses.
  final Monitoring? monitoring;

  /// The SDK of the crash reporter, for a configuration that was given an
  /// address: a test hands over a stand-in that records what it is asked.
  /// Without it, an address starts nothing and the monitoring is the console.
  final SentrySdk? sentrySdk;

  /// How the simulated latency is waited for: a real timer by default.
  final Sleep? sleep;

  /// The text of the prompt of the biometrics. The app hands over a function
  /// that reads the current language. Without one, the prompt carries the
  /// stable names of the reason and of the cancel button (see
  /// `defaultPromptText`): a build that shows them has forgotten to hand this
  /// over.
  final BiometricPromptText? biometricPromptText;

  /// The real device: the engine of the database, the secure storage, the
  /// random generator, the biometrics and the network. A phone by default
  /// (`createDevicePlatform`). The real configuration uses all of it; the
  /// development one asks it only for the biometrics, to know whether the
  /// device has some enrolled.
  final DevicePlatform? platform;

  /// The screen protection of the app, in place of the default: the native one
  /// for the real configuration (the app hands it over, as it owns the
  /// plugin), the simulation for the development one. Tests hand over the
  /// in-memory one, which they can inspect and make report a capture.
  final ScreenProtection? screenProtection;

  /// Where the content of the documents is kept, in place of the folder of the
  /// app on the device. Both configurations write the downloads there, so both
  /// need it; a test hands over a store in a directory of the machine.
  final FileStore? fileStore;

  /// What carries the requests of the real configuration, in place of the
  /// network (a scripted adapter, or the fixture server). The development
  /// configuration always talks to its own fixture server.
  final HttpClientAdapter? httpAdapter;

  /// The files the development configuration builds its server from, in place
  /// of the bundled fixtures: a test hands over files it has broken in place.
  final FixtureFiles? fixtureFiles;
}
