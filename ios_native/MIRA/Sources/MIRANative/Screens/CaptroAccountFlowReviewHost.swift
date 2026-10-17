#if DEBUG
import SwiftUI
import Foundation

/// Actual app root and recovery presenter; fixture transport never contacts a
/// provider or production. These are presentation tests, not OAuth acceptance.
public struct CaptroAccountFlowReviewHost: View {
  @StateObject private var session: MIRAAuthSession
  private let api: MIRAAPIClient
  @State private var draftOpen = false
  @State private var draft = "Retained fixture draft"
  public init() {
    let flags = ProcessInfo.processInfo.arguments
    let storage = AccountFlowFixtureStorage()
    if flags.contains("--account-signed-in") || flags.contains("--account-onboarding") || flags.contains("--account-deletion") {
      storage.saveSession(accessToken: "fixture-a", refreshToken: "fixture-refresh-a")
    }
    let defaults = UserDefaults(suiteName: "captro.account-flow.fixture")!
    defaults.removePersistentDomain(forName: "captro.account-flow.fixture")
    let auth = MIRAAuthSession(keychain: storage, defaults: defaults)
    if flags.contains("--account-guest") { auth.continueAsGuest() }
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AccountFlowFixtureProtocol.self]
    self.api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9451")!, sessionProvider: auth, session: URLSession(configuration: config))
    _session = StateObject(wrappedValue: auth)
  }
  public var body: some View {
    MIRANativeRootView(reviewSession: session, api: api)
      .overlay(alignment: .top) {
        VStack {
          Text(session.user?.id ?? (session.isGuest ? "guest" : "signed-out")).accessibilityIdentifier("account.fixture.identity")
          HStack {
            Button("Recovery") { openRecovery() }
            Button("Draft") { draftOpen = true }
            Button("Login B") { Task { await session.login(email: "b@example.invalid", password: "fixture", api: api) } }
            Button("Logout") { session.logout() }
          }
        }.font(.caption).padding(8).background(.regularMaterial)
      }
      .sheet(isPresented: $draftOpen) {
        VStack {
          TextField("Draft", text: $draft).accessibilityIdentifier("account.fixture.draft")
          Button("Recovery over draft") { openRecovery() }
          Button("Close draft") { draftOpen = false }
        }.padding()
      }
      .onAppear {
        if ProcessInfo.processInfo.arguments.contains("--recovery-cold-link") { openRecovery() }
      }
  }
  private func openRecovery() {
    let expired = ProcessInfo.processInfo.arguments.contains("--recovery-expired")
    let url = URL(string: "captro://auth/reset-password#type=recovery&access_token=\(expired ? "expired" : "fixture-recovery-b")")!
    session.handleIncomingURL(url)
    session.handleIncomingURL(url) // repeated delivery must still present exactly once
  }
}
private final class AccountFlowFixtureStorage: MIRAAuthSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var access: String?, refresh: String?
  func accessToken() async -> String? { lock.withLock { access } }
  func refreshToken() async -> String? { lock.withLock { refresh } }
  func saveSession(accessToken: String, refreshToken: String?) { lock.withLock { access=accessToken;refresh=refreshToken } }
  func clearSession() { lock.withLock { access=nil;refresh=nil } }
}
private final class AccountFlowFixtureProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true } // isolate every fixture request
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let flags=ProcessInfo.processInfo.arguments, path=request.url?.path ?? ""
    var status=200, json="{}"
    if path == "/auth/me" {
      json="{\"id\":\"fixture-a\",\"username\":\"fixture_a\",\"username_required\":\(flags.contains("--account-onboarding")),\"status\":\"\(flags.contains("--account-deletion") ? "deletion_pending" : "active")\"}"
    } else if path == "/auth/login" || path == "/auth/password/reset/confirm" {
      if flags.contains("--recovery-expired") && path.hasSuffix("confirm") { status=401;json="{\"code\":\"PASSWORD_RESET_EXPIRED\",\"detail\":\"Recovery link expired. Request a new email.\"}" }
      else { json="{\"access_token\":\"fixture-b\",\"refresh_token\":\"fixture-refresh-b\",\"user\":{\"id\":\"fixture-b\",\"username\":\"fixture_b\"}}" }
    } else if path.contains("posts") || path.contains("statuses") { json="[]" }
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:Data(json.utf8));client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif
