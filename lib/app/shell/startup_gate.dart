import 'dart:async';
import 'dart:ui' as ui;

import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/container_error.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/app/providers/app_overrides.dart';
import 'package:boardroom/app/router/app_router.dart';
import 'package:boardroom/app/shell/session_controller.dart';
import 'package:boardroom/app/shell/startup_failure_screen.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/retry_policy.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:boardroom/features/auth/presentation/error_messages.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app does to start, which is asynchronous and can fail with a code.
/// It is given the means to read the system prompt text from the translations
/// of the moment.
typedef StartApp = Future<Result<AppContainer, ContainerError>> Function(
  BiometricPromptText promptText,
);

/// The localizations for the language of the device (English when it is not
/// supported), or [forced] when a test gives one.
AppLocalizations deviceLocalizations([Locale? forced]) {
  final language =
      (forced ?? ui.PlatformDispatcher.instance.locale).languageCode;
  final supported = AppLocalizations.supportedLocales.any(
    (locale) => locale.languageCode == language,
  );
  return lookupAppLocalizations(Locale(supported ? language : 'en'));
}

/// The start of the app, as the user sees it: a translated loading state while
/// the composition root is built (it opens the local database), then the
/// screens inside the root `ProviderScope`, or the screen that says why the app
/// cannot start. The start runs once. It hands the start the means to read the
/// system prompt text from the translations of the moment: the function reads
/// the current language each time it is called, so a language changed while the
/// app runs is followed by the next prompt.
class StartupGate extends StatefulWidget {
  /// Creates the gate over [start]; [locale] forces a language (tests use it).
  const new({required this.start, this.locale, super.key});

  /// Builds what the screens need. Called once, when the gate first mounts.
  final StartApp start;

  /// Language to force, or null to follow the device.
  final Locale? locale;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  ProviderContainer? _providers;
  AppContainer? _app;
  String? _failureCode;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    Result<AppContainer, ContainerError> outcome;
    String? aborted;
    try {
      outcome = await widget.start(
        (reason) => PromptText(
          message: biometricPromptMessage(
            deviceLocalizations(widget.locale),
            reason,
          ),
          cancelLabel: deviceLocalizations(widget.locale).coreCommonCancel,
        ),
      );
    } on Object {
      outcome = err(const PlatformUnavailableError());
      aborted = startupAbortedCode;
    }
    if (!mounted) {
      if (outcome case Ok(:final value)) {
        await value.dispose();
      }
      return;
    }
    setState(() {
      switch (outcome) {
        case Ok(:final value):
          _app = value;
          _providers = _createProviders(value);
        case Err(:final error):
          _failureCode = aborted ?? error.code;
      }
    });
  }

  ProviderContainer _createProviders(AppContainer app) {
    late final ProviderContainer providers;
    final policy = RetryPolicy(
      catalog: createAppErrorCatalog(),
      isSessionEndingCode: isSessionEndingCode,
      onSessionEnded: (code, startedUnder) =>
          providers.read(sessionEndHandlerProvider)(code, startedUnder),
    );
    return providers = ProviderContainer(
      overrides: appOverrides(app),
      retry: policy.call,
    );
  }

  @override
  void dispose() {
    _providers?.dispose();
    final app = _app;
    if (app != null) {
      unawaited(app.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    if (providers != null) {
      return UncontrolledProviderScope(
        container: providers,
        child: _RouterApp(locale: widget.locale),
      );
    }
    final failureCode = _failureCode;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).coreAppName,
      locale: widget.locale,
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: failureCode == null
          ? Builder(
              builder: (context) => Scaffold(
                body: LoadingState(
                  key: const Key(CoreTestIds.startupLoading),
                  label: AppLocalizations.of(context).coreStartupLoading,
                ),
              ),
            )
          : StartupFailureScreen(code: failureCode),
    );
  }
}

class _RouterApp extends ConsumerWidget {
  const new({required this.locale});

  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context).coreAppName,
    locale: locale,
    theme: buildAppTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: ref.watch(appRouterProvider),
    builder: (context, child) =>
        SessionController(child: child ?? const SizedBox.shrink()),
  );
}
