import Foundation
import XCTest
@testable import MIRANative

@MainActor
final class CaptroReliabilityTests: XCTestCase {
  private actor DelayedStreams {
    var requests: [CheckedContinuation<MIRAStreamPlaybackInfo, Error>] = []
    let started: XCTestExpectation
    let firstStarted: XCTestExpectation?
    init(started: XCTestExpectation, firstStarted: XCTestExpectation? = nil) {
      self.started = started
      self.firstStarted = firstStarted
    }
    func resolve(_ uid: String) async throws -> MIRAStreamPlaybackInfo {
      try await withCheckedThrowingContinuation { continuation in
        requests.append(continuation)
        if requests.count == 1 { firstStarted?.fulfill() }
        started.fulfill()
      }
    }
    // Deliberately ignores cancellation, reproducing a completion already
    // delivered by a network/cache layer when its viewing context changes.
    func complete(_ index: Int, uid: String) {
      requests[index].resume(returning: MIRAStreamPlaybackInfo(uid: uid,
        hls: "https://localhost/\(uid).m3u8", dash: nil, thumbnail: nil, ready: true))
    }
  }

  func testObsoleteNeighborhoodCannotPreparePlayerAfterLateResponse() async throws {
    let started = expectation(description: "two stream requests")
    started.expectedFulfillmentCount = 2
    let firstStarted = expectation(description: "first stream request")
    let resolver = DelayedStreams(started: started, firstStarted: firstStarted)
    let manager = MIRAVideoPrewarmManager(notificationCenter: NotificationCenter(), resolve: { try await resolver.resolve($0) })
    manager.prewarm(urls: ["cfstream:first"])
    let first = try XCTUnwrap(manager.pendingTasksForTesting["cfstream:first"])
    // Let the first request enter its resolver before changing neighborhoods.
    await fulfillment(of: [firstStarted], timeout: 3)
    manager.prewarm(urls: ["cfstream:second"])
    let second = try XCTUnwrap(manager.pendingTasksForTesting["cfstream:second"])
    await fulfillment(of: [started], timeout: 3)
    await resolver.complete(0, uid: "first"); await first.value
    XCTAssertNil(manager.streamInfo(for: "cfstream:first"))
    XCTAssertTrue(manager.preparedKeysForTesting.isEmpty)
    XCTAssertEqual(manager.pendingKeysForTesting, ["cfstream:second"])
    await resolver.complete(1, uid: "second"); await second.value
    XCTAssertEqual(manager.preparedKeysForTesting, ["cfstream:second"])
    manager.cancelPendingPrewarm()
  }

  func testReturningToSameURLRejectsOldRequestWithoutRemovingNewRequest() async throws {
    let started = expectation(description: "replacement stream requests")
    started.expectedFulfillmentCount = 2
    let firstStarted = expectation(description: "original stream request")
    let resolver = DelayedStreams(started: started, firstStarted: firstStarted)
    let manager = MIRAVideoPrewarmManager(notificationCenter: NotificationCenter(), resolve: { try await resolver.resolve($0) })
    manager.prewarm(urls: ["cfstream:same"])
    let old = try XCTUnwrap(manager.pendingTasksForTesting["cfstream:same"])
    await fulfillment(of: [firstStarted], timeout: 3)
    manager.prewarm(urls: [])
    XCTAssertTrue(old.isCancelled)
    manager.prewarm(urls: ["cfstream:same"])
    let replacement = try XCTUnwrap(manager.pendingTasksForTesting["cfstream:same"])
    await fulfillment(of: [started], timeout: 3)
    await resolver.complete(0, uid: "old"); await old.value
    XCTAssertEqual(manager.pendingKeysForTesting, ["cfstream:same"])
    XCTAssertTrue(manager.preparedKeysForTesting.isEmpty)
    await resolver.complete(1, uid: "new"); await replacement.value
    XCTAssertEqual(manager.streamInfo(for: "cfstream:same")?.uid, "new")
    manager.cancelPendingPrewarm()
  }

  func testNavigationPauseAndAccountChangeRejectLatePrewarm() async throws {
    for accountChange in [false, true] {
      let started = expectation(description: "pending stream")
      let resolver = DelayedStreams(started: started)
      let center = NotificationCenter()
      let manager = MIRAVideoPrewarmManager(notificationCenter: center, resolve: { try await resolver.resolve($0) })
      manager.prewarm(urls: ["cfstream:pending"])
      let pending = try XCTUnwrap(manager.pendingTasksForTesting["cfstream:pending"])
      await fulfillment(of: [started], timeout: 3)
      if accountChange { manager.resetForAccountChange() }
      else { center.post(name: .miraPlaybackShouldPause, object: "tab_changed") }
      XCTAssertTrue(pending.isCancelled)
      await resolver.complete(0, uid: "pending"); await pending.value
      XCTAssertNil(manager.streamInfo(for: "cfstream:pending"))
      XCTAssertTrue(manager.preparedKeysForTesting.isEmpty)
    }
  }

  func testDiagnosticArchiveRetainsStackEvidenceWithoutPrivateCustomFields() throws {
    let input = Data(#"{"timeStampBegin":"2026-10-13","hangDiagnostics":[{"hangDuration":"2 sec","callStackTree":{"callStacks":[{"callStackRootFrames":[{"binaryUUID":"app-build-id","binaryName":"Captro","offsetIntoBinaryTextSegment":42,"sampleCount":7}]}]},"applicationSpecificInformation":"private text","authorization":"private credential","exceptionReason":"private text"}],"signpostMetrics":[{"message":"private text"}],"unknownCustomField":"private text"}"#.utf8)
    let data = try XCTUnwrap(MIRAPerformanceDiagnosticArchive.sanitizedPayload(input))
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(text.contains("callStackRootFrames"))
    XCTAssertTrue(text.contains("offsetIntoBinaryTextSegment"))
    XCTAssertTrue(text.contains("hangDuration"))
    XCTAssertFalse(text.contains("private"))
    XCTAssertFalse(text.contains("signpostMetrics"))
    XCTAssertFalse(text.contains("unknownCustomField"))
    XCTAssertNil(MIRAPerformanceDiagnosticArchive.sanitizedPayload(Data("not JSON".utf8)))
  }

  func testDiagnosticArchiveIsBoundedAndDeduplicatesRepeatedPayloads() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = MIRAPerformanceDiagnosticArchive(directory: directory, maxFiles: 2, maxBytes: 1024)
    for index in 0..<5 {
      let payload = Data("{\"version\":\(index),\"hangDiagnostics\":[]}".utf8)
      archive.store(payload, kind: "diagnostics")
      archive.store(payload, kind: "diagnostics")
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.count, 2)
    XCTAssertLessThanOrEqual(try files.reduce(0) { try $0 + Data(contentsOf: $1).count }, 1024)
    XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }
}
