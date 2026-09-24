import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import MIRANative

final class CaptroPostMediaTests: XCTestCase {
  func testSupportedRatiosIncludeWideLandscapeAndPreserveLegacyFormats() {
    XCTAssertEqual(MIRASupportedPostAspectRatio.allCases.map(\.rawValue), ["16:9", "4:3", "0.65:1", "4:5", "3:4", "1:1"])
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

  func testFeedUploadKeepsPhotographAspectRatioWithoutCenterCrop() async throws {
    let size = CGSize(width: 2400, height: 1200)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { _ in
      UIColor.red.setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
      UIColor.blue.setFill()
      UIRectFill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
    }
    let source = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
    let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: .feedPost)
    let preparedData = await uploader.prepareFeedImage(source)
    let prepared = try XCTUnwrap(preparedData)
    let output = try XCTUnwrap(UIImage(data: prepared))
    XCTAssertEqual(output.size.width, 2400, accuracy: 1)
    XCTAssertEqual(output.size.height, 1200, accuracy: 1)
    XCTAssertLessThan(prepared.count, 10_000_000)
  }

  func testPublishedImageMetadataRequestsAspectPreservation() async throws {
    let size = CGSize(width: 1920, height: 1080)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: size))
    }
    let media = MIRAPickedMedia(
      data: try XCTUnwrap(image.jpegData(compressionQuality: 0.8)),
      kind: .image,
      fileName: "landscape.jpg",
      mimeType: "image/jpeg"
    )
    let dimension = await media.postMediaDimension()
    XCTAssertEqual(dimension.cropMode, "preserve_aspect")
    XCTAssertEqual(dimension.format, "16:9")
  }
}
