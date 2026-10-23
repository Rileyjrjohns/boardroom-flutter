import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/use_cases/observe_connectivity.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/errors/error_catalog.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// The providers the shared components and the shell take from the outside, and
// no feature owns. The core declares the shape it depends on and throws until
// `lib/app` overrides it in the root `ProviderScope` (lib/app/providers): a
// provider nobody overrode is a programming error, hence the throw. The
// providers of a feature are in `lib/features/<feature>/presentation/
// providers.dart`, with the same rule.

/// The error of a provider nobody overrode.
UnimplementedError notOverridden(String name) => UnimplementedError(
  '$name must be overridden in the root ProviderScope '
  '(see docs/presentation.md); in a widget test, override it.',
);

/// What the shell does when a failure says the session is over: ends it for
/// the whole app. `startedUnder` is the epoch of the access the failing action
/// started under, when it said.
typedef SessionEndHandler = void Function(String code, int? startedUnder);

/// The clock of the use cases. The one instant the presentation records
/// itself, the moment the app goes to the background, is read here so that
/// `EvaluateAppLock` compares two instants of the same clock.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => throw notOverridden('clockProvider');

/// The observation of the connection of the device.
@Riverpod(keepAlive: true)
ObserveConnectivity observeConnectivityUseCase(Ref ref) =>
    throw notOverridden('observeConnectivityUseCaseProvider');

/// What the screens know of the failures of the app (the core and the
/// features put together by `lib/app`).
@Riverpod(keepAlive: true)
ErrorCatalog errorCatalog(Ref ref) =>
    throw notOverridden('errorCatalogProvider');

/// Ends the session for the whole app. Written by `auth` (the access state),
/// handed over by `lib/app`.
@Riverpod(keepAlive: true)
SessionEndHandler sessionEndHandler(Ref ref) =>
    throw notOverridden('sessionEndHandlerProvider');

/// The epoch of the access: a number that goes up every time the user moves
/// from one state of access to another. It is `auth`'s, so the core does not
/// read it: `lib/app` derives it from the access state. A query is dropped
/// when it changes, and an action reads it when it starts (see
/// `runResultAction`).
@Riverpod(keepAlive: true)
int sessionEpoch(Ref ref) => throw notOverridden('sessionEpochProvider');

/// The controls of the demo: only the dev configuration has them, so null
/// everywhere else and the demo components render nothing.
@Riverpod(keepAlive: true)
DemoControls? demoControls(Ref ref) => null;

/// What the user is owed an explanation of at the start.
@Riverpod(keepAlive: true)
AppNotices appNotices(Ref ref) => const NoNotices();
