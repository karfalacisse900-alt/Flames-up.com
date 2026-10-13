import XCTest
import UIKit

final class HomeFullBleedTests: XCTestCase {
  /// Captures native offset/bounds changes *during* each gesture, not only the
  /// resting before/after frames that previously missed transient movement.
  func testSameCarouselHomeAndDetailsGestureTrace() {
    compareSameCarousel(baseline: false)
  }

  /// The workflow applies only passive instrumentation to the released source.
  /// Record the old behavior without requiring it to satisfy the proposed fix.
  func testSameCarouselHomeAndDetailsBaselineTrace() {
    compareSameCarousel(baseline: true)
  }

  private func compareSameCarousel(baseline: Bool) {
    let app = launch(["--captro-visual-mixed-carousel", "--captro-restore-audit", "--captro-carousel-diagnostics"])
    let page = app.otherElements["home.post.page.mixed-carousel"]
    XCTAssertTrue(page.waitForExistence(timeout: 30))
    let home = page.otherElements["home.post.media"].firstMatch
    let homeFrame = home.frame
    capture(app, "comparison-home-first")
    compareGestureSequence(app, media: home, surface: "home", assertStable: !baseline, counter: { "Photo \($0) of 4" })

    // Finish on the landscape slide so pixel checks catch internal pillar/
    // letterboxing even when the outer container reports the correct ratio.
    carouselDrag(home, forward: true, velocity: .slow, diagonal: false)
    XCTAssertTrue(page.staticTexts["Photo 2 of 4"].waitForExistence(timeout: 5))
    inspectLandscapeFixture(app, media: home, surface: "home", expectFill: !baseline)
    capture(app, "comparison-home-landscape-filled")
    carouselDrag(home, forward: false, velocity: .fast, diagonal: false)
    XCTAssertTrue(page.staticTexts["Photo 1 of 4"].waitForExistence(timeout: 5))
    let readingY = page.frame.minY
    page.buttons["captro.editorialCard"].firstMatch.tap()
    let details = app.descendants(matching: .any)["post.detail.media"].firstMatch
    XCTAssertTrue(details.waitForExistence(timeout: 10))
    XCTAssertEqual(details.frame.height / details.frame.width, homeFrame.height / homeFrame.width, accuracy: 0.01)
    capture(app, "comparison-details-first")
    compareGestureSequence(app, media: details, surface: "details", assertStable: !baseline, counter: { "\($0) / 4" })
    carouselDrag(details, forward: true, velocity: .slow, diagonal: false)
    XCTAssertTrue(app.staticTexts["2 / 4"].waitForExistence(timeout: 5))
    inspectLandscapeFixture(app, media: details, surface: "details", expectFill: !baseline)
    capture(app, "comparison-details-landscape-filled")
    app.buttons["Back"].tap()
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    XCTAssertEqual(page.frame.minY, readingY, accuracy: 2)
    XCTAssertTrue(page.staticTexts["Photo 1 of 4"].exists, "Details has independent local selection; Home retains its selected media")
    let viewport = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch
    XCTAssertTrue((viewport.value as? String ?? "").contains("commands=0;"))
    capture(app, "comparison-home-return")
  }

