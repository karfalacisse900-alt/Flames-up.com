import XCTest
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import MIRANative

final class CaptroCaptureReviewTests: XCTestCase {
  func testStoryDurationDoesNotCutLongCameraRecordingToFifteenSeconds() {
    XCTAssertNil(CaptroCaptureReview.storyDuration(for: nil))
    XCTAssertNil(CaptroCaptureReview.storyDuration(for: .nan))
    XCTAssertEqual(CaptroCaptureReview.storyDuration(for: 14.5), 15)
    XCTAssertEqual(CaptroCaptureReview.storyDuration(for: 15.1), 30)
    XCTAssertEqual(CaptroCaptureReview.storyDuration(for: 45), 60)
    XCTAssertEqual(CaptroCaptureReview.storyDuration(for: 60), 60)
  }
  func testEnhancementIsSeparateAndDoesNotUpscaleOrChangeOriginal() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
    }
    let bytes = try XCTUnwrap(image.pngData())
    let original = MIRAPickedMedia(data: bytes, kind: .image, fileName: "capture.png", mimeType: "image/png")
    let enhanced = try await CaptroCaptureReview.enhanced(original)
    XCTAssertEqual(original.data, bytes)
    XCTAssertNotEqual(enhanced.localID, original.localID)
    XCTAssertEqual(enhanced.mimeType, "image/jpeg")
    let source = try XCTUnwrap(CGImageSourceCreateWithData(enhanced.data as CFData, nil))
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 320)
    XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 240)
    XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
  }

  func testEnhancementNormalizesRotatedPixelsAndDropsLocation() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    }
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
      kCGImagePropertyOrientation: 6,
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 40.0, kCGImagePropertyGPSLatitudeRef: "N"],
    ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let original = MIRAPickedMedia(data: bytes as Data, kind: .image, fileName: "rotated.jpg", mimeType: "image/jpeg")
    let enhanced = try await CaptroCaptureReview.enhanced(original)
    let geometry = await enhanced.mediaDimension()
    XCTAssertEqual(geometry.originalWidth, 40)
    XCTAssertEqual(geometry.originalHeight, 80)
    XCTAssertEqual(geometry.sourceOrientation, 1)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(enhanced.data as CFData, nil))
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    XCTAssertEqual(original.data, bytes as Data)
  }

  func testExplicitGrayscaleInputEnhancesIntoRGBWithoutChangingOriginal() async throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
      bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
    let image = try XCTUnwrap(context.makeImage())
    XCTAssertEqual(image.colorSpace?.model, .monochrome)
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let original = MIRAPickedMedia(data: bytes as Data, kind: .image, fileName: "gray.png", mimeType: "image/png")
    let enhanced = try await CaptroCaptureReview.enhanced(original)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(enhanced.data as CFData, nil))
    let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(result.colorSpace?.model, .rgb)
    XCTAssertEqual(result.width, 32)
    XCTAssertEqual(result.height, 24)
    XCTAssertEqual(original.data, bytes as Data)
  }

  func testEnhancementOutputSpacePreservesSupportedWideColor() throws {
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let output = CaptroCaptureReview.enhancementColorSpace(for: p3)
    XCTAssertEqual(output.model, .rgb)
    XCTAssertEqual(output.name as String?, p3.name as String?)
    let grayscaleOutput = CaptroCaptureReview.enhancementColorSpace(for: CGColorSpaceCreateDeviceGray())
    XCTAssertEqual(grayscaleOutput.name as String?, CGColorSpace.sRGB as String)
  }

  func testCancelledEnhancementDoesNotProcessOrReturnADerivative() async {
    let processing = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await CaptroCaptureReview.enhanced(MIRAPickedMedia(
        data: Data(), kind: .image, fileName: "cancel.jpg", mimeType: "image/jpeg"
      ))
    }
    do {
      _ = try await processing.value
      XCTFail("Cancelled enhancement must not return a derivative.")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testCancelledThumbnailDoesNotReturnAnImage() async {
    let preparation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await CaptroCaptureReview.thumbnail(MIRAPickedMedia(
        data: Data(), kind: .image, fileName: "cancel.jpg", mimeType: "image/jpeg"
      ))
    }
    let result = await preparation.value
    XCTAssertNil(result)
  }

  func testPhotoThumbnailIsBoundedAndDoesNotChangeOriginal() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
    }
    let bytes = try XCTUnwrap(image.pngData())
    let original = MIRAPickedMedia(data: bytes, kind: .image, fileName: "capture.png", mimeType: "image/png")
    let loaded = await CaptroCaptureReview.thumbnail(original, maxPixelSize: 128)
    let thumbnail = try XCTUnwrap(loaded)
    XCTAssertEqual(thumbnail.size.width, 128)
    XCTAssertEqual(thumbnail.size.height, 96)
    XCTAssertEqual(original.data, bytes)
  }

  func testUnreadableVideoThumbnailCleansUpItsTemporaryFile() async throws {
    let folder = FileManager.default.temporaryDirectory
    func files() throws -> Set<String> {
      Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)
        .filter { $0.hasPrefix("captro-capture-thumbnail-") })
    }
    let before = try files()
    let thumbnail = await CaptroCaptureReview.thumbnail(MIRAPickedMedia(
      data: Data([0, 1, 2]), kind: .video, fileName: "invalid.mov", mimeType: "video/quicktime"
    ), maxPixelSize: 128)
    XCTAssertNil(thumbnail)
    XCTAssertEqual(try files(), before)
  }
}
