import XCTest

final class CreatorSupportTests: XCTestCase {
  private func launch(_ flags: [String] = []) -> XCUIApplication {
    let app = XCUIApplication(); app.launchArguments = ["--captro-support-review"] + flags; app.launch()
    XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 15)); return app
  }
  private func reach(_ button: XCUIElement, app: XCUIApplication) {
    for _ in 0..<8 where !button.isHittable { app.swipeUp() }; XCTAssertTrue(button.isHittable)
  }
  func testActualSheetSelectsAmountAndBrowserFailureNeverClaimsPayment() {
    let app = launch(), checkout = app.buttons["support.checkout"]
    XCTAssertFalse(checkout.isEnabled)
    app.buttons["support.amount.500"].tap(); XCTAssertTrue(checkout.isEnabled)
    let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "native-support-sheet-fixture"; screenshot.lifetime = .keepAlways; add(screenshot)
    reach(checkout, app: app); checkout.tap()
    XCTAssertTrue(app.staticTexts["Could not open secure checkout. Please try again."].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Support confirmed. Thank you."].exists)
    XCTAssertTrue(checkout.isEnabled, "Failure must allow a safe retry of the same handoff")
  }
  func testLargeTextKeepsAmountsAndActionReachable() {
    let app = launch(["--support-large-text"]), amount = app.buttons["support.amount.1000"]
    reach(amount, app: app); amount.tap()
    let checkout = app.buttons["support.checkout"]; reach(checkout, app: app)
    XCTAssertTrue(checkout.isEnabled)
    let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "native-support-accessibility-fixture"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
}
