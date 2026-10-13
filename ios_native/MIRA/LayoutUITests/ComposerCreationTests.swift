import XCTest

final class ComposerCreationTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-composer"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["composer.addRequiredMedia"].waitForExistence(timeout: 15))
    return app
  }

  func testOrdinaryComposerStartsWithRequiredMediaNotTextOrVoice() {
    let app = launch()
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
    XCTAssertFalse(app.textViews["composer.writing"].exists)
    XCTAssertFalse(app.staticTexts["composer.count"].exists)
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    XCTAssertFalse(app.buttons["Record voice attachment"].exists)
    app.buttons["composer.add"].tap()
    XCTAssertTrue(app.buttons["Photos & videos"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Responses"].exists)
    XCTAssertFalse(app.buttons["Want to"].exists)
    XCTAssertFalse(app.buttons["Looking for"].exists)
  }

  func testLegacyDraftWritingRemainsEditableButCannotPublishWithoutMedia() {
    let app = launch(["--captro-composer-legacy-draft"])
    let editor = app.textViews["composer.writing"]
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    XCTAssertEqual(editor.value as? String, "Keep my saved caption.")
    XCTAssertTrue(app.staticTexts["composer.count"].exists)
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
    XCTAssertTrue(app.staticTexts["composer.mediaRequired"].exists)
    editor.tap()
    if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    editor.typeText(" Updated.")
    XCTAssertTrue((editor.value as? String ?? "").contains("Updated."))
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
    app.buttons["Keep editing"].tap()
    XCTAssertTrue((editor.value as? String ?? "").contains("Updated."))
  }

  func testAudienceAndAuthorizedStampChoicesRemainAvailable() {
    let app = launch(["--captro-composer-authorized"])
    app.buttons["composer.audience"].tap()
    let onlyMe = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Only me")).firstMatch
    XCTAssertTrue(onlyMe.waitForExistence(timeout: 5))
    onlyMe.tap()
    XCTAssertTrue(app.buttons["composer.audience"].label.contains("Only me"))
    app.buttons["composer.add"].tap()
    app.buttons["More ways to create"].tap()
    for name in ["Club", "Event", "Meetup", "Deal"] {
      XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons[name].isHittable)
    }
    capture(app, "authorized-stamp-choices-native-fixture")
    // The submenu must be mounted on Add even before an intent selector exists.
    // Verify each authorized destination, then return without publishing.
    let destinations = [("Club", "Club name"), ("Event", "Event name"),
      ("Meetup", "Meetup name"), ("Deal", "Title")]
    for (index, destination) in destinations.enumerated() {
      if index > 0 {
        app.buttons["composer.add"].tap()
        let more = app.buttons["More ways to create"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
      }
      let choice = app.buttons[destination.0]
      XCTAssertTrue(choice.waitForExistence(timeout: 5))
      choice.tap()
      XCTAssertTrue(app.navigationBars[destination.0].waitForExistence(timeout: 5))
      XCTAssertTrue(app.textFields[destination.1].exists)
      capture(app, "authorized-\(destination.0.lowercased())-editor-native-fixture")
      app.buttons["Back to composition"].tap()
      XCTAssertTrue(app.buttons["composer.add"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["composer.audience"].label.contains("Only me"))
    }
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

