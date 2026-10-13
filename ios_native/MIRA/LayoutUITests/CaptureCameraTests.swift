import XCTest

final class CaptureCameraTests: XCTestCase {
  private func launch(review: Bool, largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-capture"]
      + (review ? ["--captro-camera-review-fixture"] : [])
      + (largeText ? ["--captro-quality-large-text"] : [])
    app.launch(); return app
  }
  private func capture(_ app: XCUIApplication, _ label: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = label + "-simulator-not-camera-quality"
    attachment.lifetime = .keepAlways; add(attachment)
  }
  func testUnavailableCameraHasNoReceiptOrLibraryEntry() {
    let app = launch(review: false)
    XCTAssertTrue(app.buttons["capture.mode.photo"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["capture.mode.video"].exists)
    XCTAssertTrue(app.otherElements["capture.unavailable"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Scan a receipt"].exists)
    XCTAssertFalse(app.buttons["Choose photo"].exists)
    XCTAssertFalse(app.buttons["Import document"].exists)
    capture(app, "camera-unavailable-state")
  }
  func testReviewEnhanceCompareAndComposerCancellationKeepsCapture() {
    let app = launch(review: true)
    XCTAssertTrue(app.buttons["capture.use"].waitForExistence(timeout: 15))
    capture(app, "capture-photo-review-test-chart")
    app.buttons["capture.enhance"].tap()
    XCTAssertTrue(app.buttons["capture.compare"].waitForExistence(timeout: 15))
    app.buttons["capture.compare"].tap()
    app.buttons["capture.use"].tap()
    app.buttons["Create post"].tap()
    // Camera originals deliberately have no approved crop. Complete that real
    // framing step before cancelling the composer, rather than its crop sheet.
    XCTAssertTrue(app.buttons["post.crop.done"].waitForExistence(timeout: 15))
    let cropReady = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["post.crop.done"])
    wait(for: [cropReady], timeout: 10)
    app.buttons["post.crop.done"].tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 15))
    capture(app, "camera-to-existing-composer-test-chart")
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Discard post"].waitForExistence(timeout: 5))
    app.buttons["Discard post"].tap() // Discard this composer draft, not Capture's original.
    XCTAssertTrue(app.buttons["capture.use"].waitForExistence(timeout: 10))
    capture(app, "capture-retained-after-composer-cancel")
  }

  func testReviewRetainsCaptureAcrossTabsAndLargeTextKeepsActionsAboveNavigation() {
    let app = launch(review: true, largeText: true)
    let use = app.buttons["capture.use"]
    XCTAssertTrue(use.waitForExistence(timeout: 15))
    let tabs = app.tabBars.firstMatch
    XCTAssertTrue(tabs.exists)
    XCTAssertGreaterThanOrEqual(use.frame.height, 44)
    XCTAssertLessThanOrEqual(use.frame.maxY, tabs.frame.minY + 1,
      "Use capture must not be hidden beneath the retained bottom navigation")
    XCTAssertTrue(use.isHittable)
    app.tabBars.buttons["Home"].tap()
    app.tabBars.buttons["Capture"].tap()
    XCTAssertTrue(use.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["capture.retake"].isHittable)
    capture(app, "capture-accessibility-tab-return")
  }
}
