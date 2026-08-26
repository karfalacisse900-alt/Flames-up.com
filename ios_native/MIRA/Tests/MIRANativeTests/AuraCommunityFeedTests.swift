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
  func testFeedLoadsEveryPageAndDoesNotDuplicatePostsAtPageBoundary() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuraCommunityFeedURLProtocol.self]
    let session = URLSession(configuration: configuration)
    var requestedOffsets: [Int] = []

    AuraCommunityFeedURLProtocol.handler = { request in
      let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
      let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
      let offset = Int(values["skip"] ?? "") ?? -1
      requestedOffsets.append(offset)
      XCTAssertEqual(values["scope"], "city")
      XCTAssertEqual(values["city"], "New York City")
      XCTAssertEqual(values["limit"], "2")

      let body: String
      switch offset {
      case 0:
        body = """
        [
          {"id":"post-1","post_type":"small_post","title":"First"},
          {"id":"post-2","post_type":"small_post","title":"Second"}
        ]
        """
      case 2:
        // A newly inserted server row can move an item onto both offset pages. The client must
        // advance by the raw page count while using stable post identity to avoid duplicates.
        body = """
        [
          {"id":"post-2","post_type":"small_post","title":"Second"},
          {"id":"post-3","post_type":"meetup","title":"Third"}
        ]
        """
      default:
        body = "[]"
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

    XCTAssertEqual(requestedOffsets, [0, 2, 4])
    XCTAssertEqual(model.posts.map(\.id), ["post-1", "post-2", "post-3"])
    XCTAssertEqual(model.posts.map(\.mode), [.smallPost, .smallPost, .meetup])
    XCTAssertFalse(model.hasMore)
    XCTAssertFalse(model.isLoading)
    XCTAssertFalse(model.isLoadingMore)
    XCTAssertNil(model.errorMessage)
  }
}
