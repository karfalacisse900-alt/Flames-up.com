import XCTest

/// UI-only checks never submit credentials, change real privacy state, or pay.
final class SettingsSystemTests: XCTestCase {
  private func launch(_ flags: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test"] + flags
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name; shot.lifetime = .keepAlways; add(shot)
  }
  private func tapRow(_ title: String, app: XCUIApplication) {
    let row = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
    for _ in 0..<7 where !row.isHittable { app.swipeUp() }
    XCTAssertTrue(row.isHittable, "Missing row: \(title)")
    row.tap()
  }
  func testNativeHierarchyAndDedicatedSecurityEditors() {
    let app = launch(["--captro-quality-settings"])
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    capture(app, "settings-main-light")
    tapRow("Security", app: app)
    XCTAssertTrue(app.navigationBars["Security"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields.count, 0, "Security must be a menu, not a giant form")
    capture(app, "settings-security-menu")
    tapRow("Email", app: app)
    let email = app.textFields["settings.email.input"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Save email"].isEnabled)
    email.tap(); email.typeText("invalid")
    XCTAssertFalse(app.buttons["Save email"].isEnabled)
    capture(app, "settings-email-keyboard")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Security"].waitForExistence(timeout: 5))
    tapRow("Password", app: app)
    XCTAssertEqual(app.secureTextFields.count, 2)
    XCTAssertFalse(app.buttons["Update password"].isEnabled)
    capture(app, "settings-password")
    app.navigationBars.buttons.firstMatch.tap()
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
  }
  func testStorageConfirmationAndAppearanceAreSeparate() {
    let app = launch(["--captro-quality-settings"])
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    tapRow("Appearance", app: app)
    XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Clear media cache"].exists)
    capture(app, "settings-appearance")
    app.navigationBars.buttons.firstMatch.tap()
    tapRow("Storage & cache", app: app)
    tapRow("Clear media cache", app: app)
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    capture(app, "settings-cache-confirmation")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Storage & cache"].exists)
  }
  func testDarkLargeTextAndLegalDocuments() {
    let app = launch(["--captro-quality-settings", "--captro-quality-dark", "--captro-quality-large-text"])
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    capture(app, "settings-dark-accessibility")
    tapRow("Privacy Policy", app: app)
    XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    capture(app, "privacy-document-dark-accessibility")
    app.swipeUp(); capture(app, "privacy-document-scrolled")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
  }
  func testWelcomeLoginSignupAndBack() {
    let app = launch(["--captro-quality-auth"])
    XCTAssertTrue(app.buttons["Continue as Guest"].waitForExistence(timeout: 10))
    capture(app, "welcome-native")
    app.buttons.matching(NSPredicate(format: "label == 'Log in' OR label == 'Login'")).firstMatch.tap()
    XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5))
    capture(app, "login-native")
    XCTAssertFalse(app.buttons["Close"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Continue as Guest"].waitForExistence(timeout: 5))
    app.buttons.matching(NSPredicate(format: "label == 'Sign up' OR label == 'Sign Up'")).firstMatch.tap()
    XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 5))
    capture(app, "signup-native")
  }
}
