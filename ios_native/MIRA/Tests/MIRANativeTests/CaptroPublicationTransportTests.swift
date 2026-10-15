import XCTest
@testable import MIRANative

@MainActor
final class CaptroPublicationTransportTests: XCTestCase {
  private func client(session: MIRASessionProviding = StaticSessionProvider(token: "fixture-publication")) -> MIRAAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PublicationTransportProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://localhost:9447")!,
      sessionProvider: session, session: URLSession(configuration: configuration))
  }

  func testPublicationRecheckDoesNotJoinHeldPrePublicationFirstPage() async throws {
    let api = client()
    let requests = PublicationTransportRequests()
    let oldGate = PublicationTransportGate()
    let oldStarted = expectation(description: "Pre-publication page is in flight")
    let freshStarted = expectation(description: "Post-publication page starts separately")
    // A unique test URL isolates this fixture from the process-wide GET
    // deduplicator. The old and fresh requests still use the exact same URL.
    let path = "/posts/feed?limit=12&skip=0&scope=for_you&fixture=\(UUID().uuidString)"
    let oldData = Data("[{\"id\":\"existing\",\"image\":\"https://fixture.invalid/old.jpg\"}]".utf8)
    let newData = Data("[{\"id\":\"published\",\"image\":\"https://fixture.invalid/new.jpg\"},{\"id\":\"existing\",\"image\":\"https://fixture.invalid/old.jpg\"}]".utf8)
    PublicationTransportProtocol.handler = { transport in
      if requests.append(transport.request) == 0 {
        oldGate.hold(transport)
        oldStarted.fulfill()
      } else {
        freshStarted.fulfill()
        transport.reply(200, newData)
      }
    }
    defer { oldGate.release(status: 200, data: oldData) }
    let old = Task { () throws -> [MIRAPost] in try await api.get(path) }
    await fulfillment(of: [oldStarted], timeout: 3)
    let fresh = Task { () throws -> [MIRAPost] in try await api.getFresh(path) }
    await fulfillment(of: [freshStarted], timeout: 3)
    oldGate.release(status: 200, data: oldData)
    let afterPublication = try await fresh.value
    let beforePublication = try await old.value
    XCTAssertEqual(afterPublication.map(\.id), ["published", "existing"])
    XCTAssertEqual(beforePublication.map(\.id), ["existing"])
    XCTAssertEqual(requests.values.count, 2, "A new model generation cannot make a reused old payload fresh")
    XCTAssertEqual(requests.values.first?.url, requests.values.last?.url,
      "Fresh transport must preserve the exact selected feed/filter URL")
    XCTAssertEqual(requests.values.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(requests.values.first?.cachePolicy, .useProtocolCachePolicy)
  }

  func testFreshGetStillRejectsResponseFromEndedAuthenticationGeneration() async throws {
    let storage = PublicationSessionStorage()
    storage.saveSession(accessToken: "fixture-a", refreshToken: "fixture-refresh-a")
    let defaults = UserDefaults(suiteName: "captro.publication.auth.\(UUID().uuidString)")!
    let auth = MIRAAuthSession(keychain: storage, defaults: defaults)
    let api = client(session: auth)
    let gate = PublicationTransportGate()
    let started = expectation(description: "Fresh account A request started")
    let requests = PublicationTransportRequests()
    PublicationTransportProtocol.handler = { transport in
      requests.append(transport.request)
      gate.hold(transport)
      started.fulfill()
    }
    defer { storage.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil) }
    let fresh = Task { () -> Bool in
      do {
        let _: [MIRAPost] = try await api.getFresh("/posts/feed?fixture=\(UUID().uuidString)")
        return true
      } catch { return false }
    }
    await fulfillment(of: [started], timeout: 3)
    auth.logout()
    gate.release(status: 200, data: Data("[{\"id\":\"private-a\"}]".utf8))
    let accepted = await fresh.value
    XCTAssertFalse(accepted, "Bypassing GET deduplication must not bypass auth generation validation")
    XCTAssertEqual(requests.values.count, 1)
    XCTAssertNil(auth.user)
  }

  func testFailedFreshReadDoesNotReplaceTheOlderReadWithFakeSuccess() async throws {
    let api = client()
    let requests = PublicationTransportRequests()
    let gate = PublicationTransportGate()
    let started = expectation(description: "Normal page remains held")
    let freshStarted = expectation(description: "Fresh failing request is independent")
    let path = "/posts/feed?fixture=\(UUID().uuidString)"
    PublicationTransportProtocol.handler = { transport in
      if requests.append(transport.request) == 0 {
        gate.hold(transport)
        started.fulfill()
      } else {
        freshStarted.fulfill()
        transport.reply(503, Data("{\"error\":\"temporarily unavailable\"}".utf8))
      }
    }
    let old = Task { () throws -> [MIRAPost] in try await api.get(path) }
    await fulfillment(of: [started], timeout: 3)
    let fresh = Task { () -> Bool in
      do {
        let _: [MIRAPost] = try await api.getFresh(path)
        return true
      } catch { return false }
    }
    await fulfillment(of: [freshStarted], timeout: 3)
    gate.release(status: 200, data: Data("[{\"id\":\"existing\"}]".utf8))
    let accepted = await fresh.value
    XCTAssertFalse(accepted, "A post-publication reconciliation failure must remain a retryable error")
    XCTAssertEqual(requests.values.count, 2)
    let original = try await old.value
    XCTAssertEqual(original.map(\.id), ["existing"])
  }
}

private final class PublicationSessionStorage: MIRAAuthSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var access: String?
  private var refresh: String?
  func accessToken() async -> String? { lock.withLock { access } }
  func refreshToken() async -> String? { lock.withLock { refresh } }
  func saveSession(accessToken: String, refreshToken: String?) {
    lock.withLock { access = accessToken; refresh = refreshToken }
  }
  func clearSession() { lock.withLock { access = nil; refresh = nil } }
}

private final class PublicationTransportRequests: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [URLRequest] = []
  @discardableResult func append(_ request: URLRequest) -> Int {
    lock.withLock {
      let index = requests.count
      requests.append(request)
      return index
    }
  }
  var values: [URLRequest] { lock.withLock { requests } }
}

private final class PublicationTransportGate: @unchecked Sendable {
  private let lock = NSLock()
  private var transport: PublicationTransportProtocol?
  func hold(_ value: PublicationTransportProtocol) { lock.withLock { transport = value } }
  func release(status: Int, data: Data) {
    let value = lock.withLock { () -> PublicationTransportProtocol? in
      defer { transport = nil }
      return transport
    }
    value?.reply(status, data)
  }
}

private final class PublicationTransportProtocol: URLProtocol {
  static var handler: ((PublicationTransportProtocol) -> Void)!
  private let lock = NSLock()
  private var stopped = false
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "localhost" && request.url?.port == 9447
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.handler(self) }
  override func stopLoading() { lock.withLock { stopped = true } }
  func reply(_ status: Int, _ data: Data) {
    guard lock.withLock({ !stopped }) else { return }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
}
