import XCTest

final class StampVisualTests: XCTestCase {
  func testAllStylesRemainLiveAndOpenOnlyDetails() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-stamp-visual-test"]
    app.launch()
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
