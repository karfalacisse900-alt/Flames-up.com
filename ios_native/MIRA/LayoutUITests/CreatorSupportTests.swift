import XCTest

final class CreatorSupportTests: XCTestCase {
  private func launchSurface(_ flags: [String]) -> XCUIApplication {
    let app = XCUIApplication(); app.launchArguments = ["--captro-support-review"] + flags; app.launch()
    XCTAssertTrue(app.staticTexts["Fixture Creator"].firstMatch.waitForExistence(timeout: 15)
      || app.buttons["creator.support"].waitForExistence(timeout: 5))
    return app
  }
  func testActualProfileSupportButtonOpensCorrectRecipientAndDismissesInPlace() {
    let app = launchSurface(["--support-profile"])
    let button = app.buttons["creator.support"]; XCTAssertTrue(button.waitForExistence(timeout: 10))
    waitUntilEnabled(button)
    let before = button.frame
    button.tap()
    XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Secure Stripe checkout opens in your browser."].exists,
      "The profile sheet must preserve the server-confirmed live payment mode.")
    XCTAssertFalse(app.buttons["support.checkout"].isEnabled)
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = "profile-support-sheet-fixture"; image.lifetime = .keepAlways; add(image)
    app.buttons["Close"].tap()
    XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(button.frame.minY, before.minY, accuracy: 2)
    XCTAssertTrue(app.buttons["profile.follow"].exists)
  }
  func testActualDetailsSupportButtonOpensCorrectRecipient() {
    let app = launchSurface(["--support-details"])
    let button = app.buttons["creator.support"]; XCTAssertTrue(button.waitForExistence(timeout: 10))
    waitUntilEnabled(button)
    reach(button, app: app)
    button.tap(); XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 5))
    app.buttons["support.amount.500"].tap()
    XCTAssertTrue(app.buttons["support.checkout"].isEnabled)
    app.buttons["Close"].tap(); XCTAssertTrue(button.waitForExistence(timeout: 5))
  }
  func testAvailabilityFailureOffersRetryWithoutOpeningPayment() {
    let app = launchSurface(["--support-profile", "--support-eligibility-error"])
    let retry = app.buttons["Retry Support"]; XCTAssertTrue(retry.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["support.checkout"].exists)
    retry.tap()
    let button = app.buttons["Support"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); waitUntilEnabled(button); button.tap()
    XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 5))
  }
  func testUnsupportedStorefrontGuestAndSelfNeverOfferSupportAction() {
    for flag in ["--support-non-us", "--support-guest", "--support-self"] {
      let app = launchSurface(["--support-profile", flag])
      XCTAssertFalse(app.buttons["creator.support"].waitForExistence(timeout: 2), flag)
      XCTAssertFalse(app.buttons["support.checkout"].exists, flag); app.terminate()
    }
  }
  func testIneligibleCreatorKeepsVisibleSupportEntryButNeverOpensCheckout() {
    let app = launchSurface(["--support-profile", "--support-ineligible"])
    let button = app.buttons["creator.support"]
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    waitUntilEnabled(button)
    XCTAssertEqual(button.value as? String, "Not available")
    button.tap()
    XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Earnings")).firstMatch.exists)
    XCTAssertFalse(app.buttons["support.checkout"].isEnabled)
  }
  private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
  }
  func testProductionGateKeepsSupportVisibleButCannotStartCheckout() {
    let app = launchSurface(["--support-profile", "--support-live-disabled"])
    let button = app.buttons["creator.support"]
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    XCTAssertEqual(button.value as? String, "Not available")
    button.tap()
    XCTAssertTrue(app.staticTexts["Support Fixture Creator"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Captro has not enabled Support checkout yet. No payment can be made right now."].exists)
    XCTAssertFalse(app.buttons["support.checkout"].isEnabled)
  }
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
