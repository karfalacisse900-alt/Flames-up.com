import XCTest
import UIKit

final class VerticalFeedTests: XCTestCase {
  func testBottomFeedBaselineMeasurement() { runBottomFeed(assertStable: false) }
  func testBottomFeedPaginationAndLowerCarousel() { runBottomFeed(assertStable: true) }

  private func runBottomFeed(assertStable: Bool) {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-vertical-feed-test",
      "--captro-restore-audit", "--captro-carousel-diagnostics", "--captro-vertical-diagnostics",
      "--captro-vertical-missing-media"]
    app.launch()
    let stream = app.scrollViews["home.post.stream"]
    let first = app.otherElements["home.post.page.vertical-0"]
    XCTAssertTrue(first.waitForExistence(timeout: 40), "Fixture must finish before scroll measurements")
    attach(app, "vertical-start-local-cold-cache")

    // Case A: a carousel whose upper portion sits near the bottom of the
    // *visible viewport*, independently of the pagination/end boundary.
    let lower = app.otherElements["home.post.page.vertical-5"]
    reveal(lower, app: app, stream: stream, alignFraction: 0.55)
    XCTAssertTrue(lower.exists)
    let lowerMedia = lower.otherElements["home.post.media"].firstMatch
    let beforeLower = lowerMedia.frame
    XCTAssertLessThan(beforeLower.minY, app.tabBars.firstMatch.frame.minY - 50)
    XCTAssertGreaterThan(beforeLower.minY, stream.frame.minY + 50)
    attach(app, "lower-carousel-after-vertical")
    let initialOffset = offset(app)
    let visibleY = min(app.tabBars.firstMatch.frame.minY - 64, max(stream.frame.minY + 60, beforeLower.minY + 56))
    for (index, forward) in [true, false, true, false].enumerated() {
      let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
        CGVector(dx: app.frame.width * (forward ? 0.82 : 0.18), dy: visibleY))
      let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
        CGVector(dx: app.frame.width * (forward ? 0.18 : 0.82), dy: visibleY + (index == 2 ? 8 : 0)))
      start.press(forDuration: 0.06, thenDragTo: end, withVelocity: index % 2 == 0 ? .slow : .fast, thenHoldForDuration: 0.05)
      XCTAssertTrue(lower.staticTexts[forward ? "Photo 2 of 3" : "Photo 1 of 3"].waitForExistence(timeout: 5))
      if assertStable {
        XCTAssertEqual(lowerMedia.frame.minY, beforeLower.minY, accuracy: 2, "Horizontal swipe moved the lower row vertically")
        XCTAssertEqual(lowerMedia.frame.height, beforeLower.height, accuracy: 1)
        XCTAssertEqual(offset(app), initialOffset, accuracy: 2)
      }
    }
    attachDiagnostics(app, "lower-carousel")

    // Case B: actual production pagination acceptance, a failed page/retry,
    // and an empty final response while the last item is fully on-screen.
    let started = ProcessInfo.processInfo.systemUptime
    let last = app.otherElements["home.post.page.vertical-47"]
    var retried = false
    for _ in 0..<110 {
      let retry = app.buttons["home.pagination.retry"]
      if retry.exists && retry.isHittable {
        attach(app, "pagination-failed-preserves-content")
        retry.tap(); retried = true
      }
      if last.exists && last.frame.maxY <= app.tabBars.firstMatch.frame.minY - 1,
         app.buttons["vertical.fixture.finish"].isEnabled { break }
      verticalDrag(app, stream: stream, up: true, fast: true)
    }
    XCTAssertTrue(retried, "The real footer retry must be exercised")
    XCTAssertTrue(last.exists && last.isHittable, "Final post is reachable through ordinary vertical gestures")
    XCTAssertTrue(app.buttons["vertical.fixture.finish"].isEnabled, "Last empty response must remain gated")
    XCTAssertLessThanOrEqual(last.frame.maxY, app.tabBars.firstMatch.frame.minY + 1, "Final post must be completely reachable")
    let before = last.frame
    let beforeOffset = offset(app)
    let footerBefore = app.descendants(matching: .any)["home.pagination"].firstMatch.frame
    attach(app, "pagination-final-before-empty-response")
    attachDiagnostics(app, "before-final-response")
    app.buttons["vertical.fixture.finish"].tap()
    let state = app.descendants(matching: .any)["vertical.fixture.state"].firstMatch
    let complete = NSPredicate { _, _ in (state.value as? String ?? "").contains("\"complete\"") }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: nil)], timeout: 10), .completed)
    let after = last.frame
    let afterOffset = offset(app)
    let footerAfter = app.descendants(matching: .any)["home.pagination"].firstMatch
    attachText("before=\(before);after=\(after);offsetBefore=\(beforeOffset);offsetAfter=\(afterOffset);footerBefore=\(footerBefore);footerAfter=\(footerAfter.exists ? String(describing: footerAfter.frame) : "absent");traversalSeconds=\(ProcessInfo.processInfo.systemUptime - started)", "final-response-geometry")
    if assertStable {
      XCTAssertEqual(after.minY, before.minY, accuracy: 2, "Completing pagination changed the reading position")
      XCTAssertEqual(after.height, before.height, accuracy: 1)
      XCTAssertEqual(afterOffset, beforeOffset, accuracy: 2, "Footer removal clamped native contentOffset")
    }
    attach(app, "pagination-final-after-empty-response")
    attachDiagnostics(app, "after-final-response")
    let summary = fixtureSummary(state)
    XCTAssertEqual(summary["requests"] as? [Int], [0, 12, 24, 36, 36, 48], "No duplicated request, skipped cursor or load loop")
    XCTAssertTrue((stream.value as? String ?? "").contains("of 48"))

    // Warm-cache repeated direction changes. XCTest waits for quiescence
    // between gestures; this is NOT a finger-down reversal/deceleration test.
    for index in 0..<10 { verticalDrag(app, stream: stream, up: false, fast: index.isMultiple(of: 2)) }
    for index in 0..<10 { verticalDrag(app, stream: stream, up: true, fast: !index.isMultiple(of: 2)) }
    attachDiagnostics(app, "warm-return")
    attach(app, "vertical-warm-cache-return")
    XCTAssertEqual(fixtureSummary(state)["requests"] as? [Int], [0, 12, 24, 36, 36, 48])
    let viewport = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch
    XCTAssertTrue((viewport.value as? String ?? "").contains("commands=0;"), "Browsing must not issue restoration commands")
  }

  private func fixtureSummary(_ state: XCUIElement) -> [String: Any] {
    let text = state.value as? String ?? "{}"
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
  }

  private func reveal(_ page: XCUIElement, app: XCUIApplication, stream: XCUIElement, alignFraction: CGFloat) {
    for _ in 0..<30 {
      let target = stream.frame.minY + stream.frame.height * alignFraction
      if page.exists && abs(page.frame.minY - target) < 24 { return }
      let distance = min(320, stream.frame.height * 0.55)
      let delta = page.exists ? min(distance, max(-distance, page.frame.minY - target)) : distance
      let origin = app.coordinate(withNormalizedOffset: .zero)
      let startY = stream.frame.minY + stream.frame.height * (delta >= 0 ? 0.80 : 0.18)
      origin.withOffset(CGVector(dx: app.frame.midX, dy: startY)).press(forDuration: 0.06,
        thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: startY - delta)),
        withVelocity: .slow, thenHoldForDuration: 0.2)
    }
  }

  private func verticalDrag(_ app: XCUIApplication, stream: XCUIElement, up: Bool, fast: Bool) {
    let origin = app.coordinate(withNormalizedOffset: .zero)
    // Starts in media/stamps and stays clear of the fixed header/nav controls.
    let low = stream.frame.minY + stream.frame.height * 0.80
    let high = stream.frame.minY + stream.frame.height * 0.18
    origin.withOffset(CGVector(dx: app.frame.width * 0.54, dy: up ? low : high))
      .press(forDuration: 0.06, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.54, dy: up ? high : low)),
        withVelocity: fast ? .fast : .slow, thenHoldForDuration: 0.05)
  }

  private func offset(_ app: XCUIApplication) -> Double {
    let summary = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch.value as? String ?? ""
    return summary.split(separator: ";").first { $0.hasPrefix("offset=") }
      .flatMap { Double($0.dropFirst("offset=".count)) } ?? .nan
  }

  private func attachDiagnostics(_ app: XCUIApplication, _ stage: String) {
    for id in ["home.viewport.diagnostics", "home.viewport.trace", "carousel.diagnostics.home", "vertical.fixture.state", "home.media.diagnostics"] {
      let item = app.descendants(matching: .any)[id].firstMatch
      if item.exists { attachText(item.value as? String ?? "", "\(stage)-\(id)") }
    }
  }
  private func attachText(_ text: String, _ name: String) {
    let item = XCTAttachment(string: text); item.name = name; item.lifetime = .keepAlways; add(item)
  }
  private func attach(_ app: XCUIApplication, _ name: String) {
    let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
  }
}
