import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/app/composition/settings.dart';
import 'package:boardroom/app/composition/use_cases.dart';
import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/app/providers/app_overrides.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/retry_policy.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/create_fakes.dart';
import '../fakes/fake_auth_session.dart';

// Test support, not production code: what a widget test of a screen needs. The
// use cases are the real ones wired over the fakes (`createFakes`), the
// providers are overridden the way the app does it (`appOverrides`), and the
// screen is mounted in a `MaterialApp` with the localizations. The docs of this
// are in docs/presentation.md ("How to write a widget test").

/// The ports of a configuration, made of the fakes.
Ports portsOf(Fakes fakes) => Ports(
  clock: fakes.clock,
  monitoring: fakes.monitoring,
  auth: fakes.auth,
  biometricGate: fakes.biometricGate,
  connectivity: fakes.connectivity,
  screenProtection: fakes.screenProtection,
  meetings: fakes.meetings,
  meetingCache: fakes.meetingCache,
  documents: fakes.documents,
  documentCache: fakes.documentCache,
  votes: fakes.votes,
  outbox: fakes.outbox,
);

/// An app made of fakes: the fakes, the use cases wired over them and the
/// container that `appOverrides` reads.
final class TestApp {
  /// Creates the app. The user is signed in and the app is unlocked unless
  /// [startsLocked].
  factory({
    Fakes? fakes,
    DemoControls? demoControls,
    AppNotices? notices,
    bool startsLocked = false,
    Ports Function(Ports ports)? adaptPorts,
  }) {
    final theFakes = fakes ?? createFakes();
    final useCases = wireUseCases(
      (adaptPorts ?? (ports) => ports)(portsOf(theFakes)),
      UseCaseSettings(
        maxCacheAge: theFakes.maxCacheAge,
        maxAttempts: theFakes.maxAttempts,
        gracePeriod: appLockGracePeriod,
        startsLocked: startsLocked,
      ),
    );
    return TestApp._(
      fakes: theFakes,
      useCases: useCases,
      container: AppContainer(
        kind: AdaptersKind.dev,
        useCases: useCases,
        settings: const AppSettings(meetingsPageSize: meetingsPageSize),
        clock: theFakes.clock,
        monitoring: theFakes.monitoring,
        screenProtection: theFakes.screenProtection,
        notices: notices ?? const NoNotices(),
        demoControls: demoControls,
      ),
    );
  }

  new _({required this.fakes, required this.useCases, required this.container});

  /// One fake of every port.
  final Fakes fakes;

  /// The use cases of the app, over the fakes.
  final UseCases useCases;

  /// What the composition root hands over.
  final AppContainer container;

  /// The overrides of the root provider container.
  List<Override> get overrides => appOverrides(container);

  /// A provider container like the one of the app: the overrides, and the retry
  /// policy of the queries without the waits. [access] is where the user stands
  /// (an app that starts already open by default).
  ProviderContainer providers({
    Access access = Access.unlocked,
    List<Override> extra = const [],
  }) {
    late final ProviderContainer created;
    final policy = RetryPolicy(
      catalog: createAppErrorCatalog(),
      isSessionEndingCode: isSessionEndingCode,
      onSessionEnded: (code, startedUnder) =>
          created.read(sessionEndHandlerProvider)(code, startedUnder),
      baseDelay: Duration.zero,
    );
    created = ProviderContainer(
      overrides: [...overrides, ...extra],
      retry: policy.call,
    );
    created.read(accessControllerProvider.notifier).startAt(access);
    addTearDown(created.dispose);
    return created;
  }
}

/// The widget that mounts [child] in an app with the localizations, the theme
/// and the providers of [providers].
Widget testHost(
  ProviderContainer providers,
  Widget child, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: providers,
  child: MaterialApp(
    locale: locale,
    theme: buildAppTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

/// Mounts [screen] in an app made of fakes and returns the provider container,
/// to read the access or the state of a notifier.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  TestApp? app,
  Access access = Access.unlocked,
  Locale locale = const Locale('en'),
  List<Override> extra = const [],
}) async {
  final providers = (app ?? TestApp()).providers(access: access, extra: extra);
  await tester.pumpWidget(testHost(providers, screen, locale: locale));
  return providers;
}

/// The texts of [locale], read from the generated class so that a test holds no
/// user-facing literal.
AppLocalizations l10nOf([Locale locale = const Locale('en')]) =>
    lookupAppLocalizations(locale);

/// The finder of a test id, set as a `Key` on the widget.
Finder byTestId(String id) => find.byKey(Key(id));

/// An email and a password that pass the rules of the domain.
({String email, String password}) get validCredentials =>
    (email: 'alice@example.com', password: defaultPassword);
