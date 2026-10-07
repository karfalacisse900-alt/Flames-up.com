import XCTest

final class MediaWritingTests: XCTestCase {
  func testEditorCommitCancelAndIndependentCarouselText() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-media-writing-test"]
    app.launch()
    let text = app.descendants(matching: .any)["mediaWriting.text"].firstMatch
    XCTAssertTrue(text.waitForExistence(timeout: 40))
    text.tap(); text.typeText("FRIDAY NIGHT")
    capture(app, "writing-editor-first-photo")
    app.buttons["Next media"].tap()
    XCTAssertEqual(text.value as? String, "Your short phrase")
    text.tap(); text.typeText("NYC")
    app.buttons["Previous media"].tap()
    XCTAssertEqual(text.value as? String, "FRIDAY NIGHT")
    app.buttons["mediaWriting.done"].tap()
    XCTAssertTrue(app.staticTexts["writing.savedText"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["writing.savedText"].label, "FRIDAY NIGHT")
    app.buttons["Edit text on media"].tap()
    XCTAssertTrue(text.waitForExistence(timeout: 5))
    XCTAssertEqual(text.value as? String, "FRIDAY NIGHT")
    app.buttons["Remove text"].tap()
    app.buttons["Cancel"].tap()
    XCTAssertEqual(app.staticTexts["writing.savedText"].label, "FRIDAY NIGHT")
  }
  func testRealMediaFeedWithWritingAndStamp() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-public-feed-test", "--captro-writing-overlays",
      "--captro-public-posts=91fb95be-aa76-4449-9feb-0c742f9f80e4,9c35e9fe-3537-45b9-844d-9399abe47445,7ff613af-f80a-474a-85cc-b159bbcf6a79,edb704f7-5ae7-486b-bd86-f58266aff746"]
    app.launch()
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 40))
    for index in 0..<7 {
      capture(app, "writing-runtime-feed-\(index)")
      stream.swipeUp(velocity: .slow)
    }
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
