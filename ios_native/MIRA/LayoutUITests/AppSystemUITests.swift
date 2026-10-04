import XCTest

/// Runtime checks of shipping views with isolated DEBUG-only profile/feed data.
/// No real accounts, media uploads, privacy changes or purchases are submitted.
final class AppSystemUITests: XCTestCase {
  private func launch(_ flags: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = flags
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testProfileEditingPreservesUnsavedChangesAndNativeNavigation() {
    let app = launch(["--captro-design-quality-test", "--captro-quality-profile"])
    XCTAssertTrue(app.staticTexts["Test Creator"].waitForExistence(timeout: 15))
    capture(app, "profile-system-light")
    app.buttons["profile.edit"].tap()
    XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 5))
    let field = app.textFields["Your name"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    field.typeText(" updated")
    capture(app, "profile-editor-keyboard")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
    app.buttons["Keep editing"].tap()
    XCTAssertTrue((field.value as? String)?.contains("updated") == true)
    app.buttons["Cancel"].tap()
    app.buttons["Discard changes"].tap()
    XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture(app, "profile-to-settings")
  }
  func testProfileLargeTextDarkAndActivityEntry() {
    let app = launch(["--captro-design-quality-test", "--captro-quality-profile", "--captro-quality-dark", "--captro-quality-large-text"])
    XCTAssertTrue(app.staticTexts["Test Creator"].waitForExistence(timeout: 15))
    capture(app, "profile-system-dark-accessibility")
    let activity = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Your activity'")).firstMatch
    for _ in 0..<5 where !activity.isHittable { app.swipeUp() }
    XCTAssertTrue(activity.isHittable)
    activity.tap()
    XCTAssertTrue(app.navigationBars["Your activity"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    capture(app, "profile-activity-dark-accessibility")
  }
  func testTextOnlyFeedKeepsNaturalCardHeightAndFullBodyInDetails() {
    let app = launch(["--captro-home-feed-visual-test", "--captro-visual-text", "--captro-quality-dark"])
    let card = app.otherElements["captro.textOnlyStamp"].firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Anyone up for a walk?"].exists)
    XCTAssertFalse(app.staticTexts["More. Open full post"].exists)
    capture(app, "home-text-short-dark")
    let shortHeight = card.frame.height
    app.scrollViews["home.post.pager"].swipeLeft()
    XCTAssertTrue(app.staticTexts["Looking for people to build with"].waitForExistence(timeout: 5))
    XCTAssertGreaterThan(card.frame.height, shortHeight)
    capture(app, "home-text-long-dark")
    XCTAssertTrue(app.staticTexts["More. Open full post"].exists)
    app.staticTexts["Looking for people to build with"].tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    capture(app, "text-post-details")
  }
}
