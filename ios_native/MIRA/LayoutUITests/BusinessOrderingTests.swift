import XCTest

final class BusinessOrderingTests: XCTestCase {
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-business-review"]
    app.launch()
    return app
  }

  func testQuickAddUsesSameStorefrontAndChangesQuantityInline() {
    let app = launch()
    openShop("20000000-0000-4000-8000-000000000002", in: app)
    let add = app.buttons["Add Hotdog"]
    XCTAssertTrue(add.waitForExistence(timeout: 12))
    add.tap()
    XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Add to Bag")).firstMatch.exists)
    app.buttons["Increase quantity"].tap()
    app.buttons["View Bag · 2"].tap()
    XCTAssertTrue(app.navigationBars["Your Bag"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Hotdog"].exists)
    app.buttons["Decrease quantity"].tap()
    XCTAssertTrue(app.staticTexts["Quantity 1"].exists)
    attach("business-quick-add-bag", from: app)
  }

  func testCustomizeAndEditOptionsInBag() {
    let app = launch()
    openShop("20000000-0000-4000-8000-000000000001", in: app)
    let customize = app.buttons["Customize Iced Latte"]
    XCTAssertTrue(customize.waitForExistence(timeout: 12))
    attach("business-coffee-storefront", from: app)
    customize.tap()
    XCTAssertTrue(app.buttons["Small"].waitForExistence(timeout: 8))
    let add = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Add to Bag")).firstMatch
    XCTAssertFalse(add.isEnabled)
    app.buttons["Small"].tap()
    app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Oat milk")).firstMatch.tap()
    XCTAssertTrue(add.label.contains("5.40"))
    attach("business-latte-customization", from: app)
    add.tap()
    app.buttons["View Bag · 1"].tap()
    XCTAssertTrue(app.buttons["Edit options"].waitForExistence(timeout: 8))
    app.buttons["Edit options"].tap()
    app.buttons["Large"].tap()
    XCTAssertTrue(add.label.contains("6.40"))
    add.tap()
    XCTAssertTrue(app.staticTexts["Large · Oat milk"].waitForExistence(timeout: 5))
  }

  func testConfirmationWaitsForVerificationAndPickupShowsTheCodeWhenReady() {
    let app = launch()
    openShop("20000000-0000-4000-8000-000000000002", in: app)
    let add = app.buttons["Add Hotdog"]
    XCTAssertTrue(add.waitForExistence(timeout: 10))
    add.tap()
    app.buttons["View Bag · 1"].tap()
    XCTAssertTrue(app.buttons["Checkout"].waitForExistence(timeout: 8))
    app.buttons["Checkout"].tap()
    app.buttons["Confirm pickup and continue"].tap()
    let verify = app.buttons["Check order status"]
    XCTAssertTrue(verify.waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Order Placed!"].exists)
    verify.tap()
    XCTAssertTrue(app.staticTexts["Order Placed!"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Ready for pickup"].exists)
    attach("business-order-received", from: app)
    app.buttons["View Order"].tap()
    XCTAssertTrue(app.staticTexts["Ready for pickup"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.images["Pickup QR code"].exists)
  }

  private func openShop(_ id: String, in app: XCUIApplication) {
    let shop = app.descendants(matching: .any).matching(identifier: "business.shop.\(id)").firstMatch
    XCTAssertTrue(shop.waitForExistence(timeout: 12), app.debugDescription)
    if shop.exists { shop.tap() }
  }

  private func attach(_ name: String, from app: XCUIApplication) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
