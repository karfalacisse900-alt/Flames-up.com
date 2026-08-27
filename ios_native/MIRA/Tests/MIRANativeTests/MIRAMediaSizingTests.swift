import CoreGraphics
import XCTest
@testable import MIRANative

final class MIRAMediaSizingTests: XCTestCase {
  func testMainFeedDefaultsToFourFive() {
    let width: CGFloat = 400

    XCTAssertEqual(MIRASupportedPostAspectRatio.defaultRatio, .fourFive)
    XCTAssertEqual(MIRAMediaSizing.mainFeedDisplayRatio(for: []), 5.0 / 4.0, accuracy: 0.0001)
    XCTAssertEqual(
      MIRAMediaSizing.mainFeedHeight(for: [], width: width, screenHeight: 1000),
      width * 5.0 / 4.0,
      accuracy: 0.0001
    )
  }

  func testMainFeedSupportsTallAndImmersiveRatios() {
    let width: CGFloat = 400

    XCTAssertEqual(
      MIRAMediaSizing.mainFeedHeight(for: ["media-3x4.jpg"], width: width, screenHeight: 1000),
      width * 4.0 / 3.0,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      MIRAMediaSizing.mainFeedHeight(for: ["media-2x3.jpg"], width: width, screenHeight: 1000),
      width * 3.0 / 2.0,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      MIRAMediaSizing.mainFeedHeight(for: ["media-9x16.jpg"], width: width, screenHeight: 800),
      800 * MIRAMediaSizing.maxMainFeedScreenHeightFraction,
      accuracy: 0.0001
    )
  }

  func testSupportedPostAspectRatiosPreserveNineSixteenMetadata() {
    let selected = MIRASupportedPostAspectRatio.nearest(width: 1080, height: 1920)

    XCTAssertEqual(selected, .nineSixteen)
    XCTAssertEqual(selected.feedWidth, 1080)
    XCTAssertEqual(selected.feedHeight, 1920)
  }
}
