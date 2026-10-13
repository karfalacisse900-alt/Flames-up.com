import XCTest
import AVFoundation
import Combine
import UIKit
import SwiftUI
@testable import MIRANative

@MainActor
final class CaptroFeedStabilityTests: XCTestCase {
  private final class LazyFixtureState: ObservableObject {
    @Published var loaded = false
    @Published var mounted = true
  }
  private struct LazyFixture: View {
    @ObservedObject var state: LazyFixtureState
    let owner: CaptroFeedViewport
    var body: some View {
      if state.mounted {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(0..<40, id: \.self) { index in
              ZStack {
                Color.gray
                if state.loaded { Text("Loaded \(index)") }
              }
              .frame(height: index.isMultiple(of: 2) ? 400 : 240)
              .background(CaptroFeedViewportMarker(owner: owner, postID: "lazy-\(index)", feed: "forYou"))
            }
          }
        }
      }
    }
  }

  func testActualLazyStackDelayedContentAndRemountDoNotReplayResumeAnchor() async throws {
    let state = LazyFixtureState(), owner = CaptroFeedViewport()
    owner.updateOrder((0..<40).map { "lazy-\($0)" })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let host = UIHostingController(rootView: LazyFixture(state: state, owner: owner))
    window.rootViewController = host; window.isHidden = false
    defer { window.isHidden = true }
    func nativeScroll(_ view: UIView) -> UIScrollView? {
      if let scroll = view as? UIScrollView, !scroll.isPagingEnabled { return scroll }
      return view.subviews.lazy.compactMap { nativeScroll($0) }.first
    }
    func layoutTurn() async {
      let ready = expectation(description: "SwiftUI layout turn")
      DispatchQueue.main.async { host.view.layoutIfNeeded(); ready.fulfill() }
      await fulfillment(of: [ready], timeout: 3)
    }
    await layoutTurn()
    let scroll = try XCTUnwrap(nativeScroll(host.view))
    scroll.contentOffset.y = 500
    await layoutTurn(); owner.sample()
    let before = scroll.contentOffset.y
    owner.setActive(false); state.loaded = true
    await layoutTurn()
    owner.setActive(true); owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, before, accuracy: 1)
    XCTAssertTrue(owner.debugCommands.isEmpty)
    owner.setActive(false); state.mounted = false; await layoutTurn()
    state.mounted = true; await layoutTurn()
    owner.cancelRestorationForUserInteraction() // A new touch while the lazy tree returns.
    owner.setActive(true); await layoutTurn(); owner.sample()
    XCTAssertTrue(owner.debugCommands.isEmpty, "Late lazy registration must not replay a cancelled restore")
  }

  func testResumeCannotClampSavedAnchorAgainstPartiallyMountedContent() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController(); window.rootViewController = controller; window.isHidden = false
    defer { window.isHidden = true }
    let scroll = UIScrollView(frame: window.bounds)
    scroll.contentInsetAdjustmentBehavior = .never
    controller.view.addSubview(scroll)
    scroll.contentSize = CGSize(width: 390, height: 4000)
    let owner = CaptroFeedViewport(); owner.updateOrder(["first", "target"])
    let first = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 1000))
    let target = UIView(frame: CGRect(x: 0, y: 1000, width: 390, height: 1000))
    scroll.addSubview(first); scroll.addSubview(target)
    owner.register(first, id: "first"); owner.register(target, id: "target")
    scroll.contentOffset.y = 1123; owner.sample(); owner.setActive(false)
    target.removeFromSuperview()
    scroll.contentSize.height = 1000 // Lazy target has not remounted yet.
    let before = scroll.contentOffset.y
    owner.setActive(true); owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, before, accuracy: 0.1,
      "Reactivation must not clamp against incomplete lazy content")
    XCTAssertTrue(owner.debugCommands.isEmpty, "No unsolicited command: \(owner.debugSummary)")
    scroll.contentSize.height = 4000; scroll.addSubview(target); owner.register(target, id: "target"); owner.sample()
    XCTAssertTrue(owner.debugCommands.isEmpty, "Late remount must not trigger a stale correction")
  }

  func testSurvivingHomeScrollViewRetainsItsNativeOffsetOnResume() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController()
    window.rootViewController = controller; window.isHidden = false
    defer { window.isHidden = true }
    let scroll = UIScrollView(frame: window.bounds)
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.contentSize = CGSize(width: 390, height: 3000)
    controller.view.addSubview(scroll)
    let owner = CaptroFeedViewport()
    owner.updateOrder(["first", "second", "third"])
    for (index, id) in ["first", "second", "third"].enumerated() {
      let marker = UIView(frame: CGRect(x: 0, y: CGFloat(index) * 1000, width: 390, height: 1000))
      scroll.addSubview(marker); owner.register(marker, id: id)
    }
    scroll.contentOffset.y = 1123; owner.sample()
    owner.setActive(false)
    scroll.contentOffset.y = 1400; owner.sample()
    owner.setActive(true); owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, 1400, accuracy: 0.1)
    XCTAssertTrue(owner.debugCommands.isEmpty, "Playback resumption must not seek")
    scroll.contentOffset.y = 1250; owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, 1250, accuracy: 0.1, "No repeating correction loop")
    owner.setActive(false)
    scroll.contentOffset.y = 1500
    owner.setActive(true)
    owner.cancelRestorationForUserInteraction(); owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, 1500, accuracy: 0.1, "A new drag cancels restoration")
  }

  private final class GestureScroll: UIScrollView {
    var simulatedDeceleration = false
    var simulatedTracking = false
    override var isDecelerating: Bool { simulatedDeceleration }
    override var isTracking: Bool { simulatedTracking }
  }

  func testRecreatedScrollWaitsForTargetAndRejectsDetachedCells() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController(); window.rootViewController = controller; window.isHidden = false
    defer { window.isHidden = true }
    let owner = CaptroFeedViewport(); owner.updateOrder(["first", "target"])
    let old = UIScrollView(frame: window.bounds); controller.view.addSubview(old)
    old.contentInsetAdjustmentBehavior = .never; old.contentSize = CGSize(width: 390, height: 4000)
    let target = UIView(frame: CGRect(x: 0, y: 1000, width: 390, height: 1000))
    old.addSubview(target); owner.register(target, id: "target")
    old.contentOffset.y = 1123; owner.sample(); owner.setActive(false)
    let replacement = UIScrollView(frame: window.bounds); controller.view.addSubview(replacement)
    replacement.contentInsetAdjustmentBehavior = .never; replacement.contentSize = CGSize(width: 390, height: 1000)
    let first = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 1000))
    replacement.addSubview(first); owner.register(first, id: "first")
    owner.setActive(true); owner.sample()
    XCTAssertEqual(replacement.contentOffset.y, 0, accuracy: 0.1)
    XCTAssertTrue(owner.debugCommands.isEmpty, "Old target still in a window belongs to the wrong scroll")
    replacement.contentSize.height = 4000
    replacement.addSubview(target); owner.register(target, id: "target"); owner.sample()
    XCTAssertEqual(replacement.contentOffset.y, 1123, accuracy: 0.1)
    XCTAssertEqual(owner.debugCommands.count, 1)
    XCTAssertEqual(owner.debugCommands.first?.reason, "scroll_view_recreated")
    replacement.contentOffset.y = 1200; owner.sample()
    XCTAssertEqual(replacement.contentOffset.y, 1200, accuracy: 0.1)
    XCTAssertEqual(owner.debugCommands.count, 1)
  }

  func testOldFeedCallbackCannotRestoreNewFeedAndDecelerationCancelsPendingSeek() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController(); window.rootViewController = controller; window.isHidden = false
    defer { window.isHidden = true }
    let scroll = GestureScroll(frame: window.bounds); controller.view.addSubview(scroll)
    scroll.contentInsetAdjustmentBehavior = .never; scroll.contentSize = CGSize(width: 390, height: 4000)
    let marker = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 4000)); scroll.addSubview(marker)
    let owner = CaptroFeedViewport(); owner.updateOrder(["shared"])
    owner.register(marker, id: "shared", feed: "forYou"); scroll.contentOffset.y = 1000; owner.sample()
    owner.select("following"); owner.updateOrder(["shared"])
    owner.register(marker, id: "shared", feed: "forYou"); owner.sample()
    XCTAssertTrue(owner.debugCommands.isEmpty, "A late old-scope marker cannot satisfy restoration")
    scroll.simulatedDeceleration = true
    owner.register(marker, id: "shared", feed: "following"); owner.sample()
    scroll.simulatedDeceleration = false; owner.sample()
    XCTAssertEqual(scroll.contentOffset.y, 1000, accuracy: 0.1)
    XCTAssertTrue(owner.debugCommands.isEmpty, "Do not wait until deceleration ends and then snap")
    owner.select("around"); owner.updateOrder(["shared"])
    scroll.simulatedTracking = true; owner.register(marker, id: "shared", feed: "around"); owner.sample()
    scroll.simulatedTracking = false; owner.sample()
    XCTAssertTrue(owner.debugCommands.isEmpty, "Touch tracking cancels before pan reaches began")
  }

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

  func testPaginationCoalescesAndAdvancesByServerCountNotUniqueCount() async throws {
    let model = MainFeedModel(api: MIRAAPIClient())
    model.configureGuestMode(true)
    let initial = try (0..<11).map { try post("p\($0)") } + [post("p0")]
    let next = try (10..<22).map { try post("p\($0)") }
    var offsets: [Int] = []
    var continuation: CheckedContinuation<[MIRAPost], Error>?
    let requested = expectation(description: "one page requested")
    model.testPageLoader = { _, skip in
      offsets.append(skip)
      if skip == 0 { return initial }
      return try await withCheckedThrowingContinuation { pending in
        continuation = pending; requested.fulfill()
      }
    }
    await model.load()
    let before = model.posts.map(\.id)
    let last = try XCTUnwrap(model.posts.last)
    let page = Task { await model.loadMoreIfNeeded(after: last) }
    await fulfillment(of: [requested], timeout: 3)
    await model.loadMoreIfNeeded(after: last)
    await model.loadMoreIfNeeded(after: last)
    XCTAssertEqual(offsets, [0, 12])
    continuation?.resume(returning: next)
    await page.value
    XCTAssertEqual(Array(model.posts.prefix(before.count)).map(\.id), before)
    XCTAssertEqual(Set(model.posts.map(\.id)).count, model.posts.count)
    XCTAssertEqual(model.posts.count, 22)
  }

  func testLegacyTextPageDoesNotStrandLaterMediaOrDeleteCachedRecords() async throws {
    let model = MainFeedModel(api: MIRAAPIClient())
    model.configureGuestMode(true)
    let legacy = try (0..<12).map { index in
      try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject:
        ["id": "legacy-\(index)", "postType": "general", "content": "Original saved writing"]))
    }
    let media = try [post("photo-a"), post("photo-b")]
    var offsets: [Int] = []
    model.testPageLoader = { _, skip in
      offsets.append(skip)
      return skip == 0 ? legacy : media
    }
    await model.load()
    XCTAssertTrue(model.posts.allSatisfy(\.isLegacyOrdinaryTextPost))
    await model.loadPastLegacyTextPage()
    XCTAssertEqual(offsets, [0, 12], "Offset must include hidden raw records")
    XCTAssertEqual(model.posts.filter { !$0.isLegacyOrdinaryTextPost }.map(\.id), ["photo-a", "photo-b"])
    XCTAssertEqual(model.posts.count, 14, "Home presentation must not delete legacy content")
  }

  func testPaginationFailureKeepsRecordsAndRequiresExplicitSameCursorRetry() async throws {
    let model = MainFeedModel(api: MIRAAPIClient())
    model.configureGuestMode(true)
    let initial = try (0..<12).map { try post("retry-\($0)") }
    let next = try post("next-page")
    var offsets: [Int] = []
    var failed = false
    model.testPageLoader = { _, skip in
      offsets.append(skip)
      if skip == 0 { return initial }
      if !failed { failed = true; throw URLError(.notConnectedToInternet) }
      return [next]
    }
    await model.load()
    let before = model.posts.map(\.id)
    await model.loadMoreIfNeeded(after: try XCTUnwrap(model.posts.last))
    XCTAssertNotNil(model.paginationError)
    XCTAssertEqual(model.posts.map(\.id), before)
    XCTAssertFalse(model.isLoadingMore)
    await model.loadMoreIfNeeded(after: try XCTUnwrap(model.posts.last))
    XCTAssertEqual(offsets, [0, 12], "Visibility callbacks must not hammer a failed cursor")
    await model.retryPagination()
    XCTAssertNil(model.paginationError)
    XCTAssertEqual(offsets, [0, 12, 12])
    XCTAssertEqual(Array(model.posts.prefix(before.count)).map(\.id), before)
    XCTAssertEqual(model.posts.last?.id, "next-page")
  }

  func testObsoletePaginationFailureCannotShowRetryInNewFeed() async throws {
    let model = MainFeedModel(api: MIRAAPIClient())
    model.configureGuestMode(true)
    let initial = try (0..<12).map { try post("before-\($0)") }
    var delayed: CheckedContinuation<[MIRAPost], Error>?
    let requested = expectation(description: "pagination started")
    model.testPageLoader = { scope, skip in
      if scope == "following" { return [] }
      if skip == 0 { return initial }
      return try await withCheckedThrowingContinuation { continuation in
        delayed = continuation; requested.fulfill()
      }
    }
    await model.load()
    let last = try XCTUnwrap(model.posts.last)
    let pending = Task { await model.loadMoreIfNeeded(after: last) }
    await fulfillment(of: [requested], timeout: 3)
    model.selectFeedSection(.following)
    delayed?.resume(throwing: URLError(.timedOut))
    await pending.value
    XCTAssertNil(model.paginationError)
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

  func testRepeatedPostersAndMissingRenditionsCannotShiftSlides() throws {
    let post = try JSONDecoder().decode(MIRAPost.self, from: Data("""
      {"id":"mixed","images":["https://example.com/a.jpg","https://example.com/b.mp4","https://example.com/c.jpg"],
       "feedMediaUrls":["https://example.com/only-one-rendition.jpg"],
       "posterUrls":["https://example.com/same.jpg","https://example.com/same.jpg","https://example.com/last.jpg"]}
      """.utf8))
    XCTAssertEqual(post.feedMediaURLs, post.mediaURLs)
    XCTAssertEqual(post.posterMediaURLs.count, 3)
    XCTAssertEqual(post.posterMediaURLs[2], "https://example.com/last.jpg")
    XCTAssertEqual(Set(post.feedMediaIdentities).count, 3)
  }
}
