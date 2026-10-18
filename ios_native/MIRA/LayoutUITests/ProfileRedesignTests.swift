import XCTest

final class ProfileRedesignTests: XCTestCase {
  private func launch(visitor: Bool = false, locked: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", visitor ? "--captro-quality-visitor-profile" : "--captro-quality-profile"]
      + (locked ? ["--captro-profile-private"] : [])
    app.launch(); return app
  }
  private func capture(_ app: XCUIApplication, _ label: String) {
    let item = XCTAttachment(screenshot: app.screenshot()); item.name = label + "-isolated-fixture"
    item.lifetime = .keepAlways; add(item)
  }
  func testOwnerToolbarTabsAndCancelPreserveIntroduction() {
    let app = launch()
    XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["profile.favorites"].exists)
    XCTAssertTrue(app.buttons["Settings"].exists)
    XCTAssertTrue(app.staticTexts["City walks, photography and finding good coffee."].exists)
    capture(app, "owner-profile")
    app.buttons["profile.tab.clubs"].tap()
    XCTAssertTrue(app.staticTexts["No clubs displayed"].waitForExistence(timeout: 5))
    app.buttons["profile.tab.plans"].tap()
    XCTAssertTrue(app.staticTexts["No hosted plans loaded"].waitForExistence(timeout: 5))
    app.buttons["profile.tab.moments"].tap()
    app.buttons["profile.edit"].tap()
    let bio = app.textFields["A little about you"]
    XCTAssertTrue(bio.waitForExistence(timeout: 5))
    bio.tap(); bio.typeText(" changed")
    app.buttons["Cancel"].tap(); app.buttons["Discard changes"].tap()
    XCTAssertTrue(app.staticTexts["City walks, photography and finding good coffee."].waitForExistence(timeout: 5))
  }
  func testVisitorHasNoOwnerActionsAndPrivateCountsDoNotAppear() {
    let app = launch(visitor: true, locked: true)
    XCTAssertTrue(app.staticTexts["Private Creator"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Request to follow"].exists)
    XCTAssertFalse(app.buttons["profile.edit"].exists)
    XCTAssertFalse(app.buttons["profile.favorites"].exists)
    XCTAssertFalse(app.buttons["Settings"].exists)
    XCTAssertFalse(app.staticTexts["128 followers · 86 following"].exists)
    XCTAssertTrue(app.staticTexts["Private or unavailable profile"].exists)
    capture(app, "visitor-private-profile")
  }
  func testVisitorPublicIntroductionAndMenu() {
    let app = launch(visitor: true)
    XCTAssertTrue(app.buttons["profile.follow"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Message"].exists)
    XCTAssertTrue(app.staticTexts["128 followers · 86 following"].exists)
    capture(app, "visitor-public-profile")
    app.buttons["Profile options"].tap()
    XCTAssertTrue(app.buttons["Block"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Share profile"].exists)
  }
}
