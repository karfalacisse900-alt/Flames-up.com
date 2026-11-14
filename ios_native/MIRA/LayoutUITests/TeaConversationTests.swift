import XCTest

final class TeaConversationTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review", "--tea-request-counts"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["home.feed.selector"].waitForExistence(timeout: 20))
    app.buttons["home.feed.selector"].tap(); app.buttons["home.menu.tea"].tap()
    XCTAssertTrue(row(101, app).waitForExistence(timeout: 10))
    return app
  }
  private func row(_ n: Int, _ app: XCUIApplication) -> XCUIElement {
    app.buttons["tea.conversation.00000000-0000-4000-8000-" + String(format: "%012d", n)]
  }
  private func shot(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func back(_ app: XCUIApplication) { app.navigationBars.firstMatch.buttons.firstMatch.tap() }
  private func input(_ id: String, _ app: XCUIApplication) -> XCUIElement {
    // A SwiftUI multiline TextField is exposed as UITextView on some iOS versions.
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 8))
    return app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
  }

  func testQuietLinksFollowReplyAndFreshReturn() {
    let app = launch()
    shot("conversations-list",app)
    row(101, app).tap()
    let follow = app.buttons["tea.conversation.follow"]
    XCTAssertTrue(follow.waitForExistence(timeout: 8))
    XCTAssertFalse(app.navigationBars["Conversation"].exists)
    XCTAssertFalse(app.buttons["tea.conversation.edit"].exists)
    for host in ["youtube.com","tiktok.com","example.com"] {
      let link = app.buttons["tea.link." + host]; XCTAssertTrue(link.isHittable); XCTAssertGreaterThanOrEqual(link.frame.height,44)
    }
    XCTAssertFalse(app.staticTexts["Links"].exists)
    XCTAssertFalse(app.staticTexts["Author update"].exists)
    shot("conversation-three-inline-links",app)
    follow.tap(); XCTAssertTrue(app.buttons["Unfollow discussion"].waitForExistence(timeout: 8))
    let replyInput = input("tea.reply.input", app)
    XCTAssertTrue(replyInput.exists); replyInput.tap(); replyInput.typeText("The second opening feels stronger.")
    app.buttons["tea.reply.send"].tap()
    XCTAssertTrue(app.staticTexts["The second opening feels stronger."].waitForExistence(timeout: 8))
    back(app); row(101,app).tap()
    XCTAssertTrue(app.staticTexts["The second opening feels stronger."].waitForExistence(timeout: 8))
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String ?? "").contains("101=1"))
    back(app); row(102,app).tap()
    XCTAssertTrue(app.buttons["tea.conversation.follow"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["tea.link.youtube.com"].exists)
    shot("conversation-zero-links",app)
  }

  func testComposeEditCancelAndAuthorOnlyLinks() {
    let app=launch()
    app.buttons["tea.compose"].tap()
    let title=input("tea.compose.title",app)
    XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText("A new Tea discussion")
    let body=input("tea.compose.body",app)
    body.tap(); body.typeText("A question for the community.")
    app.buttons["Add link"].tap()
    let link=app.textFields["tea.compose.link.0"]
    link.tap(); link.typeText("https://example.com/project")
    app.buttons["tea.compose.save"].tap()
    XCTAssertTrue(app.buttons["tea.conversation.edit"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["tea.link.example.com"].exists)
    app.buttons["tea.conversation.edit"].tap()
    XCTAssertTrue(app.buttons["Remove link 1"].waitForExistence(timeout: 5))
    app.buttons["Remove link 1"].tap(); app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["tea.link.example.com"].exists)
    app.buttons["tea.conversation.edit"].tap(); app.buttons["Remove link 1"].tap(); app.buttons["tea.compose.save"].tap()
    XCTAssertTrue(app.buttons["tea.conversation.edit"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["tea.link.example.com"].exists)
    shot("conversation-author-links-removed",app)
  }

  func testBrowserReturnPreservesDiscussionAndGeometry() {
    let app=launch()
    row(103,app).tap()
    let link=app.buttons["tea.link.example.com"]
    XCTAssertTrue(link.waitForExistence(timeout: 8)); let original=link.frame.minY
    link.tap()
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    XCTAssertTrue(safari.wait(for:.runningForeground,timeout:10))
    app.activate()
    XCTAssertTrue(link.waitForExistence(timeout: 8)); XCTAssertEqual(link.frame.minY,original,accuracy:2)
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String ?? "").contains("103=1"))
    shot("conversation-browser-return",app)
  }

  func testLargeTextWrapsLinksWithoutHidingReply() {
    let app=launch(["--captro-quality-large-text"])
    row(101,app).tap()
    XCTAssertTrue(app.buttons["tea.conversation.follow"].waitForExistence(timeout: 8))
    for host in ["youtube.com","tiktok.com","example.com"] {
      let link=app.buttons["tea.link."+host]
      for _ in 0..<4 where !link.isHittable { app.swipeUp() }
      XCTAssertTrue(link.isHittable); XCTAssertGreaterThanOrEqual(link.frame.height,44)
      XCTAssertLessThanOrEqual(link.frame.maxX,app.frame.maxX)
    }
    XCTAssertTrue(input("tea.reply.input",app).isHittable)
    shot("conversation-large-text",app)
  }
}
