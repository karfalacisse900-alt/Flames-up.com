import XCTest
import UIKit

/// Offline runtime integration, not an upload or production publication test.
/// The fixture supplies a confirmed receipt and a scoped API response; the app
/// exercises its real store/subscription, reconciliation and Details navigation.
final class PublicationFeedTests: XCTestCase {
  private let existingIDs = (0..<8).map { "publication-old-\($0)" }

  func testConfirmedReceiptAtIdleTopInsertsWithoutReplacingFeed() {
    let app = launch()
    let first = app.otherElements["home.post.page.publication-old-0"]
    XCTAssertTrue(first.waitForExistence(timeout: 25))
    waitForIDs(existingIDs, app: app)
    XCTAssertTrue(offset(app).isFinite)
    attach(app, "offline-receipt-before-top-insertion")

    recordReceipt(app)
    waitForIDs(["publication-new"] + existingIDs, app: app)
    let published = app.otherElements["home.post.page.publication-new"]
    XCTAssertTrue(published.waitForExistence(timeout: 10))
    XCTAssertTrue(published.isHittable, "The eligible post should appear at the idle top")
    XCTAssertEqual(Set(ids(app)).count, 9, "Publication must neither duplicate nor replace existing posts")
    assertFreshScopedRead(app)
    XCTAssertTrue(viewPostButton(app).waitForExistence(timeout: 5))
    attach(app, "offline-receipt-new-post-banner-at-top")
    attachDiagnostics(app, "idle-top-receipt")
    openCanonicalDetails(app)
    app.buttons["Back"].tap()
    XCTAssertTrue(published.waitForExistence(timeout: 5))
    XCTAssertEqual(ids(app), ["publication-new"] + existingIDs)
  }

