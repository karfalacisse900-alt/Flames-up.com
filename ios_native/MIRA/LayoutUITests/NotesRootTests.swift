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
    XCTAssertTrue(app.staticTexts["0 qualified reads"].waitForExistence(timeout:8))
    shot("notes-author-private-insights",app)
    app.buttons["tea.detail.back"].tap()
    app.buttons["tea.filter.Clubs".lowercased()].tap()
    XCTAssertTrue(app.buttons["tea.createActivity"].waitForExistence(timeout:8))
    shot("notes-existing-clubs-filter",app)
    app.tabBars.buttons["Home"].tap(); app.tabBars.buttons["Notes"].tap()
    XCTAssertTrue(app.buttons["tea.createActivity"].exists, "Keep selected activity filter across tabs")
  }
  func testLargeTextKeepsTitleAndInterestSeparate() {
    let app = launch(["--captro-quality-large-text","--tea-engagement-fixture"])
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
  func testEngagementFeedDetailSyncUndoAndQualifiedRead() {
    let app=launch(["--tea-engagement-fixture"])
    let plus=app.buttons["tea.interest.interested."+note]
    plus.tap(); selected(plus,"Selected")
    let feedCount=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","12 people engaged")).firstMatch
    XCTAssertTrue(feedCount.waitForExistence(timeout:8))
    shot("engagement-feed-plus-union",app)
    plus.tap(); selected(plus,"Not selected")
    XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","11 people engaged")).firstMatch.waitForExistence(timeout:8))
    plus.tap(); selected(plus,"Selected")
    app.buttons["tea.conversation."+note].tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout:8))
    let count=app.staticTexts["tea.engagement."+note]
    XCTAssertTrue(count.waitForExistence(timeout:8))
    XCTAssertEqual(count.label,"12 people engaged")
    XCTAssertFalse(app.staticTexts["Your Note Insights"].exists)
    shot("engagement-reader-detail-union",app)
    // Wait for a complete qualified read, then remove plus: read still counts.
    Thread.sleep(forTimeInterval:6)
    app.buttons["tea.interest.pass."+note].tap()
    selected(app.buttons["tea.interest.pass."+note],"Selected")
    XCTAssertEqual(count.label,"12 people engaged")
    app.buttons["tea.detail.back"].tap()
    XCTAssertTrue(feedCount.waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["Loading Notes…"].exists)
  }
  func testBackgroundBeforeQualificationRestartsContinuousRead() {
    let app=launch()
    app.buttons["tea.conversation."+note].tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout:8))
    Thread.sleep(forTimeInterval:1)
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval:1)
    app.activate()
    XCTAssertFalse(app.staticTexts["tea.engagement."+note].exists)
    XCTAssertTrue(app.staticTexts["tea.engagement."+note].waitForExistence(timeout:9))
    XCTAssertEqual(app.staticTexts["tea.engagement."+note].label,"1 person engaged")
  }
  func testSecondPagePositionSurvivesTabsAndBackground() {
    let app = launch(["--tea-pages-fixture"])
    let target = app.buttons["tea.conversation.00000000-0000-4000-8000-000000000125"]
    let list = app.collectionViews["tea.conversations.list"].exists ? app.collectionViews["tea.conversations.list"] : app.tables.firstMatch
    for _ in 0..<60 {
      if target.exists && target.isHittable { break }
      // A full fling can skip this row on a small phone. Use bounded drags,
      // and correct direction if inertia has carried us past the target.
      let visible = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tea.conversation.")).allElementsBoundByIndex
        .filter { $0.isHittable }.compactMap { Int($0.identifier.suffix(12)) }
      let reverse = (visible.min() ?? 0) > 125
      let start = list.coordinate(withNormalizedOffset: CGVector(dx:0.7,dy:reverse ? 0.4 : 0.7))
      let end = list.coordinate(withNormalizedOffset: CGVector(dx:0.7,dy:reverse ? 0.7 : 0.4))
      start.press(forDuration:0.05,thenDragTo:end)
    }
    XCTAssertTrue(target.isHittable)
    guard target.exists && target.isHittable else { return }
    let before = target.frame.minY
    app.tabBars.buttons["Home"].tap(); app.tabBars.buttons["Notes"].tap()
    XCTAssertTrue(target.isHittable)
    XCTAssertEqual(target.frame.minY,before,accuracy:4)
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(target.waitForExistence(timeout:8)); XCTAssertTrue(target.isHittable)
    XCTAssertEqual(target.frame.minY,before,accuracy:4)
    XCTAssertFalse(app.staticTexts["Loading Notes…"].exists)
    shot("notes-second-page-preserved",app)
  }
}
