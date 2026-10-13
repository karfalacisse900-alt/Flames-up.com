import XCTest

final class PostPresentationReviewTests: XCTestCase {
  private func launch(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test"] + arguments
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    // Screenshot-only settling time for native sheet/navigation transitions.
    // No application delay or scrolling/playback behavior is changed.
    Thread.sleep(forTimeInterval: 1)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name + "-native-fixture"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testComposerRequiresMediaAndHasNoResponses() {
    let app = launch(["--captro-quality-composer", "--captro-composer-authorized"])
    let editor = app.textViews["composer.writing"]
    XCTAssertTrue(editor.waitForExistence(timeout: 20))
    editor.tap()
    // Fresh CI simulators can show Apple's first-keyboard QuickPath tutorial.
    if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
    editor.typeText("Keep my caption.")
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
    XCTAssertTrue(app.staticTexts["composer.mediaRequired"].exists)
    capture(app, "composer-media-required")
    app.buttons["composer.add"].tap()
    XCTAssertTrue(app.buttons["Photos & videos"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Responses"].exists)
    XCTAssertFalse(app.buttons["Yes / No"].exists)
    capture(app, "attachments-no-poll")
  }
  func testOrdinaryDetailsHasCaptionAndNoPollOrTransaction() {
    let app = launch(["--captro-presentation-review"])
    XCTAssertTrue(app.buttons["Open Details"].waitForExistence(timeout: 20))
    app.buttons["Open Details"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "post.detail.media").firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["post.detail.options"].exists)
    XCTAssertFalse(app.buttons["Yes"].exists)
    XCTAssertFalse(app.buttons["No"].exists)
    XCTAssertFalse(app.staticTexts["ORDER SUMMARY"].exists)
    capture(app, "ordinary-photo-details")
    app.swipeUp()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'An afternoon'")).firstMatch.exists)
    capture(app, "ordinary-caption-comments")
  }
  func testStoriesInventoryAndStampTapDoesNotAdvance() {
    for kind in ["general", "club", "deal", "local_offer", "event", "meetup", "group", "ticket", "booking", "party", "place", "guide", "travel", "receipt", "invoice"] {
      let app = launch(["--captro-presentation-review", "--review-kind=" + kind])
      XCTAssertTrue(app.buttons["Open Story"].waitForExistence(timeout: 15))
      app.buttons["Open Story"].tap()
      XCTAssertTrue(app.buttons["story.stamp"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["Close capture"].exists)
      capture(app, "story-" + kind)
      app.buttons["story.stamp"].tap()
      XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'A quiet afternoon'")).firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["Close capture"].exists, "Opening stamp details must not advance/dismiss the Story")
      app.terminate()
    }
  }
  func testClubAndEventDetailsKeepAuthorizedAction() {
    for kind in ["club", "event", "meetup", "deal"] {
      let app = launch(["--captro-presentation-review", "--review-kind=" + kind])
      app.buttons["Open Details"].tap()
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "post.detail.media").firstMatch.waitForExistence(timeout: 15))
      app.swipeUp()
      capture(app, "details-" + kind)
      XCTAssertFalse(app.buttons["Yes"].exists)
      XCTAssertTrue(app.staticTexts["Neighborhood " + kind.capitalized].exists)
      app.terminate()
    }
  }
  func testLargeTextStoryAndDetails() {
    let app = launch(["--captro-presentation-review", "--review-kind=club", "--captro-quality-large-text"])
    app.buttons["Open Story"].tap()
    XCTAssertTrue(app.buttons["story.openStamp"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["story.openStamp"].isHittable)
    XCTAssertGreaterThanOrEqual(app.buttons["Close capture"].frame.height, 44)
    XCTAssertGreaterThan(app.buttons["story.stamp"].frame.height, 110,
      "The accessibility test must actually enlarge the stamp, not just pass a launch flag")
    capture(app, "story-club-large-text")
    app.buttons["Close capture"].tap()
    app.buttons["Open Details"].tap()
    XCTAssertTrue(app.buttons["post.detail.options"].waitForExistence(timeout: 15))
    app.swipeUp()
    capture(app, "details-club-large-text")
  }

  func testAccessStatePresentationDoesNotOfferAnotherJoinAfterMembership() {
    for (flag, label) in [("--review-paid", "JOIN CLUB"), ("--review-unavailable", "EXPIRED"), ("--review-joined", "OPEN CLUB")] {
      let app = launch(["--captro-presentation-review", "--review-kind=club", flag])
      XCTAssertTrue(app.buttons["Open Details"].waitForExistence(timeout: 15))
      app.buttons["Open Details"].tap()
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "post.detail.media").firstMatch.waitForExistence(timeout: 15))
      app.swipeUp()
      let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
      XCTAssertTrue(action.waitForExistence(timeout: 5))
      if flag == "--review-unavailable" { XCTAssertFalse(action.isEnabled) }
      if flag == "--review-joined" {
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'JOIN CLUB'")).firstMatch.exists)
      }
      capture(app, "club-" + String(flag.dropFirst(9)))
      app.terminate()
    }
  }
}
