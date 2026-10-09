import XCTest

final class HomeFullBleedTests: XCTestCase {
  func testEveryPhotoRatioFillsScreenWidth() {
    let ratios: [(String, CGFloat)] = [("wide", 9.0 / 16), ("landscape", 9.0 / 16),
      ("portrait", 4.0 / 3), ("fourfive", 5.0 / 4), ("threefour", 4.0 / 3), ("square", 1)]
    for (name, expectedRatio) in ratios {
      let app = launch(["--captro-visual-size=\(name)"])
      let media = app.otherElements["home.post.media"].firstMatch
      XCTAssertTrue(media.waitForExistence(timeout: 15))
      XCTAssertEqual(media.frame.minX, 0, accuracy: 1)
      XCTAssertEqual(media.frame.width, app.frame.width, accuracy: 1)
      let homeRatio = media.frame.height / media.frame.width
      XCTAssertEqual(homeRatio, expectedRatio, accuracy: 0.01,
        "Supported source ratios retain their distinct natural Home proportions: \(name)")
      if name == "wide" { XCTAssertLessThan(homeRatio, 1, "Wide source metadata must still resolve to a wide Home crop") }
      XCTAssertEqual(media.frame.minY, app.scrollViews["home.post.stream"].frame.minY, accuracy: 1)
      assertStamp(app, media: media)
      capture(app, "continuous-\(name)")
      app.terminate()
    }
  }

