import XCTest

/// Regression for feature retirement, not a simulated voice conversation.
final class VoiceEntryTests: XCTestCase {
  func testNoVoiceEntryInOrdinaryComposer() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-composer"]
    app.launch()
    XCTAssertTrue(app.buttons["composer.addRequiredMedia"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["Record voice attachment"].exists)
    XCTAssertFalse(app.textViews["composer.writing"].exists)
    XCTAssertFalse(app.buttons["composer.create"].isEnabled)
  }
}
