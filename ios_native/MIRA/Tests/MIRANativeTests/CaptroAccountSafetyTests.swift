import XCTest
@testable import MIRANative

@MainActor final class CaptroAccountSafetyTests: XCTestCase {
  func testColdBootstrapOutageOffersRetryWithoutErasingSession() async throws {
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let (auth, api, keychain) = await fixture()
    AccountSafetyProtocol.handler = { $0.reply(503, Data("{\"code\":\"UPSTREAM_UNAVAILABLE\"}".utf8)) }
    await auth.bootstrap(api: api)
    XCTAssertTrue(auth.needsSessionRetry)
    let retained = await keychain.refreshToken()
    XCTAssertEqual(retained, "refresh-a")
    AccountSafetyProtocol.handler = { $0.reply(200, Data("{\"id\":\"a\",\"username\":\"tester_a\"}".utf8)) }
    await auth.bootstrap(api: api)
    XCTAssertFalse(auth.needsSessionRetry)
    XCTAssertEqual(auth.user?.id, "a")
    keychain.clearSession()
  }

  func testAPIRefreshFollowedByProfileOutageKeepsRotatedSession() async throws {
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let (auth, api, keychain) = await fixture()
    AccountSafetyProtocol.handler = { transport in
      if transport.request.url?.path == "/auth/refresh" {
        transport.reply(200, Data("{\"access_token\":\"rotated\",\"refresh_token\":\"rotated-refresh\",\"user\":{\"id\":\"a\"}}".utf8))
      } else if transport.request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-a" {
        transport.reply(401, Data("{\"code\":\"INVALID_TOKEN\"}".utf8))
      } else { transport.reply(503, Data("{\"code\":\"UPSTREAM_UNAVAILABLE\"}".utf8)) }
    }
    await auth.bootstrap(api: api)
    let retained = await keychain.refreshToken()
    XCTAssertEqual(retained, "rotated-refresh")
    XCTAssertEqual(auth.user?.id, "a")
    keychain.clearSession()
  }

  func testRefreshOutagesPreserveCredentialsAndRetry() async throws {
    for status in [429, 500, 503] {
      let (auth, api, keychain) = await fixture()
      AccountSafetyProtocol.handler = { $0.reply(status, Data("{\"code\":\"SESSION_REFRESH_UNAVAILABLE\"}".utf8)) }
      let accepted = await auth.refreshAccessTokenIfNeeded(api: api)
      XCTAssertFalse(accepted)
      let retained = await keychain.refreshToken()
      XCTAssertEqual(retained, "refresh-a")
      AccountSafetyProtocol.handler = { $0.reply(200, Self.authResponse("a")) }
      let recovered = await auth.refreshAccessTokenIfNeeded(api: api)
      XCTAssertTrue(recovered)
      keychain.clearSession()
    }
    MIRALocalJSONCache.setAccountScope(userId: nil)
  }

  func testConfirmedRefreshRejectionClearsCredentials() async throws {
    let (auth, api, keychain) = await fixture()
    AccountSafetyProtocol.handler = { $0.reply(401, Data("{\"code\":\"INVALID_TOKEN\"}".utf8)) }
    let accepted = await auth.refreshAccessTokenIfNeeded(api: api)
    XCTAssertFalse(accepted)
    let retained = await keychain.refreshToken()
    XCTAssertNil(retained)
  }

  func testExplicitRevocationDoesNotAttemptRefreshDuringAnOutage() async throws {
    for (status, code) in [(401, "SESSION_REVOKED"), (403, "ACCOUNT_DISABLED")] {
      MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
      let (auth, api, keychain) = await fixture()
      let requests = AccountSafetyRequests()
      AccountSafetyProtocol.handler = { transport in
        requests.append(transport.request)
        if transport.request.url?.path == "/auth/refresh" { transport.reply(503, Data("{}".utf8)) }
        else { transport.reply(status, Data("{\"code\":\"\(code)\"}".utf8)) }
      }
      await auth.bootstrap(api: api)
      let retained = await keychain.refreshToken()
      XCTAssertNil(retained)
      XCTAssertNil(auth.user)
      XCTAssertFalse(auth.needsSessionRetry)
      XCTAssertFalse(requests.values.contains { $0.url?.path == "/auth/refresh" })
    }
    MIRALocalJSONCache.setAccountScope(userId: nil)
  }

  func testRotatedCredentialsSurviveMissingProfile() async throws {
    let (auth, api, keychain) = await fixture()
    AccountSafetyProtocol.handler = { $0.reply(200, Data("{\"access_token\":\"rotated\",\"refresh_token\":\"rotated-refresh\",\"user\":null,\"profile_pending\":true}".utf8)) }
    let accepted = await auth.refreshAccessTokenIfNeeded(api: api)
    XCTAssertTrue(accepted)
    let retained = await keychain.refreshToken()
    XCTAssertEqual(retained, "rotated-refresh")
    keychain.clearSession()
  }

  func testRecoveryForAnotherAccountDoesNotSwitchCurrentAccount() async throws {
    let (auth, api, keychain) = await fixture()
    AccountSafetyProtocol.handler = { $0.reply(200, Self.authResponse("a")) }
    await auth.login(email: "a@example.invalid", password: "fixture", api: api)
    auth.passwordResetContext = MIRAPasswordResetContext(accessToken: "recovery-b", refreshToken: nil, email: nil)
    AccountSafetyProtocol.handler = { $0.reply(200, Self.authResponse("b")) }
    let completed = await auth.completePasswordReset(password: "fixture-new-password", api: api)
    XCTAssertTrue(completed)
    XCTAssertEqual(auth.user?.id, "a")
    let retained = await keychain.accessToken()
    XCTAssertEqual(retained, "fixture-a")
    XCTAssertNil(auth.passwordResetContext)
    keychain.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil)
  }

  private func fixture() async -> (MIRAAuthSession, MIRAAPIClient, AccountSafetySessionStorage) {
    let id = UUID().uuidString
    // This is a hostless logic-test bundle. System Keychain writes are not a
    // reliable fixture here; they returned nil before requests in CI. Exercise
    // the real auth/request code using an explicit, verifiably seeded store.
    let keychain = AccountSafetySessionStorage()
    keychain.saveSession(accessToken: "fixture-a", refreshToken: "refresh-a")
    let seededAccess = await keychain.accessToken()
    let seededRefresh = await keychain.refreshToken()
    XCTAssertEqual(seededAccess, "fixture-a")
    XCTAssertEqual(seededRefresh, "refresh-a")
    let auth = MIRAAuthSession(keychain: keychain, defaults: UserDefaults(suiteName: "captro.test.auth.\(id)")!)
    return (auth, client(session: auth), keychain)
  }

  private func client(session: MIRASessionProviding = StaticSessionProvider()) -> MIRAAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AccountSafetyProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://localhost:9445")!,
      sessionProvider: session, session: URLSession(configuration: config))
  }

  private nonisolated static func authResponse(_ account: String) -> Data {
    Data("{\"access_token\":\"fixture-\(account)\",\"refresh_token\":\"refresh-\(account)\",\"user\":{\"id\":\"\(account)\",\"username\":\"tester_\(account)\"}}".utf8)
  }

  func testDelayedRefreshCannotRestoreLoggedOutCredentials() async throws {
    let (auth, api, keychain) = await fixture()
    defer { keychain.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil) }
    let started = expectation(description: "Refresh A started")
    let gate = AccountSafetyGate()
    AccountSafetyProtocol.handler = { transport in gate.hold(transport); started.fulfill() }
    let refresh = Task { await auth.refreshAccessTokenIfNeeded(api: api) }
    await fulfillment(of: [started], timeout: 3)
    auth.logout()
    gate.release(status: 200, data: Self.authResponse("a"))
    let accepted = await refresh.value
    let stored = await keychain.accessToken()
    XCTAssertFalse(accepted)
    XCTAssertNil(auth.user)
    XCTAssertNil(stored)
  }

  func testDelayedRefreshFailureCannotSignOutNewAccount() async throws {
    let (auth, api, keychain) = await fixture()
    defer { keychain.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil) }
    let started = expectation(description: "Refresh A started")
    let gate = AccountSafetyGate()
    AccountSafetyProtocol.handler = { transport in
      if transport.request.url?.path == "/auth/refresh" { gate.hold(transport); started.fulfill() }
      else { transport.reply(200, Self.authResponse("b")) }
    }
    let refresh = Task { await auth.refreshAccessTokenIfNeeded(api: api) }
    await fulfillment(of: [started], timeout: 3)
    auth.logout()
    await auth.login(email: "fixture@example.invalid", password: "fixture", api: api)
    gate.release(status: 401, data: Data("{}".utf8))
    _ = await refresh.value
    let stored = await keychain.accessToken()
    XCTAssertEqual(auth.user?.id, "b")
    XCTAssertEqual(stored, "fixture-b")
    XCTAssertNil(auth.errorMessage)
  }

  func testLateUnauthorizedMutationIsNotReplayedAsNewAccount() async throws {
    let (auth, api, keychain) = await fixture()
    defer { keychain.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil) }
    let started = expectation(description: "Account A mutation started")
    let gate = AccountSafetyGate()
    let requests = AccountSafetyRequests()
    AccountSafetyProtocol.handler = { transport in
      requests.append(transport.request)
      if transport.request.url?.path == "/fixture-action" { gate.hold(transport); started.fulfill() }
      else { transport.reply(200, Self.authResponse("b")) }
    }
    let mutation = Task { () -> Bool in
      do {
        let _: [String: Bool] = try await api.post("/fixture-action", body: ["enabled": true])
        return true
      } catch { return false }
    }
    await fulfillment(of: [started], timeout: 3)
    auth.logout()
    await auth.login(email: "fixture@example.invalid", password: "fixture", api: api)
    gate.release(status: 401, data: Data("{}".utf8))
    let accepted = await mutation.value
    XCTAssertFalse(accepted)
    XCTAssertEqual(requests.values.filter { $0.url?.path == "/fixture-action" }.count, 1)
    XCTAssertFalse(requests.values.contains { $0.url?.path == "/auth/refresh" })
    XCTAssertEqual(auth.user?.id, "b")
  }

  func testDelayedBootstrapDoesNotReplaceNewAccount() async throws {
    let (auth, api, keychain) = await fixture()
    // A never-before-used namespace guarantees the real uncached bootstrap path.
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    defer { keychain.clearSession(); MIRALocalJSONCache.setAccountScope(userId: nil) }
    let started = expectation(description: "Account A bootstrap started")
    let gate = AccountSafetyGate()
    AccountSafetyProtocol.handler = { transport in
      if transport.request.url?.path == "/auth/me" { gate.hold(transport); started.fulfill() }
      else { transport.reply(200, Self.authResponse("b")) }
    }
    let restore = Task { await auth.bootstrap(api: api) }
    await fulfillment(of: [started], timeout: 3)
    auth.logout()
    await auth.login(email: "fixture@example.invalid", password: "fixture", api: api)
    gate.release(status: 200, data: Data("{\"id\":\"a\",\"username\":\"tester_a\"}".utf8))
    await restore.value
    XCTAssertEqual(auth.user?.id, "b")
    XCTAssertFalse(auth.isBootstrapping)
  }

  func testSameAPNSTokenIsUnregisteredAndRegisteredForNewAccount() async {
    let registry = MIRAPushTokenRegistry(), api = client()
    let requests = AccountSafetyRequests()
    AccountSafetyProtocol.handler = { transport in
      requests.append(transport.request)
      transport.reply(200, Data("{\"ok\":true}".utf8))
    }
    let token = String(repeating: "a", count: 64)
    await registry.registerDeviceToken(token, accountID: "a", accessToken: "fixture-a", api: api)
    await registry.registerDeviceToken(token, accountID: "a", accessToken: "fixture-a-refreshed", api: api)
    await registry.registerDeviceToken(token, accountID: "b", accessToken: "fixture-b", api: api)
    XCTAssertEqual(requests.values.map(\.httpMethod), ["POST", "DELETE", "POST"])
    XCTAssertEqual(requests.values.map { $0.value(forHTTPHeaderField: "Authorization") },
      ["Bearer fixture-a", "Bearer fixture-a-refreshed", "Bearer fixture-b"])
    XCTAssertTrue(requests.values.allSatisfy { $0.url?.path == "/notifications/device-token" })
  }

  func testInflightPushRegistrationIsRemovedBeforeNewAccountRegisters() async {
    let registry = MIRAPushTokenRegistry(), api = client()
    let started = expectation(description: "A registration started")
    let gate = AccountSafetyGate(), requests = AccountSafetyRequests()
    AccountSafetyProtocol.handler = { transport in
      requests.append(transport.request)
      if transport.request.httpMethod == "POST",
         transport.request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-a" {
        gate.hold(transport); started.fulfill()
      } else { transport.reply(200, Data("{\"ok\":true}".utf8)) }
    }
    let token = String(repeating: "a", count: 64)
    let first = Task { await registry.registerDeviceToken(token, accountID: "a", accessToken: "fixture-a", api: api) }
    await fulfillment(of: [started], timeout: 3)
    registry.endSession()
    let next = Task { await registry.registerDeviceToken(token, accountID: "b", accessToken: "fixture-b", api: api) }
    gate.release(status: 200, data: Data("{\"ok\":true}".utf8))
    await first.value
    await next.value
    XCTAssertEqual(requests.values.map(\.httpMethod), ["POST", "DELETE", "POST"])
    XCTAssertEqual(requests.values.map { $0.value(forHTTPHeaderField: "Authorization") },
      ["Bearer fixture-a", "Bearer fixture-a", "Bearer fixture-b"])
  }

  func testProfilePersistenceKeepsExplicitOwnerNamespace() async throws {
    let profile = try JSONDecoder().decode(MIRAUser.self, from: Data("{\"id\":\"a\"}".utf8))
    let other = UUID().uuidString
    MIRALocalJSONCache.setAccountScope(userId: other)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let key = "auth-persistence-\(UUID().uuidString)"
    await MIRALocalJSONCache.save(profile, key: key, accountUserID: "a")
    let wrongAccount = await MIRALocalJSONCache.load(MIRAUser.self, key: key)
    XCTAssertNil(wrongAccount)
    MIRALocalJSONCache.setAccountScope(userId: "a")
    let own = await MIRALocalJSONCache.load(MIRAUser.self, key: key)
    XCTAssertEqual(own?.id, "a")
    await MIRALocalJSONCache.remove(key: key)
  }

  func testRefreshDuringFirstPushRegistrationUpdatesLogoutCredentials() async {
    let registry = MIRAPushTokenRegistry(), api = client()
    let started = expectation(description: "First registration is delayed")
    let removed = expectation(description: "Logout removes the registration")
    let gate = AccountSafetyGate(), requests = AccountSafetyRequests()
    AccountSafetyProtocol.handler = { transport in
      requests.append(transport.request)
      if transport.request.httpMethod == "POST" {
        gate.hold(transport); started.fulfill()
      } else {
        transport.reply(200, Data("{\"ok\":true}".utf8))
        removed.fulfill()
      }
    }
    let token = String(repeating: "a", count: 64)
    let first = Task { await registry.registerDeviceToken(token, accountID: "a", accessToken: "fixture-old", api: api) }
    await fulfillment(of: [started], timeout: 3)
    let nextRevision = registry.revision + 1
    let refreshed = Task { await registry.registerDeviceToken(token, accountID: "a", accessToken: "fixture-refreshed", api: api) }
    // Wait for the real queued transition, not a guessed network delay.
    let deadline = Date().addingTimeInterval(3)
    while registry.revision < nextRevision, Date() < deadline { await Task.yield() }
    XCTAssertEqual(registry.revision, nextRevision)
    gate.release(status: 200, data: Data("{\"ok\":true}".utf8))
    await first.value
    await refreshed.value
    registry.endSession()
    await fulfillment(of: [removed], timeout: 3)
    XCTAssertEqual(requests.values.map(\.httpMethod), ["POST", "DELETE"])
    XCTAssertEqual(requests.values.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-refreshed")
  }
}

private final class AccountSafetySessionStorage: MIRAAuthSessionStorage, @unchecked Sendable {
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

private final class AccountSafetyRequests: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [URLRequest] = []
  func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; requests.append(request) }
  var values: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

private final class AccountSafetyGate: @unchecked Sendable {
  private let lock = NSLock()
  private var transport: AccountSafetyProtocol?
  func hold(_ value: AccountSafetyProtocol) { lock.lock(); defer { lock.unlock() }; transport = value }
  func release(status: Int, data: Data) {
    lock.lock(); let value = transport; transport = nil; lock.unlock()
    value?.reply(status, data)
  }
}

private final class AccountSafetyProtocol: URLProtocol {
  static var handler: ((AccountSafetyProtocol) -> Void)!
  private let lock = NSLock()
  private var stopped = false
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "localhost" && request.url?.port == 9445 }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.handler(self) }
  override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
  func reply(_ status: Int, _ data: Data) {
    lock.lock(); let shouldReply = !stopped; lock.unlock()
    guard shouldReply else { return }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
}
