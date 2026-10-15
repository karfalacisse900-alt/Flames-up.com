import XCTest
import UIKit
@testable import MIRANative

/// Controlled cold loads, not a claim about real-device FPS. Each loader stays
/// suspended until explicitly released, so concurrency is measured without
/// network timing or sleep-based work simulation.
final class CaptroImageLoadAdmissionTests: XCTestCase {
  private actor Loads {
    var active = Set<String>()
    var started: [String] = []
    var peak = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var open = false

    func load(_ key: String) async {
      started.append(key)
      active.insert(key)
      peak = max(peak, active.count)
      if !open { await withCheckedContinuation { continuations.append($0) } }
      active.remove(key)
    }
    func releaseAll() {
      open = true
      let pending = continuations
      continuations.removeAll()
      pending.forEach { $0.resume() }
    }
    func hasStarted(_ key: String) -> Bool { started.contains(key) }
    func startedCount(_ key: String) -> Int { started.filter { $0 == key }.count }
  }

  private func eventually(_ predicate: @escaping () async -> Bool,
                          file: StaticString = #filePath, line: UInt = #line) async {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if await predicate() { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Condition did not become true", file: file, line: line)
  }

  private func url(_ key: String) -> URL {
    URL(string: "https://image-admission-test.invalid/\(key).jpg")!
  }

  func testTenCarouselColdBatchesMeasureFortyLegacyLoadsVersusTwoSharedPrefetchLoads() async {
    let legacy = Loads()
    let old = Task {
      await withTaskGroup(of: Void.self) { rows in
        for row in 0..<10 {
          rows.addTask {
            await withTaskGroup(of: Void.self) { batch in
              // This is the previous four-child limit, applied independently
              // by every mounted carousel / feed-neighborhood invocation.
              for slide in 0..<4 { batch.addTask { await legacy.load("\(row)-\(slide)") } }
            }
          }
        }
      }
    }
    await eventually { await legacy.peak == 40 }
    await legacy.releaseAll()
    await old.value

    let admission = MIRAImageLoadAdmission()
    let current = Loads()
    let pipeline = MIRAImageLoadPipeline(admission: admission, testLoader: { remote in
      await current.load(remote.absoluteString)
      return nil
    })
    let requests = (0..<40).map { index in
      Task { await pipeline.image(for: url("cold-\(index)"), maxPixelSize: 560, priority: .prefetch) }
    }
    await eventually { admission.snapshot.active == 2 && admission.snapshot.waiting == 38 }
    let speculative = admission.snapshot
    XCTAssertEqual(speculative.peakPrefetch, 2)
    let measuredBefore = await legacy.peak
    let measuredAfter = await current.peak
    XCTAssertEqual(measuredBefore, 40)
    XCTAssertEqual(measuredAfter, 2)
    print("IMAGE_ADMISSION_CONTROLLED_COLD legacy_peak=\(measuredBefore) shared_prefetch_peak=\(measuredAfter) requests=40")
    await current.releaseAll()
    for request in requests { _ = await request.value }
    XCTAssertEqual(admission.snapshot.admitted, 40)
    XCTAssertEqual(admission.snapshot.active, 0)
    XCTAssertEqual(admission.snapshot.waiting, 0)
  }

  func testVisibleReadersPromoteQueuedPrefetchWithoutDuplicateWork() async {
    let admission = MIRAImageLoadAdmission(maximumActive: 2, maximumPrefetch: 1)
    let loads = Loads()
    let pipeline = MIRAImageLoadPipeline(admission: admission, testLoader: { remote in
      await loads.load(remote.absoluteString)
      return nil
    })
    let firstURL = url("first"), nextURL = url("next")
    let first = Task { await pipeline.image(for: firstURL, maxPixelSize: 560, priority: .prefetch) }
    await eventually { await loads.hasStarted(firstURL.absoluteString) }
    let background = Task { await pipeline.image(for: nextURL, maxPixelSize: 560, priority: .prefetch) }
    await eventually { admission.snapshot.waiting == 1 }
    let visible = Task { await pipeline.image(for: nextURL, maxPixelSize: 560) }
    await eventually { await loads.hasStarted(nextURL.absoluteString) }
    XCTAssertEqual(admission.snapshot.active, 2)
    XCTAssertEqual(admission.snapshot.activePrefetch, 1)
    background.cancel() // The visible reader still owns the promoted load.
    await loads.releaseAll()
    _ = await first.value; _ = await background.value; _ = await visible.value
    let occurrences = await loads.startedCount(nextURL.absoluteString)
    XCTAssertEqual(occurrences, 1, "Promotion must share the same URL/size load")
    XCTAssertEqual(admission.snapshot.active, 0)
  }

