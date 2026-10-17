import XCTest

final class AccountRecoveryTests: XCTestCase {
  private func launch(_ flags:[String]) -> XCUIApplication {
    let app=XCUIApplication();app.launchArguments=["--captro-account-flow-review"]+flags;app.launch()
    XCTAssertTrue(app.staticTexts["account.fixture.identity"].waitForExistence(timeout:20));return app
  }
  private func fillReset(_ app:XCUIApplication) {
    XCTAssertTrue(app.secureTextFields["New password"].waitForExistence(timeout:8))
    XCTAssertEqual(app.navigationBars.matching(identifier:"New password").count,1)
    app.secureTextFields["New password"].tap();app.secureTextFields["New password"].typeText("fixture-password-123")
    app.secureTextFields["Confirm password"].tap();app.secureTextFields["Confirm password"].typeText("fixture-password-123")
  }
  func testRecoveryFromEveryRootPreservesIdentityAndDraftOnCancel() {
    for (flag,identity) in [("","signed-out"),("--account-guest","guest"),("--account-signed-in","fixture-a"),
                          ("--account-onboarding","fixture-a"),("--account-deletion","fixture-a")] {
      let app=launch(flag.isEmpty ? [] : [flag])
      let expected=NSPredicate(format:"label == %@",identity)
      XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:expected,object:app.staticTexts["account.fixture.identity"])],timeout:15),.completed)
      app.buttons["Draft"].tap();app.buttons["Recovery over draft"].tap();fillReset(app)
      app.buttons["Cancel"].tap()
      XCTAssertTrue(app.textFields["account.fixture.draft"].waitForExistence(timeout:5))
      XCTAssertEqual(app.textFields["account.fixture.draft"].value as? String,"Retained fixture draft")
      app.buttons["Close draft"].tap();XCTAssertEqual(app.staticTexts["account.fixture.identity"].label,identity)
      app.terminate()
    }
  }
  func testColdRepeatedDifferentAccountRecoveryCompletesWithoutSwitchingAndExpiredLinkStaysRecoverable() {
    let app=launch(["--account-signed-in","--recovery-cold-link"]);fillReset(app)
    app.buttons["Save new password"].tap()
    XCTAssertTrue(app.buttons["Recovery"].waitForExistence(timeout:8))
    XCTAssertEqual(app.staticTexts["account.fixture.identity"].label,"fixture-a")
    app.terminate()
    let expired=launch(["--account-guest","--recovery-expired"]);expired.buttons["Recovery"].tap();fillReset(expired)
    expired.buttons["Save new password"].tap()
    XCTAssertTrue(expired.staticTexts["Recovery link expired. Request a new email."].waitForExistence(timeout:8))
    expired.buttons["Cancel"].tap();XCTAssertEqual(expired.staticTexts["account.fixture.identity"].label,"guest")
  }
}
