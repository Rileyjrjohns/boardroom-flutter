import Flutter
import UIKit

/// Screen protection for iOS.
///
/// iOS has no public API that blocks screenshots or screen recordings. What this class does instead,
/// while protection is on:
///
/// - **App switcher.** When a scene resigns active (app switcher, control centre, notification centre,
///   a system prompt) an opaque view is put over each of its windows, and taken away when the scene
///   becomes active again. The snapshot the system takes for the app switcher shows the view, not the
///   content. The scene notifications are used, because the app is scene based.
/// - **Screenshots.** Reported, not blocked.
/// - **Recording, mirroring, AirPlay.** Reported from the capture state of the scenes on iOS 17 and
///   later (`UITraitCollection.sceneCaptureState`), and from `UIScreen` before.
///
/// What really keeps content out of screenshots and recordings is the secure view
/// (`ScreenProtectionSecureView`), not this class.
///
/// The cover is on only while protection is on. Which screens need protection is the business of the
/// application layer, not of the plugin: it does what it is told.
///
/// Threading: all state is read and written on the main queue; the calls from Dart hop there.
final class ScreenProtectionHost: ScreenProtectionHostApi {
  private var protectionEnabled = false
  private var sceneObservers: [NSObjectProtocol] = []

  private var sink: PigeonEventSink<CaptureEventMessage>?
  private var screenshotObserver: NSObjectProtocol?
  private var captureObservers: [NSObjectProtocol] = []
  /// Opaque registrations of the trait observers (`UITraitChangeRegistration`, iOS 17).
  private var traitRegistrations: [(scene: UIWindowScene, registration: Any)] = []
  private var lastCaptured: Bool?

  // MARK: - Calls from Dart

  func setProtectionEnabled(enabled: Bool) async throws {
    await MainActor.run { setProtection(enabled) }
  }

  func isCaptured() async throws -> Bool {
    return await MainActor.run { isCurrentlyCaptured() }
  }

  func capabilities() throws -> ProtectionCapabilities {
    return ProtectionCapabilities(
      protection: true,
      screenshotDetection: true,
      recordingDetection: true,
      secureView: true)
  }

  // MARK: - Listening

  /// Dart started listening to the capture events.
  func startListening(_ sink: PigeonEventSink<CaptureEventMessage>) {
    self.sink = sink
    startObservingScreenshots()
    startObservingCapture()
  }

  /// Dart stopped listening: the observers of the system are removed.
  func stopListening() {
    sink = nil
    stopObservingScreenshots()
    stopObservingCapture()
  }

  /// The plugin is detached from the engine: leave the windows as found.
  func tearDown() {
    stopListening()
    stopObservingScenes()
    for scene in windowScenes() {
      uncover(scene)
    }
    protectionEnabled = false
  }

  // MARK: - Protection (the cover)

  private func setProtection(_ enabled: Bool) {
    protectionEnabled = enabled
    if enabled {
      startObservingScenes()
      // Protection can be turned on while the app is already inactive (a system prompt is up).
      for scene in windowScenes() where scene.activationState == .foregroundInactive {
        cover(scene)
      }
    } else {
      stopObservingScenes()
      for scene in windowScenes() {
        uncover(scene)
      }
    }
  }