  func testCombinedVisibleAndPrefetchWorkNeverExceedsOneGlobalBudget() async {
    let admission = MIRAImageLoadAdmission()
    let loads = Loads()
    let pipeline = MIRAImageLoadPipeline(admission: admission, testLoader: { remote in
      await loads.load(remote.absoluteString)
      return nil
    })
    let background = (0..<12).map { index in
      Task { await pipeline.image(for: url("background-\(index)"), maxPixelSize: 560, priority: .prefetch) }
    }
    await eventually { admission.snapshot.activePrefetch == 2 && admission.snapshot.waiting == 10 }
    let visible = (0..<12).map { index in
      Task { await pipeline.image(for: url("visible-\(index)"), maxPixelSize: 560) }
    }
    await eventually { admission.snapshot.active == 6 && admission.snapshot.waiting == 18 }
    XCTAssertEqual(admission.snapshot.peakActive, 6)
    XCTAssertEqual(admission.snapshot.peakPrefetch, 2)
    await loads.releaseAll()
    for request in background + visible { _ = await request.value }
    XCTAssertLessThanOrEqual(admission.snapshot.peakActive, 6)
    XCTAssertLessThanOrEqual(admission.snapshot.peakPrefetch, 2)
    XCTAssertEqual(admission.snapshot.admitted, 24)
  }

  func testCancelledQueuedReadersDoNotStartAndActiveWorkRetainsPermitUntilFinished() async {
    let admission = MIRAImageLoadAdmission(maximumActive: 1, maximumPrefetch: 1)
    let loads = Loads()
    let pipeline = MIRAImageLoadPipeline(admission: admission, testLoader: { remote in
      // Deliberately ignores cancellation to model an ImageIO decode unwinding.
      await loads.load(remote.absoluteString)
      return nil
    })
    let first = Task { await pipeline.image(for: url("active"), maxPixelSize: 560) }
    await eventually { admission.snapshot.active == 1 }
    let queued = Task { await pipeline.image(for: url("cancelled"), maxPixelSize: 560) }
    await eventually { admission.snapshot.waiting == 1 }
    queued.cancel()
    _ = await queued.value
    XCTAssertEqual(admission.snapshot.cancelledWaiting, 1)
    first.cancel()
    XCTAssertEqual(admission.snapshot.active, 1, "Cancellation is not proof that active decode has ended")
    let replacement = Task { await pipeline.image(for: url("replacement"), maxPixelSize: 560) }
    await eventually { admission.snapshot.waiting == 1 }
    XCTAssertEqual(admission.snapshot.peakActive, 1)
    await loads.releaseAll()
    _ = await first.value; _ = await replacement.value
    let cancelledStarts = await loads.startedCount(url("cancelled").absoluteString)
    XCTAssertEqual(cancelledStarts, 0)
    XCTAssertEqual(admission.snapshot.peakActive, 1)
    XCTAssertEqual(admission.snapshot.active, 0)
  }

  func testCancellationBeforeWaitingDoesNotLeaveAnOrphanedPermit() async {
    let admission = MIRAImageLoadAdmission(maximumActive: 1, maximumPrefetch: 1)
    let id = UUID()
    admission.register(id, priority: .prefetch)
    admission.cancelWaiting(id)
    let granted = await admission.waitForSlot(id)
    XCTAssertFalse(granted)
    XCTAssertEqual(admission.snapshot.active, 0)
    XCTAssertEqual(admission.snapshot.waiting, 0)
  }

  func testPromotionBeforeDetachedLoadAwaitsItsSlotIsRetained() async {
    let admission = MIRAImageLoadAdmission(maximumActive: 2, maximumPrefetch: 1)
    let first = UUID(), promoted = UUID()
    admission.register(first, priority: .prefetch)
    let firstGranted = await admission.waitForSlot(first)
    XCTAssertTrue(firstGranted)
    admission.register(promoted, priority: .prefetch)
    admission.promote(promoted)
    let promotedGranted = await admission.waitForSlot(promoted)
    XCTAssertTrue(promotedGranted)
    XCTAssertEqual(admission.snapshot.active, 2)
    XCTAssertEqual(admission.snapshot.activePrefetch, 1)
    admission.release(first)
    admission.release(promoted)
    XCTAssertEqual(admission.snapshot.active, 0)
  }

  func testOldAccountScopeIsRejectedBeforeAnyImageWorkStarts() async {
    let admission = MIRAImageLoadAdmission()
    let loads = Loads()
    let pipeline = MIRAImageLoadPipeline(admission: admission, testLoader: { remote in
      await loads.load(remote.absoluteString)
      return nil
    })
    let result = await pipeline.image(for: url("old-account"), maxPixelSize: 560,
      expectedScope: "retired-account-\(UUID().uuidString)")
    XCTAssertNil(result)
    XCTAssertEqual(admission.snapshot.admitted, 0)
    XCTAssertEqual(admission.snapshot.waiting, 0)
  }
}
