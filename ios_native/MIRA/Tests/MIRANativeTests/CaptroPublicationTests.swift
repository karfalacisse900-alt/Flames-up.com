import XCTest
import Combine
@testable import MIRANative

@MainActor final class CaptroPublicationTests: XCTestCase {
  private func post(_ id: String, type: String = "general", media: [String] = ["https://example.invalid/photo.jpg"]) throws -> MIRAPost {
    try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject:
      ["id": id, "userId": "publication-test", "postType": type, "images": media, "content": "Test caption"]))
  }
  private func model() -> MainFeedModel {
    let model = MainFeedModel(api: CaptroComposerTestAPI.make())
    model.currentUserId = "publication-test"; model.currentUsername = "publication-test"
    model.testAutomaticPagination = false
    model.testPageSorter = { $0 }
    return model
  }
  private func receipt(_ post: MIRAPost) -> CaptroPublishedPost {
    CaptroPublishedPost(post: post, accountScope: MIRALocalJSONCache.currentScopeIdentifier)
  }

  func testServerEligiblePublicationInsertsAtIdleTopWithoutReplacingExistingFeed() async throws {
    let model = model(), old = try (0..<12).map { try post("old-\($0)") }
    var fresh = old
    model.testPageLoader = { _, _ in fresh }
    await model.load()
    for (index, type) in ["general", "cover", "club", "event", "meetup", "deal", "group", "offer", "ticket"].enumerated() {
      let published = try post("published-\(index)", type: type,
        media: index % 2 == 0 ? ["https://example.invalid/photo.jpg"] : ["https://example.invalid/clip.mp4", "https://example.invalid/photo.jpg"])
      fresh = [published] + old
      let before = model.posts.map(\.id)
      await model.reconcilePublication(receipt(published), canInsertNow: { true })
      XCTAssertEqual(model.posts.first?.id, published.id)
      XCTAssertEqual(Array(model.posts.dropFirst()).map(\.id), before)
      XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 12, "Local insertion isn't a consumed server row")
      await model.reconcilePublication(receipt(published), canInsertNow: { true })
      XCTAssertEqual(model.posts.filter { $0.id == published.id }.count, 1)
    }
  }

  func testLowerReadingPositionKeepsOrderUntilIntentionalRefresh() async throws {
    let model = model(), old = try (0..<12).map { try post("reading-\($0)") }, published = try post("new")
    var fresh = old
    model.testPageLoader = { _, _ in fresh }
    await model.load()
    fresh = [published] + old
    await model.reconcilePublication(receipt(published), canInsertNow: { false })
    XCTAssertEqual(model.posts.map(\.id), old.map(\.id))
    XCTAssertEqual(model.publicationNotice?.receipt.post.id, "new")
    XCTAssertEqual(model.publicationNotice?.state, .available)
    model.applyPublicationIfAtTop(false)
    XCTAssertEqual(model.posts.map(\.id), old.map(\.id))
    await model.load(forceRefresh: true, userInitiated: true)
    XCTAssertTrue(model.posts.contains { $0.id == "new" })
    XCTAssertEqual(Set(model.posts.map(\.id)).count, model.posts.count)
  }

  func testCreationReturnMayInsertOnlyAfterViewportIsIdleAtTop() async throws {
    let model = model(), old = try post("old"), published = try post("new")
    model.posts = [old]
    model.testPageLoader = { _, _ in [published, old] }
    await model.reconcilePublication(receipt(published), canInsertNow: { false })
    model.applyPublicationIfAtTop(true)
    model.applyPublicationIfAtTop(true)
    XCTAssertEqual(model.posts.map(\.id), ["new", "old"])
  }

  func testOutOfScopePublicationHasViewRouteWithoutBypassingFeedAuthority() async throws {
    let model = model(), old = try post("old"), published = try post("not-returned")
    model.posts = [old]
    model.testPageLoader = { _, _ in [old] }
    await model.reconcilePublication(receipt(published), canInsertNow: { true })
    XCTAssertEqual(model.posts.map(\.id), ["old"])
    XCTAssertEqual(model.publicationNotice?.state, .outsideFeed)
    XCTAssertEqual(model.publicationNotice?.receipt.post.id, published.id)
    model.applyPublicationIfAtTop(true)
    XCTAssertEqual(model.posts.map(\.id), ["old"])
  }

  func testPublicationFetchFailurePreservesPostsAndRetriesSafely() async throws {
    let model = model(), old = try post("old"), published = try post("new")
    model.posts = [old]
    model.testPageLoader = { _, _ in throw URLError(.notConnectedToInternet) }
    await model.reconcilePublication(receipt(published), canInsertNow: { true })
    XCTAssertEqual(model.posts.map(\.id), ["old"])
    XCTAssertEqual(model.publicationNotice?.state, .retry)
    model.testPageLoader = { _, _ in [published, old] }
    await model.reconcilePublication(receipt(published), canInsertNow: { true })
    XCTAssertEqual(model.posts.map(\.id), ["new", "old"])
  }

  func testOldFirstPageFailureCannotOverwriteConfirmedPublication() async throws {
    let model = model(), old = try post("old"), published = try post("new")
    model.posts = [old]
    let started = expectation(description: "old first page")
    var pending: CheckedContinuation<[MIRAPost], Error>?
    var calls = 0
    model.testPageLoader = { _, _ in
      calls += 1
      if calls == 1 { return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() } }
      return [published, old]
    }
    let request = Task { await model.load(forceRefresh: true) }
    await fulfillment(of: [started], timeout: 3)
    await model.reconcilePublication(receipt(published), canInsertNow: { true })
    pending?.resume(throwing: URLError(.timedOut))
    await request.value
    XCTAssertEqual(model.posts.map(\.id), ["new", "old"])
    XCTAssertNil(model.errorMessage)
    XCTAssertFalse(model.isLoading)
  }

  func testBackgroundRefreshCoalescesWhilePublicationEligibilityIsPending() async throws {
    let model = model(), old = try post("old"), published = try post("new")
    model.posts = [old]
    let started = expectation(description: "publication read")
    var pending: CheckedContinuation<[MIRAPost], Error>?
    var calls = 0
    model.testPageLoader = { _, _ in
      calls += 1
      return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
    }
    let reconcile = Task { await model.reconcilePublication(receipt(published), canInsertNow: { true }) }
    await fulfillment(of: [started], timeout: 3)
    await model.load(forceRefresh: true)
    await model.loadMoreIfNeeded(after: old)
    XCTAssertEqual(calls, 1)
    pending?.resume(returning: [published, old])
    await reconcile.value
    XCTAssertEqual(model.publicationNotice?.state, .available)
    XCTAssertEqual(model.posts.map(\.id), ["new", "old"])
  }

  func testAccountSwitchRejectsLatePublicationAndClearsReceipt() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "publication-a")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let model = model(), published = try post("account-a")
    let accountA = receipt(published)
    let started = expectation(description: "A eligibility read")
    var pending: CheckedContinuation<[MIRAPost], Error>?
    model.testPageLoader = { _, _ in try await withCheckedThrowingContinuation { pending = $0; started.fulfill() } }
    let request = Task { await model.reconcilePublication(accountA, canInsertNow: { true }) }
    await fulfillment(of: [started], timeout: 3)
    MIRALocalJSONCache.setAccountScope(userId: "publication-b")
    model.resetForAccountChange()
    pending?.resume(returning: [published]); await request.value
    XCTAssertTrue(model.posts.isEmpty)
    XCTAssertNil(model.publicationNotice)
    XCTAssertFalse(model.api.publications.record(published, expectedScope: accountA.accountScope))
    XCTAssertNil(model.api.publications.latest)
  }

  func testPublicationRejectsSuspendedOldPaginationWithoutConsumingItsCursor() async throws {
    let model = model(), old = try (0..<12).map { try post("old-page-\($0)") }
    let published = try post("published-during-page"), next = try post("next-page")
    var firstPage = old
    var requests: [Int] = []
    var delayed: CheckedContinuation<[MIRAPost], Error>?
    let started = expectation(description: "old pagination suspended")
    var holdNextPage = true
    model.testPageLoader = { _, skip in
      requests.append(skip)
      if skip == 0 { return firstPage }
      if holdNextPage {
        holdNextPage = false
        return try await withCheckedThrowingContinuation { delayed = $0; started.fulfill() }
      }
      return [published, next]
    }
    await model.load()
    let pagination = Task { await model.loadMoreIfNeeded(after: old.last!) }
    await fulfillment(of: [started], timeout: 3)
    firstPage = [published] + old
    await model.reconcilePublication(receipt(published), canInsertNow: { true })
    delayed?.resume(returning: [next])
    await pagination.value
    XCTAssertEqual(model.posts.map(\.id), [published.id] + old.map(\.id))
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 12,
      "The rejected request did not accept a page or consume its cursor")
    await model.retryPagination()
    XCTAssertEqual(requests, [0, 12, 0, 12])
    XCTAssertEqual(model.posts.filter { $0.id == published.id }.count, 1)
    XCTAssertEqual(model.posts.last?.id, next.id)
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 14)
    XCTAssertNil(model.paginationError)
    XCTAssertFalse(model.isLoadingMore)
  }

  func testTopInsertionDuringPageRankingRejectsDuplicateAndRetriesUnconsumedPage() async throws {
    let model = model(), old = try (0..<12).map { try post("old-rank-\($0)") }
    let published = try post("published-while-ranking"), next = try post("rank-next")
    var firstPage = old
    var offsets: [Int] = []
    model.testPageLoader = { _, skip in
      offsets.append(skip)
      return skip == 0 ? firstPage : [published, next]
    }
    await model.load()
    firstPage = [published] + old
    await model.reconcilePublication(receipt(published), canInsertNow: { false })
    let started = expectation(description: "pagination ranking suspended")
    var ranking: CheckedContinuation<[MIRAPost], Never>?
    var holdRanking = true
    model.testPageSorter = { records in
      guard holdRanking else { return records }
      holdRanking = false
      return await withCheckedContinuation { ranking = $0; started.fulfill() }
    }
    let pagination = Task { await model.loadMoreIfNeeded(after: old.last!) }
    await fulfillment(of: [started], timeout: 3)
    model.applyPublicationIfAtTop(true)
    ranking?.resume(returning: [published, next])
    await pagination.value
    XCTAssertEqual(model.posts.map(\.id), [published.id] + old.map(\.id))
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 12)
    XCTAssertTrue(model.canLoadMore)
    await model.retryPagination()
    XCTAssertEqual(offsets, [0, 0, 12, 12])
    XCTAssertEqual(model.posts.filter { $0.id == published.id }.count, 1)
    XCTAssertEqual(model.posts.last?.id, next.id)
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 14)
  }

  func testDeferredFeedCacheWriteCannotUseTheNextAccountsNamespace() async throws {
    let accountA = "cache-publication-a-\(UUID().uuidString)"
    let accountB = "cache-publication-b-\(UUID().uuidString)"
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    MIRALocalJSONCache.setAccountScope(userId: accountA)
    let expectedA = MIRALocalJSONCache.currentScopeIdentifier
    let oldA = try post("private-a"), ownB = try post("private-b")
    await MIRAAppCacheStore.shared.saveFeed([oldA], expectedScope: expectedA)
    let started = expectation(description: "cache write queued before logout")
    var release: CheckedContinuation<Void, Never>?
    let deferredWrite = Task {
      await withCheckedContinuation { release = $0; started.fulfill() }
      await MIRAAppCacheStore.shared.saveFeed([try post("late-a")], expectedScope: expectedA)
    }
    await fulfillment(of: [started], timeout: 3)
    MIRALocalJSONCache.setAccountScope(userId: accountB)
    await MIRAAppCacheStore.shared.saveFeed([ownB], expectedScope: MIRALocalJSONCache.currentScopeIdentifier)
    release?.resume()
    try await deferredWrite.value
    let accountBPosts = await MIRAAppCacheStore.shared.loadFeed()
    XCTAssertEqual(accountBPosts?.map(\.id), [ownB.id])
    MIRALocalJSONCache.setAccountScope(userId: accountA)
    let accountAPosts = await MIRAAppCacheStore.shared.loadFeed()
    XCTAssertEqual(accountAPosts?.map(\.id), [oldA.id], "Stale queued work is dropped, not written under another account")
    await MIRALocalJSONCache.remove(key: "native.main.feed.v7.cache_first")
    MIRALocalJSONCache.setAccountScope(userId: accountB)
    await MIRALocalJSONCache.remove(key: "native.main.feed.v7.cache_first")
  }

  func testExpiredCursorKeepsReadingOrderUntilExplicitRefresh() async throws {
    let model = model(), old = try (0..<12).map { try post("expired-cursor-\($0)") }
    let refreshed = try post("fresh-reading-session")
    var offsets: [Int] = []
    var freshRequest = false
    model.testPageLoader = { _, skip in
      offsets.append(skip)
      if skip == 0 { return freshRequest ? [refreshed] : old }
      freshRequest = true
      throw MIRAAPIError.server(status: 400, code: "FEED_CURSOR_INVALID", detail: "Expired cursor")
    }
    await model.load()
    await model.loadMoreIfNeeded(after: old.last!)
    XCTAssertEqual(model.posts.map(\.id), old.map(\.id))
    XCTAssertTrue(model.paginationNeedsRefresh)
    XCTAssertNotNil(model.paginationError)
    XCTAssertFalse(model.isLoadingMore)
    await model.loadMoreIfNeeded(after: old.last!)
    await model.loadPastLegacyTextPage()
    XCTAssertEqual(offsets, [0, 12], "Visibility callbacks cannot repeatedly retry or silently reset an expired session")
    await model.retryPagination()
    XCTAssertEqual(offsets, [0, 12, 0])
    XCTAssertEqual(model.posts.map(\.id), [refreshed.id])
    XCTAssertFalse(model.paginationNeedsRefresh)
    XCTAssertNil(model.paginationError)
    XCTAssertFalse(model.canLoadMore)
  }

  func testConsumingOldPublicationCannotClearNewerReceipt() throws {
    let store = CaptroPublicationStore()
    let scope = MIRALocalJSONCache.currentScopeIdentifier
    XCTAssertTrue(store.record(try post("first-receipt"), expectedScope: scope))
    let first = try XCTUnwrap(store.latest)
    XCTAssertTrue(store.record(try post("newer-receipt"), expectedScope: scope))
    let newer = try XCTUnwrap(store.latest)
    XCTAssertFalse(store.consume(first))
    XCTAssertEqual(store.latest, newer)
    XCTAssertTrue(store.consume(newer))
    XCTAssertNil(store.latest)
    XCTAssertFalse(store.consume(newer), "Remounts cannot replay an already-consumed success receipt")
  }

  func testPublicationConsumptionAfterPublishedSetterDoesNotRestoreConsumedReceipt() async throws {
    let store = CaptroPublicationStore()
    let consumed = expectation(description: "publication setter completed before consumption")
    let subscription = store.$latest.sink { receipt in
      guard let receipt else { return }
      Task { @MainActor in
        XCTAssertTrue(store.consume(receipt))
        consumed.fulfill()
      }
    }
    defer { subscription.cancel() }
    XCTAssertTrue(store.record(try post("single-delivery"), expectedScope: MIRALocalJSONCache.currentScopeIdentifier))
    await fulfillment(of: [consumed], timeout: 3)
    XCTAssertNil(store.latest,
      "Synchronous consumption inside @Published willSet would be overwritten by the setter's pending receipt")
  }

  func testMissingMediaMetadataDoesNotHideSupportedPhotoVideoOrStructuredPost() throws {
    for type in ["general", "photo", "video", "cover", "club", "event", "meetup", "deal", "group", "offer", "ticket"] {
      XCTAssertFalse(try post(type, type: type).isLegacyOrdinaryTextPost)
    }
    for type in ["club", "event", "meetup", "deal", "group", "offer", "ticket"] {
      XCTAssertFalse(try post(type, type: type, media: []).isLegacyOrdinaryTextPost)
    }
    XCTAssertTrue(try post("legacy", media: []).isLegacyOrdinaryTextPost)
  }
}
