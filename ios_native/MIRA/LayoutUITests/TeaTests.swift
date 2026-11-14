import XCTest

final class TeaTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review"] + extra
    app.launch()
    let menu = app.buttons["home.feed.selector"]
    XCTAssertTrue(menu.waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertTrue(app.buttons["home.create.post"].exists)
    XCTAssertFalse(app.tabBars.buttons["Tea"].exists)
    menu.tap()
    let tea = app.buttons["home.menu.tea"]
    XCTAssertTrue(tea.waitForExistence(timeout: 8), app.debugDescription)
    tea.tap()
    selectListings(app)
    return app
  }

  private func selectListings(_ app: XCUIApplication) {
    // Do not tap coordinates captured while the full-screen cover is entering.
    let title = app.navigationBars["Tea"].staticTexts["Tea"]
    XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
    let section = app.buttons["Clubs & Events"]
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: section)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    section.tap()
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: section)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed, app.debugDescription)
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

  func testHomeMenuOpensIndividualEventAndExistingCheckout() {
    let app = launch()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 10))
    attach("tea-list", from: app)
    tapRow(3, in: app)
    XCTAssertTrue(app.staticTexts["Rooftop Session"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["$20 Entry"].exists)
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
    app.buttons["tea.back.home"].tap()
    XCTAssertTrue(app.buttons["home.create.post"].waitForExistence(timeout: 8))
  }

  func testJoinUsesCommerceAndBusinessOpensExistingMenu() {
    let app = launch()
    tapRow(1, in: app)
    let join = app.buttons["tea.primary-action"]
    XCTAssertTrue(join.waitForExistence(timeout: 8))
    XCTAssertEqual(join.label, "Join")
    XCTAssertTrue(app.descendants(matching: .any)["tea.linked.activity:00000000-0000-4000-8000-000000000003"].exists)
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

  func testFreshReopenDoesNotRequestAgainAndFailedRefreshKeepsDetails() {
    let app = launch(["--tea-request-counts", "--tea-slow", "--tea-refresh-failure"])
    tapRow(3, in: app)
    XCTAssertTrue(app.buttons["tea.primary-action"].waitForExistence(timeout: 10))
    let actionY = app.buttons["tea.primary-action"].frame.midY
    XCTAssertEqual(app.staticTexts["tea.test.requests"].value as? String, "3=1")
    back(app); tapRow(3, in: app)
    XCTAssertTrue(app.buttons["tea.primary-action"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.staticTexts["Loading details"].exists)
    XCTAssertEqual(app.staticTexts["tea.test.requests"].value as? String, "3=1")
    XCTAssertEqual(app.buttons["tea.primary-action"].frame.midY, actionY, accuracy: 2)
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertEqual(app.staticTexts["tea.test.requests"].value as? String, "3=1")
    let details = app.collectionViews["tea.detail"]
    // The collection is a container, not a tappable accessibility control.
    // Its real action must remain usable; the drag below proves scrolling.
    XCTAssertTrue(details.exists)
    XCTAssertTrue(app.buttons["tea.primary-action"].isHittable)
    let pullStart = details.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
    let pullEnd = details.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
    pullStart.press(forDuration: 0.1, thenDragTo: pullEnd)
    XCTAssertTrue(app.buttons["tea.detail.retry"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["$20 Entry"].exists)
    XCTAssertTrue(app.buttons["tea.primary-action"].exists)
    attach("tea-offline-retains-details", from: app)
    app.buttons["tea.detail.retry"].tap()
    let recovered = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["tea.detail.retry"])
    wait(for: [recovered], timeout: 10)
    XCTAssertEqual(app.staticTexts["tea.test.requests"].value as? String, "3=3")
  }

  func testFirstLoadRetryAndSwitchingItemsNeverShowsWrongDetails() {
    let app = launch(["--tea-request-counts", "--tea-detail-retry", "--tea-slow"])
    tapRow(3, in: app)
    XCTAssertTrue(app.buttons["tea.detail.retry"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["tea.primary-action"].exists)
    app.buttons["tea.detail.retry"].tap()
    XCTAssertTrue(app.buttons["tea.primary-action"].waitForExistence(timeout: 10))
    back(app); tapRow(2, in: app); back(app); tapRow(3, in: app)
    XCTAssertTrue(app.staticTexts["$20 Entry"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Photo Walk"].exists)
    XCTAssertEqual(app.buttons["tea.primary-action"].label, "Buy Ticket")
    back(app); app.buttons["tea.back.home"].tap()
    app.buttons["home.feed.selector"].tap(); app.buttons["home.menu.tea"].tap()
    selectListings(app)
    tapRow(3, in: app)
    XCTAssertTrue(app.buttons["tea.primary-action"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Loading details"].exists)
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String)?.contains("3=2") == true)
  }
}

private extension XCUIElement {
  func matchingLabel(_ value: String, in seconds: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: self)
    return XCTWaiter.wait(for: [expectation], timeout: seconds) == .completed
  }
}
