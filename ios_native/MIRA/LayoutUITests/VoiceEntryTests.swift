import XCTest

/// Exercises the active Capture -> Voice route without provider credentials.
/// This verifies denial/cleanup and renders the actual neutral character; it
/// does not substitute for an authenticated, physical-device conversation.
final class VoiceEntryTests: XCTestCase {
  func testDeniedMicrophoneNeverShowsReadyAndCanEnd() {
    let app = XCUIApplication()
    app.resetAuthorizationStatus(for: .microphone)
    app.launchArguments = ["--captro-design-quality-test", "--captro-quality-capture"]
    app.launch()
    let voice = app.buttons["Voice, Talk to Captro"]
    XCTAssertTrue(voice.waitForExistence(timeout: 10))
    voice.tap()
    if app.buttons["Continue"].waitForExistence(timeout: 3) {
      app.buttons["Continue"].tap()
    }
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let denial = springboard.alerts.buttons.matching(
      NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")).firstMatch
    XCTAssertTrue(denial.waitForExistence(timeout: 10))
    denial.tap()
    XCTAssertTrue(app.staticTexts["Microphone access needed"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Connected"].exists)
    XCTAssertFalse(app.buttons["Mute microphone"].isEnabled)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "voice-actual-route-permission-denied-neutral-character"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["End conversation"].tap()
    XCTAssertTrue(voice.waitForExistence(timeout: 5))
  }
}
