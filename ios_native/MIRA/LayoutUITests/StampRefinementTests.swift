import XCTest

final class StampRefinementTests: XCTestCase {
  private let ids = ["13dbab96-958b-4408-8d57-c4b92f4090b1", "9c35e9fe-3537-45b9-844d-9399abe47445",
    "7ff613af-f80a-474a-85cc-b159bbcf6a79", "4037e860-4c23-48de-8328-de2219eb54d2",
    "ecbb00c1-f3f3-4d51-9fd8-dca889f9352a"]

  func testBeforePublicStampExamples() { publicExamples(baseline: true) }
  func testPublicStampExamples() { publicExamples(baseline: false) }

  private func publicExamples(baseline: Bool) {
    let app = launch(["--captro-public-feed-test", "--captro-public-posts=\(ids.joined(separator: ","))"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 30))
    for (index, id) in ids.enumerated() {
      let page = app.otherElements["home.post.page.\(id)"]
      reveal(page, stream: stream, app: app)
      XCTAssertTrue(page.exists)
      if !baseline {
        let stamp = page.otherElements["home.post.stamp"].firstMatch
        let media = page.otherElements["home.post.media"].firstMatch
        XCTAssertTrue(stamp.exists)
        XCTAssertEqual(stamp.frame.width / media.frame.width, 0.73, accuracy: 0.01)
        XCTAssertEqual(stamp.frame.minX, min(22, media.frame.width * 0.054), accuracy: 1)
        XCTAssertGreaterThan(media.frame.maxX - stamp.frame.maxX, media.frame.width * 0.20)
        if index < 2 {
          XCTAssertFalse(page.buttons["home.post.stamp.expand"].exists, "Ordinary club captions are complete by default")
        }
      }
      capture(app, "\(baseline ? "before" : "after")-stamp-\(index)")
      if !baseline && index == 2 {
        let media = page.otherElements["home.post.media"].firstMatch
        let more = page.buttons["home.post.stamp.expand"]
        if more.exists && more.isHittable { more.tap() }
        let height = page.frame.height
        media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.12))
          .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.12)))
        XCTAssertTrue(page.staticTexts["Photo 2 of 10"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.height, height, accuracy: 1)
        capture(app, "after-expanded-carousel")
      }
    }
  }

  func testInlineExpansionAndCollapse() {
    let app = launch(["--captro-visual-size=threefour", "--captro-visual-long-text", "--captro-visual-pager", "--captro-visual-video"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 15))
    let page = app.otherElements["home.post.page.full-bleed-threefour-0"]
    let media = page.otherElements["home.post.media"].firstMatch
    let stamp = page.otherElements["home.post.stamp"].firstMatch
    let more = page.buttons["home.post.stamp.expand"]
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    let beforeMedia = media.frame
    let beforeStamp = stamp.frame
    let beforeHeight = page.frame.height
    capture(app, "inline-collapsed")
    more.tap()
    let less = page.buttons["home.post.stamp.collapse"]
    XCTAssertTrue(less.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Back"].exists, "Reading must stay in Home")
    XCTAssertEqual(media.frame.height, beforeMedia.height, accuracy: 1)
    XCTAssertEqual(media.frame.minY, beforeMedia.minY, accuracy: 2)
    XCTAssertEqual(stamp.frame.minY, beforeStamp.minY, accuracy: 2)
    XCTAssertGreaterThan(page.frame.height, beforeHeight)
    XCTAssertGreaterThan(stamp.frame.maxY, media.frame.maxY)
    let pause = page.buttons["Pause video"].firstMatch
    XCTAssertTrue(pause.isHittable, "Expanded reading must not cover playback controls")
    pause.tap()
    XCTAssertTrue(page.buttons["Play video"].firstMatch.waitForExistence(timeout: 3))
    let next = app.otherElements["home.post.page.full-bleed-threefour-1"]
    if next.exists { XCTAssertGreaterThanOrEqual(next.frame.minY, stamp.frame.maxY + 11) }
    capture(app, "inline-expanded")
    for _ in 0..<5 where !less.isHittable { stream.swipeUp(velocity: .slow) }
    XCTAssertTrue(less.isHittable)
    less.tap()
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    XCTAssertEqual(page.frame.height, beforeHeight, accuracy: 2)
    capture(app, "inline-collapsed-again")
    // A separate title action still opens Details.
    reveal(page, stream: stream, app: app)
    page.buttons["captro.editorialCard"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
  }

  func testLargeTextStampAndShortCaption() {
    let app = launch(["--captro-visual-size=fourfive", "--captro-quality-large-text", "--captro-quality-dark"])
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 15))
    let stamp = app.otherElements["home.post.stamp"].firstMatch
    XCTAssertGreaterThan(stamp.frame.width / media.frame.width, 0.85)
    XCTAssertGreaterThanOrEqual(stamp.frame.minX, 16)
    XCTAssertLessThanOrEqual(stamp.frame.maxX, media.frame.maxX - 15)
    capture(app, "stamp-accessibility-dark")
  }

  private func launch(_ args: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test"] + args
    app.launch(); return app
  }
  private func reveal(_ page: XCUIElement, stream: XCUIElement, app: XCUIApplication) {
    for _ in 0..<12 {
      let target = stream.frame.minY + 8
      if page.exists && page.frame.minY >= target - 12 && page.frame.minY < target + 30 { return }
      let delta = page.exists ? min(300, max(-300, page.frame.minY - target)) : 280
      if abs(delta) < 2 { return }
      let origin = app.coordinate(withNormalizedOffset: .zero)
      let start = stream.frame.minY + min(400, stream.frame.height * 0.65)
      origin.withOffset(CGVector(dx: app.frame.midX, dy: start))
        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: start - delta)),
          withVelocity: .slow, thenHoldForDuration: 0.3)
      if page.exists && page.frame.minY >= stream.frame.minY && page.frame.maxY < app.tabBars.firstMatch.frame.minY { return }
    }
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
