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

  func testDraftCannotBeDiscardedAccidentally() {
    let app = launch(["--captro-quality-composer"])
    let editor = app.textViews["What do you want to share?"]
    XCTAssertTrue(editor.waitForExistence(timeout: 15))
    editor.tap()
    editor.typeText("A draft worth keeping")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
    capture(app, "discard-confirmation")
    app.buttons["Keep editing"].tap()
    XCTAssertEqual(editor.value as? String, "A draft worth keeping")
  }

  func testCacheClearReportsActualCompletion() {
    let app = launch(["--captro-quality-settings"])
    let appearance = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Appearance & cache")).firstMatch
    XCTAssertTrue(appearance.waitForExistence(timeout: 10))
    for _ in 0..<4 where !appearance.isHittable { app.swipeUp() }
    appearance.tap()
    let clear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Clear media cache")).firstMatch
    XCTAssertTrue(clear.waitForExistence(timeout: 5))
    for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
    clear.tap()
    XCTAssertTrue(app.staticTexts["Cached media cleared. Images reload as needed."].waitForExistence(timeout: 10))
    capture(app, "cache-completed")
  }

  func testSearchClearAndLegalReading() {
    let app = launch(["--captro-quality-search"])
    let field = app.textFields["Search people"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("z")
    XCTAssertTrue(app.staticTexts["Search people by name or username."].exists)
    capture(app, "search-keyboard")
    app.buttons["Clear search"].tap()
    XCTAssertEqual(field.value as? String, "Search people")
    app.terminate()
    let legal = launch(["--captro-quality-legal", "--captro-quality-large-text"])
    XCTAssertTrue(legal.navigationBars["Privacy"].waitForExistence(timeout: 10))
    legal.swipeUp()
    capture(legal, "legal-large-text")
  }
}
