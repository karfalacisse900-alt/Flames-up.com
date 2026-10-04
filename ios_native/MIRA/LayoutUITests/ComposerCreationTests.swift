import XCTest

final class ComposerCreationTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-composer"] + extra
    app.launch()
    XCTAssertTrue(app.textViews["composer.writing"].waitForExistence(timeout: 15))
    if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    return app
  }
  private func snapshot(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name; shot.lifetime = .keepAlways; add(shot)
  }
  private func dismissKeyboard(_ app: XCUIApplication) {
    let done = app.buttons["composer.keyboardDone"]
    if done.waitForExistence(timeout: 5) { done.tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
  }
  private func select(_ app: XCUIApplication, _ title: String) {
    app.buttons["composer.intent"].tap()
    XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
    app.buttons[title].tap()
  }
  func testEmptyFilledKeyboardAndIntentPreservation() {
    let app = launch()
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
    XCTAssertTrue(app.staticTexts["What do you want to do?"].exists)
    XCTAssertFalse(app.staticTexts["Create Post"].exists)
    XCTAssertFalse(app.buttons["Personal"].exists)
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    snapshot(app, "composer-empty-keyboard")
    dismissKeyboard(app)
    snapshot(app, "composer-empty")
    select(app, "Looking for")
    let editor = app.textViews["composer.writing"]
    editor.tap()
    if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    let message = "A designer and a developer to help me start a company in NYC. I’m building Captro and looking for people to build with."
    editor.typeText(message)
    XCTAssertTrue(app.buttons["composer.create"].isEnabled)
    snapshot(app, "composer-filled-keyboard")
    dismissKeyboard(app)
    snapshot(app, "composer-filled")
    select(app, "Concern")
    XCTAssertEqual(editor.value as? String, message)
    XCTAssertFalse(app.buttons["Add time"].exists)
    snapshot(app, "composer-concern")
    select(app, "Want to")
    XCTAssertTrue(app.buttons["Add time"].exists)
    XCTAssertEqual(editor.value as? String, message)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
    app.buttons["Keep editing"].tap()
    XCTAssertEqual(editor.value as? String, message)
  }
  func testAudienceResponsesAndFailureRetainDraft() {
    let app = launch()
    dismissKeyboard(app)
    app.buttons["composer.audience"].tap()
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Only me")).firstMatch.tap()
    XCTAssertTrue(app.buttons["composer.audience"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["composer.audience"].label.contains("Only me"))
    app.textViews["composer.writing"].tap()
    app.textViews["composer.writing"].typeText("Who wants to build something together?")
    dismissKeyboard(app)
    app.buttons["composer.add"].tap()
    app.buttons["Add response"].tap()
    XCTAssertTrue(app.buttons["Custom choices"].waitForExistence(timeout: 5))
    app.buttons["Custom choices"].tap()
    let fields = app.textFields
    XCTAssertGreaterThanOrEqual(fields.count, 2)
    fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("Design")
    fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("Engineering\n")
    let use = app.buttons["Use poll"]
    for _ in 0..<4 where !use.isHittable {
      let scroll = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable && $0.frame.height > 100 }
      scroll?.swipeUp()
    }
    use.tap()
    XCTAssertTrue(app.buttons["Edit response options"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Design · Engineering"].exists)
    app.buttons["composer.create"].tap()
    XCTAssertTrue(app.staticTexts["composer.error"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.textViews["composer.writing"].value as? String, "Who wants to build something together?")
    XCTAssertTrue(app.buttons["composer.create"].isEnabled)
    snapshot(app, "composer-publish-failure")
  }
  func testAuthorizedObjectReturnsToOriginalWriting() {
    let app = launch(["--captro-composer-authorized"])
    app.textViews["composer.writing"].tap()
    app.textViews["composer.writing"].typeText("Join us on the rooftop.")
    dismissKeyboard(app)
    select(app, "Event")
    XCTAssertTrue(app.textFields["Event name"].waitForExistence(timeout: 5))
    app.textFields["Event name"].tap(); app.textFields["Event name"].typeText("Rooftop evening")
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["composer.object"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textViews["composer.writing"].value as? String, "Join us on the rooftop.")
    snapshot(app, "composer-structured-summary")
  }
  func testLargeTextDarkAndCharacterLimit() {
    let app = launch(["--captro-quality-large-text", "--captro-quality-dark"])
    let editor = app.textViews["composer.writing"]
    editor.tap(); editor.typeText(String(repeating: "a", count: 501))
    XCTAssertEqual((editor.value as? String)?.count, 500)
    XCTAssertTrue(app.staticTexts["500/500"].exists)
    dismissKeyboard(app)
    snapshot(app, "composer-large-text-dark-limit")
    XCTAssertTrue(app.buttons["composer.create"].isHittable)
    XCTAssertGreaterThanOrEqual(app.buttons["composer.intent"].frame.height, 44)
  }
}

