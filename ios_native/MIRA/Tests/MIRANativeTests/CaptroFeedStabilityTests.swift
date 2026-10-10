import XCTest
import AVFoundation
import Combine
@testable import MIRANative

@MainActor
final class CaptroFeedStabilityTests: XCTestCase {
  private func post(_ id: String, likes: Int = 0) throws -> MIRAPost {
    try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject:
      ["id": id, "likesCount": likes, "images": ["https://example.com/\(id).jpg"]]))
  }

  func testBackgroundKeepsOrderAndDefersNewPosts() throws {
    let original = try (0..<40).map { try post("p\($0)") }
    let refresh = try [post("new"), post("p12", likes: 99), post("p1", likes: 2)]
    let result = CaptroFeedReconciliation.background(existing: original, fresh: refresh)
    XCTAssertEqual(result.map(\.id), original.map(\.id))
    XCTAssertEqual(result[12].likesCount, 99)
    XCTAssertEqual(result[12].feedFrameHeightToWidthRatio, original[12].feedFrameHeightToWidthRatio)
    XCTAssertEqual(CaptroFeedReconciliation.unique(original + original).count, 40)
  }

  func testMediaIdentitySurvivesSignedURLRefreshAndWritingReorder() throws {
    XCTAssertEqual(MIRAPost.mediaIdentity("https://example.com/a.jpg?token=old"),
      MIRAPost.mediaIdentity("https://example.com/a.jpg?token=new"))
    var first = try post("a")
    var writing = CaptroMediaWriting(); writing.text = "A ONLY"
    first.editorOverlays = [CaptroMediaWritingEnvelope(type: "media_writing", mediaIndex: 0, writing: writing)]
    first = first.bindingWritingIdentities()
    var reordered = try JSONDecoder().decode(MIRAPost.self, from: Data("""
      {"id":"a","images":["https://example.com/b.jpg","https://example.com/a.jpg"]}
      """.utf8))
    reordered.editorOverlays = first.editorOverlays
    XCTAssertNil(reordered.mediaWriting(at: 0))
    XCTAssertEqual(reordered.mediaWriting(at: 1)?.text, "A ONLY")
    let roundTrip = try JSONDecoder().decode(MIRAPost.self, from: JSONEncoder().encode(reordered))
    XCTAssertEqual(roundTrip.mediaWriting(at: 1)?.text, "A ONLY")
  }

  func testLateForYouResponseCannotReplaceFollowing() async throws {
    let model = MainFeedModel(api: MIRAAPIClient())
    model.configureGuestMode(true)
    var requests: [String: CheckedContinuation<[MIRAPost], Error>] = [:]
    let firstStarted = expectation(description: "for you requested")
    let secondStarted = expectation(description: "following requested")
    model.testPageLoader = { scope, _ in
      try await withCheckedThrowingContinuation { continuation in
        requests[scope] = continuation
        if scope == "for_you" { firstStarted.fulfill() } else { secondStarted.fulfill() }
      }
    }
    let initial = Task { await model.load() }
    await fulfillment(of: [firstStarted], timeout: 3)
    model.selectFeedSection(.following)
    await fulfillment(of: [secondStarted], timeout: 3)
    let accepted = expectation(description: "following accepted")
    let subscription = model.$posts.filter { $0.map(\.id) == ["following"] }.prefix(1).sink { _ in accepted.fulfill() }
    requests.removeValue(forKey: "following")?.resume(returning: [try post("following")])
    await fulfillment(of: [accepted], timeout: 5)
    requests.removeValue(forKey: "for_you")?.resume(returning: [try post("stale")])
    await initial.value
    subscription.cancel()
    XCTAssertEqual(model.posts.map(\.id), ["following"])
  }

  func testSinglePlayerOwnershipAndLateRelease() {
    let first = AVPlayer(), second = AVPlayer()
    MIRAPlaybackCoordinator.activateVideo(first, id: "first")
    MIRAPlaybackCoordinator.activateVideo(second, id: "second")
    XCTAssertTrue(first.isMuted)
    XCTAssertEqual(first.rate, 0)
    MIRAPlaybackCoordinator.releaseVideo(first)
    XCTAssertTrue(MIRAPlaybackCoordinator.ownsVideo(second))
    MIRAPlaybackCoordinator.releaseVideo(second)
    XCTAssertFalse(MIRAPlaybackCoordinator.ownsVideo(second))
  }

  func testSupportedHomeFramesAndUnknownMetadataAreDeterministic() {
    for ratio: CGFloat in [1, 1.25, 4.0 / 3, 9.0 / 16] {
      XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(ratio), ratio, accuracy: 0.001)
    }
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(16.0 / 9), 1.25)
    XCTAssertEqual(MIRAMediaSizing.homeDisplayRatio(3), 1.25)
    XCTAssertEqual(MIRAMediaSizing.mainFeedDisplayRatio(for: [], aspectRatios: []), 1.25)
    XCTAssertEqual(MIRAMediaSizing.mainFeedDisplayRatio(for: [], aspectRatios: [1.25, 0.5625]), 1.25)
  }
}
