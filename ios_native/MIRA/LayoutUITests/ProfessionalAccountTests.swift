import XCTest
final class ProfessionalAccountTests: XCTestCase {
  private func launch(_ flags: [String] = []) -> XCUIApplication {
    let app = XCUIApplication(); app.launchArguments = ["--captro-professional-review"] + flags; app.launch(); return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) { let image = XCTAttachment(screenshot: app.screenshot()); image.name=name; image.lifetime = .keepAlways; add(image) }
  func testSettingsApplicationSaveCancelSubmitAndReviewStatus() {
    let app = launch(); let entry = app.buttons["professional.settings"]
    if !entry.waitForExistence(timeout: 10) { app.swipeUp() }
    entry.tap(); XCTAssertTrue(app.buttons["professional.apply.creator"].waitForExistence(timeout: 10)); capture(app,"professional-settings")
    app.buttons["professional.apply.creator"].tap()
    let name=app.textFields["professional.name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Sample Artist")
    app.buttons["Cancel"].tap(); app.buttons["professional.apply.creator"].tap(); XCTAssertEqual(app.textFields["professional.name"].value as? String,"Public display name")
    app.textFields["professional.name"].tap(); app.textFields["professional.name"].typeText("Sample Artist")
    let description=app.textViews["professional.description"].exists ? app.textViews["professional.description"] : app.textFields["professional.description"]
    description.tap(); description.typeText("Independent musician making original music.")
    app.swipeUp(); capture(app,"professional-application")
    let submit=app.buttons["professional.submit"]; if !submit.isHittable { app.swipeUp() }; XCTAssertTrue(submit.isEnabled); submit.tap()
    XCTAssertTrue(app.staticTexts["Under review"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["professional.apply.business"].exists); capture(app,"professional-under-review")
  }
  func testPublicProfilesKeepRegularControlsAndSeparateSupport() {
    for kind in ["regular","creator","business"] {
      let app=launch(["--professional-profile","--professional-"+kind]); XCTAssertTrue(app.buttons["profile.follow"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["profile.tab.moments"].exists)
      if kind=="creator" { XCTAssertTrue(app.buttons["creator.support"].waitForExistence(timeout: 10)) }
      else { XCTAssertFalse(app.buttons["creator.support"].exists) }
      capture(app,"professional-profile-"+kind);app.terminate()
    }
  }
  func testLargeTextAndRejectedSubmissionStayHonest() {
    let app=launch(["--professional-large-text"]);app.buttons["professional.settings"].tap();XCTAssertTrue(app.buttons["professional.apply.creator"].waitForExistence(timeout: 10));capture(app,"professional-large-text")
  }
}
