// The typed channel between Dart and the native side of the plugin. Pigeon
// reads this file and writes the Dart, Kotlin and Swift code that both sides
// compile, so a name or a type that drifts fails the build instead of failing
// at run time. The generated files are committed (the native builds need them);
// regenerate them with the command in the README of the plugin.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/boardroom/screenprotection/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.boardroom.screenprotection'),
    swiftOut:
        'ios/screen_protection/Sources/screen_protection/Messages.g.swift',
  ),
)
/// What the platform can do, as the plugin found out when it started.
class ProtectionCapabilities {
  ProtectionCapabilities({
    required this.protection,
    required this.screenshotDetection,
    required this.recordingDetection,
    required this.secureView,
  });

  /// The screen can be protected (always true on Android and iOS).
  final bool protection;

  /// A screenshot of the app is reported (Android 14 and later, iOS).
  final bool screenshotDetection;

  /// A recording of the screen is reported (Android 15 and later, iOS).
  final bool recordingDetection;

  /// A secure view can leave its content out of captures (iOS, through a
  /// private flag; on Android the window flag does it for everything).
  final bool secureView;
}

/// What the native side reports about the screen being captured.
sealed class CaptureEventMessage {}

/// A screenshot of the app was taken.
class ScreenshotTakenMessage extends CaptureEventMessage {}

/// The screen started or stopped being recorded, mirrored or AirPlayed.
class CaptureChangedMessage extends CaptureEventMessage {
  CaptureChangedMessage({required this.captured});

  /// Whether the screen is captured now.
  final bool captured;
}

/// The secure view could not leave its content out of captures: the content is
/// shown, and visible in captures.
class SecureLayerFallbackMessage {
  SecureLayerFallbackMessage({required this.reason});

  /// Why, as a sentence for a log and not for the user.
  final String reason;
}

/// The calls Dart makes to the native side.
@HostApi()
abstract class ScreenProtectionHostApi {
  /// Turns the protection on or off. Idempotent. Completes once the change is
  /// made; fails when the platform could not make it.
  @async
  void setProtectionEnabled(bool enabled);

  /// Whether the screen is being recorded, mirrored or AirPlayed right now.
  /// Always false where the platform cannot tell.
  @async
  bool isCaptured();

  /// What this platform can do.
  ProtectionCapabilities capabilities();
}

/// The events of the native side, one stream for each method. The system
/// listeners behind a stream exist only while somebody listens to it, and each
/// stream is listened to on its own: the fallback of the secure view is apart
/// from the capture events so that listening to it starts no capture detection.
@EventChannelApi()
abstract class ScreenProtectionEvents {
  /// Screenshots, and the screen being recorded or mirrored.
  CaptureEventMessage streamCaptureEvents();

  /// The secure view could not leave its content out of captures.
  SecureLayerFallbackMessage streamSecureLayerFallbacks();
}
