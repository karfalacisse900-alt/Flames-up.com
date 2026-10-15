import XCTest
@testable import MIRANative

@MainActor
final class CaptroFeedPageTests: XCTestCase {
  private func page(_ ids: [String], cursor: String? = nil, more: Bool = false) throws -> Data {
    let records = ids.map { ["id": $0, "images": ["https://example.invalid/photo.jpg"]] as [String: Any] }
    var value: [String: Any] = ["posts": records, "hasMore": more]
    if let cursor { value["nextCursor"] = cursor }
    return try JSONSerialization.data(withJSONObject: value)
  }

  private func fixture(_ responses: [Data]) -> (MainFeedModel, FeedPageResponses) {
    let queue = FeedPageResponses(responses)
    FeedPageProtocol.handler = { transport in
      guard let data = queue.take(transport.request) else {
        transport.fail(URLError(.badServerResponse)); return
      }
      transport.reply(data)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FeedPageProtocol.self]
    // A unique local base path isolates the shared GET request deduplicator.
    let api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9448/\(UUID().uuidString)/")!,
      sessionProvider: StaticSessionProvider(token: "fixture-feed-pages"), session: URLSession(configuration: configuration))
    let model = MainFeedModel(api: api)
    model.currentUserId = "feed-page-fixture"; model.currentUsername = "feed-page-fixture"
    model.testAutomaticPagination = false
    model.testPageSorter = { $0 }
    return (model, queue)
  }

  private func query(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }

  func testCursorAndLegacyDecodingKeepEmptyContinuationsDistinctFromEndOfFeed() throws {
    let decoder = JSONDecoder()
    let continuing = try decoder.decode(CaptroFeedPage.self, from: page([], cursor: "next", more: true))
    XCTAssertTrue(continuing.posts.isEmpty)
    XCTAssertTrue(continuing.hasMore)
    XCTAssertTrue(continuing.usesCursor)
    XCTAssertEqual(continuing.nextCursor, "next")
    let ended = try decoder.decode(CaptroFeedPage.self, from: page([]))
    XCTAssertFalse(ended.hasMore)
    XCTAssertNil(ended.nextCursor)
    XCTAssertThrowsError(try decoder.decode(CaptroFeedPage.self, from: page([], more: true)))
    XCTAssertThrowsError(try decoder.decode(CaptroFeedPage.self, from: page([], cursor: "", more: true)))

    let legacyRecords = (0..<12).map { ["id": "legacy-\($0)"] }
    let legacy = try decoder.decode(CaptroFeedPage.self, from: JSONSerialization.data(withJSONObject: legacyRecords))
    XCTAssertFalse(legacy.usesCursor)
    XCTAssertTrue(legacy.hasMore)
    XCTAssertNil(legacy.nextCursor)
    XCTAssertFalse(try decoder.decode(CaptroFeedPage.self, from: Data("[]".utf8)).hasMore)
  }

  func testEmptyFirstPageContinuesWithItsCursorEvenWhileOffsetRemainsZero() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "cursor-empty-\(UUID().uuidString)")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let cursor = "cursor+with /?&=reserved#characters"
    let (model, requests) = fixture([
      try page([], cursor: cursor, more: true),
      try page([], cursor: "filtered-second-page", more: true),
      try page(["visible-after-filtered-pages"])
    ])
    await model.load()
    XCTAssertTrue(model.posts.isEmpty)
    XCTAssertTrue(model.canLoadMore)
    XCTAssertFalse(model.isLoading)
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 0)
    await model.retryPagination()
    XCTAssertTrue(model.posts.isEmpty)
    XCTAssertTrue(model.canLoadMore)
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 0)
    await model.retryPagination()
    XCTAssertEqual(model.posts.map(\.id), ["visible-after-filtered-pages"])
    XCTAssertFalse(model.canLoadMore)
    XCTAssertEqual(requests.values.count, 3)
    XCTAssertNil(query(requests.values[0], "cursor"))
    XCTAssertEqual(query(requests.values[1], "cursor"), cursor)
    XCTAssertEqual(query(requests.values[2], "cursor"), "filtered-second-page")
    XCTAssertEqual(requests.values.compactMap { query($0, "skip") }, ["0", "0", "0"])
    XCTAssertNil(model.paginationError)
    await MIRALocalJSONCache.remove(key: "native.main.feed.v7.cache_first")
  }

  func testPublicationEligibilityReadDoesNotConsumeExistingFeedCursor() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "cursor-publish-\(UUID().uuidString)")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let oldIDs = (0..<12).map { "original-\($0)" }
    let publishedData = try page(["canonical-published"] + oldIDs, cursor: "new-first-page-cursor", more: true)
    let published = try JSONDecoder().decode(CaptroFeedPage.self, from: publishedData).posts[0]
    let (model, requests) = fixture([
      try page(oldIDs, cursor: "existing-reading-cursor", more: true), publishedData,
      try page([oldIDs.last!, "later-post"])
    ])
    await model.load()
    await model.reconcilePublication(CaptroPublishedPost(post: published,
      accountScope: MIRALocalJSONCache.currentScopeIdentifier), canInsertNow: { true })
    XCTAssertEqual(model.posts.map(\.id), [published.id] + oldIDs)
    await model.retryPagination()
    XCTAssertEqual(model.posts.map(\.id), [published.id] + oldIDs + ["later-post"])
    XCTAssertEqual(Set(model.posts.map(\.id)).count, model.posts.count)
    XCTAssertEqual(requests.values.count, 3)
    XCTAssertNil(query(requests.values[1], "cursor"), "Publication checks the current first page, not the reader's continuation")
    XCTAssertEqual(requests.values[1].cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(query(requests.values[2], "cursor"), "existing-reading-cursor",
      "A separate eligibility check must not skip the reader into the new first page's continuation")
    XCTAssertEqual(query(requests.values[2], "skip"), "12")
    XCTAssertFalse(model.canLoadMore)
    await MIRALocalJSONCache.remove(key: "native.main.feed.v7.cache_first")
  }

  func testLegacyArrayBackendStillAdvancesRawOffsetAcrossDuplicatePosts() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "legacy-pages-\(UUID().uuidString)")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    func legacy(_ ids: [String]) throws -> Data {
      try JSONSerialization.data(withJSONObject: ids.map {
        ["id": $0, "images": ["https://example.invalid/photo.jpg"]] as [String: Any]
      })
    }
    let first = (0..<12).map { "legacy-\($0)" }
    let (model, requests) = fixture([try legacy(first), try legacy(["legacy-11", "legacy-12"])])
    await model.load()
    await model.retryPagination()
    XCTAssertEqual(model.posts.map(\.id), first + ["legacy-12"])
    XCTAssertEqual(model.paginationOffsetForTesting(.forYou), 14)
    XCTAssertFalse(model.canLoadMore)
    XCTAssertEqual(requests.values.count, 2)
    XCTAssertEqual(query(requests.values[1], "skip"), "12")
    XCTAssertNil(query(requests.values[1], "cursor"))
    await MIRALocalJSONCache.remove(key: "native.main.feed.v7.cache_first")
  }
}

private final class FeedPageResponses: @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [Data]
  private var requests: [URLRequest] = []
  init(_ responses: [Data]) { self.responses = responses }
  func take(_ request: URLRequest) -> Data? {
    lock.withLock {
      requests.append(request)
      return responses.isEmpty ? nil : responses.removeFirst()
    }
  }
  var values: [URLRequest] { lock.withLock { requests } }
}

private final class FeedPageProtocol: URLProtocol {
  static var handler: ((FeedPageProtocol) -> Void)!
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "localhost" && request.url?.port == 9448
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.handler(self) }
  override func stopLoading() {}
  func fail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
  func reply(_ data: Data) {
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
}
