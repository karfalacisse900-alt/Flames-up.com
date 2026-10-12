import XCTest
@testable import MIRANative

final class CaptroMediaGeometryTests: XCTestCase {
  private func framedPost(_ ratio: Double, title: String = "Opening", reversed: Bool = false) throws -> MIRAPost {
    let urls = reversed ? ["b", "a"] : ["a", "b"]
    let dimensions = urls.map { name in
      ["width": 1080, "height": 1920, "framing": ["version": 1,
        "source_aspect_ratio": 0.5625, "display_aspect_ratio": ratio,
        "crop_x": 0.5, "crop_y": name == "a" ? 0.2 : 0.8]] as [String: Any]
    }
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject:
      ["id": "cached-framing", "title": title,
       "images": urls.map { "https://example.com/\($0).jpg?token=\(title)" }, "media_dimensions": dimensions]))
  }

  @MainActor
  func testDelayedDetailsRefreshPreservesOpeningGeometryButUpdatesContent() async throws {
    let opening = try framedPost(0.75)
    let fresh = try framedPost(16.0 / 9, title: "Refreshed")
    let model = PostDetailModel(post: opening, api: MIRAAPIClient())
    let started = expectation(description: "Details refresh started")
    var pending: CheckedContinuation<MIRAPost, Error>?
    model.testPostLoader = {
      try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
    }
    let refresh = Task { await model.refreshPost() }
    await fulfillment(of: [started], timeout: 3)
    let before = model.mediaSnapshot.geometry(post: model.post, index: 0)
    pending?.resume(returning: fresh)
    await refresh.value
    XCTAssertEqual(model.post.title, "Refreshed")
    XCTAssertEqual(model.mediaSnapshot.geometry(post: model.post, index: 0), before)
    XCTAssertEqual(before, opening.mediaGeometry(at: 0))
    // Deliberate edits are different from a background refresh.
    model.applyPostRecord(fresh)
    XCTAssertEqual(model.mediaSnapshot.geometry(post: model.post, index: 0).displayAspectRatio, 16.0 / 9)
  }

  func testSnapshotUsesMediaIdentityAcrossURLRefreshAndReordering() throws {
    let opening = try framedPost(0.75)
    let fresh = try framedPost(1, title: "NewToken", reversed: true)
    let snapshot = CaptroPostMediaSnapshot(post: opening)
    XCTAssertEqual(snapshot.geometry(post: fresh, index: 1), opening.mediaGeometry(at: 0))
    XCTAssertEqual(snapshot.geometry(post: fresh, index: 0), opening.mediaGeometry(at: 1))
  }

  func testOrientationSurvivesAPIDecodingAndDiskRoundTrip() throws {
    let data = Data("""
      {"width":1080,"height":1920,"source_orientation":6,"source_pixel_width":1920,"source_pixel_height":1080,"rotation_degrees":90}
      """.utf8)
    for strategy: JSONDecoder.KeyDecodingStrategy in [.useDefaultKeys, .convertFromSnakeCase] {
      let decoder = JSONDecoder(); decoder.keyDecodingStrategy = strategy
      let dimension = try decoder.decode(MIRAMediaDimension.self, from: data)
      let cached = try JSONDecoder().decode(MIRAMediaDimension.self, from: JSONEncoder().encode(dimension))
      XCTAssertEqual(cached.sourceOrientation, 6)
      XCTAssertEqual(cached.sourcePixelWidth, 1920)
      XCTAssertEqual(cached.sourcePixelHeight, 1080)
      XCTAssertEqual(cached.rotationDegrees, 90)
    }
  }

  func testLegacyNYPLFormatWinsOverUnrotatedSourceDimensions() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let post = try decoder.decode(MIRAPost.self, from: Data("""
    {"id":"legacy-nypl","images":["https://example.com/library.jpg"],"media_dimensions":[
      {"width":4032,"height":3024,"original_width":4032,"original_height":3024,
       "display_aspect_ratio":0.75,"feed_aspect_ratio":0.75,"format":"3:4"}]}
    """.utf8))
    let geometry = post.mediaGeometry(at: 0)
    XCTAssertEqual(geometry.displayAspectRatio, 0.75)
    XCTAssertFalse(geometry.usesSourceCoordinates, "Do not double-crop an EXIF-oriented legacy image using untrusted source dimensions")
    let size = geometry.size(width: 390)
    XCTAssertEqual(geometry.sourceRect(in: size), CGRect(origin: .zero, size: size))
    XCTAssertEqual(size.height, 520)
  }
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
