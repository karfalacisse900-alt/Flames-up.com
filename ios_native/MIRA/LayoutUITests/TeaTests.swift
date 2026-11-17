import XCTest

final class TeaTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review"] + extra
    app.launch()
    let tea = app.buttons["home.tea"]
    XCTAssertTrue(tea.waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertTrue(app.buttons["home.create.post"].exists)
    XCTAssertFalse(app.buttons["home.inbox"].exists)
    XCTAssertFalse(app.tabBars.buttons["Tea"].exists)
    tea.tap()
    selectListings(app)
    return app
  }

  private func selectListings(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["tea.compose"].waitForExistence(timeout: 8), app.debugDescription)
    app.buttons["tea.filter.clubs"].tap()
    let activities = app.buttons["tea.activities"]
    XCTAssertTrue(activities.waitForExistence(timeout: 5)); activities.tap()

  }

  private func row(_ number: Int, source: String = "activity", in app: XCUIApplication) -> XCUIElement {
    let id = "00000000-0000-4000-8000-" + String(format: "%012d", number)
    return app.buttons["tea.row.\(source):\(id)"]
  }

  func testActivityCreationUsesExistingFormsAndPreservesPaidChoice() {
    for (name, field) in [("Club", "Club name"), ("Event", "Event name"), ("Meetup", "Meetup name"), ("Deal", "Title")] {
      let app = launch()
      let create = app.buttons["tea.createActivity"]
      XCTAssertTrue(create.waitForExistence(timeout: 8)); create.tap()
      let choice = app.buttons[name]
      XCTAssertTrue(choice.waitForExistence(timeout: 8)); choice.tap()
      guard app.textFields[field].waitForExistence(timeout: 20) else {
        XCTFail("Existing \(name) form did not open: " + app.debugDescription); return
      }
      XCTAssertFalse(app.buttons["Photos & videos"].exists, "No regular post prerequisite")
      if name == "Club" {
        XCTAssertTrue(app.buttons["Free"].exists)
        app.buttons["Paid"].tap()
        XCTAssertTrue(app.staticTexts["Currency"].exists || app.buttons["Currency"].exists)
      }
      attach("tea-create-" + name.lowercased(), from: app)
      app.terminate()
    }
  }

  func testFreeClubPublicationReturnsToTeaAndNotHome() {
    let app = launch()
    app.buttons["tea.createActivity"].tap()
    XCTAssertTrue(app.buttons["Club"].waitForExistence(timeout: 8)); app.buttons["Club"].tap()
    let name = app.textFields["Club name"]
    XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("Isolated new club")
    // Restored drafts keep their real access settings. This journey creates a
    // free club explicitly, independent of the paid-choice fixture above.
    app.buttons["Free"].tap()
    XCTAssertTrue(app.navigationBars["Club"].buttons["Done"].isEnabled)
    app.navigationBars["Club"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["composer.intent"].waitForExistence(timeout: 8))
    app.buttons["composer.intent"].tap()
    XCTAssertTrue(name.waitForExistence(timeout: 8))
    XCTAssertEqual(name.value as? String, "Isolated new club")
    XCTAssertFalse(app.buttons["Photo or video"].exists, "A listing cannot turn into a Home post")
    app.navigationBars["Club"].buttons["Done"].tap()
    let publish = app.buttons["composer.create"]
    XCTAssertTrue(publish.waitForExistence(timeout: 8)); XCTAssertTrue(publish.isEnabled); publish.tap()
    XCTAssertTrue(app.staticTexts["Isolated new club"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertFalse(app.buttons["composer.create"].exists)
    attach("tea-created-listing-details", from: app)
    // Existing Details back returns to Tea; the refreshed list owns this item.
    let back = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(back.exists); back.tap()
    XCTAssertTrue(app.buttons["tea.createActivity"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Isolated new club"].firstMatch.waitForExistence(timeout: 8))
    app.buttons["tea.back.home"].tap()
    XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Isolated new club"].exists)
    XCTAssertFalse(app.staticTexts["New post"].exists)
  }

  func testRestrictedAccountCannotOpenActivityForm() {
    let app = launch(["--tea-create-denied"])
    app.buttons["tea.createActivity"].tap()
    XCTAssertTrue(app.alerts["Create activity"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.textFields["Club name"].exists)
    XCTAssertTrue(app.alerts.buttons["Retry"].exists)
  }

  func testProfileCityDoesNotHideClubsAndHomeEntryNeedsOneTap() {
    let app = launch()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 10),
      "The signed-in fixture has a city; eligible clubs without a matching city must still appear")
    XCTAssertTrue(app.buttons["tea.filter.all"].exists)
    XCTAssertTrue(app.staticTexts["Clubs & Events"].exists)
    XCTAssertFalse(app.buttons["home.menu.tea"].exists)
    attach("tea-clubs-with-profile-city", from: app)
    app.buttons["tea.back.home"].tap()
    let tea = app.buttons["home.tea"]
    XCTAssertTrue(tea.waitForExistence(timeout: 8))
    XCTAssertEqual(tea.frame.width, 44, accuracy: 1)
    XCTAssertEqual(tea.frame.midY, app.buttons["home.create.post"].frame.midY, accuracy: 1)
    attach("home-direct-tea-button", from: app)
  }

  func testFiltersKeepDistinctResultsAndUnavailableFollowingIsHonest() {
    let app = launch()
    app.buttons["tea.filter.clubs"].tap()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 8))
    XCTAssertTrue(row(1, in: app).staticTexts["Club"].exists)
    XCTAssertFalse(row(3, in: app).exists)
    app.buttons["tea.filter.events"].tap()
    XCTAssertTrue(row(3, in: app).waitForExistence(timeout: 8))
    XCTAssertTrue(row(3, in: app).staticTexts["Event"].exists)
    XCTAssertFalse(row(1, in: app).exists)
    app.buttons["tea.filter.following"].tap()
    XCTAssertTrue(app.alerts["Following"].waitForExistence(timeout: 5))
    app.alerts["Following"].buttons["OK"].tap()
    XCTAssertTrue(app.buttons["tea.filter.events"].isSelected)
    app.buttons["tea.filter.nearby"].tap()
    let city = app.alerts["Nearby activities"].textFields.firstMatch
    XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap(); city.typeText("Boston")
    app.alerts["Nearby activities"].buttons["Show activities"].tap()
    XCTAssertTrue(app.staticTexts["No activities to show yet."].waitForExistence(timeout: 8))
    XCTAssertFalse(row(1, in: app).exists)
    app.buttons["tea.filter.clubs"].tap()
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 8))
    app.buttons["tea.filter.all"].tap()
    XCTAssertTrue(app.buttons["tea.conversation.00000000-0000-4000-8000-000000000101"].waitForExistence(timeout: 8))
    XCTAssertFalse(row(1, in: app).isHittable)
    attach("tea-reference-list", from: app)
  }

  func testContextLabelsUseActualTypeAndExplicitCityResults() {
    let app = launch(["--tea-nearby-fixture"])
    XCTAssertTrue(row(1, in: app).waitForExistence(timeout: 8))
    XCTAssertTrue(row(1, in: app).staticTexts["Club"].exists)
    XCTAssertTrue(row(2, in: app).staticTexts["Meetup"].exists)
    XCTAssertTrue(row(3, in: app).staticTexts["Event"].exists)
    XCTAssertTrue(row(5, in: app).staticTexts["Offer"].exists)
    XCTAssertFalse(row(1, in: app).staticTexts["Nearby"].exists)
    attach("tea-real-activity-context", from: app)
    app.buttons["tea.filter.nearby"].tap()
    let city = app.alerts["Nearby activities"].textFields.firstMatch
    XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap(); city.typeText("New York")
    app.alerts["Nearby activities"].buttons["Show activities"].tap()
    XCTAssertTrue(row(3, in: app).waitForExistence(timeout: 8))
    XCTAssertTrue(row(3, in: app).staticTexts["Event"].exists)
    XCTAssertTrue(row(3, in: app).staticTexts["Nearby"].exists)
    XCTAssertFalse(row(1, in: app).exists, "An unrelated city result must not leak from the previous list")
    attach("tea-explicit-city-context", from: app)
    app.buttons["tea.filter.all"].tap()
    let post = app.buttons["tea.conversation.00000000-0000-4000-8000-000000000101"]
    XCTAssertTrue(post.waitForExistence(timeout: 8))
    XCTAssertFalse(post.staticTexts["Nearby"].exists, "An ordinary conversation has no asserted city association")
    XCTAssertFalse(post.staticTexts["Event"].exists)
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

  func testHomeTeaButtonOpensIndividualEventAndExistingCheckout() {
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

  func testJoinUsesCommerceAndDiscoveryOmitsBusinessDirectory() {
    let app = launch()
    tapRow(1, in: app)
    let join = app.buttons["tea.primary-action"]
    XCTAssertTrue(join.waitForExistence(timeout: 8))
    XCTAssertEqual(join.label, "Join")
    XCTAssertTrue(app.descendants(matching: .any)["tea.linked.activity:00000000-0000-4000-8000-000000000003"].exists)
    join.tap()
    XCTAssertTrue(app.buttons["tea.primary-action"].matchingLabel("MEMBERSHIP ACTIVE", in: 10))
    back(app)
    XCTAssertFalse(row(4, source: "business", in: app).exists,
      "Shopping directories are omitted; storefront ordering remains covered by BusinessOrderingTests")
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
    app.buttons["home.tea"].tap()
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
