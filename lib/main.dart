import 'package:boardroom/app/app.dart';
import 'package:boardroom/app/container/configuration.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/app/container/runtime.dart';
import 'package:boardroom/core/infrastructure/monitoring/console_monitoring.dart';
import 'package:boardroom/features/documents/infrastructure/native/native_screen_protection.dart';
import 'package:boardroom/features/documents/infrastructure/native/pigeon_screen_protection_module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Entry point: hands control to the app, with the screen protection of the
/// device (the native plugin where the platform has one). The configuration is
/// chosen by `--dart-define` (see `RawSettings.fromEnvironment`): `dev` serves
/// the fixtures through the simulated server, `http` talks to a real API.
void main() {
  runApp(
    BoardroomApp(
      start: (promptText) => startContainer(
        const RawSettings.fromEnvironment(),
        ContainerRuntime(
          biometricPromptText: promptText,
          screenProtection: NativeScreenProtection(
            module: loadScreenProtectionModule(),
            monitoring: const ConsoleMonitoring(),
          ),
        ),
        development: kDebugMode,
      ),
    ),
  );
}