  func testVideoFillsScreenWidth() {
    let app = launch(["--captro-visual-size=threefour", "--captro-visual-video"])
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 15))
    let homeRatio = media.frame.height / media.frame.width
    let supportedRatios: [CGFloat] = [9.0 / 16, 1, 5.0 / 4, 4.0 / 3]
    let supported = supportedRatios.contains(where: { ratio in abs(homeRatio - ratio) < 0.01 })
    XCTAssertTrue(supported)
    XCTAssertEqual(homeRatio, 4.0 / 3, accuracy: 0.01)
    assertStamp(app, media: media)
    let pause = app.buttons["Pause video"].firstMatch
    XCTAssertTrue(pause.waitForExistence(timeout: 10))
    pause.tap()
    XCTAssertTrue(app.buttons["Play video"].firstMatch.waitForExistence(timeout: 3))
    capture(app, "continuous-video")
  }

  func testLongCaptionStaysInsideBoundedStamp() {
    let app = launch(["--captro-visual-size=fourfive", "--captro-visual-long-text"])
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 15))
    assertStamp(app, media: media)
    capture(app, "continuous-long-caption")
    app.buttons["captro.editorialCard"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    app.buttons["Back"].tap()
    XCTAssertEqual(media.frame.minY, app.scrollViews["home.post.stream"].frame.minY, accuracy: 1)
  }

  // Run separately while simctl records the actual native UI, with labeled
  // DEBUG fixtures rather than private production posts or substituted mock UI.
  func testContinuousStreamRecording() {
    let app = launch(["--captro-visual-stream", "--captro-visual-video"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 20))
    let fixed = app.otherElements["home.fixed.controls"]
    let stories = app.scrollViews["home.story.rail"]
    XCTAssertGreaterThanOrEqual(stories.frame.minX, fixed.frame.maxX - 1)
    for index in 0..<7 {
      let page = app.otherElements["home.post.page.stream-\(index)"]
      reveal(page, in: stream, app: app)
      XCTAssertTrue(page.exists && page.frame.intersects(stream.frame),
        "Post \(index) must be reachable by normal vertical scrolling")
      if index < 6 {
        let media = page.otherElements["home.post.media"].firstMatch
        XCTAssertTrue(media.exists)
        XCTAssertEqual(page.frame.height, media.frame.height, accuracy: 1,
          "No per-post bottom filler or separate caption region")
        let next = app.otherElements["home.post.page.stream-\(index + 1)"]
        if next.exists {
          // Text-only cards have 12 pt of their own inner top padding. Their
          // accessibility frame excludes that padding; media rows do not.
          XCTAssertEqual(next.frame.minY - page.frame.maxY, index == 5 ? 24 : 12, accuracy: 2,
            "Next post follows with normal spacing, not a viewport spacer")
        }
      }
      capture(app, "stream-\(index)")
      if index == 3 {
        let pause = page.buttons["Pause video"].firstMatch
        XCTAssertTrue(pause.isHittable)
        pause.tap()
        XCTAssertTrue(page.buttons["Play video"].firstMatch.waitForExistence(timeout: 3))
        page.buttons["Play video"].firstMatch.tap()
      }
      if index == 5 {
        let before = page.frame.height
        let media = page.otherElements["home.post.media"].firstMatch
        media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
          .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
        XCTAssertTrue(page.staticTexts["Photo 2 of 3"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.height, before, accuracy: 1)
        capture(app, "stream-carousel-second-slide")
      }
    }
    stream.swipeUp()
    let last = app.otherElements["home.post.page.stream-6"]
    XCTAssertLessThanOrEqual(last.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
      "Scroll-content inset makes the final post reachable above navigation")
  }

  func testTextOnlyAndAccessibilityDoNotReserveMediaHeight() {
    let app = launch(["--captro-visual-text", "--captro-quality-dark", "--captro-quality-large-text"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 15))
    XCTAssertFalse(app.otherElements["home.post.media"].exists)
    XCTAssertFalse(app.staticTexts["MOMENT"].exists)
    XCTAssertFalse(app.staticTexts["More"].exists)
    XCTAssertTrue(app.staticTexts["A walk around the neighborhood"].exists)
    capture(app, "continuous-text-accessibility-dark")
    let secondPost = app.otherElements["home.post.page.text-system-1"]
    reveal(secondPost, in: stream, app: app)
    let secondTitle = secondPost.staticTexts["Looking for people to build with"]
    XCTAssertTrue(secondTitle.exists)
    XCTAssertGreaterThanOrEqual(secondTitle.frame.minY, stream.frame.minY - 1)
    XCTAssertLessThan(secondTitle.frame.maxY, app.tabBars.firstMatch.frame.minY,
      "The next text post must be readable above floating navigation")
  }

  func testPublicContentStreamRecording() {
    // Public read-only content, selected for this regression. Nothing is copied
    // into the app bundle or published. Missing/deleted posts fail honestly.
    let ids = ["7ff613af-f80a-474a-85cc-b159bbcf6a79", "ecbb00c1-f3f3-4d51-9fd8-dca889f9352a",
      "edb704f7-5ae7-486b-bd86-f58266aff746", "9c35e9fe-3537-45b9-844d-9399abe47445",
      "224b562d-34cd-40d9-8d6a-ed05e73b68bd"]
    let app = launch(["--captro-public-feed-test", "--captro-public-posts=\(ids.joined(separator: ","))"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 30))
    for (index, id) in ids.enumerated() {
      let page = app.otherElements["home.post.page.\(id)"]
      reveal(page, in: stream, app: app)
      XCTAssertGreaterThanOrEqual(page.frame.minY, stream.frame.minY - 12)
      XCTAssertLessThan(page.frame.minY, app.tabBars.firstMatch.frame.minY)
      let media = page.otherElements["home.post.media"].firstMatch
      XCTAssertTrue(media.exists)
      XCTAssertEqual(page.frame.height, media.frame.height, accuracy: 1)
      let regularStamp = page.buttons["captro.editorialCard"].firstMatch
      let compactStamp = page.buttons["captro.editorialCard.compact"].firstMatch
      XCTAssertTrue((regularStamp.exists ? regularStamp : compactStamp).isHittable,
        "The real stamp action must be reachable, not just its non-interactive parent container")
      capture(app, "public-feed-\(index)")
      if index == 1 {
        XCTAssertEqual(media.frame.height, media.frame.width * 0.75, accuracy: 1)
        let originalY = page.frame.minY
        let stamp = page.buttons["captro.editorialCard"].firstMatch
        let compact = page.buttons["captro.editorialCard.compact"].firstMatch
        (stamp.exists ? stamp : compact).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertEqual(page.frame.minY, originalY, accuracy: 2, "Returning from details preserves scroll offset")
      }
      if index == 4 {
        let height = page.frame.height
        media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.18))
          .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.18)))
        XCTAssertTrue(page.staticTexts["Photo 2 of 10"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.height, height, accuracy: 1)
        capture(app, "public-carousel-second-slide")
      }
    }
  }

  private func launch(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test"] + arguments
    app.launch()
    return app
  }

  private func reveal(_ page: XCUIElement, in stream: XCUIElement, app: XCUIApplication) {
    for _ in 0..<12 {
      let targetY = stream.frame.minY + 8
      if page.exists && page.frame.minY >= targetY - 12 && page.frame.minY < targetY + 30 { return }
      let delta = page.exists ? min(300, max(-300, page.frame.minY - targetY)) : 280
      if abs(delta) < 2 { return }
      let origin = app.coordinate(withNormalizedOffset: .zero)
      let startY = stream.frame.minY + min(400, stream.frame.height * 0.65)
      origin.withOffset(CGVector(dx: app.frame.midX, dy: startY))
        .press(forDuration: 0.05,
          thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: startY - delta)),
          withVelocity: .slow, thenHoldForDuration: 0.3)
      // A short final item cannot necessarily align with the top. Accept it
      // only when fully visible. Never start a carousel drag above the header
      // simply because some lower portion of the item is still hittable.
      if page.exists && page.frame.minY >= stream.frame.minY &&
          page.frame.maxY < app.tabBars.firstMatch.frame.minY { return }
    }
  }

  private func assertStamp(_ app: XCUIApplication, media: XCUIElement) {
    let regular = app.buttons["captro.editorialCard"].firstMatch
    let stamp = regular.exists ? regular : app.buttons["captro.editorialCard.compact"].firstMatch
    XCTAssertTrue(stamp.exists)
    XCTAssertLessThanOrEqual(stamp.frame.height, min(280, media.frame.height * 0.60) + 1)
    XCTAssertGreaterThanOrEqual(stamp.frame.minY, media.frame.minY)
    XCTAssertLessThanOrEqual(stamp.frame.maxY, media.frame.maxY)
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
