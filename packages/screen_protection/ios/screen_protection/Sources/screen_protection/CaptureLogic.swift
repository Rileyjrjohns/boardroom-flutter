import Foundation

/// How the system tells the screen is captured, as a pure decision, so that it reads the same in the
/// code and in a test: on iOS 17 and later the capture state of the scenes, and `UIScreen.isCaptured`
/// where the state is not specified (iOS 16, or a scene that has not been given one).
enum CaptureDecision {
  /// What one scene says about the capture.
  enum SceneState {
    case active
    case inactive
    case unspecified
  }

  /// Captured when one scene is being captured; not captured when a scene said it is not and none said
  /// it is; otherwise whatever the screens say.
  static func isCaptured(scenes: [SceneState], screensCaptured: Bool) -> Bool {
    if scenes.contains(.active) {
      return true
    }
    if scenes.contains(.inactive) {
      return false
    }
    return screensCaptured
  }
}

/// The private `CALayer` property that the system sets on the layer of a secure text field, and the
/// value it sets: the layer is left out of screenshots, screen recordings and mirroring.
enum CaptureMask {
  static let key = "disableUpdateMask"
  static let setter = "setDisableUpdateMask:"
  /// The two bits set for a secure text field.
  static let hiddenFromCapture = (1 << 1) | (1 << 4)
  static let visible = 0

  /// The value of the property for a layer that is, or is not, left out of captures.
  static func mask(hidden: Bool) -> Int {
    return hidden ? hiddenFromCapture : visible
  }
}
