import XCTest
import Foundation
@testable import MIRANative

final class CaptroTeaConversationTests: XCTestCase {
  @MainActor func testActualTransportCoalescesDetailAndReplaysUncertainReplyIdentity() async throws {
    TeaConversationProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TeaConversationProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let api = MIRAAPIClient(session: session)
    let seed = try JSONDecoder().decode(CaptroTeaConversation.self, from: TeaConversationProtocol.postData)
    let model = api.teaConversations.model(for: seed)
    async let first: Void = model.load()
    async let second: Void = model.load()
    _ = await (first, second)
    await model.load()
    XCTAssertEqual(TeaConversationProtocol.snapshot().detailReads, 1)
    XCTAssertEqual(model.post?.title, "Server title")
    model.draft = "Keep the same reply"
    await model.sendReply()
    XCTAssertTrue(model.replyPending); XCTAssertNotNil(model.replyError)
    await model.sendReply()
    let sent = TeaConversationProtocol.snapshot().replyIDs
    XCTAssertEqual(sent.count, 2); XCTAssertFalse(sent.first?.isEmpty ?? true)
    XCTAssertEqual(sent.first, sent.last)
    XCTAssertEqual(model.replies.count, 1); XCTAssertFalse(model.replyPending)
    XCTAssertEqual(model.draft, "")
    struct RefreshFixture: Encodable { let refreshToken = "isolated-fixture" }
    let _: CaptroTeaConversation = try await api.post("/auth/refresh", body: RefreshFixture())
    XCTAssertNotNil(model.post, "Refreshing credentials must not blank a discussion")
    XCTAssertTrue(model.valid)
  }
  @MainActor func testPresentationCacheKeepsDraftAndEvictsOnAccountSwitchOrInvalidation() {
    MIRALocalJSONCache.setAccountScope(userId: "tea-a")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let api = MIRAAPIClient()
    let seed = CaptroTeaConversation(id: "post", title: "Draft", body: "Body", links: [],
      author: CaptroTeaAuthor(id: "tea-a", name: "Author", username: "author"),
      createdAt: "2026-11-13T12:00:00Z", version: 1, isAuthor: true, following: false)
    let first = api.teaConversations.model(for: seed)
    first.draft = "An unfinished reply"
    XCTAssertTrue(first === api.teaConversations.model(for: seed))
    XCTAssertEqual(api.teaConversations.model(for: seed).draft, "An unfinished reply")
    MIRALocalJSONCache.setAccountScope(userId: "tea-b")
    XCTAssertFalse(first.valid)
    let next = api.teaConversations.model(for: seed)
    XCTAssertFalse(first === next); XCTAssertNil(first.post); XCTAssertEqual(next.draft, "")
    api.teaConversations.invalidate()
    XCTAssertNil(next.post); XCTAssertFalse(next.valid)
  }
  func testDomainsUseExactBoundariesAndPreserveDestinations() {
    XCTAssertEqual(CaptroTeaLink("https://www.youtube.com/watch?v=a&signature=keep")?.hostname,"youtube.com")
    XCTAssertEqual(CaptroTeaLink("https://www.youtube.com/watch?v=a&signature=keep")?.url.query,"v=a&signature=keep")
    XCTAssertEqual(CaptroTeaLink("https://youtu.be/a")?.platform,"YouTube")
    XCTAssertEqual(CaptroTeaLink("https://m.tiktok.com/a")?.platform,"TikTok")
    for host in ["youtube.com.evil.example","notyoutube.com","tiktok.com.evil.example","example.com"] {
      XCTAssertNil(CaptroTeaLink("https://"+host)?.platform)
    }
    for value in ["http://youtube.com","https://user:secret@youtube.com","javascript:alert(1)","https://localhost","https://127.0.0.1","https://example.com\n"] {
      XCTAssertNil(CaptroTeaLink(value))
    }
  }
  func testOnlySupportedCaptroPathsRouteToProfile() {
    XCTAssertEqual(CaptroTeaLink("https://captro-site.pages.dev/profile/user_123")?.profile?.id,"user_123")
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev.evil.example/profile/user_123")?.profile)
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev/unknown/user_123")?.profile)
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev/profile/user_123?redirect=other")?.profile)
  }
  func testConversationDecodingOmitsUnrecognizedStoredAuthorUpdateData() throws {
    let data = Data(#"{"id":"test","title":"A title","body":"Text","links":[],"author":{"id":"a","name":"Artist","username":"artist"},"createdAt":"2026-11-13T12:00:00Z","version":1,"isAuthor":false,"following":false,"author_update":{"body":"Old stored value"}}"#.utf8)
    let value=try JSONDecoder().decode(CaptroTeaConversation.self,from:data)
    XCTAssertTrue(value.links.isEmpty);XCTAssertEqual(value.body,"Text")
    XCTAssertNotNil(captroTeaDate(value.createdAt))
  }
}

private final class TeaConversationProtocol: URLProtocol {
  struct State { var detailReads = 0; var replyIDs: [String] = [] }
  private static let lock = NSLock()
  private static var state = State()
  static let postData = Data(#"{"id":"post","title":"Server title","body":"Text","links":[],"author":{"id":"a","name":"Artist","username":"artist"},"createdAt":"2026-11-13T12:00:00Z","version":1,"isAuthor":false,"following":false}"#.utf8)
  static func reset() { lock.withLock { state = State() } }
  static func snapshot() -> State { lock.withLock { state } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let isReply = request.url!.path.hasSuffix("/replies")
    let isWrite = request.httpMethod == "POST"
    var bodyData = request.httpBody ?? Data()
    if bodyData.isEmpty, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }; bodyData.append(contentsOf: bytes.prefix(count))
      }
    }
    let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
    let attempt: Int = Self.lock.withLock {
      if isReply && isWrite { Self.state.replyIDs.append(body["request_id"] as? String ?? "") }
      if !isReply { Self.state.detailReads += 1 }
      return Self.state.replyIDs.count
    }
    if isReply && isWrite && attempt == 1 {
      client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
    }
    let data: Data
    if isReply && isWrite {
      data = try! JSONSerialization.data(withJSONObject: ["id": body["request_id"] ?? "", "body": body["body"] ?? "", "createdAt": "2026-11-13T12:00:00Z", "author": ["id":"a", "name":"Artist", "username":"artist"]])
    } else { data = isReply ? Data(#"{"items":[]}"#.utf8) : Self.postData }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
