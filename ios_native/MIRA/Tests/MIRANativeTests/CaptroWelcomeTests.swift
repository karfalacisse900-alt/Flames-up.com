import XCTest
@testable import MIRANative

final class CaptroWelcomeTests: XCTestCase {
  func testFixedPageAllocatesRemainingHeightWithoutChangingArtworkRatio() {
    for width in [CGFloat(320), 375, 390, 440] {
      for height in [CGFloat(548), 728, 830, 920] {
        for controls in [CGFloat(330), 390, 510] {
          let hero = CaptroWelcomeLayout.fittedArtworkHeight(width: width, availableHeight: height, controlsHeight: controls)
          XCTAssertGreaterThanOrEqual(hero, 0)
          XCTAssertLessThanOrEqual(hero + controls, height)
          XCTAssertLessThanOrEqual(hero, CaptroWelcomeLayout.artworkHeight(width: width))
        }
      }
    }
  }
  func testSourceGeometryAndZoomDoNotStretchOrClipArtwork() {
    for width in [CGFloat(320), 375, 390, 402, 430, 440, 480, 600] {
      let displayedWidth = min(width, CaptroWelcomeLayout.maximumWidth)
      XCTAssertEqual(CaptroWelcomeLayout.artworkHeight(width: width) / displayedWidth,
                     932.0 / 870.0 * 1.03, accuracy: 0.0001)
    }
    XCTAssertGreaterThanOrEqual(CaptroWelcomeLayout.requiredThreeXSource.width, 1484)
    XCTAssertGreaterThan(CaptroWelcomeLayout.requiredThreeXSource.width, CaptroWelcomeLayout.sourceSize.width)
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
