import XCTest

final class TeaNoteTests: XCTestCase {
  private func launch(largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test","--captro-tea-review","--tea-notes-fixture"] + (largeText ? ["--captro-quality-large-text"] : [])
    app.launch(); XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout:20)); app.buttons["home.tea"].tap()
    XCTAssertTrue(app.buttons[id("tea.conversation.",101)].waitForExistence(timeout:10))
    return app
  }
  private func id(_ prefix: String, _ number: Int) -> String { prefix + "00000000-0000-4000-8000-" + String(format:"%012d",number) }
  private func shot(_ name: String, _ app: XCUIApplication) {
    let item = XCTAttachment(screenshot:app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
  }
  private func field(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.textFields[id].exists ? app.textFields[id] : app.textViews[id] }
  func testCastingApplicationFromRowKeepsRowClosedAndConfirmsOnlyAfterSubmit() {
    let app = launch()
    XCTAssertTrue(app.staticTexts["Notes"].exists)
    XCTAssertTrue(app.staticTexts[id("tea.note.identity.",101)].label.contains("Brooklyn"))
    shot("notes-list",app)
    app.buttons[id("tea.note.action.",101)].tap()
    XCTAssertTrue(app.textFields["tea.application.name"].waitForExistence(timeout:10))
    XCTAssertFalse(app.buttons["tea.detail.back"].exists,"Action must not also open the Note row")
    XCTAssertFalse(app.staticTexts["tea.application.confirmed"].exists)
    app.textFields["tea.application.name"].tap(); app.textFields["tea.application.name"].typeText("Fixture Applicant")
    let availability = field("tea.application.availability",app); availability.tap(); availability.typeText("Saturday afternoon")
    app.swipeUp()
    shot("notes-private-application",app)
    app.buttons["tea.application.submit"].tap()
    XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"tea.application.confirmed").firstMatch.waitForExistence(timeout:10))
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons[id("tea.conversation.",101)].waitForExistence(timeout:8))
    app.buttons[id("tea.note.action.",101)].tap()
    XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"tea.application.confirmed").firstMatch.waitForExistence(timeout:8))
  }
  func testLargeTextNotesAndExistingDealDestination() {
    let app = launch(largeText:true)
    let identity = app.staticTexts[id("tea.note.identity.",101)]
    XCTAssertTrue(identity.label.contains("Brooklyn")); XCTAssertLessThanOrEqual(identity.frame.maxX,app.frame.width)
    shot("notes-large-text",app)
    let deal = app.buttons[id("tea.note.action.",102)]
    for _ in 0..<5 { if deal.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(deal.isHittable); deal.tap()
    XCTAssertTrue(app.staticTexts["Weekend Pastry Offer"].waitForExistence(timeout:10))
    shot("notes-existing-deal",app)
  }
  func testPlainNoteAndOptionalActionComposer() {
    let app = launch()
    app.buttons["tea.compose"].tap()
    XCTAssertTrue(app.textFields["tea.compose.title"].waitForExistence(timeout:8))
    app.textFields["tea.compose.title"].tap(); app.textFields["tea.compose.title"].typeText("A plain Note")
    let body = field("tea.compose.body",app); body.tap(); body.typeText("A question for everyone.")
    XCTAssertTrue(app.buttons["tea.compose.save"].isEnabled)
    app.buttons["tea.compose.save"].tap()
    XCTAssertTrue(app.buttons["tea.conversation.edit"].waitForExistence(timeout:10))
    XCTAssertTrue(app.staticTexts["A plain Note"].exists)
    shot("notes-plain-detail",app)
    app.buttons["tea.conversation.edit"].tap()
    let action = app.buttons["tea.compose.action"]
    for _ in 0..<3 { if action.isHittable { break }; app.swipeUp() }
    action.tap()
    XCTAssertTrue(app.textFields["tea.action.url"].waitForExistence(timeout:8))
    app.textFields["tea.action.url"].tap(); app.textFields["tea.action.url"].typeText("javascript:bad")
    XCTAssertFalse(app.buttons["tea.action.done"].isEnabled)
    shot("notes-invalid-link",app)
  }
}
