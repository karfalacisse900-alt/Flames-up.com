import XCTest

final class FavoritesTests: XCTestCase {
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
