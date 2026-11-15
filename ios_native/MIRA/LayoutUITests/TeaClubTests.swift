import XCTest

final class TeaClubTests: XCTestCase {
  private func launch(owner: Bool = true, large: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review", owner ? "--tea-club-owner" : "--tea-club-member"] + (large ? ["--captro-quality-large-text"] : [])
    app.launch()
    XCTAssertTrue(app.buttons["home.feed.selector"].waitForExistence(timeout: 20))
    app.buttons["home.feed.selector"].tap(); app.buttons["home.menu.tea"].tap()
    XCTAssertTrue(app.segmentedControls["tea.sections"].waitForExistence(timeout: 8))
    app.segmentedControls["tea.sections"].buttons["Clubs & Events"].tap()
    let row = app.buttons["tea.row.activity:00000000-0000-4000-8000-000000000001"]
    XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
    XCTAssertTrue(app.segmentedControls["tea.club.tabs"].waitForExistence(timeout: 8))
    return app
  }
  private func shot(_ name: String, _ app: XCUIApplication) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }
  private func input(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.textFields[id].exists ? app.textFields[id] : app.textViews[id] }
  private func tab(_ name: String, _ app: XCUIApplication) { app.segmentedControls["tea.club.tabs"].buttons[name].tap() }

  func testMemberChatQuoteLinksInfoAndDraftSurviveTabs() {
    let app = launch(owner: false)
    XCTAssertTrue(app.staticTexts["Welcome to our next photo walk."].waitForExistence(timeout: 8))
    shot("club-chat-member",app)
    // Consecutive Maya messages have one author control, not one per message.
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Open profile for Maya")).count, 1)
    app.staticTexts["I’ll bring my camera."].press(forDuration: 1)
    XCTAssertTrue(app.buttons["Reply"].waitForExistence(timeout: 5)); app.buttons["Reply"].tap()
    let field = input("tea.club.input",app); field.tap(); field.typeText("I will join you.")
    app.buttons["tea.club.send"].tap()
    XCTAssertTrue(app.staticTexts["I will join you."].waitForExistence(timeout: 8))
    let quoted = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","tea.club.quote.")).firstMatch
    XCTAssertTrue(quoted.exists); quoted.tap()
    field.tap(); field.typeText("Saved draft")
    tab("Links",app); XCTAssertTrue(app.buttons["tea.club.add-link"].waitForExistence(timeout:5))
    app.buttons["tea.club.add-link"].tap()
    app.textFields["tea.club.link-name"].tap(); app.textFields["tea.club.link-name"].typeText("Walk route")
    app.textFields["tea.club.link-url"].tap(); app.textFields["tea.club.link-url"].typeText("https://example.com/walk")
    app.buttons["tea.club.link-save"].tap()
    XCTAssertTrue(app.staticTexts["Walk route"].waitForExistence(timeout:8)); shot("club-links",app)
    tab("Info",app)
    XCTAssertTrue(app.staticTexts["Be kind. Keep shared work within the club."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["tea.club.invites"].exists); shot("club-info-member",app)
    tab("Chat",app); XCTAssertEqual(input("tea.club.input",app).value as? String,"Saved draft")
  }

  func testOrganizerPinRoomsAndRevocableInvite() {
    let app = launch()
    XCTAssertTrue(app.staticTexts["Welcome to our next photo walk."].waitForExistence(timeout:8))
    app.staticTexts["Welcome to our next photo walk."].press(forDuration:1)
    XCTAssertTrue(app.buttons["Pin message"].waitForExistence(timeout:5)); app.buttons["Pin message"].tap()
    XCTAssertTrue(app.buttons["tea.club.pin"].waitForExistence(timeout:8)); shot("club-chat-pinned",app)
    app.buttons["tea.club.rooms"].tap()
    XCTAssertTrue(app.textFields["tea.room.name"].waitForExistence(timeout:5))
    app.textFields["tea.room.name"].tap(); app.textFields["tea.room.name"].typeText("Announcements\n")
    let announcements = app.switches["Only organizers can post"]
    // SwiftUI exposes the whole label row as the switch's AX frame. Its
    // midpoint is the label, outside the actual native UISwitch hit area.
    XCTAssertTrue(announcements.isHittable)
    announcements.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
      .withOffset(CGVector(dx: -25, dy: 0)).tap()
    XCTAssertEqual(announcements.value as? String,"1")
    app.buttons["tea.room.create"].tap()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Announcements")).firstMatch.waitForExistence(timeout:8))
    XCTAssertTrue(app.staticTexts["Announcements · organizers can post"].exists)
    app.swipeDown(); shot("club-rooms",app)
    app.navigationBars["Rooms"].buttons["Done"].tap()
    tab("Info",app); shot("club-info-organizer",app)
    app.buttons["tea.club.invites"].tap()
    XCTAssertTrue(app.buttons["tea.invite.create"].waitForExistence(timeout:5)); app.buttons["tea.invite.create"].tap()
    XCTAssertTrue(app.buttons["Copy link"].waitForExistence(timeout:8)); shot("club-invites-active",app)
    app.buttons["Revoke invite"].tap()
    XCTAssertTrue(app.staticTexts["Revoked"].waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["Copy link"].exists); shot("club-invites-revoked",app)
  }

  func testLargeTextAndReturningToSameClubPreserveDraft() {
    let app = launch(owner:false,large:true)
    XCTAssertTrue(app.staticTexts["I’ll bring my camera."].waitForExistence(timeout:8))
    let field=input("tea.club.input",app); XCTAssertTrue(field.isHittable); field.tap(); field.typeText("Keep this draft")
    XCTAssertGreaterThanOrEqual(app.buttons["tea.club.send"].frame.height,44)
    shot("club-large-text",app)
    app.buttons["tea.club.back"].tap()
    let row=app.buttons["tea.row.activity:00000000-0000-4000-8000-000000000001"]
    XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
    XCTAssertTrue(input("tea.club.input",app).waitForExistence(timeout:5))
    XCTAssertEqual(input("tea.club.input",app).value as? String,"Keep this draft")
  }
}
