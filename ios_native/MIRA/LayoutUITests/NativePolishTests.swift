import XCTest

/// Same production views and isolated transports before and after the polish.
final class NativePolishTests: XCTestCase {
  private func launch(_ flags: [String], dark: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = flags + (dark ? ["--captro-quality-dark"] : [])
    app.launch()
    return app
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testLightAndDarkScreenComparison() {
    for dark in [false, true] {
      let suffix = dark ? "dark" : "light"
      var app = launch(["--captro-home-feed-visual-test", "--captro-visual-mixed-carousel"], dark: dark)
      XCTAssertTrue(app.otherElements["home.post.page.mixed-carousel"].waitForExistence(timeout: 20))
      capture("home-\(suffix)", app); app.terminate()

      app = launch(["--captro-design-quality-test", "--captro-tea-review"], dark: dark)
      XCTAssertTrue(app.buttons["home.feed.selector"].waitForExistence(timeout: 20))
      app.buttons["home.feed.selector"].tap(); app.buttons["home.menu.tea"].tap()
      let row = app.buttons["tea.row.activity:00000000-0000-4000-8000-000000000003"]
      XCTAssertTrue(row.waitForExistence(timeout: 10)); capture("tea-list-\(suffix)", app); row.tap()
      XCTAssertTrue(app.buttons["tea.primary-action"].waitForExistence(timeout: 10))
      capture("tea-detail-\(suffix)", app); app.terminate()

      app = launch(["--captro-design-quality-test", "--captro-quality-chat", "--captro-polish-chat"], dark: dark)
      let conversation = app.buttons.containing(.staticText, identifier: "alex").firstMatch
      XCTAssertTrue(conversation.waitForExistence(timeout: 15)); capture("inbox-\(suffix)", app)
      conversation.tap()
      XCTAssertTrue(app.staticTexts["Are you joining the photo walk?"].waitForExistence(timeout: 10))
      capture("chat-\(suffix)", app); app.terminate()

      app = launch(["--captro-design-quality-test", "--captro-quality-profile"], dark: dark)
      XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["City walks, photography and finding good coffee."].waitForExistence(timeout: 10))
      capture("profile-\(suffix)", app); app.terminate()
    }
  }

  func testChatFailureRetryAndAccessibleComposer() {
    let app = launch(["--captro-design-quality-test", "--captro-quality-chat", "--captro-polish-chat",
                      "--captro-polish-chat-error", "--captro-quality-large-text"], dark: true)
    let conversation = app.buttons.containing(.staticText, identifier: "alex").firstMatch
    XCTAssertTrue(conversation.waitForExistence(timeout: 15)); conversation.tap()
    let retry = app.buttons["chat.retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Start the chat"].exists)
    capture("chat-error-dark-large-text", app)
    retry.tap()
    XCTAssertTrue(app.staticTexts["Are you joining the photo walk?"].waitForExistence(timeout: 8))
    let add = app.buttons["Add attachment"]
    XCTAssertTrue(add.isHittable)
    XCTAssertGreaterThanOrEqual(add.frame.width, 44)
    XCTAssertGreaterThanOrEqual(add.frame.height, 44)
    add.tap()
    XCTAssertTrue(app.buttons["Close attachments"].exists)
    capture("chat-attachments-dark-large-text", app)
    app.buttons["Close attachments"].tap()
    let field = app.textFields["Message"]
    if field.exists { field.tap(); field.typeText("Draft retained") }
    else {
      let editor = app.textViews.firstMatch
      XCTAssertTrue(editor.exists); editor.tap(); editor.typeText("Draft retained")
    }
    capture("chat-keyboard-dark-large-text", app)
  }
}
