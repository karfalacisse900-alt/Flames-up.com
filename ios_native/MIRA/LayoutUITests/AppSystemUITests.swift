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
  func testProfileLargeTextDarkAndSettingsEntry() {
    let app = launch(["--captro-design-quality-test", "--captro-quality-profile", "--captro-quality-dark", "--captro-quality-large-text"])
    XCTAssertTrue(app.staticTexts["Test Creator"].waitForExistence(timeout: 15))
    capture(app, "profile-system-dark-accessibility")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Your activity'")).firstMatch.exists)
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved items'")).firstMatch.exists)
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    capture(app, "profile-settings-dark-accessibility")
  }
  func testTextOnlyFeedKeepsNaturalCardHeightAndFullBodyInDetails() {
    let app = launch(["--captro-home-feed-visual-test", "--captro-visual-text", "--captro-quality-dark"])
    // SwiftUI exposes the independently tappable content and creator rows,
    // rather than inventing an additional accessible container around them.
    let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A walk around the neighborhood'")).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Anyone up for a walk?"].exists)
    // The pager keeps the neighboring page in the accessibility tree.
    // Verify the visible page, not existence anywhere in the scroll view.
    XCTAssertFalse(card.staticTexts["More. Open full post"].isHittable)
    capture(app, "home-text-short-dark")
    let shortHeight = card.frame.height
    app.scrollViews["home.post.stream"].swipeUp()
    let longTitle = app.staticTexts["Looking for people to build with"]
    XCTAssertTrue(longTitle.waitForExistence(timeout: 5))
    XCTAssertTrue(longTitle.isHittable)
    let longCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Looking for people to build with'")).firstMatch
    XCTAssertTrue(longCard.isHittable)
    XCTAssertGreaterThan(longCard.frame.height, shortHeight)
    capture(app, "home-text-long-dark")
    // Home copy is finished/bounded without a reading CTA. Details remains
    // available through the post itself and retains the complete source text.
    XCTAssertFalse(app.staticTexts["More. Open full post"].isHittable)
    longTitle.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    capture(app, "text-post-details")
  }

  func testAudioControlsAppearInsideTextStamp() {
    let app = launch(["--captro-home-feed-visual-test", "--captro-visual-text", "--captro-visual-audio"])
    let play = app.buttons["Play recording"]
    XCTAssertTrue(play.waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Play attached music"].exists)
    let creator = app.buttons.matching(NSPredicate(format: "label CONTAINS '@test_creator'")).firstMatch
    XCTAssertTrue(creator.exists)
    XCTAssertLessThan(play.frame.maxY, creator.frame.minY)
    capture(app, "home-stamp-voice-and-music")
  }

  func testStoryNativeOpenCloseAndChatRoute() {
    let app = launch(["--captro-design-quality-test", "--captro-quality-story"])
    for index in 0..<3 {
      app.buttons["Open test Story"].tap()
      let close = app.buttons["Close capture"]
      XCTAssertTrue(close.waitForExistence(timeout: 5))
      if index == 0 { capture(app, "story-native-presentation") }
      close.tap()
      XCTAssertTrue(app.buttons["Open test Story"].waitForExistence(timeout: 5))
    }
    app.terminate()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-chat"]
    app.launch()
    XCTAssertTrue(app.staticTexts["No chats yet"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.navigationBars["Messages"].exists)
    let compose = app.buttons["New conversation"]
    let visible = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: compose)
    wait(for: [visible], timeout: 15)
    capture(app, "chat-empty-native")
  }
}
