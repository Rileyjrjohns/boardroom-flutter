import XCTest

@testable import screen_protection

final class CaptureDecisionTests: XCTestCase {
  func testAnActiveSceneMeansCaptured() {
    XCTAssertTrue(CaptureDecision.isCaptured(scenes: [.inactive, .active], screensCaptured: false))
  }

  func testASceneThatSaysNotCapturedBeatsTheScreens() {
    XCTAssertFalse(CaptureDecision.isCaptured(scenes: [.inactive, .unspecified], screensCaptured: true))
  }

  func testWithNoStateForAnySceneTheScreensDecide() {
    XCTAssertTrue(CaptureDecision.isCaptured(scenes: [.unspecified], screensCaptured: true))
    XCTAssertFalse(CaptureDecision.isCaptured(scenes: [.unspecified], screensCaptured: false))
    XCTAssertTrue(CaptureDecision.isCaptured(scenes: [], screensCaptured: true))
    XCTAssertFalse(CaptureDecision.isCaptured(scenes: [], screensCaptured: false))
  }
}

final class CaptureMaskTests: XCTestCase {
  func testTheMaskIsTheOneOfASecureTextField() {
    XCTAssertEqual(CaptureMask.mask(hidden: true), (1 << 1) | (1 << 4))
    XCTAssertEqual(CaptureMask.mask(hidden: true), 18)
  }

  func testAVisibleLayerHasNoMask() {
    XCTAssertEqual(CaptureMask.mask(hidden: false), 0)
  }

  func testTheSetterIsTheOneOfTheKey() {
    XCTAssertEqual(CaptureMask.setter, "setDisableUpdateMask:")
    XCTAssertEqual(CaptureMask.key, "disableUpdateMask")
  }
}
