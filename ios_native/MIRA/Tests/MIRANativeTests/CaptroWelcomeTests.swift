import XCTest
@testable import MIRANative

final class CaptroWelcomeTests: XCTestCase {
  func testBundledLockupFitsSmallPhonesAndKeepsSuppliedAspectRatio() {
    for width in [CGFloat(0), 320, 375, 390, 440, 600] {
      let logo = CaptroWelcomeLayout.logoWidth(availableWidth: width)
      XCTAssertGreaterThanOrEqual(logo, 0)
      XCTAssertLessThanOrEqual(logo, max(0, width - 64))
      XCTAssertLessThanOrEqual(logo, 240)
      XCTAssertEqual(CaptroWelcomeLayout.logoHeight(width: logo), logo * 624 / 2400, accuracy: 0.001)
    }
  }
  @MainActor func testGuestDoesNotAcquireCredentials() async {
    let storage = WelcomeTestStorage()
    let defaults = UserDefaults(suiteName: "welcome-unit-\(UUID().uuidString)")!
    let session = MIRAAuthSession(keychain: storage, defaults: defaults)
    session.continueAsGuest()
    XCTAssertTrue(session.isGuest); XCTAssertNil(session.user)
    let token = await session.accessToken()
    XCTAssertNil(token); XCTAssertFalse(storage.savedCredentials)
    session.exitGuestMode()
    XCTAssertFalse(session.isGuest); XCTAssertNil(session.user)
  }
}
private final class WelcomeTestStorage: MIRAAuthSessionStorage {
  var savedCredentials = false
  func accessToken() async -> String? { nil }
  func refreshToken() async -> String? { nil }
  func saveSession(accessToken: String, refreshToken: String?) { savedCredentials = true }
  func clearSession() {}
}