  func testConfirmedReceiptWhileReadingPreservesPositionAndOpensCanonicalPost() {
    let app = launch()
    XCTAssertTrue(app.otherElements["home.post.page.publication-old-0"].waitForExistence(timeout: 25))
    waitForIDs(existingIDs, app: app)
    let stream = app.scrollViews["home.post.stream"]
    let reading = app.otherElements["home.post.page.publication-old-1"]
    reveal(reading, in: stream, app: app)
    XCTAssertTrue(reading.exists && reading.isHittable)
    let before = reading.frame
    let beforeOffset = offset(app)
    XCTAssertGreaterThan(beforeOffset, 50, "Exercise lower-feed receipt handling, not the top insertion branch")
    attach(app, "offline-receipt-lower-reading-before")

    recordReceipt(app)
    waitUntil("Fresh scoped read completes", timeout: 10) {
      (self.state(app)["freshFeedReads"] as? Int ?? 0) >= 1 &&
        app.staticTexts["New post"].exists
    }
    XCTAssertEqual(ids(app), existingIDs, "New publication must remain pending while browsing lower posts")
    XCTAssertEqual(reading.frame.minY, before.minY, accuracy: 2)
    XCTAssertEqual(reading.frame.height, before.height, accuracy: 1)
    XCTAssertEqual(offset(app), beforeOffset, accuracy: 2)
    assertFreshScopedRead(app)
    attach(app, "offline-receipt-new-post-banner-preserves-reading")
    attachDiagnostics(app, "lower-feed-receipt")

    openCanonicalDetails(app)
    app.buttons["Back"].tap()
    XCTAssertTrue(reading.waitForExistence(timeout: 5))
    XCTAssertEqual(ids(app), existingIDs)
    XCTAssertEqual(reading.frame.minY, before.minY, accuracy: 2, "View post must return to the original reading position")
    XCTAssertEqual(reading.frame.height, before.height, accuracy: 1)
    XCTAssertEqual(offset(app), beforeOffset, accuracy: 2)
    let viewport = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch
    XCTAssertTrue((viewport.value as? String ?? "").contains("commands=0;"),
      "Receipt, Details navigation and returning to the mounted feed must not issue restoration commands")
    attach(app, "offline-receipt-details-return-preserves-reading")
    attachDiagnostics(app, "lower-feed-details-return")
  }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-publication-feed-test",
      "--captro-restore-audit", "--captro-vertical-diagnostics"]
    app.launch()
    return app
  }

  private func openCanonicalDetails(_ app: XCUIApplication) {
    viewPostButton(app).tap()
    let media = app.descendants(matching: .any)["post.detail.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["PUBLICATION RECEIPT FIXTURE — NOT A REAL UPLOAD"].waitForExistence(timeout: 10),
      "The real View post route must show the canonical receipt post, not the previously visible post")
    attach(app, "offline-receipt-canonical-details")
  }

  private func assertFreshScopedRead(_ app: XCUIApplication) {
    let snapshot = state(app)
    XCTAssertEqual(snapshot["receiptRecorded"] as? Bool, true)
    XCTAssertGreaterThanOrEqual(snapshot["feedReads"] as? Int ?? 0, 2, "Initial load plus post-publication read")
    XCTAssertEqual(snapshot["freshFeedReads"] as? Int, 1, "Receipt must perform a real cache-bypassing URLSession read")
    let scopes = snapshot["feedScopes"] as? [String] ?? []
    XCTAssertFalse(scopes.isEmpty)
    XCTAssertTrue(scopes.allSatisfy { $0 == "for_you" }, "Publication must revalidate the active scoped feed")
  }

  private func viewPostButton(_ app: XCUIApplication) -> XCUIElement {
    // SwiftUI propagates the notice container's accessibility identifier to
    // its buttons. Select its real, unique action label rather than an ID the
    // runtime replaces. This still exercises the production Details route.
    app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
      "home.publication.notice", "View post")).firstMatch
  }

  private func recordReceipt(_ app: XCUIApplication) {
    let button = app.buttons["publication.fixture.record"]
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    XCTAssertTrue(button.isEnabled)
    let frame = button.frame
    app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.midX, dy: frame.maxY - 22)).tap()
    waitUntil("Receipt action must run in its original account scope", timeout: 5) {
      let snapshot = self.state(app)
      return snapshot["recordAttempts"] as? Int == 1 && snapshot["receiptRecorded"] as? Bool == true
    }
    XCTAssertEqual(state(app)["scopeMatches"] as? Bool, true)
  }

  private func waitForIDs(_ expected: [String], app: XCUIApplication) {
    waitUntil("Expected stable feed order", timeout: 15) { self.ids(app) == expected }
  }
  private func ids(_ app: XCUIApplication) -> [String] { state(app)["orderedIDs"] as? [String] ?? [] }
  private func state(_ app: XCUIApplication) -> [String: Any] {
    let item = app.descendants(matching: .any)["publication.fixture.state"].firstMatch
    let text = item.value as? String ?? "{}"
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
  }
  private func offset(_ app: XCUIApplication) -> Double {
    let summary = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch.value as? String ?? ""
    return summary.split(separator: ";").first { $0.hasPrefix("offset=") }
      .flatMap { Double($0.dropFirst("offset=".count)) } ?? .nan
  }
  private func waitUntil(_ message: String, timeout: TimeInterval, condition: @escaping () -> Bool) {
    let predicate = NSPredicate { _, _ in condition() }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout),
      .completed, message)
  }

  private func reveal(_ page: XCUIElement, in stream: XCUIElement, app: XCUIApplication) {
    // Native slow drags only. The fixture never scrolls or writes an offset.
    for _ in 0..<12 {
      let target = stream.frame.minY + 100
      if page.exists && abs(page.frame.minY - target) < 24 { return }
      let distance = min(250, stream.frame.height * 0.4)
      let delta = page.exists ? min(distance, max(-distance, page.frame.minY - target)) : distance
      let origin = app.coordinate(withNormalizedOffset: .zero)
      let startY = stream.frame.minY + stream.frame.height * (delta >= 0 ? 0.75 : 0.2)
      origin.withOffset(CGVector(dx: app.frame.width * 0.45, dy: startY)).press(forDuration: 0.06,
        thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.45, dy: startY - delta)),
        withVelocity: .slow, thenHoldForDuration: 0.2)
    }
  }

  private func attach(_ app: XCUIApplication, _ name: String) {
    let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
  }
  private func attachDiagnostics(_ app: XCUIApplication, _ stage: String) {
    for id in ["publication.fixture.state", "home.viewport.diagnostics", "home.viewport.trace"] {
      let element = app.descendants(matching: .any)[id].firstMatch
      guard element.exists else { continue }
      let item = XCTAttachment(string: element.value as? String ?? "")
      item.name = "\(stage)-\(id)"; item.lifetime = .keepAlways; add(item)
    }
  }
}
