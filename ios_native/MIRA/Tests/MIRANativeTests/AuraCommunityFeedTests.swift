import Foundation
import XCTest
@testable import MIRANative

private final class AuraCommunityFeedURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: MIRAAPIError.emptyResponse)
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class AuraCommunityFeedTests: XCTestCase {
  override func tearDown() {
    AuraCommunityFeedURLProtocol.handler = nil
    super.tearDown()
  }

  @MainActor
  func testCursorFeedTrustsEnvelopeAcrossShortAndFullPageBoundaries() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuraCommunityFeedURLProtocol.self]
    let session = URLSession(configuration: configuration)
    var requestedCursors: [String?] = []

    AuraCommunityFeedURLProtocol.handler = { request in
      let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
      let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
      requestedCursors.append(values["cursor"])
      XCTAssertEqual(values["scope"], "city")
      XCTAssertEqual(values["city"], "New York City")
      XCTAssertEqual(values["limit"], "2")
      XCTAssertEqual(values["pagination"], "cursor")
      XCTAssertNil(values["skip"])

      let body: String
      switch values["cursor"] {
      case nil:
        // The envelope is authoritative: a short page can still have a continuation.
        body = """
        {
          "items":[{"id":"post-1","post_type":"small_post","title":"First"}],
          "next_cursor":"cursor-1",
          "has_more":true
        }
        """
      case "cursor-1":
        // A boundary item can be repeated defensively by a data source. Stable post identity
        // keeps the rendered feed deduplicated without changing the server cursor.
        body = """
        {
          "items":[
            {"id":"post-1","post_type":"small_post","title":"First"},
            {"id":"post-2","post_type":"meetup","title":"Second"}
          ],
          "next_cursor":"cursor-2",
          "has_more":true
        }
        """
      case "cursor-2":
        // Even though this page is full, has_more=false must stop pagination.
        body = """
        {
          "items":[
            {"id":"post-3","post_type":"small_post","title":"Third"},
            {"id":"post-4","post_type":"meetup","title":"Fourth"}
          ],
          "next_cursor":null,
          "has_more":false
        }
        """
      default:
        XCTFail("Unexpected cursor \(values["cursor"] ?? "nil")")
        body = "{\"items\":[],\"next_cursor\":null,\"has_more\":false}"
      }
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: try XCTUnwrap(request.url),
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      return (response, Data(body.utf8))
    }

    let api = MIRAAPIClient(
      baseURL: URL(string: "https://api.flames-up.com/api")!,
      sessionProvider: StaticSessionProvider(token: "test-session"),
      session: session
    )
    let model = AuraCommunityFeedModel(api: api, pageSize: 2)

    await model.load(scope: .city, city: "New York City", refresh: true)
    await model.loadNextPage(scope: .city, city: "New York City")
    await model.loadNextPage(scope: .city, city: "New York City")
    await model.loadNextPage(scope: .city, city: "New York City")

    XCTAssertEqual(requestedCursors.count, 3)
    XCTAssertNil(requestedCursors[0])
    XCTAssertEqual(requestedCursors[1], "cursor-1")
    XCTAssertEqual(requestedCursors[2], "cursor-2")
    XCTAssertEqual(model.posts.map(\.id), ["post-1", "post-2", "post-3", "post-4"])
    XCTAssertEqual(model.posts.map(\.mode), [.smallPost, .meetup, .smallPost, .meetup])
    XCTAssertFalse(model.hasMore)
    XCTAssertFalse(model.isLoading)
    XCTAssertFalse(model.isLoadingMore)
    XCTAssertNil(model.errorMessage)
  }

  @MainActor
  func testBareArrayResponseFallsBackToLegacyOffsetPagination() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuraCommunityFeedURLProtocol.self]
    let session = URLSession(configuration: configuration)
    var queries: [[String: String]] = []

    AuraCommunityFeedURLProtocol.handler = { request in
      let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
      let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
      queries.append(values)

      let body: String
      if queries.count == 1 {
        body = """
        [
          {"id":"legacy-1","post_type":"small_post","title":"First"},
          {"id":"legacy-2","post_type":"meetup","title":"Second"}
        ]
        """
      } else {
        body = """
        [{"id":"legacy-3","post_type":"small_post","title":"Third"}]
        """
      }

      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: try XCTUnwrap(request.url),
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      return (response, Data(body.utf8))
    }

    let api = MIRAAPIClient(
      baseURL: URL(string: "https://api.flames-up.com/api")!,
      sessionProvider: StaticSessionProvider(token: "test-session"),
      session: session
    )
    let model = AuraCommunityFeedModel(api: api, pageSize: 2)

    await model.load(scope: .friends, city: "New York City", refresh: true)
    await model.loadNextPage(scope: .friends, city: "New York City")
    await model.loadNextPage(scope: .friends, city: "New York City")

    XCTAssertEqual(queries.count, 2)
    XCTAssertEqual(queries[0]["pagination"], "cursor")
    XCTAssertNil(queries[0]["cursor"])
    XCTAssertNil(queries[0]["skip"])
    XCTAssertNil(queries[1]["pagination"])
    XCTAssertEqual(queries[1]["skip"], "2")
    XCTAssertEqual(model.posts.map(\.id), ["legacy-1", "legacy-2", "legacy-3"])
    XCTAssertFalse(model.hasMore)
    XCTAssertNil(model.errorMessage)
  }
}
