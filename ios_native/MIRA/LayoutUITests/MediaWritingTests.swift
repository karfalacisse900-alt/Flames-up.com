import XCTest

final class MediaWritingTests: XCTestCase {
  func testPostFramingPreviewCommitAndCancel() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-media-writing-test", "--captro-framing-test"]
    app.launch()
    let done = app.buttons["post.crop.done"]
    XCTAssertTrue(done.waitForExistence(timeout: 30))
    let format = app.segmentedControls["post.crop.format"]
    XCTAssertTrue(format.waitForExistence(timeout: 10))
    XCTAssertTrue(format.buttons["4:5"].isSelected, "Tall source defaults to the supported 4:5 crop")
    let canvas = app.descendants(matching: .any)["post.crop.preview"].firstMatch
    XCTAssertTrue(canvas.exists)
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
      .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
    capture(app, "framing-tall-source-repositioned")
    format.buttons["1:1"].tap()
    capture(app, "framing-square-preview")
    done.tap()
    let ratio = app.staticTexts["framing.savedRatio"]
    XCTAssertTrue(ratio.waitForExistence(timeout: 5)); XCTAssertEqual(ratio.label, "1.0")
    let crop = app.staticTexts["framing.savedCropY"].label
    XCTAssertNotEqual(crop, "0.5", "Drag must change the stored focal point")
    app.buttons["Edit text on media"].tap()
    XCTAssertTrue(format.waitForExistence(timeout: 5))
    format.buttons["16:9"].tap()
    app.buttons["Cancel"].tap()
    XCTAssertEqual(ratio.label, "1.0", "Cancel must preserve the prior selected format")
    XCTAssertEqual(app.staticTexts["framing.savedCropY"].label, crop)
  }
  func testEditorCommitCancelAndIndependentCarouselText() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-media-writing-test"]
    app.launch()
    let text = app.descendants(matching: .any)["mediaWriting.text"].firstMatch
    XCTAssertTrue(text.waitForExistence(timeout: 40))
    text.tap(); text.typeText("FRIDAY NIGHT")
    capture(app, "writing-editor-first-photo")
    app.buttons["Next media"].tap()
    XCTAssertTrue(["", "Your short phrase"].contains(text.value as? String ?? "unexpected"), "The next media item must not inherit the first item's writing")
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
    XCTAssertTrue(app.otherElements["home.post.media"].firstMatch.waitForExistence(timeout: 40))
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
