import 'package:boardroom/app/app.dart';
import 'package:boardroom/core/infrastructure/monitoring/console_monitoring.dart';
import 'package:boardroom/features/documents/infrastructure/native/native_screen_protection.dart';
import 'package:boardroom/features/documents/infrastructure/native/pigeon_screen_protection_module.dart';
import 'package:flutter/material.dart';

/// Entry point: hands control to the app, with the screen protection of the
/// device (the native plugin where the platform has one).
void main() {
  runApp(
    BoardroomApp(
      screenProtection: NativeScreenProtection(
        module: loadScreenProtectionModule(),
        monitoring: const ConsoleMonitoring(),
      ),
    ),
  );
}