  private func compareGestureSequence(_ app: XCUIApplication, media: XCUIElement,
    surface: String, assertStable: Bool, counter: (Int) -> String) {
    let initial = media.frame
    // XCTest waits for quiescence between these completed gestures. This covers
    // alternate directions, not a reversal with the finger still down or a
    // touch interrupting native deceleration. Those remain physical-device
    // checks, as does uncached network loading (these media fixtures are local).
    let actions: [(Bool, XCUIGestureVelocity, Bool)] = [
      (true, .slow, false), (false, .fast, false),
      (true, .slow, true), (false, .slow, true),
      (true, .fast, false), (false, .fast, false)
    ]
    for (index, action) in actions.enumerated() {
      carouselDrag(media, forward: action.0, velocity: action.1, diagonal: action.2)
      XCTAssertTrue(app.staticTexts[counter(action.0 ? 2 : 1)].waitForExistence(timeout: 5), "\(surface) gesture \(index)")
      if assertStable {
        XCTAssertEqual(media.frame.minY, initial.minY, accuracy: 2, "\(surface) horizontal swipe changed the vertical position")
        XCTAssertEqual(media.frame.height, initial.height, accuracy: 1)
      }
    }
    let probe = app.descendants(matching: .any)["carousel.diagnostics.\(surface)"].firstMatch
    XCTAssertTrue(probe.exists)
    let text = probe.value as? String ?? "{}"
    let attachment = XCTAttachment(string: text)
    attachment.name = "carousel-trajectory-\(surface)"; attachment.lifetime = .keepAlways; add(attachment)
    let metrics = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    XCTAssertGreaterThan(metrics["totalSamples"] as? Int ?? 0, 5, "Missing native trajectory, do not claim measured")
    XCTAssertGreaterThanOrEqual(metrics["gestureCount"] as? Int ?? 0, 6)
    let samples = metrics["samples"] as? [[String: Any]] ?? []
    XCTAssertTrue(samples.contains { ($0["feedGesture"] as? Int ?? -1) >= 0 },
      "The vertical parent must be observed; a missing parent is not proof of zero movement")
    if assertStable {
      for key in ["maxGestureFeedOffsetRange", "maxGestureFrameYRange", "maxGestureFrameWidthRange", "maxGestureFrameHeightRange"] {
        XCTAssertLessThanOrEqual(metrics[key] as? Double ?? .infinity, 1.5, "\(surface) \(key): \(text)")
      }
    }
  }

