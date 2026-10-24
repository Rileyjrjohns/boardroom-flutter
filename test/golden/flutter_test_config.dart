import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/edge_tolerant_comparator.dart';

// Applies to every test of test/golden. Two kinds of golden image exist:
//
// - the CI goldens (goldens/ci), where the text is drawn as plain blocks and no
//   shadow is rendered. They do not depend on the fonts or on the text
//   rendering of the operating system, so the same file is produced on macOS
//   and on Linux. They are the ones that are committed and that CI compares.
// - the platform goldens (goldens/<os>), with the real text, to read the screens
//   by eye. They depend on the machine, so they are never committed and are
//   only produced when PLATFORM_GOLDENS=1 is set (docs/development.md, "Golden tests").
//
// The images are compared up to the smoothing of edges, which differs by
// operating system (support/edge_tolerant_comparator.dart).
//
// Dates read the same everywhere: the time zone of the device is replaced by
// UTC.

/// Asks for the platform goldens too, in addition to the CI ones.
const String platformGoldensVariable = 'PLATFORM_GOLDENS';

Future<void> testExecutable(FutureOr<void> Function() testMain) {
  final withPlatformGoldens =
      Platform.environment[platformGoldensVariable] == '1';
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(
        enabled: withPlatformGoldens,
      ),
      ciGoldensConfig: const CiGoldensConfig(),
    ),
    run: () async {
      goldenFileComparator = EdgeTolerantComparator(
        Uri.file('${Directory.current.path}/test/golden/golden_test.dart'),
      );
      setUpAll(() async {
        await initializeDateFormatting();
        Formatters.deviceTimeOverride = (epochMillis) =>
            DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);
      });
      tearDownAll(() => Formatters.deviceTimeOverride = null);
      await testMain();
    },
  );
}
