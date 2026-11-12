import XCTest

final class TeaTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review"] + extra
    app.launch()
    let tab = app.tabBars.buttons["Tea"]
    XCTAssertTrue(tab.waitForExistence(timeout: 20), app.debugDescription)
    if tab.exists { tab.tap() }
    return app
  }

  private func row(_ number: Int, source: String = "activity", in app: XCUIApplication) -> XCUIElement {
    let id = "00000000-0000-4000-8000-" + String(format: "%012d", number)
    return app.buttons["tea.row.\(source):\(id)"]
  }

  private func tapRow(_ number: Int, source: String = "activity", in app: XCUIApplication) {
    let target = row(number, source: source, in: app)
    XCTAssertTrue(target.waitForExistence(timeout: 10), app.debugDescription)
    if target.exists { target.tap() }
  }

  private func back(_ app: XCUIApplication) {
    let nav = app.navigationBars.firstMatch
    nav.buttons.firstMatch.tap()
  }

  func testTeaTabOpensIndividualEventAndExistingCheckout() {
    let app = launch()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 10))
    attach("tea-list", from: app)
    tapRow(3, in: app)
    XCTAssertTrue(app.staticTexts["Rooftop Session"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["$20"].exists)
    XCTAssertFalse(app.staticTexts["Comments"].exists)
    let buy = app.buttons["tea.primary-action"]
    XCTAssertTrue(buy.exists)
    XCTAssertEqual(buy.label, "Buy Ticket")
    attach("tea-event-detail", from: app)
    buy.tap()
    XCTAssertTrue(app.navigationBars["Payment"].waitForExistence(timeout: 12))
    XCTAssertTrue(app.staticTexts["Test payment"].exists)
    app.buttons["Close"].tap()
    back(app)
    XCTAssertTrue(row(3, in: app).waitForExistence(timeout: 8))
  }

  func testJoinUsesCommerceAndBusinessOpensExistingMenu() {
    let app = launch()
    tapRow(1, in: app)
    let join = app.buttons["tea.primary-action"]
    XCTAssertTrue(join.waitForExistence(timeout: 8))
    XCTAssertEqual(join.label, "Join")
    join.tap()
    XCTAssertTrue(app.buttons["tea.primary-action"].matchingLabel("MEMBERSHIP ACTIVE", in: 10))
    back(app)
    tapRow(4, source: "business", in: app)
    XCTAssertTrue(app.staticTexts["Sample pickup"].waitForExistence(timeout: 8))
    let business = app.buttons["View Business"].firstMatch
    XCTAssertTrue(business.exists)
    business.tap()
    XCTAssertTrue(app.staticTexts["Menu"].waitForExistence(timeout: 8))
  }

  func testRetryPaginationAndReturnToSameScrollPosition() {
    let app = launch(["--tea-initial-error"])
    let retry = app.buttons["Retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 10))
    retry.tap()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 10))
    let target = row(23, in: app)
    for _ in 0..<12 where !target.isHittable { app.swipeUp() }
    XCTAssertTrue(target.isHittable, app.debugDescription)
    guard target.isHittable else { return }
    let original = target.frame.midY
    target.tap()
    XCTAssertTrue(app.staticTexts["Neighborhood event 23"].waitForExistence(timeout: 8))
    back(app)
    XCTAssertTrue(target.waitForExistence(timeout: 8))
    XCTAssertEqual(target.frame.midY, original, accuracy: 16)
  }

  private func attach(_ name: String, from app: XCUIApplication) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}

private extension XCUIElement {
  func matchingLabel(_ value: String, in seconds: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: self)
    return XCTWaiter.wait(for: [expectation], timeout: seconds) == .completed
  }
}
