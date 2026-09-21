import XCTest

final class StampVisualTests: XCTestCase {
  func testFiveFamiliesAtRealFeedSizeAndOpenOnlyDetails() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-stamp-visual-test"]
    app.launch()
    let stamp = app.buttons.matching(identifier: "captro.editorialCard").firstMatch
    XCTAssertTrue(stamp.waitForExistence(timeout: 5))
    stamp.tap()
    XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
    app.buttons["Close"].tap()
    _ = app.otherElements["stamp.photo.loaded"].waitForExistence(timeout: 12)
    let families = ["place", "club", "event", "meetup", "deal"]
    for (index, family) in families.enumerated() {
      let next = app.buttons["stamp.next"]
      XCTAssertTrue(next.waitForExistence(timeout: 5))
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "feed-\(family)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      if index < families.count - 1 { next.tap() }
    }
  }
}
