import Flutter
import UIKit
import os

private let secureViewLog = Logger(
  subsystem: "com.boardroom.screenprotection", category: "SecureView")

/// The private layer property behind the capture exclusion (`CaptureMask`), when this version of iOS
/// has it.
enum CaptureExclusion {
  static let key = CaptureMask.key
  static let setter = NSSelectorFromString(CaptureMask.setter)

  /// Whether this version of iOS gives the layer the property. It is private, so it can disappear.
  static func isAvailable(on layer: CALayer) -> Bool {
    return layer.responds(to: setter)
  }
}

/// Counts how many secure views hide the same layer, so that the layer is shown again only when the
/// last one has gone. Main thread only.
final class CaptureExclusionRegistry {
  static let shared = CaptureExclusionRegistry()

  private var holds: [ObjectIdentifier: (layer: CALayer, count: Int)] = [:]

  /// Leaves the layer out of captures. Returns false when the layer cannot be (the property is
  /// missing), and then holds nothing.
  func hide(_ layer: CALayer) -> Bool {
    guard CaptureExclusion.isAvailable(on: layer) else { return false }
    let id = ObjectIdentifier(layer)
    let count = (holds[id]?.count ?? 0) + 1
    holds[id] = (layer: layer, count: count)
    if count == 1 {
      layer.setValue(CaptureMask.mask(hidden: true), forKey: CaptureExclusion.key)
    }
    return true
  }

  /// Lets go of a layer that `hide` held; the layer is shown again with the last release.
  func release(_ layer: CALayer) {
    let id = ObjectIdentifier(layer)
    guard let held = holds[id] else { return }
    if held.count <= 1 {
      holds[id] = nil
      layer.setValue(CaptureMask.mask(hidden: false), forKey: CaptureExclusion.key)
    } else {
      holds[id] = (layer: layer, count: held.count - 1)
    }
  }

  /// How many layers are held (for a test).
  var heldCount: Int { holds.count }
}

/// Where the fallback of the secure views goes: the stream Dart listens to. A reason that is reported
/// before Dart listens is kept and told when it does.
final class SecureLayerFallbackReporter {
  static let shared = SecureLayerFallbackReporter()

  private var sink: PigeonEventSink<SecureLayerFallbackMessage>?
  private var pending: [String] = []

  func report(_ reason: String) {
    if let sink = sink {
      sink.success(SecureLayerFallbackMessage(reason: reason))
    } else {
      pending.append(reason)
    }
  }

  func attach(_ sink: PigeonEventSink<SecureLayerFallbackMessage>) {
    self.sink = sink
    let reasons = pending
    pending = []
    reasons.forEach { sink.success(SecureLayerFallbackMessage(reason: $0)) }
  }

  func detach() {
    sink = nil
  }
}

final class SecureLayerFallbackHandler: StreamSecureLayerFallbacksStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<SecureLayerFallbackMessage>
  ) {
    SecureLayerFallbackReporter.shared.attach(sink)
  }

  override func onCancel(withArguments arguments: Any?) {
    SecureLayerFallbackReporter.shared.detach()
  }
}

/// A view that, while it is in a window, leaves the content of the Flutter view out of screenshots,
/// screen recordings and mirroring, and is invisible and takes no touch.
///
/// **The technique.** iOS has no public API that keeps a view out of captures. A `UITextField` with
/// `isSecureTextEntry = true` is left out of them because UIKit sets the private `disableUpdateMask`
/// property on the layer that draws it. This view sets the same property on a layer, through
/// key-value coding.
///
/// **Which layer.** Flutter draws every widget into one surface, the Flutter view, so a widget cannot
/// be a native subview of this view the way a React Native child is. The view therefore marks the
/// Flutter view, the top view of the window the platform view is in: everything Flutter draws is left
/// out while a secure view exists, and the layer is shown again when the last one is removed. That is
/// wider than the widget that asked for it, and the Dart widget is mounted only while the content is
/// shown.
///
/// **It is undocumented behaviour.** The property is private to Core Animation. It is set only when
/// the layer answers to its setter, so an iOS version without it leaves the content visible and never
/// crashes; that case is reported (an event on the stream of fallbacks and a line in the log of the
/// system under the subsystem `com.boardroom.screenprotection`).
final class ScreenProtectionSecureView: UIView {
  private var hiddenLayer: CALayer?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      hide()
    } else {
      show()
    }
  }

  deinit {
    // Only main-thread teardown reaches here in practice; the registry is main-thread state.
    if let layer = hiddenLayer {
      DispatchQueue.main.async { CaptureExclusionRegistry.shared.release(layer) }
    }
  }

  /// The top view of the window the view is in: the Flutter view.
  private func topView() -> UIView {
    var top: UIView = self
    while let parent = top.superview, !(parent is UIWindow) {
      top = parent
    }
    return top
  }

  private func hide() {
    guard hiddenLayer == nil else { return }
    let layer = topView().layer
    if CaptureExclusionRegistry.shared.hide(layer) {
      hiddenLayer = layer
      secureViewLog.info("layer left out of captures")
    } else {
      let reason = "the layer has no \(CaptureExclusion.key) property"
      secureViewLog.error(
        "secure layer unavailable, content shown: \(reason, privacy: .public)")
      SecureLayerFallbackReporter.shared.report(reason)
    }
  }

  private func show() {
    guard let layer = hiddenLayer else { return }
    hiddenLayer = nil
    CaptureExclusionRegistry.shared.release(layer)
  }
}

/// Builds the native side of the Dart `SecureView`.
final class SecureViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    return SecurePlatformView(frame: frame)
  }
}

private final class SecurePlatformView: NSObject, FlutterPlatformView {
  private let secureView: ScreenProtectionSecureView

  init(frame: CGRect) {
    secureView = ScreenProtectionSecureView(frame: frame)
    super.init()
  }

  func view() -> UIView {
    return secureView
  }
}
