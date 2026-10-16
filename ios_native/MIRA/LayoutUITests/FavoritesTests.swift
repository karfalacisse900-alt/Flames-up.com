import XCTest

final class FavoritesTests: XCTestCase {
  private func launch(_ flags: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-favorites-review"] + flags
    app.launch()
    XCTAssertTrue(app.buttons["favorite.star.review-post"].waitForExistence(timeout: 20))
    return app
  }
  private func expectLabel(_ label: String, on element: XCUIElement) {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
  }
  private func dismissNotice(_ app: XCUIApplication) {
    if app.buttons["Dismiss confirmation"].exists { app.buttons["Dismiss confirmation"].tap() }
  }
  func testCarouselSaveDetailsUnsaveAndSavedLibraryStaySynchronized() {
    let app = launch(["--review-carousel"])
    let media = app.descendants(matching: .any)["home.post.media"].firstMatch
    let frame = media.frame
    media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.18))
      .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.18)))
    XCTAssertTrue(app.staticTexts["Photo 2 of 2"].waitForExistence(timeout: 5))
    let star = app.buttons["favorite.star.review-post"]
    star.tap(); expectLabel("Remove from Favorites", on: star)
    XCTAssertEqual(media.frame.minY, frame.minY, accuracy: 1)
    XCTAssertEqual(media.frame.height, frame.height, accuracy: 1)
    XCTAssertTrue(app.staticTexts["Photo 2 of 2"].exists)
    dismissNotice(app)
    media.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.25)).tap()
    XCTAssertTrue(app.buttons["post.detail.options"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["Post"].exists)
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES 'Comments [0-9]+'" )).firstMatch.exists)
    XCTAssertTrue(app.textFields["Add a comment"].exists)
    app.buttons["post.detail.options"].tap()
    for label in ["Like post", "Unlike post", "Share post", "Organize in collection"] { XCTAssertFalse(app.buttons[label].exists) }
    XCTAssertTrue(app.buttons["Report post"].exists)
    app.buttons["Remove from Favorites"].tap()
    XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5)); dismissNotice(app)
    app.navigationBars.buttons.firstMatch.tap()
    expectLabel("Save to Favorites", on: star)
    XCTAssertTrue(app.staticTexts["Photo 2 of 2"].exists)
    XCTAssertEqual(media.frame.minY, frame.minY, accuracy: 1)
    star.tap(); expectLabel("Remove from Favorites", on: star); dismissNotice(app)
    app.swipeUp(); app.buttons["Favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.post.review-post"].waitForExistence(timeout: 5))
    capture(app, "saved-library-synchronized")
  }
  func testRapidTapsFailureRollbackRetryAndDragCancellation() {
    let app = launch(["--favorites-fail-once", "--favorites-delayed", "--review-carousel"])
    let star = app.buttons["favorite.star.review-post"]
    star.tap(); star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 8))
    expectLabel("Save to Favorites", on: star)
    XCTAssertFalse(app.buttons["post.detail.options"].exists, "Busy star taps must not open Details")
    app.buttons["Retry"].tap(); expectLabel("Remove from Favorites", on: star)
    dismissNotice(app)
    star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.05, thenDragTo: star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -2)))
    XCTAssertFalse(app.navigationBars["Save to collections"].exists)
    expectLabel("Remove from Favorites", on: star)
    capture(app, "favorite-retry-no-navigation")
  }
  func testBareVideoCreatorOnlyInDetailsAndTopLeftControlsDoNotNavigate() {
    let app = launch(["--review-video", "--review-empty"])
    XCTAssertFalse(app.descendants(matching: .any)["home.post.attribution"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["home.post.stamp"].exists)
    XCTAssertFalse(app.staticTexts["@captro_test"].exists)
    let media = app.descendants(matching: .any)["home.post.media"].firstMatch
    checkControls(app, surface: "home", media: media)
    let star = app.buttons["favorite.star.review-post"]
    star.tap(); expectLabel("Remove from Favorites", on: star)
    XCTAssertEqual(app.buttons["home.video.play"].label, "Play video", "Saving must retain the deliberate pause")
    dismissNotice(app)
    capture(app, "bare-home-video-top-left-controls")
    media.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
    XCTAssertTrue(app.buttons["post.detail.options"].waitForExistence(timeout: 5))
    let detailMedia = app.descendants(matching: .any)["post.detail.media"].firstMatch
    checkControls(app, surface: "details", media: detailMedia)
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["@captro_test"].exists)
    let input = app.textFields["Add a comment"]
    input.tap(); input.typeText("A real comment still works")
    app.buttons["Send comment"].tap()
    XCTAssertTrue(app.staticTexts["A real comment still works"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES 'Comments [0-9]+'" )).firstMatch.exists)
    capture(app, "details-creator-comments-no-headings")
  }
  private func checkControls(_ app: XCUIApplication, surface: String, media: XCUIElement) {
    let play = app.buttons["\(surface).video.play"], mute = app.buttons["\(surface).video.mute"]
    XCTAssertTrue(play.waitForExistence(timeout: 5)); XCTAssertTrue(mute.isHittable)
    XCTAssertEqual(play.frame.minX, media.frame.minX + 12, accuracy: 1)
    XCTAssertEqual(play.frame.minY, media.frame.minY + 12, accuracy: 1)
    XCTAssertEqual(play.frame.minY, mute.frame.minY, accuracy: 1)
    XCTAssertGreaterThanOrEqual(play.frame.width, 44); XCTAssertGreaterThanOrEqual(mute.frame.height, 44)
    play.tap(); expectLabel("Play video", on: play)
    let oldMute = mute.label; mute.tap(); XCTAssertNotEqual(mute.label, oldMute)
    XCTAssertTrue(play.exists)
    if surface == "home" { XCTAssertFalse(app.buttons["post.detail.options"].exists) }
  }
  func testTapHoldCancelCollectionsAndUndo() {
    let app=XCUIApplication()
    app.launchArguments=["--captro-design-quality-test","--captro-favorites-review"]
    app.launch()
    let star=app.buttons["favorite.star.review-post"]
    XCTAssertTrue(star.waitForExistence(timeout:20))
    let frame=star.frame
    XCTAssertEqual(star.label,"Save to Favorites")
    star.press(forDuration:0.7)
    XCTAssertTrue(app.navigationBars["Save to collections"].waitForExistence(timeout:5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(star.waitForExistence(timeout:5)); XCTAssertEqual(star.label,"Save to Favorites")
    XCTAssertFalse(app.staticTexts["review.details.opened"].exists)
    star.tap()
    let saved=NSPredicate(format:"label == %@","Remove from Favorites")
    expectation(for:saved,evaluatedWith:star); waitForExpectations(timeout:5)
    XCTAssertEqual(star.frame.minY,frame.minY,accuracy:1)
    capture(app,"favorites-star-saved")
    if app.buttons["Dismiss confirmation"].exists {app.buttons["Dismiss confirmation"].tap()}
    star.press(forDuration:0.7)
    XCTAssertTrue(app.buttons["Dining"].waitForExistence(timeout:5))
    app.buttons["Dining"].tap(); app.buttons["New York"].tap()
    capture(app,"favorites-multiple-collections")
    app.buttons["Done"].tap()
    XCTAssertTrue(star.waitForExistence(timeout:5))
    expectation(for:saved,evaluatedWith:star); waitForExpectations(timeout:5)
    star.tap()
    XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout:5)); app.buttons["Undo"].tap()
    expectation(for:saved,evaluatedWith:star); waitForExpectations(timeout:5)
    if app.buttons["Dismiss confirmation"].exists {app.buttons["Dismiss confirmation"].tap()}
    star.press(forDuration:0.7)
    XCTAssertTrue(app.buttons["Dining"].waitForExistence(timeout:5))
    XCTAssertEqual(app.buttons["Dining"].value as? String,"Selected")
    XCTAssertEqual(app.buttons["New York"].value as? String,"Selected")
    app.buttons["Cancel"].tap()
    app.swipeUp()
    XCTAssertTrue(app.buttons["Favorites"].waitForExistence(timeout:5)); app.buttons["Favorites"].tap()
    XCTAssertTrue(app.buttons["All saved"].waitForExistence(timeout:5))
    capture(app,"favorites-all-saved")
  }
  private func capture(_ app:XCUIApplication,_ name:String) {
    let screenshot=XCTAttachment(screenshot:app.screenshot()); screenshot.name=name+"-native-fixture"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
}
