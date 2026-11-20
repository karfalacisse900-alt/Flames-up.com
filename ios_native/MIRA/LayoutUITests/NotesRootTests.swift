import XCTest

final class NotesRootTests: XCTestCase {
  private let note = "00000000-0000-4000-8000-000000000101"
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review", "--tea-density-fixture", "--captro-image-recovery-review"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout: 20), "Home remains the default destination")
    XCTAssertFalse(app.tabBars.buttons["Capture"].exists)
    XCTAssertTrue(app.tabBars.buttons["Notes"].exists)
    app.tabBars.buttons["Notes"].tap()
    XCTAssertTrue(app.buttons["tea.conversation." + note].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["tea.back.home"].exists, "Root Notes has no back arrow")
    return app
  }
  private func shot(_ name: String, _ app: XCUIApplication) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }
  private func selected(_ button: XCUIElement, _ value: String) {
    expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: button)
    waitForExpectations(timeout: 8)
  }
  func testRootNavigationInterestUndoAndDraftSurviveReturn() {
    let app = launch()
    for number in 101...103 {
      XCTAssertTrue(app.buttons["tea.interest.interested.00000000-0000-4000-8000-" + String(format: "%012d", number)].exists)
      XCTAssertTrue(app.buttons["tea.interest.pass.00000000-0000-4000-8000-" + String(format: "%012d", number)].exists)
    }
    let plus = app.buttons["tea.interest.interested." + note]
    plus.tap(); selected(plus,"Selected")
    shot("notes-root-feed-interest",app)
    XCTAssertFalse(app.buttons["tea.detail.back"].exists, "Interest must not open the row")
    app.buttons["tea.conversation." + note].tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.tabBars.buttons["Notes"].exists, "No tab bar below the detail composer")
    XCTAssertFalse(app.buttons["tea.author.follow"].exists)
    XCTAssertFalse(app.otherElements["tea.insights"].exists, "Reader must not receive author Insights")
    selected(plus,"Selected")
    let minus = app.buttons["tea.interest.pass." + note]
    minus.tap(); selected(minus,"Selected"); selected(plus,"Not selected")
    minus.tap(); selected(minus,"Not selected")
    shot("notes-reader-detail",app)
    let draft = app.descendants(matching:.any).matching(identifier:"tea.reply.input").firstMatch
    XCTAssertTrue(draft.exists); draft.tap(); draft.typeText("Keep this unfinished reply")
    app.buttons["tea.detail.back"].tap()
    app.tabBars.buttons["Home"].tap(); app.tabBars.buttons["Notes"].tap()
    XCTAssertFalse(app.staticTexts["Loading Notes…"].exists)
    app.buttons["tea.conversation." + note].tap()
    XCTAssertTrue(draft.waitForExistence(timeout:8))
    XCTAssertTrue((draft.value as? String ?? "").contains("Keep this unfinished reply"))
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(draft.waitForExistence(timeout:8))
    XCTAssertTrue((draft.value as? String ?? "").contains("Keep this unfinished reply"))
  }
  func testAuthorInsightsAndActivityEntryRemainAvailable() {
    let app = launch(["--tea-interest-owner"])
    app.buttons["tea.conversation." + note].tap()
    XCTAssertTrue(app.staticTexts["Your Note Insights"].waitForExistence(timeout:8))
    XCTAssertTrue(app.staticTexts["0 unique opens"].waitForExistence(timeout:8))
    shot("notes-author-private-insights",app)
    app.buttons["tea.detail.back"].tap()
    app.buttons["tea.filter.Clubs".lowercased()].tap()
    XCTAssertTrue(app.buttons["tea.createActivity"].waitForExistence(timeout:8))
    shot("notes-existing-clubs-filter",app)
    app.tabBars.buttons["Home"].tap(); app.tabBars.buttons["Notes"].tap()
    XCTAssertTrue(app.buttons["tea.createActivity"].exists, "Keep selected activity filter across tabs")
  }
  func testLargeTextKeepsTitleAndInterestSeparate() {
    let app = launch(["--captro-quality-large-text"])
    let row = app.buttons["tea.conversation." + note]
    let plus = app.buttons["tea.interest.interested." + note]
    XCTAssertGreaterThanOrEqual(plus.frame.width,44)
    XCTAssertGreaterThanOrEqual(plus.frame.height,44)
    XCTAssertGreaterThanOrEqual(plus.frame.minY,row.frame.maxY-1)
    XCTAssertLessThanOrEqual(plus.frame.maxX,app.frame.maxX)
    shot("notes-root-large-text",app)
    row.tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout:8))
    shot("notes-detail-large-text",app)
  }
}
