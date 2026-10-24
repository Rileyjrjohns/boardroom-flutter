import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../support/presentation/test_app.dart';

// Test support, not production code: what the golden tests of the screens
// share. A screen is mounted the way the widget tests mount it (the real use
// cases over the fakes, in a MaterialApp with the theme and the translations)
// and drawn at the size of a phone.

/// The width of the phones of the goldens, in logical pixels.
const double phoneWidth = 390;

/// The height of the phones of the goldens. A screen that scrolls and is longer
/// than this asks for [tallPhoneHeight].
const double phoneHeight = 844;

/// The height of a screen that scrolls, tall enough to show it whole.
const double tallPhoneHeight = 1700;

/// Puts the app in the state a golden shows, before the screen is mounted: the
/// meetings on the "server", a copy saved on the device, the network down...
typedef Prepare = FutureOr<void> Function(TestApp app);

/// The provider containers of the scenarios of the golden under way.
final List<ProviderContainer> _containers = [];

/// A golden image of [scenarios] side by side, one column each. Once the image
/// is compared, the screens are taken down and their providers disposed: the
/// queries hold timers that a test may not leave pending.
void screenGoldenTest(
  String description, {
  required String fileName,
  required List<GoldenTestScenario> scenarios,
}) {
  unawaited(
    goldenTest(
      description,
      fileName: fileName,
      builder: () =>
          GoldenTestGroup(columns: scenarios.length, children: scenarios),
      whilePerforming: (tester) async {
        return () async {
          await tester.pumpWidget(const SizedBox.shrink());
          _containers
            ..forEach((providers) => providers.dispose())
            ..clear();
        };
      },
    ),
  );
}

/// One state of a screen, as a column of a golden image.
GoldenTestScenario goldenScenario({
  required String name,
  required Widget Function() screen,
  required Prepare prepare,
  Locale locale = const Locale('en'),
  double height = phoneHeight,
  int meetingsPageSize = 10,
  bool deviceOffline = false,
  List<Override> overrides = const [],
}) => GoldenTestScenario(
  name: name,
  constraints: BoxConstraints.tight(Size(phoneWidth, height)),
  child: _GoldenScreen(
    screen: screen,
    prepare: prepare,
    locale: locale,
    size: Size(phoneWidth, height),
    meetingsPageSize: meetingsPageSize,
    deviceOffline: deviceOffline,
    overrides: overrides,
  ),
);

class _GoldenScreen extends StatefulWidget {
  const new({
    required this.screen,
    required this.prepare,
    required this.locale,
    required this.size,
    required this.meetingsPageSize,
    required this.deviceOffline,
    required this.overrides,
  });

  final Widget Function() screen;
  final Prepare prepare;
  final Locale locale;
  final Size size;
  final int meetingsPageSize;
  final bool deviceOffline;
  final List<Override> overrides;

  @override
  State<_GoldenScreen> createState() => _GoldenScreenState();
}

class _GoldenScreenState extends State<_GoldenScreen> {
  late final Future<ProviderContainer> _providers = _start();

  Future<ProviderContainer> _start() async {
    final app = TestApp(meetingsPageSize: widget.meetingsPageSize);
    await widget.prepare(app);
    final providers = app.providers(extra: widget.overrides);
    _containers.add(providers);
    if (widget.deviceOffline) {
      // The shell reports it from the platform; a screen alone is told by hand.
      providers
          .read(connectivityStateProvider.notifier)
          .set(ConnectivityStatus.offline);
    }
    return providers;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProviderContainer>(
      future: _providers,
      builder: (context, snapshot) {
        final providers = snapshot.data;
        if (providers == null) {
          return const SizedBox.shrink();
        }
        return MediaQuery(
          data: MediaQueryData(size: widget.size),
          child: UncontrolledProviderScope(
            container: providers,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: widget.locale,
              theme: buildAppTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: widget.screen()),
            ),
          ),
        );
      },
    );
  }
}
