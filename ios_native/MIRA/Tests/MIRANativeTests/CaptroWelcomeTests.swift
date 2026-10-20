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
    XCTAssertEqual(CaptroWelcomeLayout.sourceSize, CGSize(width: 1254, height: 1254))
    for width in [CGFloat(320), 375, 390, 402, 430, 440, 480, 600] {
      let displayedWidth = min(width, CaptroWelcomeLayout.maximumWidth)
      XCTAssertEqual(CaptroWelcomeLayout.artworkHeight(width: width) / displayedWidth,
                     1.03, accuracy: 0.0001)
      for height in [CGFloat(0), 100, 300, 600] {
        let fitted = CaptroWelcomeLayout.fittedImageSize(width: width, height: height)
        XCTAssertEqual(fitted.width, fitted.height, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(fitted.width * CaptroWelcomeLayout.maximumZoom, displayedWidth + 0.0001)
        XCTAssertLessThanOrEqual(fitted.height * CaptroWelcomeLayout.maximumZoom, height + 0.0001)
      }
    }
    // Base art is 480 / 1.03 points wide; final zoom reaches 480 points.
    XCTAssertEqual(CaptroWelcomeLayout.requiredThreeXSource, CGSize(width: 1440, height: 1440))
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
