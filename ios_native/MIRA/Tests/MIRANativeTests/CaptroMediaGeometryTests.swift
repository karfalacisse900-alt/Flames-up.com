import XCTest
@testable import MIRANative

final class CaptroMediaGeometryTests: XCTestCase {
  func testSupportedFormatsAndTallUploadDefault() {
    for ratio in CaptroPostMediaGeometry.ratios {
      XCTAssertEqual(CaptroPostMediaGeometry.selectedRatio(for: ratio), ratio, accuracy: 0.00001)
    }
    XCTAssertEqual(CaptroPostMediaGeometry.selectedRatio(for: 9/16), 0.8)
    XCTAssertEqual(CaptroPostMediaGeometry.selectedRatio(for: .nan), 0.8)
  }
  func testSharedCropCompositionAtDifferentDisplayWidths() {
    for ratio in CaptroPostMediaGeometry.ratios {
      let geometry = CaptroPostMediaGeometry(sourceAspectRatio: 9/16, displayAspectRatio: ratio, cropY: 0.82)
      let reference = geometry.sourceRect(in: geometry.size(width: 390))
      for width: CGFloat in [160, 320, 430, 768] {
        let size = geometry.size(width: width)
        let rect = geometry.sourceRect(in: size)
        XCTAssertEqual(size.width / size.height, ratio, accuracy: 0.00001)
        XCTAssertEqual(rect.minY / width, reference.minY / 390, accuracy: 0.00001)
        XCTAssertEqual(rect.height / width, reference.height / 390, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(rect.height + 0.001, size.height)
        XCTAssertGreaterThanOrEqual(rect.width + 0.001, size.width)
      }
    }
  }
  func testPersistedCropRoundTripAndStableMixedCarousel() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let post = try decoder.decode(MIRAPost.self, from: Data("""
    {"id":"geometry", "images":["https://example.com/a.jpg","https://example.com/b.mp4"],
    "media_dimensions":[
      {"width":1080,"height":1920,"framing":{"version":1,"source_aspect_ratio":0.5625,"display_aspect_ratio":0.8,"crop_x":0.5,"crop_y":0.9}},
      {"width":1920,"height":1080,"framing":{"version":1,"source_aspect_ratio":1.7777777777777777,"display_aspect_ratio":0.8,"crop_x":0.2,"crop_y":0.5}}
    ]}
    """.utf8))
    let saved = try JSONDecoder().decode(MIRAPost.self, from: JSONEncoder().encode(post))
    for index in 0...1 {
      XCTAssertEqual(post.mediaGeometry(at: index), saved.mediaGeometry(at: index))
      XCTAssertEqual(saved.mediaGeometry(at: index).displayAspectRatio, 0.8)
      XCTAssertEqual(saved.mediaGeometry(at: index).size(width: 390).height, 487.5)
    }
    XCTAssertEqual(saved.mediaGeometry(at: 0).cropY, 0.9)
    XCTAssertEqual(saved.mediaGeometry(at: 1).cropX, 0.2)
  }
  func testMissingMetadataIsDeterministicNotDownloadDriven() throws {
    let post = try JSONDecoder().decode(MIRAPost.self, from: Data("{\"id\":\"legacy\",\"images\":[\"https://example.com/a.jpg\"]}".utf8))
    XCTAssertEqual(post.mediaGeometry(at: 0).displayAspectRatio, 0.8)
    XCTAssertEqual(post.feedFrameHeightToWidthRatio, 1.25)
  }
}
