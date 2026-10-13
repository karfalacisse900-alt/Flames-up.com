import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import MIRANative

final class CaptroImageUploadPreparationTests: XCTestCase {
  func testPostAndStoryPreservePNGBytesAndDeclareActualMIME() async throws {
    let source = try XCTUnwrap(makeImage(width: 120, height: 80).pngData())
    for target in [MIRAMediaUploadTarget.feedPost, .general] {
      let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: target)
      let prepared = try await uploader.prepareImageUpload(MIRAPickedMedia(
        data: source, kind: .image, fileName: "camera.original.jpg", mimeType: "image/jpeg"
      ))
      XCTAssertEqual(prepared.data, source)
      XCTAssertEqual(prepared.mimeType, "image/png")
      XCTAssertEqual(prepared.fileName, "camera.original.png")
    }
  }

  func testSupportedImageHeadersKeepHEIFAndWebPMIMEInsteadOfBeingRenamedJPEG() async throws {
    // Header-only fixtures verify transport classification, not camera decoding.
    // Actual HEIF capture/decoding is a separate hardware verification requirement.
    let fixtures: [(Data, String, String)] = [
      (Data([0, 0, 0, 24]) + Data("ftypheic".utf8), "image/heic", "heic"),
      (Data([0, 0, 0, 24]) + Data("ftypmif1".utf8), "image/heif", "heif"),
      (Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBP".utf8), "image/webp", "webp"),
    ]
    for (bytes, mime, fileExtension) in fixtures {
      for target in [MIRAMediaUploadTarget.feedPost, .general] {
        let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: target)
        let prepared = try await uploader.prepareImageUpload(MIRAPickedMedia(
          data: bytes, kind: .image, fileName: "original.jpg", mimeType: "image/jpeg"
        ))
        XCTAssertEqual(prepared.data, bytes)
        XCTAssertEqual(prepared.mimeType, mime)
        XCTAssertEqual(prepared.fileName, "original.\(fileExtension)")
      }
      XCTAssertEqual(pickedMediaKind(from: [], fallbackData: bytes).0, .image)
      XCTAssertEqual(pickedMediaKind(from: [], fallbackData: bytes).2, mime)
    }
  }

  func testJPEGBytesAndEXIFOrientationSurvivePostAndStoryPreparation() async throws {
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(makeImage(width: 80, height: 40).cgImage),
      [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    for target in [MIRAMediaUploadTarget.feedPost, .general] {
      let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: target)
      let prepared = try await uploader.prepareImageUpload(MIRAPickedMedia(
        data: bytes as Data, kind: .image, fileName: "rotated.jpeg", mimeType: "image/jpeg"
      ))
      XCTAssertEqual(prepared.data, bytes as Data)
      XCTAssertEqual(prepared.mimeType, "image/jpeg")
      let geometry = await MIRAPickedMedia(data: prepared.data, kind: .image,
        fileName: prepared.fileName, mimeType: prepared.mimeType).mediaDimension()
      XCTAssertEqual(geometry.sourceOrientation, 6)
      XCTAssertEqual(geometry.originalWidth, 40)
      XCTAssertEqual(geometry.originalHeight, 80)
    }
  }

  func testUnsupportedImageConvertsWithoutStoryDownsampling() async throws {
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(makeImage(width: 2400, height: 1600).cgImage), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    for target in [MIRAMediaUploadTarget.feedPost, .general] {
      let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: target)
      let prepared = try await uploader.prepareImageUpload(MIRAPickedMedia(
        data: bytes as Data, kind: .image, fileName: "original.tiff", mimeType: "image/tiff"
      ))
      let image = try XCTUnwrap(UIImage(data: prepared.data))
      XCTAssertEqual(image.size.width * image.scale, 2400)
      XCTAssertEqual(image.size.height * image.scale, 1600)
      XCTAssertEqual(prepared.mimeType, "image/jpeg")
      XCTAssertLessThanOrEqual(prepared.data.count, 10_000_000)
    }
  }

  func testOversizeImageIsCompressedWithinProviderLimitWithoutChangingPixels() async throws {
    let original = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(makeImage(width: 160, height: 80).cgImage),
      [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    var bytes = original as Data
    // Trailing padding exercises the byte limit without allocating a huge bitmap.
    bytes.append(Data(repeating: 0, count: 10_000_001 - bytes.count))
    let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: .general)
    let prepared = try await uploader.prepareImageUpload(MIRAPickedMedia(
      data: bytes, kind: .image, fileName: "oversize.jpg", mimeType: "image/jpeg"
    ))
    XCTAssertLessThanOrEqual(prepared.data.count, 10_000_000)
    let geometry = await MIRAPickedMedia(data: prepared.data, kind: .image,
      fileName: prepared.fileName, mimeType: prepared.mimeType).mediaDimension()
    XCTAssertEqual(geometry.sourcePixelWidth, 160)
    XCTAssertEqual(geometry.sourcePixelHeight, 80)
    XCTAssertEqual(geometry.sourceOrientation, 6)
    XCTAssertEqual(geometry.originalWidth, 80)
    XCTAssertEqual(geometry.originalHeight, 160)
  }

  func testCancelledPreparationDoesNotReturnUploadBytes() async {
    let preparation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: .feedPost)
      return try await uploader.prepareImageUpload(MIRAPickedMedia(
        data: Data([0xff, 0xd8, 0xff]), kind: .image, fileName: "cancel.jpg", mimeType: "image/jpeg"
      ))
    }
    do {
      _ = try await preparation.value
      XCTFail("A cancelled preparation must not continue into upload.")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  private func makeImage(width: Int, height: Int) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
  }
}
