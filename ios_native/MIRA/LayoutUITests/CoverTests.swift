import XCTest

final class CoverTests: XCTestCase {
  func testCoverSelectorOpensRealPhotoPicker() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-composer"]
    app.launch()
    XCTAssertTrue(app.buttons["composer.intent"].waitForExistence(timeout: 40))
    app.buttons["composer.intent"].tap()
    XCTAssertTrue(app.buttons["Cover"].waitForExistence(timeout: 5))
    capture(app, "cover-start-with-four-choices")
    app.buttons["Cover"].tap()
    XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))
    // PhotosUI is the real system picker, not a Captro placeholder sheet.
    XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 10)
      || app.staticTexts["Photos"].exists || app.buttons["Photos"].exists)
    capture(app, "cover-real-system-photo-picker")
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.buttons["composer.intent"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
  }

  /// Run only after protected CI installs a disposable real account and legally
  /// available photography. Publishes Only me, reads real saved records in Home.
  func testRealPrivateCoverPublishing() {
    let cases = [("fashion.jpg", "WHAT I WORE\nTHIS WEEK", "Handwritten"),
      ("nightlife.jpg", "FRIDAY NIGHT\nIN NYC", "Bold"),
      ("dining.jpg", "BROOKLYN\nDINNER SPOTS", "Handwritten"),
      ("travel.jpg", "A WEEKEND IN\nNEW YORK", "Classic"),
      ("photography.jpg", "LITTLE MOMENTS", "Classic"),
      ("video.mp4", "FRIDAY NIGHT\nIN NYC", "Bold")]
    for (file, phrase, style) in cases {
      let app = XCUIApplication()
      app.launchArguments = ["--captro-design-quality-test", "--captro-quality-cover-runtime", "--cover-file=\(file)"]
      app.launch()
      XCTAssertTrue(app.buttons["composer.intent"].waitForExistence(timeout: 45))
      XCTAssertTrue(app.buttons["composer.audience"].label.contains("Only me"))
      app.buttons["composer.intent"].tap(); app.buttons["Cover"].tap()
      let text = app.descendants(matching: .any)["mediaWriting.text"].firstMatch
      XCTAssertTrue(text.waitForExistence(timeout: 10))
      text.tap(); text.typeText(phrase)
      app.buttons["Style"].tap()
      app.buttons[style].tap()
      if file == "dining.jpg" {
        app.switches["Rectangular backing"].tap()
        app.buttons["Text color"].tap(); app.buttons["Black"].tap()
      }
      capture(app, "cover-editor-\(file)")
      let done = app.buttons["mediaWriting.done"]
      XCTAssertTrue(done.isEnabled, "Cover layout must fit before committing")
      done.tap()
      XCTAssertTrue(app.buttons["Edit cover"].waitForExistence(timeout: 5))
      capture(app, "cover-composer-\(file)")
      let create = app.buttons["composer.create"]
      XCTAssertTrue(create.isEnabled)
      create.tap()
      let stream = app.scrollViews["home.post.stream"]
      XCTAssertTrue(stream.waitForExistence(timeout: 150), "Upload/moderation/publishing must really succeed")
      XCTAssertTrue(app.otherElements["home.post.media"].firstMatch.waitForExistence(timeout: 30))
      XCTAssertFalse(app.otherElements["home.post.stamp"].firstMatch.exists, "Cover must not get a competing ordinary stamp")
      capture(app, "cover-published-home-\(file)")
      app.terminate()
    }
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