  private func startObservingScenes() {
    guard sceneObservers.isEmpty else { return }
    let center = NotificationCenter.default
    sceneObservers = [
      center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) {
        [weak self] notification in
        guard let self, self.protectionEnabled, let scene = notification.object as? UIWindowScene
        else { return }
        self.cover(scene)
      },
      center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) {
        [weak self] notification in
        guard let self, let scene = notification.object as? UIWindowScene else { return }
        self.uncover(scene)
      },
    ]
  }

  private func stopObservingScenes() {
    sceneObservers.forEach(NotificationCenter.default.removeObserver)
    sceneObservers = []
  }

  /// Puts the cover over every normal window of the scene that has none. System windows (the keyboard,
  /// the status bar) are left alone.
  private func cover(_ scene: UIWindowScene) {
    for window in scene.windows where window.windowLevel == .normal && !window.isHidden {
      if window.subviews.contains(where: { $0 is ScreenProtectionCoverView }) { continue }
      let cover = ScreenProtectionCoverView(frame: window.bounds)
      window.addSubview(cover)
      window.bringSubviewToFront(cover)
    }
  }

  private func uncover(_ scene: UIWindowScene) {
    for window in scene.windows {
      window.subviews.filter { $0 is ScreenProtectionCoverView }.forEach { $0.removeFromSuperview() }
    }
  }

  private func windowScenes() -> [UIWindowScene] {
    return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  }

  // MARK: - Screenshots

  private func startObservingScreenshots() {
    guard screenshotObserver == nil else { return }
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.sink?.success(ScreenshotTakenMessage())
    }
  }

  private func stopObservingScreenshots() {
    if let observer = screenshotObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    screenshotObserver = nil
  }

  // MARK: - Capture (recording, mirroring, AirPlay)

  private func startObservingCapture() {
    guard captureObservers.isEmpty && traitRegistrations.isEmpty else { return }
    lastCaptured = isCurrentlyCaptured()

    let center = NotificationCenter.default
    if #available(iOS 17.0, *) {
      // The state is a trait of the scene: observe it on each window scene, including the ones that
      // connect later.
      windowScenes().forEach { observeTraits(of: $0) }
      captureObservers.append(
        center.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) {
          [weak self] notification in
          guard let self, self.sink != nil, let scene = notification.object as? UIWindowScene
          else { return }
          self.observeTraits(of: scene)
          self.reportCaptureIfChanged()
        })
      captureObservers.append(
        center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) {
          [weak self] notification in
          guard let self, let scene = notification.object as? UIScene else { return }
          self.traitRegistrations.removeAll { $0.scene === scene }
          self.reportCaptureIfChanged()
        })
    } else {
      captureObservers.append(
        center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) {
          [weak self] _ in
          self?.reportCaptureIfChanged()
        })
    }
  }

  @available(iOS 17.0, *)
  private func observeTraits(of scene: UIWindowScene) {
    guard !traitRegistrations.contains(where: { $0.scene === scene }) else { return }
    // UIKit declares the trait observation main-actor isolated. Every entry point of this class runs
    // on the main queue, so the assumption holds (and is checked at run time).
    let registration = MainActor.assumeIsolated {
      scene.registerForTraitChanges([UITraitSceneCaptureState.self]) {
        [weak self] (_: UIWindowScene, _: UITraitCollection) in
        self?.reportCaptureIfChanged()
      }
    }
    traitRegistrations.append((scene: scene, registration: registration))
  }

  private func stopObservingCapture() {
    captureObservers.forEach(NotificationCenter.default.removeObserver)
    captureObservers = []
    if #available(iOS 17.0, *) {
      for entry in traitRegistrations {
        if let registration = entry.registration as? UITraitChangeRegistration {
          MainActor.assumeIsolated { entry.scene.unregisterForTraitChanges(registration) }
        }
      }
    }
    traitRegistrations = []
    lastCaptured = nil
  }

  private func reportCaptureIfChanged() {
    let captured = isCurrentlyCaptured()
    guard captured != lastCaptured else { return }
    lastCaptured = captured
    sink?.success(CaptureChangedMessage(captured: captured))
  }

  private func isCurrentlyCaptured() -> Bool {
    let scenes = windowScenes()
    var states: [CaptureDecision.SceneState] = []
    if #available(iOS 17.0, *) {
      states = scenes.map { scene in
        switch scene.traitCollection.sceneCaptureState {
        case .active: return .active
        case .inactive: return .inactive
        default: return .unspecified
        }
      }
    }
    return CaptureDecision.isCaptured(
      scenes: states, screensCaptured: scenes.contains { $0.screen.isCaptured })
  }
}

/// The view over the content while the app is inactive: opaque, in the colour of the system background,
/// with nothing on it. It shows no text, so there is nothing to translate.
private final class ScreenProtectionCoverView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .systemBackground
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    isUserInteractionEnabled = true
  }

  required init?(coder: NSCoder) {
    return nil
  }
}
