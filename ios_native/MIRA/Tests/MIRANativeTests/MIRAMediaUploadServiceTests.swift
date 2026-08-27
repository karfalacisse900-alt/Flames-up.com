import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import MIRANative

final class MIRAMediaUploadServiceTests: XCTestCase {
  func testFallbackSniffingRecognizesPNGWithoutTrustingFilename() {
    let data = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    let result = pickedMediaKind(from: [], fallbackData: data)

    XCTAssertEqual(result.0, .image)
    XCTAssertEqual(result.2, "image/png")
    XCTAssertTrue(result.1.hasSuffix(".png"))
  }

  func testFallbackSniffingDoesNotMisclassifyHEICAsVideo() {
    let data = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
    let result = pickedMediaKind(from: [], fallbackData: data)

    XCTAssertEqual(result.0, .image)
    XCTAssertEqual(result.2, "image/heic")
    XCTAssertTrue(result.1.hasSuffix(".heic"))
  }

  func testFallbackSniffingRecognizesMP4AndWebMVideoContainers() {
    let mp4 = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d])
    let webM = Data([0x1a, 0x45, 0xdf, 0xa3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    let mp4Result = pickedMediaKind(from: [], fallbackData: mp4)
    let webMResult = pickedMediaKind(from: [], fallbackData: webM)

    XCTAssertEqual(mp4Result.0, .video)
    XCTAssertEqual(mp4Result.2, "video/mp4")
    XCTAssertEqual(webMResult.0, .video)
    XCTAssertEqual(webMResult.2, "video/webm")
  }
}
