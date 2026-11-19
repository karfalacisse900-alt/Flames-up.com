import XCTest

/// Foreground captures through Captro's real root, navigation, loaders and views.
/// Public content is captured once; no authenticated production writes occur.
final class NativeConsistencyTests: XCTestCase {
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name; image.lifetime = .keepAlways; add(image)
  }
  private func input(_ id: String, _ app: XCUIApplication) -> XCUIElement {
    let field = app.textFields[id]
    return field.exists ? field : app.textViews[id]
  }
  private func tab(_ name: String, _ app: XCUIApplication) {
    let studio = app.buttons["capture.navigation." + name.lowercased()]
    if studio.exists && studio.isHittable { studio.tap(); return }
    let native = app.tabBars.buttons[name]
    let button = native.exists ? native : app.buttons[name].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
  }
  private func checkBounds(_ element: XCUIElement, _ app: XCUIApplication) {
    XCTAssertGreaterThan(element.frame.width, 0)
    XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1)
    XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1)
  }
  private func runScreens(large: Bool) throws {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review",
      "--captro-consistency-review", "--captro-image-recovery-review"]
      + (large ? ["--captro-quality-large-text"] : [])
    app.launch()
    let suffix = large ? "accessibility" : "default"
    XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout: 25))
    let post = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'home.post.page.'")).firstMatch
    XCTAssertTrue(post.waitForExistence(timeout: 15))
    // Image network/decode is deterministic but asynchronous in the real loader.
    // A brief settling interval is identical for both captures; no UI loading is suppressed.
    Thread.sleep(forTimeInterval: 2)
    capture("home-" + suffix, app)
    app.buttons["home.tea"].tap()
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tea.conversation.'"))
    let row = rows.firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 2)
    capture("notes-" + suffix, app)
    let measurements = rows.allElementsBoundByIndex.filter { $0.frame.width > 0 }.map { element -> [String: Any] in
      checkBounds(element, app)
      return ["id":element.identifier,"x":element.frame.minX,"y":element.frame.minY,
        "width":element.frame.width,"height":element.frame.height]
    }
    let metrics = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: .prettyPrinted), uniformTypeIdentifier: "public.json")
    metrics.name = "row-metrics-" + suffix; metrics.lifetime = .keepAlways; add(metrics)
    let originalY = row.frame.minY
    row.tap()
    let reply = input("tea.reply.input", app)
    XCTAssertTrue(reply.waitForExistence(timeout: 12))
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    checkBounds(reply, app)
    capture("note-detail-" + suffix, app)
    let thread = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tea.thread.'")).firstMatch
    for _ in 0..<4 where thread.exists && !thread.isHittable { app.swipeUp() }
    if thread.exists && thread.isHittable {
      thread.tap(); capture("note-thread-" + suffix, app)
    }
    reply.tap(); reply.typeText("Review draft stays here")
    capture("note-keyboard-" + suffix, app)
    app.buttons["tea.detail.back"].tap()
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    XCTAssertEqual(row.frame.minY, originalY, accuracy: 2)
    row.tap()
    XCTAssertTrue(input("tea.reply.input", app).waitForExistence(timeout: 8))
    XCTAssertEqual(input("tea.reply.input", app).value as? String, "Review draft stays here")
    app.buttons["tea.detail.back"].tap()
    app.buttons["tea.back.home"].tap()
    tab("Capture", app)
    XCTAssertTrue(app.buttons["capture.mode.photo"].waitForExistence(timeout: 10))
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deny = springboard.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")).firstMatch
    if deny.waitForExistence(timeout: 3) { deny.tap() }
    XCTAssertTrue(app.staticTexts["capture.unavailable"].firstMatch.waitForExistence(timeout: 8))
    capture("capture-" + suffix, app)
    tab("Me", app)
    XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 2)
    capture("profile-" + suffix, app)
    let chats = app.buttons["Chats"]
    XCTAssertTrue(chats.isHittable); chats.tap()
    let conversation = app.buttons.containing(.staticText, identifier: "alex").firstMatch
    XCTAssertTrue(conversation.waitForExistence(timeout: 10))
    capture("inbox-" + suffix, app); conversation.tap()
    XCTAssertTrue(app.staticTexts["Are you joining the photo walk?"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    capture("chat-" + suffix, app)
    let message = app.textFields["Message"].exists ? app.textFields["Message"] : app.textViews.firstMatch
    XCTAssertTrue(message.isHittable); checkBounds(message, app)
    message.tap(); message.typeText("Chat review draft")
    capture("chat-keyboard-" + suffix, app)
    app.terminate()
  }
  func testDefaultScreensAndRestoration() throws { try runScreens(large: false) }
  func testLargerTextScreensAndRestoration() throws { try runScreens(large: true) }
}
