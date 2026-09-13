import XCTest

final class DesignQualityTests: XCTestCase {
  private func launch(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test"] + arguments
    app.launch()
    return app
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testControlsAndSheetScrolling() {
    let app = launch()
    XCTAssertTrue(app.buttons["Open sheet"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Unavailable action"].isEnabled)
    XCTAssertGreaterThanOrEqual(app.buttons["Open sheet"].frame.height, 44)
    capture(app, "controls-light")
    app.buttons["Open sheet"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    let scroll = app.scrollViews["quality.sheet.scroll"]
    scroll.swipeUp()
    scroll.swipeDown()
    XCTAssertTrue(app.buttons["Done"].exists, "Scrolling must not dismiss the sheet")
    capture(app, "sheet-scrolled")
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["More actions"].waitForExistence(timeout: 5))
    app.buttons["More actions"].tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    capture(app, "action-menu")
    app.buttons["Cancel"].tap()
  }

  func testWelcomeAndFormsAtLargeText() {
    let app = launch(["--captro-quality-auth", "--captro-quality-large-text"])
    XCTAssertTrue(app.buttons["Continue as Guest"].waitForExistence(timeout: 10))
    capture(app, "welcome-large-text")
    let login = app.buttons.matching(NSPredicate(format: "label == 'Log in' OR label == 'Login'")).firstMatch
    XCTAssertTrue(login.exists)
    login.tap()
    XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5))
    capture(app, "auth-large-text")
    XCTAssertTrue(app.buttons["Close"].exists)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["Continue as Guest"].waitForExistence(timeout: 5))
  }

  func testSettingsDarkAndLargeText() {
    let app = launch(["--captro-quality-settings", "--captro-quality-dark", "--captro-quality-large-text"])
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    capture(app, "settings-dark-large-text")
    app.swipeUp()
    capture(app, "settings-dark-scrolled")
  }
}
