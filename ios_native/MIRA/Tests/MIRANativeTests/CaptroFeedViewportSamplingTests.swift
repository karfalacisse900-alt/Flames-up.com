import XCTest
import UIKit
@testable import MIRANative

/// These tests exercise sampling/identity and its work bound. They do not
/// establish frame rate or reproduce a physical iPhone's reported shaking.
@MainActor
final class CaptroFeedViewportSamplingTests: XCTestCase {
  private final class GestureScroll: UIScrollView {
    var simulatedTracking = false
    var simulatedDragging = false
    var simulatedDeceleration = false
    override var isTracking: Bool { simulatedTracking }
    override var isDragging: Bool { simulatedDragging }
    override var isDecelerating: Bool { simulatedDeceleration }
  }

  @MainActor
  private struct Fixture {
    let window: UIWindow
    let scroll: GestureScroll
    let owner: CaptroFeedViewport

    init(ids: [String]) {
      window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
      let controller = UIViewController()
      window.rootViewController = controller
      window.isHidden = false
      scroll = GestureScroll(frame: window.bounds)
      scroll.contentInsetAdjustmentBehavior = .never
      scroll.contentSize = CGSize(width: 390, height: 10_000)
      controller.view.addSubview(scroll)
      owner = CaptroFeedViewport()
      owner.updateOrder(ids)
    }

    @discardableResult
    func mount(_ id: String, y: CGFloat, height: CGFloat = 400) -> UIView {
      let marker = UIView(frame: CGRect(x: 0, y: y, width: 390, height: height))
      scroll.addSubview(marker)
      owner.register(marker, id: id)
      return marker
    }
  }

  func testSamplingVisitsMountedMarkersNotEveryLoadedPost() {
    let fixture = Fixture(ids: (0..<100_000).map { "post-\($0)" })
    defer { fixture.window.isHidden = true }
    fixture.mount("post-50001", y: 800)
    fixture.mount("post-50000", y: 400)
    fixture.mount("post-49999", y: 0)
    fixture.owner.sample()
    XCTAssertEqual(fixture.owner.debugLastVisitedMarkerCount, 3,
      "A scroll tick must not traverse 100,000 loaded IDs to find three lazy markers")
    XCTAssertEqual(fixture.owner.debugLastFrameCount, 3)
    XCTAssertEqual(fixture.owner.debugLastVisibleIDs, ["post-49999", "post-50000"],
      "Registration/dictionary order must not change the first-visible reading anchor")
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
  }

  func testUnchangedVisibilityDoesNotRepublishOrMoveTheScrollView() {
    let fixture = Fixture(ids: ["first", "second", "third"])
    defer { fixture.window.isHidden = true }
    fixture.mount("third", y: 800)
    fixture.mount("second", y: 400)
    fixture.mount("first", y: 0)
    var callbacks: [String?] = []
    fixture.owner.onVisible = { callbacks.append($0) }
    for _ in 0..<100 { fixture.owner.sample() }
    XCTAssertEqual(callbacks.count, 1)
    XCTAssertEqual(callbacks.first!, "first")
    XCTAssertEqual(fixture.owner.debugVisiblePublicationCount, 1)
    XCTAssertEqual(fixture.scroll.contentOffset.y, 0)
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)

