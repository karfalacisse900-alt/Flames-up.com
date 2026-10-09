import XCTest

final class EditorialMenuTests: XCTestCase {
  func testHomeFeedSelectorStaysInHeaderAndChangesSelection() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test"]
    app.launch()
    let selector = app.buttons["home.feed.selector"]
    XCTAssertTrue(selector.waitForExistence(timeout: 15))
    let header = app.otherElements["home.fixed.controls"]
    let storyRail = app.scrollViews["home.story.rail"]
    let beforeRailX = storyRail.frame.minX
    selector.tap()
    for name in ["Around", "Following", "For You"] {
      XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
    }
    XCTAssertFalse(app.buttons["NYC"].exists)
    capture(app, "editorial-home-feed-selector")
    app.buttons["Around"].tap()
    XCTAssertTrue(selector.label.contains("Around"))
    XCTAssertEqual(storyRail.frame.minX, beforeRailX, accuracy: 1)
    XCTAssertTrue(header.exists)
  }

  func testComposerMenusAreCompactAndChoicesCommitImmediately() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-composer"]
    app.launch()
    let intent = app.buttons["composer.intent"]
    XCTAssertTrue(intent.waitForExistence(timeout: 15))
    intent.tap()
    XCTAssertTrue(app.buttons["Want to"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Cover"].exists)
    capture(app, "editorial-create-intent")
    app.buttons["Looking for"].tap()
    XCTAssertTrue(intent.label.contains("is looking for"))
    app.buttons["composer.audience"].tap()
    XCTAssertTrue(app.buttons["Only me"].waitForExistence(timeout: 5))
    capture(app, "editorial-create-audience")
    app.buttons["Only me"].tap()
    XCTAssertTrue(app.buttons["composer.audience"].label.contains("Only me"))
    app.buttons["composer.add"].tap()
    XCTAssertTrue(app.buttons["Photos & videos"].waitForExistence(timeout: 5))
    capture(app, "editorial-create-add")
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