  private func carouselDrag(_ media: XCUIElement, forward: Bool, velocity: XCUIGestureVelocity, diagonal: Bool) {
    media.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: 0.16))
      .press(forDuration: 0.06,
        thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: diagonal ? 0.20 : 0.16)),
        withVelocity: velocity, thenHoldForDuration: 0.05)
  }

  private func inspectLandscapeFixture(_ app: XCUIApplication, media: XCUIElement, surface: String, expectFill: Bool) {
    func color(at point: CGPoint, in image: UIImage) -> [Int]? {
      guard let source = image.cgImage else { return nil }
      let scale = CGFloat(source.width) / app.frame.width
      guard let pixel = source.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)) else { return nil }
      var rgba = [UInt8](repeating: 0, count: 4)
      let result = rgba.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
      }
      return result ? rgba.prefix(3).map(Int.init) : nil
    }
    let frame = media.frame
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let image = app.screenshot().image
      guard let center = color(at: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.35), in: image) else { return false }
      return zip(center, [84, 122, 133]).allSatisfy { pair in abs(pair.0 - pair.1) < 18 }
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "Landscape fixture has not loaded")
    let image = app.screenshot().image
    // Sample all four edges: a landscape image fitted into a portrait frame has
    // top/bottom bands, while a portrait image in landscape has side bands.
    let points = [CGPoint(x: frame.minX + 4, y: frame.minY + frame.height * 0.35),
      CGPoint(x: frame.maxX - 4, y: frame.minY + frame.height * 0.35),
      CGPoint(x: frame.midX, y: frame.minY + 4),
      CGPoint(x: frame.minX + frame.width * 0.25, y: frame.maxY - 4)]
    let colors = points.map { color(at: $0, in: image) ?? [] }
    let attachment = XCTAttachment(string: "surface=\(surface); frame=\(frame); edges(left,right,top,bottom)=\(colors); expected=[84,122,133]")
    attachment.name = "carousel-media-edge-pixels-\(surface)"; attachment.lifetime = .keepAlways; add(attachment)
    for rgb in colors {
      XCTAssertEqual(rgb.count, 3)
      if expectFill {
        XCTAssertTrue(zip(rgb, [84, 122, 133]).allSatisfy { pair in abs(pair.0 - pair.1) < 18 },
          "Unexpected internal media band: \(rgb)")
      }
    }
  }

  func testLazyFeedGestureDirectionsAndBackgroundReturn() {
    let app = launch(["--captro-visual-mixed-carousel", "--captro-restore-audit", "--captro-stability-updates"])
    let stream = app.scrollViews["home.post.stream"]
    let page = app.otherElements["home.post.page.mixed-carousel"]
    XCTAssertTrue(page.waitForExistence(timeout: 20))
    let media = page.otherElements["home.post.media"].firstMatch
    let original = page.frame
    // Slightly diagonal horizontal drags must remain carousel gestures.
    for _ in 0..<3 {
      media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15))
        .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.19)))
      XCTAssertTrue(page.staticTexts["Photo 2 of 4"].waitForExistence(timeout: 5))
      XCTAssertEqual(page.frame.minY, original.minY, accuracy: 2)
      XCTAssertEqual(page.frame.height, original.height, accuracy: 1)
      media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.19))
        .press(forDuration: 0.4, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)))
      XCTAssertTrue(page.staticTexts["Photo 1 of 4"].waitForExistence(timeout: 5))
      XCTAssertEqual(page.frame.minY, original.minY, accuracy: 2)
    }
    // Native vertical motion starting over the media must remain enabled.
    media.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
      .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.05)))
    XCTAssertLessThan(page.frame.minY, original.minY - 10)
    let restingY = page.frame.minY
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(stream.waitForExistence(timeout: 10))
    XCTAssertEqual(page.frame.minY, restingY, accuracy: 2)
    let probe = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch
    let summary = probe.value as? String ?? "missing"
    XCTAssertTrue(summary.contains("commands=0;"), summary)
    let result = XCTAttachment(string: summary); result.name = "viewport-gestures-background"; result.lifetime = .keepAlways; add(result)
    capture(app, "lazy-feed-gestures-background-return")
  }

  func testLazyFeedTabReturnDoesNotIssueScrollCommands() {
    let app = launch(["--captro-visual-video", "--captro-stability-forty", "--captro-restore-audit", "--captro-stability-updates"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 20))
    let page = app.otherElements["home.post.page.stress-7"]
    reveal(page, in: stream, app: app)
    let beforeY = page.frame.minY
    let probe = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch
    XCTAssertTrue(probe.exists)
    let before = probe.value as? String ?? "missing"
    let initial = XCTAttachment(string: before); initial.name = "viewport-before-tab"; initial.lifetime = .keepAlways; add(initial)
    app.tabBars.buttons["Me"].tap()
    app.tabBars.buttons["Home"].tap()
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    let after = probe.value as? String ?? "missing"
    let result = XCTAttachment(string: after); result.name = "viewport-after-tab"; result.lifetime = .keepAlways; add(result)
    XCTAssertTrue(after.contains("commands=0;"), "Surviving lazy Home scroll view must not receive a restoration command: \(after)")
    XCTAssertEqual(page.frame.minY, beforeY, accuracy: 2)
    capture(app, "lazy-feed-tab-return")
  }

  func testCachedHomeSurvivesConflictingDelayedDetailsRefresh() {
    let app = launch(["--captro-visual-size=threefour", "--captro-visual-pager", "--captro-delayed-detail-framing-test"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 20))
    for index in 0...1 {
      let page = app.otherElements["home.post.page.full-bleed-threefour-\(index)"]
      reveal(page, in: stream, app: app)
      let media = page.otherElements["home.post.media"].firstMatch
      let home = media.frame
      let readingY = page.frame.minY
      XCTAssertEqual(home.height / home.width, 4.0 / 3, accuracy: 0.01)
      capture(app, "cached-home-\(index)")
      page.buttons["captro.editorialCard"].firstMatch.tap()
      let details = app.descendants(matching: .any)["post.detail.media"].firstMatch
      XCTAssertTrue(details.waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Refreshed server title")).firstMatch.waitForExistence(timeout: 15))
      XCTAssertEqual(details.frame.height / details.frame.width, home.height / home.width, accuracy: 0.01,
        "Fresh conflicting landscape metadata must not replace the opening portrait composition")
      capture(app, "details-after-conflicting-refresh-\(index)")
      app.buttons["Back"].tap()
      XCTAssertTrue(page.waitForExistence(timeout: 5))
      XCTAssertEqual(page.frame.minY, readingY, accuracy: 2)
      XCTAssertEqual(media.frame.height, home.height, accuracy: 1)
      capture(app, "cached-home-return-\(index)")
    }
  }

  func testLiveNYPLHomeAndDetailsShareStoredPortraitFrame() {
    let app = launch(["--captro-public-feed-test", "--captro-public-posts=7ff613af-f80a-474a-85cc-b159bbcf6a79"])
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 45))
    XCTAssertEqual(media.frame.height / media.frame.width, 4.0 / 3, accuracy: 0.01)
    capture(app, "live-NYPL-home-shared-framing")
    app.buttons["captro.editorialCard"].firstMatch.tap()
    let detail = app.descendants(matching: .any)["post.detail.media"].firstMatch
    XCTAssertTrue(detail.waitForExistence(timeout: 10))
    XCTAssertEqual(detail.frame.height / detail.frame.width, 4.0 / 3, accuracy: 0.01)
    capture(app, "live-NYPL-details-shared-framing")
  }
  func testFortyMixedPostsAndDetailsReturn() {
    verifyMixedPosts(count: 40)
  }
  func testHundredMixedPostsAndDetailsReturn() { verifyMixedPosts(count: 100) }
  private func verifyMixedPosts(count: Int) {
    let app = launch(["--captro-visual-video", count == 100 ? "--captro-stability-hundred" : "--captro-stability-forty", "--captro-stability-updates"])
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(stream.waitForExistence(timeout: 20))
    for index in 0..<count {
      let page = app.otherElements["home.post.page.stress-\(index)"]
      reveal(page, in: stream, app: app)
      XCTAssertTrue(page.exists && page.frame.intersects(stream.frame), "Stable post \(index) remains reachable")
      if [0, 7, 14].contains(index) {
        let title = page.buttons["captro.editorialCard"].firstMatch
        XCTAssertTrue(title.isHittable, "Details action must be reachable")
        if title.exists {
          let y = page.frame.minY
          title.tap()
          XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
          app.buttons["Back"].tap()
          XCTAssertTrue(page.waitForExistence(timeout: 5))
          XCTAssertEqual(page.frame.minY, y, accuracy: 2, "Details return must preserve pixel offset")
        }
      }
      if index % 10 == 0 || index == 39 { capture(app, "stable-stream-\(index)") }
    }
  }

  func testIdleBackgroundUpdatesPreserveReadingPositionAndHeader() {
    let app = launch(["--captro-visual-mixed-carousel", "--captro-stability-updates"])
    let page = app.otherElements["home.post.page.mixed-carousel"]
    XCTAssertTrue(page.waitForExistence(timeout: 20))
    let media = page.otherElements["home.post.media"].firstMatch
    media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.14))
      .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.14)))
    XCTAssertTrue(page.staticTexts["Photo 2 of 4"].waitForExistence(timeout: 5))
    let before = media.frame
    let elapsed = expectation(description: "Two minutes of background updates")
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { elapsed.fulfill() }
    wait(for: [elapsed], timeout: 125)
    XCTAssertEqual(media.frame.minY, before.minY, accuracy: 1)
    XCTAssertEqual(media.frame.height, before.height, accuracy: 1)
    XCTAssertTrue(page.staticTexts["Photo 2 of 4"].exists)
    XCTAssertFalse(app.staticTexts["For You"].exists)
    let menu = app.buttons["home.feed.selector"]
    let create = app.buttons["Create post"]
    XCTAssertEqual(menu.frame.width, 44, accuracy: 1)
    XCTAssertEqual(create.frame.width, 44, accuracy: 1)
    XCTAssertEqual(menu.frame.midY, create.frame.midY, accuracy: 1)
    capture(app, "stable-after-two-minute-background-updates")
    menu.tap()
    XCTAssertTrue(app.staticTexts["For You"].waitForExistence(timeout: 3) || app.buttons["For You"].exists)
    capture(app, "header-feed-choice-menu")
  }

  func testEveryPhotoRatioFillsScreenWidth() {
    let ratios: [(String, CGFloat)] = [("wide", 9.0 / 16), ("landscape", 9.0 / 16),
      ("portrait", 5.0 / 4), ("fourfive", 5.0 / 4), ("threefour", 4.0 / 3), ("square", 1)]
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
      app.buttons["captro.editorialCard"].firstMatch.tap()
      let detail = app.descendants(matching: .any)["post.detail.media"].firstMatch
      XCTAssertTrue(detail.waitForExistence(timeout: 5))
      XCTAssertEqual(detail.frame.height / detail.frame.width, homeRatio, accuracy: 0.01,
        "Home and Details must match for \(name)")
      capture(app, "details-matching-\(name)")
      app.terminate()
    }
  }

  func testMixedCarouselKeepsOneFeedFrame() {
    let app = launch(["--captro-visual-mixed-carousel"])
    let page = app.otherElements["home.post.page.mixed-carousel"]
    XCTAssertTrue(page.waitForExistence(timeout: 20))
    let media = page.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.exists)
    let fixedHeight = page.frame.height
    XCTAssertEqual(media.frame.height / media.frame.width, 1.25, accuracy: 0.01)
    capture(app, "mixed-carousel-first-photo")
    for index in 2...4 {
      media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.14))
        .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.14)))
      XCTAssertTrue(page.staticTexts["Photo \(index) of 4"].waitForExistence(timeout: 5))
      XCTAssertEqual(page.frame.height, fixedHeight, accuracy: 1, "Swipe must not resize the post")
      capture(app, "mixed-carousel-slide-\(index)")
    }
    for index in (1...3).reversed() {
      media.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.14))
        .press(forDuration: 0.05, thenDragTo: media.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.14)))
      XCTAssertTrue(page.staticTexts["Photo \(index) of 4"].waitForExistence(timeout: 5))
      XCTAssertEqual(page.frame.height, fixedHeight, accuracy: 1)
    }
    page.buttons["captro.editorialCard"].tap()
    let detailMedia = app.collectionViews["post.detail.media"]
    let writing = app.staticTexts["post.detail.mediaWriting"].firstMatch
    XCTAssertTrue(detailMedia.waitForExistence(timeout: 5))
    XCTAssertEqual(detailMedia.frame.height / detailMedia.frame.width, 1.25, accuracy: 0.01,
      "Details must use the exact same selected framing as Home")
    XCTAssertTrue(writing.waitForExistence(timeout: 5))
    XCTAssertFalse(detailMedia.staticTexts["FIRST PHOTO"].exists,
      "Original media stays clear in Details")
    XCTAssertGreaterThanOrEqual(writing.frame.minY, detailMedia.frame.maxY - 1,
      "Details writing belongs below the clean original media")
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
          // Page frames include their own content padding. Only the stream's
          // 12 pt inter-post spacing sits between adjacent page frames.
          XCTAssertEqual(next.frame.minY - page.frame.maxY, 12, accuracy: 2,
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
    XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.otherElements["home.post.media"].exists)
    XCTAssertFalse(app.staticTexts["MOMENT"].exists)
    XCTAssertFalse(app.staticTexts["More"].exists)
    XCTAssertFalse(app.staticTexts["A walk around the neighborhood"].exists)
    XCTAssertFalse(app.staticTexts["Looking for people to build with"].exists)
    XCTAssertFalse(app.otherElements["home.post.page.text-system-1"].exists,
      "Retired ordinary text posts do not leave an empty feed card at accessibility sizes")
    capture(app, "retired-text-accessibility-dark")
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
