/// The typed channel to the native side of the plugin: the calls, the capture
/// events and what the platform can do. The app reaches it through the
/// `ScreenProtection` port (lib/features/documents/infrastructure/native).
library;

export 'src/messages.g.dart'
    show
        CaptureChangedMessage,
        CaptureEventMessage,
        ProtectionCapabilities,
        ScreenProtectionHostApi,
        ScreenshotTakenMessage,
        streamCaptureEvents;
