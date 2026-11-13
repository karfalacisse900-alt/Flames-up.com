import XCTest
@testable import MIRANative

@MainActor
final class CaptroTeaCacheTests: XCTestCase {
  private func entry(_ number: Int = 1) -> CaptroTeaEntry {
    let id = String(format: "00000000-0000-4000-8000-%012d", number)
    return CaptroTeaEntry(id: "business:" + id, kind: "business", name: "Business \(number)", status: "active",
                         color: "sage", timestamp: "2026-11-13T12:00:00Z", icon: nil,
                         destination: CaptroTeaDestination(source: "business", id: id))
  }
  private func details(_ item: CaptroTeaEntry) -> CaptroTeaDetails {
    CaptroTeaDetails(item: item, post: nil, commerce: nil, business: CaptroBusiness(), linkedEvents: nil)
  }

  func testFreshHitAndStaleRefreshKeepSnapshotAndForceBypassesFreshness() async throws {
    var clock = Date(); var requests = 0
    let item = entry(); let response = details(item)
    let store = CaptroTeaDetailStore(scope: { "a" }, now: { clock }) { _ in requests += 1; return response }
    _ = try await store.load(item); _ = try await store.load(item)
    XCTAssertEqual(requests, 1)
    clock = clock.addingTimeInterval(61)
    XCTAssertEqual(store.snapshot(for: item)?.item.id, item.id)
    _ = try await store.load(item); XCTAssertEqual(requests, 2)
    _ = try await store.load(item, force: true); XCTAssertEqual(requests, 3)
    clock = clock.addingTimeInterval(601)
    XCTAssertNil(store.snapshot(for: item))
  }

  func testConcurrentReadersShareWorkAndBothReceiveCorrectItem() async throws {
    var requests = 0
    let item = entry(); let response = details(item)
    let store = CaptroTeaDetailStore(scope: { "a" }) { _ in
      requests += 1
      try await Task.sleep(for: .milliseconds(40))
      return response
    }
    async let first = store.load(item)
    async let second = store.load(item)
    let results = try await [first, second]
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(results.map(\.item.id), [item.id, item.id])
  }

  func testOfflineKeepsSnapshotButAccessDenialEvictsIt() async throws {
    var error: Error?
    let item = entry(); let response = details(item)
    let store = CaptroTeaDetailStore(scope: { "a" }) { _ in
      if let error { throw error }; return response
    }
    _ = try await store.load(item)
    error = URLError(.notConnectedToInternet)
    do { _ = try await store.load(item, force: true); XCTFail("Expected offline failure") } catch {}
    XCTAssertNotNil(store.snapshot(for: item))
    error = MIRAAPIError.server(status: 403, code: "PRIVATE", detail: "Unavailable")
    do { _ = try await store.load(item, force: true); XCTFail("Expected access denial") } catch {}
    XCTAssertNil(store.snapshot(for: item))
    error = nil
    _ = try await store.load(item)
    XCTAssertNotNil(store.snapshot(for: item))
  }

  func testAccountSwitchRejectsLateResponseAndNeverHydratesPreviousAccount() async throws {
    var scope = "a:1"
    let item = entry(); let response = details(item)
    let store = CaptroTeaDetailStore(scope: { scope }) { _ in
      try await Task.sleep(for: .milliseconds(50)); return response
    }
    let pending = Task { try await store.load(item) }
    await Task.yield()
    scope = "b:2"
    XCTAssertNil(store.snapshot(for: item))
    do { _ = try await pending.value; XCTFail("Old account completion accepted") } catch {}
    _ = try await store.load(item)
    scope = "a:3"
    XCTAssertNil(store.snapshot(for: item))
  }

  func testMutationInvalidatesAndWrongDestinationCannotReplaceSnapshot() async throws {
    var requests = 0; var wrong = false
    let item = entry(); let response = details(item); let other = details(entry(2))
    let store = CaptroTeaDetailStore(scope: { "a" }) { _ in
      requests += 1; return wrong ? other : response
    }
    _ = try await store.load(item)
    store.invalidate()
    XCTAssertNotNil(store.snapshot(for: item))
    _ = try await store.load(item); XCTAssertEqual(requests, 2)
    wrong = true
    do { _ = try await store.load(item, force: true); XCTFail("Wrong destination accepted") } catch {}
    XCTAssertNil(store.snapshot(for: item))
  }

  func testDistinctItemsAndBoundedRetention() async throws {
    var responses: [String: CaptroTeaDetails] = [:]
    for number in 1...25 { let item = entry(number); responses[item.destination.detailPath!] = details(item) }
    var clock = Date()
    let store = CaptroTeaDetailStore(scope: { "a" }, now: { clock }) { responses[$0]! }
    for number in 1...25 {
      let item = entry(number)
      let result = try await store.load(item)
      XCTAssertEqual(result.item.id, item.id)
      clock = clock.addingTimeInterval(1)
    }
    XCTAssertNil(store.snapshot(for: entry(1)))
    XCTAssertEqual(store.snapshot(for: entry(25))?.item.name, "Business 25")
    store.invalidate(discard: true)
    XCTAssertNil(store.snapshot(for: entry(25)))
  }

  func testInvalidatedInFlightResultCannotOverwriteNewRead() async throws {
    let item = entry(); let response = details(item)
    var pending: CheckedContinuation<CaptroTeaDetails, Error>?
    var requests = 0
    let started = expectation(description: "First read is held")
    let store = CaptroTeaDetailStore(scope: { "a" }) { _ in
      requests += 1
      if requests == 1 {
        return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
      }
      return response
    }
    let old = Task { try await store.load(item) }
    await fulfillment(of: [started], timeout: 2)
    store.invalidate()
    _ = try await store.load(item)
    pending?.resume(returning: response)
    do { _ = try await old.value; XCTFail("Invalidated completion accepted") } catch {}
    XCTAssertEqual(requests, 2)
    XCTAssertEqual(store.snapshot(for: item)?.item.id, item.id)
  }
}
