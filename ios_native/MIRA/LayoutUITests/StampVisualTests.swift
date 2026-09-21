import XCTest

final class StampVisualTests: XCTestCase {
  func testAllStylesRemainLiveAndOpenOnlyDetails() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-stamp-visual-test"]
    app.launch()
    let stamp = app.buttons.matching(identifier: "captro.stamp").firstMatch
    XCTAssertTrue(stamp.waitForExistence(timeout: 5))
    stamp.tap()
    XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
    app.buttons["Close"].tap()
    for index in 0..<15 {
      let next = app.buttons["stamp.next"]
      if !next.isHittable { app.swipeUp() }
      XCTAssertTrue(next.waitForExistence(timeout: 5))
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "stamp-\(index)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      next.tap()
    }
  }
}
