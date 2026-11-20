import XCTest

final class TeaInlineReplyTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test","--captro-tea-review","--tea-density-fixture","--tea-inline-fixture","--captro-image-recovery-review"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout:20))
    app.tabBars.buttons["Notes"].tap()
    let row = app.buttons["tea.conversation.00000000-0000-4000-8000-000000000101"]
    XCTAssertTrue(row.waitForExistence(timeout:10)); row.tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout:10))
    return app
  }
  private func shot(_ name: String,_ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func sentence(_ app: XCUIApplication,_ prefix: String) -> XCUIElement {
    app.textViews.matching(NSPredicate(format:"identifier BEGINSWITH 'tea.sentence.' AND label BEGINSWITH %@",prefix)).firstMatch
  }
  private func tapExcerpt(_ element: XCUIElement) {
    element.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.25)).tap()
  }
  func testNightlifeCollapsedExpandedAndSelectionRetained() {
    let app = launch()
    let text = sentence(app,"Looking for")
    XCTAssertTrue(text.waitForExistence(timeout:10)); XCTAssertEqual(text.value as? String,"2 replies, collapsed")
    XCTAssertFalse(app.staticTexts["Hide replies"].exists)
    shot("nightlife-inline-collapsed",app)
    tapExcerpt(text)
    XCTAssertTrue(app.staticTexts["Don’t ever"].waitForExistence(timeout:8))
    XCTAssertEqual(text.value as? String,"2 replies, expanded")
    shot("nightlife-inline-expanded",app)
    XCTAssertTrue(app.buttons["tea.conversation.follow"].exists)
    XCTAssertTrue(app.buttons["tea.interest.pass.00000000-0000-4000-8000-000000000101"].exists)
    tapExcerpt(text)
    XCTAssertFalse(app.staticTexts["Don’t ever"].exists)
    XCTAssertEqual(text.value as? String,"2 replies, collapsed")
    // Native selection remains available on the same underlined caption.
    text.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.25)).press(forDuration:1.2)
    let replyAction = app.buttons["Reply to this part"]
    XCTAssertTrue(replyAction.waitForExistence(timeout:5)); replyAction.tap()
    XCTAssertTrue(app.staticTexts["tea.reply.target"].waitForExistence(timeout:5))
    let quote = app.staticTexts["tea.reply.target-quote"].label
    XCTAssertFalse(quote.isEmpty)
    XCTAssertLessThan(quote.count, "Looking for a good vibe, music, and a chill crowd.".count,
      "Native selection must target an excerpt, never substitute the entire caption")
    shot("nightlife-inline-selected-excerpt",app)
    app.buttons["tea.reply.clear-target"].tap()
  }
  func testLargeTextAndHundredAnchors() {
    let app = launch(["--captro-quality-large-text"])
    let text = sentence(app,"Looking for")
    XCTAssertTrue(text.waitForExistence(timeout:10))
    XCTAssertLessThanOrEqual(text.frame.maxX,app.frame.width-10)
    shot("nightlife-inline-large-text",app)
    app.terminate()
    let long = launch(["--tea-inline-long"])
    let first = sentence(long,"Sentence 1 "), second = sentence(long,"Sentence 2 ")
    XCTAssertTrue(first.waitForExistence(timeout:10))
    tapExcerpt(first); XCTAssertTrue(long.staticTexts["Reply 1"].waitForExistence(timeout:8))
    tapExcerpt(second); XCTAssertTrue(long.staticTexts["Reply 2"].waitForExistence(timeout:8))
    XCTAssertFalse(long.staticTexts["Reply 1"].exists)
    shot("hundred-anchors-one-inline-thread",long)
  }
}
