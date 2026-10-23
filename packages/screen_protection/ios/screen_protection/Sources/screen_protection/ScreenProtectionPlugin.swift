import Flutter
import UIKit

/// The identifier the secure view is registered under: the Dart widget asks for this view type.
let secureViewType = "screen_protection/secure_view"

/// Registers the calls, the streams of events and the secure view of the plugin.
public final class ScreenProtectionPlugin: NSObject, FlutterPlugin {
  private let host = ScreenProtectionHost()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ScreenProtectionPlugin()
    let messenger = registrar.messenger()
    let host = instance.host

    ScreenProtectionHostApiSetup.setUp(binaryMessenger: messenger, api: host)
    StreamCaptureEventsStreamHandler.register(
      with: messenger, streamHandler: CaptureEventsHandler(host: host))
    StreamSecureLayerFallbacksStreamHandler.register(
      with: messenger, streamHandler: SecureLayerFallbackHandler())
    registrar.register(SecureViewFactory(), withId: secureViewType)

    // The registrar keeps the plugin alive for the life of the engine, and so the host.
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    host.tearDown()
  }
}

/// Starts the observers of the system when Dart listens to the capture events, and stops them when it
/// does not any more, so that nothing runs for nobody.
private final class CaptureEventsHandler: StreamCaptureEventsStreamHandler {
  private let host: ScreenProtectionHost

  init(host: ScreenProtectionHost) {
    self.host = host
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<CaptureEventMessage>) {
    host.startListening(sink)
  }

  override func onCancel(withArguments arguments: Any?) {
    host.stopListening()
  }
}
