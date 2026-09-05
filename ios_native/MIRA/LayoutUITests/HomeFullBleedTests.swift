import XCTest

final class HomeFullBleedTests: XCTestCase {
  func testVideoFillsScreenWidth() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-visual-size=threefour", "--captro-visual-video"]
    app.launch()
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 15))
    XCTAssertEqual(media.frame.minX, 0, accuracy: 0.5)
    XCTAssertEqual(media.frame.maxX, app.frame.width, accuracy: 0.5)
    XCTAssertTrue(app.buttons["Pause video"].firstMatch.waitForExistence(timeout: 10))
    app.buttons["Pause video"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Play video"].firstMatch.exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "full-bleed-video"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.terminate()
  }

  func testEveryPhotoRatioFillsScreenWidth() throws {
    for ratio in ["landscape", "portrait", "fourfive", "threefour", "square"] {
      let app = XCUIApplication()
      app.launchArguments = ["--captro-home-feed-visual-test", "--captro-visual-size=\(ratio)"]
      app.launch()
      let media = app.otherElements["home.post.media"].firstMatch
      XCTAssertTrue(media.waitForExistence(timeout: 15), "Missing media for \(ratio)")
      XCTAssertEqual(media.frame.minX, 0, accuracy: 0.5, "Left gutter for \(ratio)")
      XCTAssertEqual(media.frame.maxX, app.frame.width, accuracy: 0.5, "Right gutter for \(ratio)")
      XCTAssertGreaterThan(media.frame.height, 100)
      XCTAssertLessThanOrEqual(media.frame.maxY, app.frame.maxY)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "full-bleed-\(ratio)"
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
  }
}
