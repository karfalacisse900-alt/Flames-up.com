import XCTest
import UniformTypeIdentifiers
@testable import MIRANative

final class CaptroPostMediaTests: XCTestCase {
  func testFiveSupportedRatiosAreUnchangedForBothMediaKinds() {
    XCTAssertEqual(MIRASupportedPostAspectRatio.allCases.map(\.rawValue), ["4:3", "0.65:1", "4:5", "3:4", "1:1"])
    for ratio in MIRASupportedPostAspectRatio.allCases {
      XCTAssertEqual(MIRASupportedPostAspectRatio.nearest(width: ratio.feedWidth, height: ratio.feedHeight), ratio)
    }
  }

  func testHEICIsNotMistakenForVideoBecauseOfItsContainerHeader() {
    let heicHeader = Data([0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99])
    XCTAssertEqual(pickedMediaKind(from: [.heic], fallbackData: heicHeader).0, .image)
    XCTAssertEqual(pickedMediaKind(from: [.movie], fallbackData: Data()).0, .video)
  }

  func testVideoReferencesDoNotIncludePosterImagesOrOrdinaryImageNames() {
    XCTAssertTrue("cfstream:abc123xyz".isVideoURL)
    XCTAssertTrue("https://videodelivery.net/abc123xyz/manifest/video.m3u8".isVideoURL)
    XCTAssertTrue("https://example.com/upload.MOV?token=test".isVideoURL)
    XCTAssertFalse("https://videodelivery.net/abc123xyz/thumbnails/thumbnail.jpg".isVideoURL)
    XCTAssertFalse("https://example.com/stream-in-the-woods.jpg".isVideoURL)
  }

  func testVideoLimitsRejectInvalidFilesBeforeNetworkUpload() {
    XCTAssertNoThrow(try CaptroPostVideoLimits.validate(byteCount: 1_000, duration: 60))
    XCTAssertThrowsError(try CaptroPostVideoLimits.validate(byteCount: 200_000_001, duration: 10))
    for duration in [0, -1, 61, Double.nan, Double.infinity] {
      XCTAssertThrowsError(try CaptroPostVideoLimits.validate(byteCount: 1_000, duration: duration))
    }
  }
}
