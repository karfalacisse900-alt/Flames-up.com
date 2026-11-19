import XCTest
import UIKit

final class TeaConversationTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-design-quality-test", "--captro-tea-review", "--tea-request-counts"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["home.tea"].waitForExistence(timeout: 20))
    XCTAssertFalse(app.buttons["home.inbox"].exists)
    app.buttons["home.tea"].tap()
    XCTAssertTrue(row(101, app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["tea.compose"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["tea.menu"].exists)
    return app
  }
  private func row(_ n: Int, _ app: XCUIApplication) -> XCUIElement {
    app.buttons["tea.conversation.00000000-0000-4000-8000-" + String(format: "%012d", n)]
  }
  private func shot(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func back(_ app: XCUIApplication) { app.buttons["tea.detail.back"].tap() }
  private func input(_ id: String, _ app: XCUIApplication) -> XCUIElement {
    // A SwiftUI multiline TextField is exposed as UITextView on some iOS versions.
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 8))
    return app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
  }

  func testAvatarPixelsPreviewWidthAndAutomaticAccessReload() {
    let app = launch(["--tea-avatar-fixture", "--captro-image-recovery-review", "--review-server-fallback", "--tea-slow"])
    let first = row(101, app)
    let preview = app.staticTexts["tea.preview.00000000-0000-4000-8000-000000000101"]
    XCTAssertTrue(preview.waitForExistence(timeout: 8))
    XCTAssertGreaterThan(preview.frame.width, app.frame.width * 0.65, "Reply count must not constrain the preview column")
    XCTAssertLessThanOrEqual(preview.frame.height, 48)
    XCTAssertFalse(app.staticTexts["Conversations"].exists)
    let heading = app.images["tea.heading"]
    XCTAssertTrue(heading.exists, "Tea uses the bundled Captro symbol and outlined wordmark")
    XCTAssertEqual(heading.frame.width, 86, accuracy: 1)
    XCTAssertEqual(heading.frame.height, 23, accuracy: 1)
    XCTAssertFalse(app.staticTexts["Tea"].exists)
    // Check the actual row separator pixels, not just the presence of a view.
    let screenshot = app.screenshot().image.cgImage!
    let scale = CGFloat(screenshot.width) / app.frame.width
    // AX rounds the button bounds independently of the half-point overlay.
    // Inspect its narrow boundary band, not one potentially adjacent white pixel.
    let bandHeight = Int(4 * scale)
    let strip = screenshot.cropping(to: CGRect(x: first.frame.midX * scale,
      y: (first.frame.maxY - 2) * scale, width: 1, height: CGFloat(bandHeight)))!
    var separator = [UInt8](repeating: 0, count: 4 * bandHeight)
    let separatorContext = CGContext(data: &separator, width: 1, height: bandHeight, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    separatorContext.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: CGFloat(bandHeight)))
    let hasDivider = stride(from: 0, to: separator.count, by: 4).contains { i in
      (195...225).contains(Int(separator[i])) && separator[i] == separator[i + 1] && separator[i + 1] == separator[i + 2]
    }
    XCTAssertTrue(hasDivider, "Tea rows need a visible fine divider; got \(separator)")
    let rendered = NSPredicate { _, _ in
      let image = app.screenshot().image
      guard let cg = image.cgImage else { return false }
      let scale = CGFloat(cg.width) / app.frame.width
      let point = CGPoint(x: (first.frame.minX + 24) * scale, y: (first.frame.minY + 40) * scale)
      guard let sample = cg.cropping(to: CGRect(x: point.x, y: point.y, width: 2, height: 2)) else { return false }
      var rgba = [UInt8](repeating: 0, count: 4)
      let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return rgba[0] > 220 && rgba[1] < 30 && rgba[2] < 30
    }
    expectation(for: rendered, evaluatedWith: app)
    waitForExpectations(timeout: 10)
    shot("tea-avatar-pixels-and-compact-density", app)
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String ?? "").contains("0=1"))
    app.buttons["tea.test.invalidate"].tap()
    let reloaded = NSPredicate { _, _ in (app.staticTexts["tea.test.requests"].value as? String ?? "").contains("0=2") }
    expectation(for: reloaded, evaluatedWith: app); waitForExpectations(timeout: 10)
    XCTAssertTrue(first.waitForExistence(timeout: 10), "Access invalidation must start a new authorized load")
    XCTAssertFalse(app.staticTexts["Refresh to see available conversations."].exists)
    XCTAssertFalse(app.staticTexts["Loading Tea"].exists)
    first.tap()
    XCTAssertTrue(app.buttons["tea.conversation.follow"].waitForExistence(timeout: 8))
    back(app)
    XCTAssertTrue(first.waitForExistence(timeout: 8))
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
      let link = app.buttons["tea.link." + host]; XCTAssertTrue(link.isHittable); XCTAssertGreaterThanOrEqual(link.frame.height + 0.000001,44)
    }
    XCTAssertFalse(app.staticTexts["Links"].exists)
    XCTAssertFalse(app.staticTexts["Author update"].exists)
    shot("conversation-three-inline-links",app)
    follow.tap(); XCTAssertTrue(app.buttons["Unfollow discussion"].waitForExistence(timeout: 8))
    // Check the fresh cache immediately. Keyboard automation may legitimately
    // take longer than the production 30-second freshness window on CI.
    back(app); row(101,app).tap()
    XCTAssertTrue(app.buttons["Unfollow discussion"].waitForExistence(timeout: 8))
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String ?? "").contains("101=1"))
    let replyInput = input("tea.reply.input", app)
    XCTAssertTrue(replyInput.exists); replyInput.tap(); replyInput.typeText("The second opening feels stronger.")
    app.buttons["tea.reply.send"].tap()
    XCTAssertTrue(app.staticTexts["The second opening feels stronger."].waitForExistence(timeout: 8))
    back(app); row(101,app).tap()
    XCTAssertTrue(app.staticTexts["The second opening feels stronger."].waitForExistence(timeout: 8))
    back(app); row(102,app).tap()
    XCTAssertTrue(app.buttons["tea.conversation.follow"].waitForExistence(timeout: 8))
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tea.link.")).count, 0)
    shot("conversation-zero-links",app)
  }

  func testComposeEditCancelAndAuthorOnlyLinks() {
    let app=launch()
    let postButton = app.buttons["tea.compose"]
    // Native toolbar accessibility bounds can be smaller than their hit area.
    // Exercise both edges of the required 44 pt target with real coordinates.
    postButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .withOffset(CGVector(dx: 0, dy: -21.5)).tap()
    XCTAssertTrue(input("tea.compose.title", app).waitForExistence(timeout: 8))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(postButton.waitForExistence(timeout: 8))
    postButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .withOffset(CGVector(dx: 0, dy: 21.5)).tap()
    let title=input("tea.compose.title",app)
    XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText("A new Tea discussion")
    let body=input("tea.compose.body",app)
    body.tap(); body.typeText("A question for the community.")
    app.buttons["Add link"].tap()
    let link=input("tea.compose.link.0",app)
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
    // Initialize the simulator's browser separately from the measured link tap.
    // A cold Safari process can otherwise spend the test interval starting up.
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
    safari.launch()
    XCTAssertTrue(safari.wait(for:.runningForeground,timeout:10))
    let app=launch()
    row(103,app).tap()
    let link=app.buttons["tea.link.example.com"]
    XCTAssertTrue(link.waitForExistence(timeout: 8)); let original=link.frame.minY
    XCTAssertNotEqual(safari.state, .runningForeground)
    XCTAssertTrue(link.isHittable)
    link.tap()
    // Verify the browser actually received the URL. On iOS 26 the launch
    // instance can report a stale process state after an external activation.
    // Query Safari's native address field directly. Traversing every descendant
    // crosses into its transient WebContent process and can fail even while the
    // native URL bar is visible and correct (kAXErrorServerNotFound on iOS 26).
    let address = safari.textFields["TabBarItemTitle"]
    XCTAssertTrue(address.waitForExistence(timeout:10))
    XCTAssertTrue((address.value as? String ?? "").contains("example.com"))
    app.activate()
    XCTAssertTrue(link.waitForExistence(timeout: 8)); XCTAssertEqual(link.frame.minY,original,accuracy:2)
    XCTAssertTrue((app.staticTexts["tea.test.requests"].value as? String ?? "").contains("103=1"))
    shot("conversation-browser-return",app)
  }

  func testLargeTextWrapsLinksWithoutHidingReply() {
    let app=launch(["--captro-quality-large-text"])
    row(101,app).tap()
    XCTAssertTrue(app.buttons["tea.conversation.follow"].waitForExistence(timeout: 8))
    let heading = app.descendants(matching: .any).matching(identifier: "tea.heading").firstMatch
    XCTAssertTrue(heading.exists)
    XCTAssertLessThanOrEqual(heading.frame.height, 44, "Brand heading must stay inside the navigation bar at accessibility sizes")
    XCTAssertGreaterThan(app.staticTexts["Which music video intro works better?"].frame.height, 44,
      "The fixture must apply accessibility text size, not merely set a launch flag")
    for host in ["youtube.com","tiktok.com","example.com"] {
      let link=app.buttons["tea.link."+host]
      for _ in 0..<4 where !link.isHittable { app.swipeUp() }
      // CGRect subtraction can represent 44 as 43.99999999999994.
      XCTAssertTrue(link.isHittable); XCTAssertGreaterThanOrEqual(link.frame.height + 0.000001,44)
      XCTAssertLessThanOrEqual(link.frame.maxX,app.frame.maxX)
    }
    XCTAssertTrue(input("tea.reply.input",app).isHittable)
    shot("conversation-large-text",app)
  }

  func testSentenceRepliesCollapsedExpandedAndClearKeepsDraft() {
    let app=launch(["--tea-sentence-fixture"])
    row(101,app).tap()
    let thread=app.buttons["tea.thread.1:23:63"]
    XCTAssertTrue(thread.waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["Where did you end up shooting?"].exists)
    shot("sentence-replies-collapsed",app)
    thread.tap()
    XCTAssertTrue(app.staticTexts["Where did you end up shooting?"].waitForExistence(timeout:8))
    shot("sentence-replies-expanded",app)
    thread.tap()
    let sentence=app.staticTexts["tea.sentence.1:23:63"]
    sentence.press(forDuration:1)
    XCTAssertTrue(app.buttons["Reply to this part"].waitForExistence(timeout:5))
    app.buttons["Reply to this part"].tap()
    XCTAssertTrue(app.staticTexts["tea.reply.target"].exists)
    let field=input("tea.reply.input",app); field.tap(); field.typeText("A great location.")
    shot("sentence-reply-composer",app)
    XCTAssertTrue(app.buttons["tea.reply.clear-target"].isHittable)
    app.buttons["tea.reply.clear-target"].tap()
    XCTAssertEqual(field.value as? String,"A great location.")
    XCTAssertFalse(app.staticTexts["tea.reply.target"].exists)
    app.buttons["tea.reply.send"].tap()
    for _ in 0..<4 where !app.staticTexts["A great location."].isHittable { app.swipeUp() }
    XCTAssertTrue(app.staticTexts["A great location."].exists)
  }

  func testTargetedSendAndAuthorFollowAreSeparateFromDiscussionFollow() {
    let app=launch(["--tea-sentence-fixture"])
    row(101,app).tap()
    let author=app.buttons["tea.author.follow"]
    XCTAssertTrue(author.waitForExistence(timeout:8)); author.tap()
    XCTAssertTrue(app.buttons["Unfollow author"].waitForExistence(timeout:8))
    XCTAssertTrue(app.buttons["Follow discussion"].exists)
    app.buttons["tea.author.profile"].tap()
    XCTAssertTrue(app.buttons["profile.follow"].waitForExistence(timeout:8))
    app.navigationBars.firstMatch.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["tea.detail.back"].waitForExistence(timeout:5))
    app.buttons["tea.author.avatar"].tap()
    XCTAssertTrue(app.buttons["profile.follow"].waitForExistence(timeout:8))
    app.navigationBars.firstMatch.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Unfollow author"].waitForExistence(timeout:8),"Opening the avatar must not toggle the separate follow control")
    let first=app.staticTexts["tea.sentence.1:0:22"]
    first.press(forDuration:1); app.buttons["Reply to this part"].tap()
    let field=input("tea.reply.input",app); field.tap(); field.typeText("Which phone did you use?")
    app.buttons["tea.reply.send"].tap()
    XCTAssertTrue(app.buttons["tea.thread.1:0:22"].waitForExistence(timeout:8))
    XCTAssertTrue(app.staticTexts["Which phone did you use?"].waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["tea.reply.target"].exists)
    shot("multiple-sentence-threads",app)
  }

  func testEditedCaptionKeepsOriginalQuoteAndLargeTextComposer() {
    let app=launch(["--tea-sentence-fixture","--tea-sentence-owner","--captro-quality-large-text"])
    row(101,app).tap()
    XCTAssertTrue(app.buttons["tea.conversation.edit"].waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["tea.author.follow"].exists)
    app.buttons["tea.conversation.edit"].tap()
    let body=input("tea.compose.body",app)
    body.tap(); body.typeText(" A different ending.")
    app.buttons["tea.compose.save"].tap()
    let earlier=app.staticTexts["Earlier text"]
    for _ in 0..<5 where !earlier.isHittable { app.swipeUp() }
    XCTAssertTrue(earlier.exists)
    XCTAssertFalse(app.buttons["tea.thread.2:23:63"].exists,"Old replies must never move to the new caption revision")
    let original=app.buttons["tea.thread.1:23:63"]
    for _ in 0..<4 where !original.isHittable { app.swipeUp() }
    XCTAssertTrue(original.isHittable); original.tap()
    XCTAssertTrue(app.staticTexts["Where did you end up shooting?"].waitForExistence(timeout:8))
    XCTAssertTrue(input("tea.reply.input",app).isHittable)
    shot("sentence-edited-caption-large-text",app)
  }
}