    fixture.scroll.contentOffset.y = 400
    fixture.owner.sample()
    XCTAssertEqual(callbacks.count, 2)
    XCTAssertEqual(callbacks.last!, "second")
    XCTAssertEqual(fixture.scroll.contentOffset.y, 400)
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
  }

  func testPaginationAndFooterExtentChangesDoNotRequestRestorationDuringDeceleration() {
    let fixture = Fixture(ids: ["first", "reading", "next"])
    defer { fixture.window.isHidden = true }
    fixture.mount("first", y: 0, height: 1_000)
    fixture.mount("reading", y: 1_000, height: 600)
    fixture.mount("next", y: 1_600, height: 600)
    fixture.scroll.contentOffset.y = 1_123
    fixture.owner.sample()
    fixture.scroll.simulatedDeceleration = true
    fixture.owner.updateOrder(["first", "reading", "next"] + (0..<80).map { "page-\($0)" })
    fixture.scroll.contentSize.height += 30_000
    fixture.owner.sample()
    XCTAssertEqual(fixture.scroll.contentOffset.y, 1_123)
    XCTAssertEqual(fixture.owner.debugLastVisitedMarkerCount, 3)
    XCTAssertEqual(fixture.owner.debugLastVisibleIDs.first, "reading")
    fixture.scroll.simulatedDeceleration = false
    fixture.scroll.contentSize.height -= 60 // A footer disappears at end of feed.
    fixture.owner.sample()
    XCTAssertEqual(fixture.scroll.contentOffset.y, 1_123)
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty,
      "This verifies viewport ownership only; the lazy layout needs a separate runtime pagination check")
  }

  func testDetachedUnknownAndReusedMarkersCannotWinVisibility() {
    let fixture = Fixture(ids: ["post"])
    defer { fixture.window.isHidden = true }
    let old = fixture.mount("post", y: 0)
    fixture.mount("not-in-order", y: 0)
    fixture.owner.sample()
    XCTAssertEqual(fixture.owner.debugLastVisibleIDs, ["post"])
    XCTAssertEqual(fixture.owner.debugLastFrameCount, 1)
    old.removeFromSuperview()
    fixture.owner.sample()
    XCTAssertEqual(fixture.owner.debugLastFrameCount, 0)
    fixture.mount("post", y: 200)
    fixture.owner.sample()
    XCTAssertEqual(fixture.owner.debugLastFrameCount, 1)
    XCTAssertEqual(fixture.owner.debugLastVisibleIDs, ["post"])
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
  }

  func testTopAndIdleHintRejectsMotionHiddenViewsAndPendingNavigation() {
    let fixture = Fixture(ids: ["post"])
    defer { fixture.window.isHidden = true }
    XCTAssertFalse(fixture.owner.isAtTopAndIdle, "An unattached owner has no position evidence")
    fixture.mount("post", y: 0)
    fixture.owner.sample()
    XCTAssertTrue(fixture.owner.isAtTopAndIdle)
    fixture.scroll.contentInset.top = 20
    fixture.scroll.contentOffset.y = -20
    XCTAssertTrue(fixture.owner.isAtTopAndIdle)
    fixture.scroll.contentOffset.y = -40
    XCTAssertFalse(fixture.owner.isAtTopAndIdle, "Rubber-banding is not a stable top position")
    fixture.scroll.contentOffset.y = -20
    fixture.scroll.simulatedTracking = true
    XCTAssertFalse(fixture.owner.isAtTopAndIdle)
    fixture.scroll.simulatedTracking = false
    fixture.scroll.simulatedDragging = true
    XCTAssertFalse(fixture.owner.isAtTopAndIdle)
    fixture.scroll.simulatedDragging = false
    fixture.scroll.simulatedDeceleration = true
    XCTAssertFalse(fixture.owner.isAtTopAndIdle)
    fixture.scroll.simulatedDeceleration = false
    fixture.owner.setActive(false)
    XCTAssertFalse(fixture.owner.isAtTopAndIdle)
    fixture.owner.setActive(true)
    XCTAssertTrue(fixture.owner.isAtTopAndIdle)
    fixture.owner.select("following")
    XCTAssertFalse(fixture.owner.isAtTopAndIdle, "A pending feed selection owns its own one-shot restoration")
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
  }

  func testDiagnosticHistoryIsOptInBoundedAndCarriesGeometryNotContent() throws {
    let fixture = Fixture(ids: ["stable-id"])
    defer { fixture.window.isHidden = true }
    fixture.mount("stable-id", y: 0)
    fixture.owner.debugRecordsSamples = false
    fixture.owner.sample()
    XCTAssertEqual(fixture.owner.debugTrace, "[]")
    fixture.owner.debugRecordsSamples = true
    for _ in 0..<300 { fixture.owner.sample() }
    let samples = try JSONDecoder().decode([CaptroFeedViewport.SampleMetrics].self,
      from: Data(fixture.owner.debugTrace.utf8))
    XCTAssertEqual(samples.count, 256)
    let last = try XCTUnwrap(samples.last)
    XCTAssertEqual(last.loadedIDs, 1)
    XCTAssertEqual(last.visitedMarkers, 1)
    XCTAssertEqual(last.rows.first?.id, "stable-id")
    XCTAssertEqual(last.rows.first?.height, 400)
    XCTAssertEqual(last.offsetY, 0)
    XCTAssertEqual(last.visibleCallbackMilliseconds, 0)
    XCTAssertGreaterThanOrEqual(last.milliseconds, last.geometryMilliseconds)
    XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
    XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
  }

  func testFrameCadenceCountsHitchesOnlyInsideObservedInteractionSegments() {
    var metrics = CaptroFeedViewport.FrameCadenceMetrics()
    let budget = 1.0 / 60
    metrics.record(timestamp: 1, budget: budget)
    metrics.record(timestamp: 1 + budget, budget: budget)
    metrics.record(timestamp: 1 + budget + 0.04, budget: budget)
    metrics.record(timestamp: 1 + budget + 0.16, budget: budget)
    metrics.pause()
    metrics.record(timestamp: 100, budget: budget)
    metrics.record(timestamp: 100 + budget, budget: budget)
    XCTAssertEqual(metrics.intervals, 4)
    XCTAssertEqual(metrics.overOneAndHalfBudget, 2)
    XCTAssertEqual(metrics.overTwoBudgets, 2)
    XCTAssertEqual(metrics.over50Milliseconds, 1)
    XCTAssertEqual(metrics.over100Milliseconds, 1)
    XCTAssertEqual(metrics.maximumGapMilliseconds, 120, accuracy: 0.001,
      "Time spent idle/on another screen must not be recorded as a scroll hitch")
  }

  func testSamplingCostWithThreeMarkersAtOneHundredAndOneHundredThousandLoadedIDs() {
    // A same-process measurement of the real viewport sampler's scaling, not
    // an FPS assertion. The runtime fixture separately measures lazy scrolling.
    var measurements: [String] = []
    for count in [100, 100_000] {
      let fixture = Fixture(ids: (0..<count).map { "post-\($0)" })
      fixture.mount("post-0", y: 0)
      fixture.mount("post-1", y: 400)
      fixture.mount("post-2", y: 800)
      fixture.owner.debugRecordsSamples = false
      fixture.owner.sample() // Warm actor/geometry and publish initial visibility.
      let start = ProcessInfo.processInfo.systemUptime
      for _ in 0..<1_000 { fixture.owner.sample() }
      let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
      measurements.append("loaded=\(count),mounted=3,samples=1000,totalMs=\(elapsed),maxSampleMs=\(fixture.owner.debugMaxSampleMilliseconds)")
      XCTAssertEqual(fixture.owner.debugLastVisitedMarkerCount, 3)
      XCTAssertEqual(fixture.owner.debugVisiblePublicationCount, 1)
      XCTAssertTrue(fixture.owner.debugCommands.isEmpty)
      fixture.window.isHidden = true
    }
    let attachment = XCTAttachment(string: measurements.joined(separator: "\n"))
    attachment.name = "viewport-mounted-sampling-scaling-not-frame-rate"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testLegacyAndMountedCandidateEnumerationBenchmark() {
    // Compare the old/new candidate-collection algorithms using identical
    // UIKit markers on one simulator process. This deliberately excludes
    // restoration, playback callbacks and actual scrolling; it is not an
    // assertion that the old path caused a visible hitch.
    var measurements: [String] = []
    for loadedCount in [100, 1_000, 100_000] {
      for mountedCount in [3, 12] {
        let ids = (0..<loadedCount).map { "post-\($0)" }
        let fixture = Fixture(ids: ids)
        var markers: [String: UIView] = [:]
        let indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        for index in (0..<mountedCount).reversed() {
          let id = ids[index * (loadedCount / mountedCount)]
          markers[id] = fixture.mount(id, y: CGFloat(index) * 400)
        }
        func legacyCandidates() -> [(String, CGRect)] {
          let live = markers.filter { $0.value.window != nil && $0.value.isDescendant(of: fixture.scroll) }
          return ids.compactMap { id in
            guard let view = live[id] else { return nil }
            return (id, view.convert(view.bounds, to: fixture.scroll))
          }
        }
        func mountedCandidates() -> [(String, CGRect)] {
          var result: [(String, Int, CGRect)] = []
          for (id, view) in markers {
            guard view.window != nil, view.isDescendant(of: fixture.scroll), let index = indexByID[id] else { continue }
            result.append((id, index, view.convert(view.bounds, to: fixture.scroll)))
          }
          result.sort { $0.1 < $1.1 }
          return result.map { ($0.0, $0.2) }
        }
        let before = legacyCandidates(), after = mountedCandidates()
        XCTAssertEqual(before.map { $0.0 }, after.map { $0.0 })
        XCTAssertEqual(before.map { $0.1 }, after.map { $0.1 })
        func elapsed(_ work: () -> [(String, CGRect)]) -> Double {
          let start = ProcessInfo.processInfo.systemUptime
          var total = 0
          for _ in 0..<100 { total += work().count }
          XCTAssertEqual(total, mountedCount * 100)
          return (ProcessInfo.processInfo.systemUptime - start) * 1000
        }
        let legacyMs = elapsed(legacyCandidates)
        let mountedMs = elapsed(mountedCandidates)
        measurements.append("loaded=\(loadedCount),mounted=\(mountedCount),iterations=100,legacyCandidateMs=\(legacyMs),mountedCandidateMs=\(mountedMs)")
        fixture.window.isHidden = true
      }
    }
    let attachment = XCTAttachment(string: measurements.joined(separator: "\n"))
    attachment.name = "viewport-candidate-before-after-not-frame-rate"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
