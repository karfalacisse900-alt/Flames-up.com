import XCTest

/// Same optimized app, deterministic 48-post corpus and gesture schedule in
/// both revisions. These are simulator measurements, never physical-iPhone FPS.
final class FeedScrollPerformanceTests: XCTestCase {
  func testNormalAndFastGoodTransport() { exercise(slowNetwork: false) }
  func testNormalAndFastWeakTransport() { exercise(slowNetwork: true) }

  private func exercise(slowNetwork: Bool) {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-vertical-feed-test",
      "--captro-restore-audit", "--captro-vertical-diagnostics", "--captro-scroll-performance",
      slowNetwork ? "--captro-vertical-slow-network" : "--captro-vertical-good-network"]
    app.launch()
    let stream = app.scrollViews["home.post.stream"]
    XCTAssertTrue(app.otherElements["home.post.page.vertical-0"].waitForExistence(timeout: 90))
    snapshot(app, phase: "cold-start")
    let options = XCTMeasureOptions()
    options.iterationCount = 1
    // Do not fake gestures with setContentOffset or replay an artificial
    // animation. XCTest uses native drag/release and waits for quiescence.
    measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
      XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
      for index in 0..<26 {
        drag(app, stream: stream, up: true, speed: index < 6 ? 650 : 2400, diagonal: index % 5 == 0)
        handlePagination(app)
        if index % 6 == 5 { snapshot(app, phase: "down-\(index)") }
      }
      snapshot(app, phase: "bottom")
      for index in 0..<12 {
        drag(app, stream: stream, up: false, speed: index % 2 == 0 ? 2400 : 650, diagonal: false)
      }
      snapshot(app, phase: "warm-up")
      for index in 0..<12 {
        drag(app, stream: stream, up: true, speed: index % 2 == 0 ? 650 : 2400, diagonal: index % 4 == 0)
        handlePagination(app)
      }
      snapshot(app, phase: "warm-bottom")
    }
    let summary = app.descendants(matching: .any)["home.viewport.diagnostics"].firstMatch.value as? String ?? ""
    XCTAssertTrue(summary.contains("commands=0;"), "Ordinary browsing must not issue offset commands")
    XCTAssertTrue((stream.value as? String ?? "").contains("of 48"), "The mixed corpus must reach multiple pages")
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = slowNetwork ? "weak-final" : "good-final"
    image.lifetime = .keepAlways; add(image)
  }

  private func drag(_ app: XCUIApplication, stream: XCUIElement, up: Bool, speed: Double, diagonal: Bool) {
    let bounds = stream.frame
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let x = bounds.midX
    let high = bounds.minY + bounds.height * 0.18
    let low = bounds.minY + bounds.height * 0.80
    origin.withOffset(CGVector(dx: x, dy: up ? low : high)).press(forDuration: 0.03,
      thenDragTo: origin.withOffset(CGVector(dx: x + (diagonal ? 22 : 0), dy: up ? high : low)),
      withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: 0)
  }

  private func handlePagination(_ app: XCUIApplication) {
    let retry = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
      "home.pagination.retry", "Try again")).firstMatch
    if retry.exists && retry.isHittable { retry.tap() }
    let finish = app.buttons["vertical.fixture.finish"]
    if finish.exists && finish.isEnabled {
      finish.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: finish.frame.width / 2, dy: finish.frame.height - 22)).tap()
    }
  }

  private func snapshot(_ app: XCUIApplication, phase: String) {
    for id in ["home.viewport.diagnostics", "home.viewport.trace", "vertical.fixture.state",
      "home.work.diagnostics", "vertical.network.diagnostics"] {
      let element = app.descendants(matching: .any)[id].firstMatch
      if element.exists {
        let attachment = XCTAttachment(string: element.value as? String ?? "")
        attachment.name = "\(phase)-\(id)"; attachment.lifetime = .keepAlways; add(attachment)
      }
    }
  }
}
