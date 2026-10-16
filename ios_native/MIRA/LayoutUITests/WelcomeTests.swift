import XCTest

/// Actual native welcome controls; no provider credentials or production writes.
final class WelcomeTests: XCTestCase {
  private func launch(_ flags: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-welcome-review"] + flags
    app.launch()
    XCTAssertTrue(app.descendants(matching: .any)["welcome.headline"].firstMatch.waitForExistence(timeout: 15))
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func reach(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.isHittable)
  }
  func testArtworkNativeControlsAndLegalRoundTrip() {
    let app = launch(["--welcome-reduce-motion"])
    capture(app, "welcome-native-still")
    let google = app.buttons["welcome.google"]
    XCTAssertTrue(google.isEnabled)
    XCTAssertTrue(app.buttons.matching(identifier: "Continue with Apple").firstMatch.isEnabled)
    let privacy = app.buttons["welcome.privacy"]
    reach(privacy, in: app); privacy.tap()
    XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    capture(app, "welcome-privacy-native")
    app.navigationBars.buttons.firstMatch.tap()
    let terms = app.buttons["welcome.terms"]
    reach(terms, in: app); terms.tap()
    capture(app, "welcome-terms-native")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.descendants(matching: .any)["welcome.headline"].firstMatch.exists)
  }
  func testNormalWelcomeIsFixedAndEveryActionFitsWithoutScrolling() {
    let app = launch(["--welcome-reduce-motion"])
    XCTAssertEqual(app.scrollViews.count, 0, "Normal welcome must have no vertical scroll/bounce container")
    let google = app.buttons["welcome.google"]
    let original = google.frame
    for id in ["welcome.google", "welcome.guest", "welcome.terms", "welcome.privacy"] {
      let action = app.buttons[id]
      XCTAssertTrue(action.isHittable, "\(id) must fit immediately")
      XCTAssertGreaterThanOrEqual(action.frame.minY, 0)
      XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY - 10)
    }
    app.swipeUp(); XCTAssertEqual(google.frame.minY, original.minY, accuracy: 1)
    app.swipeDown(); XCTAssertEqual(google.frame.minY, original.minY, accuracy: 1)
    capture(app, "welcome-fixed-all-actions")
  }
  func testConsentCancelAndExistingEmailRoute() {
    let app = launch(["--welcome-reduce-motion"])
    let google = app.buttons["welcome.google"]
    reach(google, in: app); google.tap()
    XCTAssertTrue(app.staticTexts["Before you continue"].waitForExistence(timeout: 5))
    capture(app, "welcome-consent-preserved")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(google.waitForExistence(timeout: 5)); google.tap()
    let email = app.buttons["welcome.email"]
    reach(email, in: app); email.tap()
    XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    capture(app, "welcome-existing-email-route")
  }
  func testGuestIsUnauthenticatedAndLargeTextReachable() {
    let app = launch(["--welcome-reduce-motion", "--welcome-large-text"])
    capture(app, "welcome-accessibility-heading")
    let google = app.buttons["welcome.google"]
    reach(google, in: app)
    // Reachability alone previously passed with a double-scaled, clipped label.
    XCTAssertLessThan(google.frame.height, 190, "Google text must scale once and remain a compact readable action")
    XCTAssertLessThanOrEqual(google.frame.maxX, app.frame.maxX)
    XCTAssertGreaterThanOrEqual(google.frame.minX, app.frame.minX)
    capture(app, "welcome-accessibility-actions")
    let guest = app.buttons["welcome.guest"]
    reach(guest, in: app); guest.tap()
    XCTAssertTrue(app.staticTexts["welcome.guest.confirmed"].waitForExistence(timeout: 5))
    app.buttons["Back to welcome"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["welcome.headline"].firstMatch.waitForExistence(timeout: 5))
  }
  func testFailurePresentationAndImmediateInteractionDuringReveal() {
    let app = launch(["--welcome-error"])
    let google = app.buttons["welcome.google"]
    reach(google, in: app)
    XCTAssertTrue(google.isEnabled)
    capture(app, "welcome-native-error")
    google.tap()
    XCTAssertTrue(app.staticTexts["Before you continue"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(google.waitForExistence(timeout: 5))
  }
}
