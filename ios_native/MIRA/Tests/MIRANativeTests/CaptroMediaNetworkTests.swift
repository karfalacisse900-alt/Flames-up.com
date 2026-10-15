import AVFoundation
import XCTest
@testable import MIRANative

final class CaptroMediaNetworkTests: XCTestCase {
  private let source = "https://media.captro.app/source.jpg?token=kept"
  private func derivative(_ width: Int, source: String) -> String {
    "https://api.flames-up.com/cdn-cgi/image/width=\(width),fit=scale-down,quality=84/\(source)"
  }
  func testBothUserPreferenceAndLowDataModeRestrictWorkWithoutClassifyingWifi() {
    for budget in [MIRAMediaNetworkPolicy.Budget(dataSaver: true), .init(constrained: true)] {
      XCTAssertTrue(budget.reducesData)
      XCTAssertFalse(budget.permitsPrefetch)
      XCTAssertEqual(budget.maximumImageLoads, 3)
      XCTAssertEqual(budget.maximumImagePrefetches, 0)
      XCTAssertEqual(budget.maximumPreparedPlayers, 0)
      XCTAssertEqual(budget.imagePixelLimit, 720)
      XCTAssertEqual(budget.preferredVideoBitRate, 700_000)
    }
    let normal = MIRAMediaNetworkPolicy.Budget()
    XCTAssertTrue(normal.permitsPrefetch)
    XCTAssertEqual(normal.maximumImageLoads, 6)
    XCTAssertEqual(normal.maximumImagePrefetches, 2)
    XCTAssertEqual(normal.preferredVideoBitRate, 0)
  }
  func testOfflineAndMemoryPressureStopSpeculationNotVisibleAdmission() {
    for budget in [MIRAMediaNetworkPolicy.Budget(connected: false), .init(memoryPressure: true)] {
      XCTAssertFalse(budget.permitsPrefetch)
      XCTAssertGreaterThan(budget.maximumImageLoads, 0)
      XCTAssertEqual(budget.maximumPreparedPlayers, 0)
    }
  }
  func testOnlyUncroppedDerivativeOfExactSignedSourceIsAccepted() {
    let valid = derivative(1080, source: source)
    XCTAssertEqual(CaptroImageDelivery.uncropped(valid, of: source), valid)
    XCTAssertEqual(CaptroImageDelivery.uncropped(source, of: source), source)
    XCTAssertNil(CaptroImageDelivery.uncropped(valid.replacingOccurrences(of: "fit=scale-down", with: "fit=cover"), of: source))
    XCTAssertNil(CaptroImageDelivery.uncropped(valid.replacingOccurrences(of: "kept", with: "another"), of: source))
    XCTAssertNil(CaptroImageDelivery.uncropped(valid.replacingOccurrences(of: "api.flames-up.com", with: "other.invalid"), of: source))
    XCTAssertNil(CaptroImageDelivery.uncropped("https://imagedelivery.net/account/id/unverified-variant", of: source))
  }
  private func post(feeds: [String], thumbnails: [String]) throws -> MIRAPost {
    let object: [String: Any] = ["id": "delivery-test", "images": [source, "https://media.captro.app/b.jpg"],
      "feedMediaUrls": feeds, "thumbnailUrls": thumbnails,
      "mediaDimensions": [["width": 1080, "height": 1350], ["width": 1920, "height": 1080]]]
    return try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func testDataSaverChoosesThumbnailWithoutChangingIdentityOrCrop() throws {
    let feed = derivative(1080, source: source), thumb = derivative(480, source: source)
    let post = try post(feeds: [feed, ""], thumbnails: [thumb, ""])
    let identity = post.feedMediaIdentities, geometry = post.mediaGeometry(at: 0)
    XCTAssertEqual(post.imageDelivery(at: 0, dataSaver: false)?.display, feed)
    XCTAssertEqual(post.imageDelivery(at: 0, dataSaver: false)?.preview, thumb)
    XCTAssertEqual(post.imageDelivery(at: 0, dataSaver: true)?.display, thumb)
    XCTAssertNil(post.imageDelivery(at: 0, dataSaver: true)?.preview)
    XCTAssertEqual(post.feedMediaIdentities, identity)
    XCTAssertEqual(post.mediaGeometry(at: 0), geometry)
  }
  func testPartialDerivativeArrayCannotShiftOntoDifferentCarouselSlide() throws {
    let post = try post(feeds: [derivative(1080, source: source)], thumbnails: [derivative(480, source: source)])
    XCTAssertEqual(post.imageDelivery(at: 0, dataSaver: false)?.display, source)
    XCTAssertEqual(post.imageDelivery(at: 1, dataSaver: true)?.display, "https://media.captro.app/b.jpg")
    XCTAssertNil(post.imageDelivery(at: 1, dataSaver: false)?.preview)
    XCTAssertNil(post.imageDelivery(at: 8, dataSaver: false))
  }
  func testNativeBufferingAndDataSaverAreAppliedToRealPlayerItem() {
    let item = AVPlayerItem(url: URL(string: "https://video.invalid/manifest.m3u8")!)
    MIRAVideoBufferingPolicy.apply(to: item, budget: .init(constrained: true))
    XCTAssertEqual(item.preferredForwardBufferDuration, 0)
    XCTAssertEqual(item.preferredPeakBitRate, 700_000)
    XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 854, height: 854))
    XCTAssertFalse(item.canUseNetworkResourcesForLiveStreamingWhilePaused)
    MIRAVideoBufferingPolicy.apply(to: item, budget: .init())
    XCTAssertEqual(item.preferredPeakBitRate, 0)
  }
}
