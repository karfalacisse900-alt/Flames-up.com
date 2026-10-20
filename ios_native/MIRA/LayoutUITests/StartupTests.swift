import XCTest

/// The real root/coordinator and an isolated session transport; not OAuth or
/// physical cold-launch evidence. No production credentials or provider calls.
final class StartupTests: XCTestCase {
  private func launch(_ flags: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-account-flow-review"] + flags
    app.launch()
    return app
  }
  private func keep(_ app: XCUIApplication, _ label: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = label; shot.lifetime = .keepAlways; add(shot)
  }
  func testSlowStartupLeavesBrandingForHonestLoadingThenCorrectRoute() {
    let app = launch(["--account-signed-in", "--startup-slow"])
    XCTAssertTrue(app.descendants(matching: .any)["startup.resolving"].firstMatch.waitForExistence(timeout: 4))
    XCTAssertFalse(app.buttons["Continue as guest"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    keep(app, "startup-slow-routing-not-welcome")
    XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.staticTexts["account.fixture.identity"].label, "fixture-a")
    keep(app, "startup-signed-in-destination")
  }
  func testOfflineStartupLeavesLogoAndOffersRetryWithoutLosingCredentials() {
    let app = launch(["--account-signed-in", "--startup-offline"])
    XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Your sign-in is saved. Check your connection and try again."].exists)
    XCTAssertFalse(app.buttons["Continue as guest"].exists)
    keep(app, "startup-offline-retry")
  }
  func testWarmResumeAndTabChangesDoNotReplayOrBlockInteraction() {
    let app = launch(["--account-signed-in"])
    XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
    app.buttons["Draft"].tap()
    XCTAssertTrue(app.textFields["account.fixture.draft"].waitForExistence(timeout: 5))
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(app.textFields["account.fixture.draft"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["startup.resolving"].firstMatch.exists)
    app.buttons["Close draft"].tap()
    XCTAssertTrue(app.tabBars.buttons["Home"].isHittable)
  }
  func testBackgroundDuringSlowStartupDoesNotRestartOrLeaveTouchBlocker() {
    let app = launch(["--account-signed-in", "--startup-slow"])
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
    app.buttons["Draft"].tap()
    XCTAssertTrue(app.textFields["account.fixture.draft"].waitForExistence(timeout: 5))
  }
  func testColdLaunchResponsiveness() {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-account-flow-review", "--account-signed-in"]
    let options = XCTMeasureOptions(); options.iterationCount = 3
    measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
      app.launch()
      XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
      app.terminate()
    }
  }
  func testReducedMotionSignedOutLaunchReachesWorkingWelcomeAndDoesNotReplay() {
    let app = launch(["--startup-reduce-motion"])
    XCTAssertTrue(app.buttons["Continue as guest"].waitForExistence(timeout: 15))
    app.buttons["Continue as guest"].tap()
    XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(app.tabBars.buttons["Home"].isHittable)
    XCTAssertFalse(app.descendants(matching: .any)["startup.resolving"].firstMatch.exists)
    keep(app, "startup-reduce-motion-guest")
  }
}
