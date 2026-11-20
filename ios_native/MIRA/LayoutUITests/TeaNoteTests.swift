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
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id("tea.note.identity.",101)).firstMatch.label.contains("Brooklyn"))
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
    let identity = app.descendants(matching: .any).matching(identifier: id("tea.note.identity.",101)).firstMatch
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
    XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"tea.compose.title").firstMatch.waitForExistence(timeout:8))
    let title = field("tea.compose.title",app); title.tap(); title.typeText("A plain Note")
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
  func testInlineComposerPanelsPreserveDraftAndSave() {
    let app = launch()
    app.buttons["tea.compose"].tap()
    let title = field("tea.compose.title", app)
    XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText("Nightlife NYC")
    let body = field("tea.compose.body", app)
    body.tap(); body.typeText("Where’s everyone going tonight?")
    app.buttons["tea.compose.borough"].tap()
    app.buttons["tea.compose.borough.Bronx"].tap()
    shot("new-note-inline-borough", app)
    app.buttons["tea.compose.link"].tap()
    let link = app.textFields["tea.compose.link.new"]
    XCTAssertTrue(link.waitForExistence(timeout: 5))
    shot("new-note-inline-link", app)
    link.tap(); link.typeText("https://example.com/signup")
    app.buttons["tea.compose.link.add"].tap()
    app.buttons["tea.compose.action"].tap()
    XCTAssertFalse(app.navigationBars["Note action"].exists, "Action stays inside New Note")
    let label = app.textFields["tea.action.label"]
    XCTAssertTrue(label.waitForExistence(timeout: 5))
    shot("new-note-inline-action", app)
    label.tap(); label.typeText("Join the test")
    let url = app.textFields["tea.action.url"]
    url.tap(); url.typeText("https://example.com/apply")
    app.buttons["tea.compose.borough"].tap()
    XCTAssertTrue(app.buttons["tea.compose.borough.Bronx"].isSelected)
    app.buttons["tea.compose.action"].tap()
    XCTAssertEqual(app.textFields["tea.action.label"].value as? String, "Join the test")
    XCTAssertEqual(app.textFields["tea.action.url"].value as? String, "https://example.com/apply")
    let done = app.buttons["tea.action.done"]
    for _ in 0..<3 { if done.isHittable { break }; app.swipeUp() }
    done.tap()
    app.buttons["tea.compose.save"].tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Nightlife NYC"].exists)
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Where’s everyone going tonight?")).firstMatch.exists)
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Join the test")).firstMatch.exists)
  }
  func testInlineComposerLargeText() {
    let app = launch(largeText: true)
    app.buttons["tea.compose"].tap()
    let title = field("tea.compose.title", app)
    XCTAssertTrue(title.waitForExistence(timeout: 8))
    title.tap(); title.typeText("A longer neighborhood Note title")
    let body = field("tea.compose.body", app)
    body.tap(); body.typeText("Where should we meet this weekend?")
    let borough = app.buttons["tea.compose.borough"]
    for _ in 0..<3 { if borough.isHittable { break }; app.swipeUp() }
    borough.tap()
    let staten = app.buttons["tea.compose.borough.Staten Island"]
    for _ in 0..<3 { if staten.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(staten.isHittable)
    XCTAssertLessThanOrEqual(staten.frame.maxX, app.frame.maxX)
    staten.tap()
    shot("new-note-inline-large-text", app)
    XCTAssertTrue(app.buttons["tea.compose.save"].isEnabled)
  }

}
