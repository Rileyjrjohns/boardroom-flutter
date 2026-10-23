import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/composition/use_cases.dart';
import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/dev_ports.dart';
import 'package:boardroom/app/container/http_ports.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/container/wiring.dart';
import 'package:boardroom/core/domain/shared/result.dart';

/// The values of `settings.dart` that the use cases take, and whether the app
/// starts locked.
UseCaseSettings _useCaseSettings({required bool startsLocked}) =>
    UseCaseSettings(
      maxCacheAge: maxCacheAge,
      maxAttempts: maxVoteDeliveryAttempts,
      gracePeriod: appLockGracePeriod,
      startsLocked: startsLocked,
    );

const AppSettings _appSettings = AppSettings(
  meetingsPageSize: meetingsPageSize,
);

AppContainer _containerOf(AdaptersKind kind, Wiring wiring) => AppContainer(
  kind: kind,
  useCases: wireUseCases(
    wiring.ports,
    _useCaseSettings(startsLocked: wiring.startsLocked),
  ),
  settings: _appSettings,
  clock: wiring.ports.clock,
  monitoring: wiring.ports.monitoring,
  screenProtection: wiring.ports.screenProtection,
  notices: wiring.notices,
  demoControls: wiring.demoControls,
  onDispose: wiring.onDispose,
);

/// The composition root: builds the whole object graph for a configuration,
/// with manual typed constructor injection. It is a factory, not a singleton:
/// every call returns an independent container, with its own server, caches and
/// outbox, and the app calls it once per app instance. There is no container
/// library and no lookup by name.
///
/// It is asynchronous because the real configuration has to open its database,
/// which reads the key from the keychain, opens a file and migrates its schema.
/// It answers with a [Result], and never throws: a database that cannot be
/// opened is an error to show, not an exception, and so is a part of the device
/// that fails (`platformUnavailable`). The app does not start on another
/// configuration instead.
Future<Result<AppContainer, ContainerError>> createContainer(
  AppConfiguration configuration,
  ContainerRuntime runtime,
) async {
  try {
    final wiring = switch (configuration) {
      DevConfiguration() => await createDevPorts(configuration, runtime),
      HttpConfiguration() => await createHttpPorts(configuration, runtime),
    };
    switch (wiring) {
      case Ok(:final value):
        return ok(_containerOf(configuration.kind, value));
      case Err(:final error):
        return err(error);
    }
    // The ports of the device and of the network promise not to throw, but the
    // plugins under them are native code that can fail to load or to start.
    // What was thrown says nothing safe to keep.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return err(platformUnavailable());
  }
}

/// [createContainer] for the raw settings of the environment (see
/// [parseConfiguration]) and the kind of build: what the app calls, with what
/// it read.
Future<Result<AppContainer, ContainerError>> startContainer(
  RawSettings settings,
  ContainerRuntime runtime, {
  required bool development,
}) async {
  final configuration = parseConfiguration(settings, development: development);
  switch (configuration) {
    case Ok(:final value):
      return await createContainer(value, runtime);
    case Err(:final error):
      return err(error);
  }
}
