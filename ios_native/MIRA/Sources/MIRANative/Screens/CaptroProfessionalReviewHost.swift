#if DEBUG
import Foundation
import SwiftUI

/// Isolated transport around shipping Settings and visitor profile screens.
public struct CaptroProfessionalReviewHost: View {
  private let api: MIRAAPIClient
  @StateObject private var session: MIRAAuthSession
  public init() {
    let defaults = UserDefaults(suiteName: "captro.professional.review")!
    defaults.removePersistentDomain(forName: "captro.professional.review")
    let auth = MIRAAuthSession(keychain: ProfessionalReviewStorage(), defaults: defaults)
    _session = StateObject(wrappedValue: auth)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProfessionalReviewProtocol.self]
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost/api")!, sessionProvider: auth, session: URLSession(configuration: config))
  }
  public var body: some View {
    NavigationStack {
      if ProcessInfo.processInfo.arguments.contains("--professional-profile") {
        UserProfileNativeView(userId: "sample", api: api)
      } else { SettingsNativeView(api: api, authSession: session) }
    }
    .environmentObject(MIRALocalization.shared)
    .environment(\.captroSupportViewerID, "viewer")
    .environment(\.captroSupportRuntime, CaptroSupportRuntime(enabled: true, currentStorefront: { "USA" }, openBrowser: { _ in false }))
    .preferredColorScheme(.light)
    .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--professional-large-text") ? .accessibility1 : .large)
  }
}
private final class ProfessionalReviewStorage: MIRAAuthSessionStorage, @unchecked Sendable {
  func accessToken() async -> String? { "professional-test-only" }
  func refreshToken() async -> String? { nil }
  func saveSession(accessToken: String, refreshToken: String?) {}
  func clearSession() {}
}
private final class ProfessionalReviewProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var applications: [[String:Any]] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.path.replacingOccurrences(of: "/api", with: "")
    let flags = ProcessInfo.processInfo.arguments
    let creator = flags.contains("--professional-creator")
    let business = flags.contains("--professional-business")
    let data: [String:Any] = ["displayName":creator ? "Sam Rivera" : "Sample Coffee", "category":creator ? "photographer" : "coffee_bakery", "description":creator ? "Portraits, live shows and the city between them." : "Coffee and fresh pastries in Brooklyn.", "area":"Brooklyn", "links":[], "pickup":!creator, "portfolioPostIds":[]]
    var payload: Any = [String:Any](); var status = 200
    if path == "/auth/me" || path == "/users/sample" {
      payload = ["id":path == "/auth/me" ? "viewer" : "sample", "username":"sample_profile", "fullName":"Sam Rivera", "bio":"Sharing everyday moments.", "followersCount":12, "followingCount":8, "postsCount":0, "professional":creator || business ? [["role":creator ? "creator" : "business"].merging(data) { _,n in n }] : []]
    } else if path == "/professional/me" {
      payload = ["applications":Self.lock.withLock { Self.applications },"roles":[]]
    } else if path.hasPrefix("/professional/creator/") {
      let body = readBody().flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String:Any] ?? [:]
      if flags.contains("--professional-rejected") { status=409; payload=["detail":"Application changed. Reload before submitting."] }
      else {
        Self.lock.withLock { Self.applications = [["role":"creator","status":path.hasSuffix("submit") ? "under_review" : "draft","public_data":body["public"] ?? [:],"version":1,"applicant_message":body["message"] ?? ""]] }
        payload=["ok":true]
      }
    } else if path.hasPrefix("/creator-support/eligibility/") { payload=["visible":creator,"enabled":false,"mode":"test","reason":"rollout_disabled"] }
    else if path.hasSuffix("/showcase") { payload=["clubs":[]] }
    else if path.hasSuffix("/posts") || path == "/blocks" { payload=[] as [String] }
    guard let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"]), let bytes = try? JSONSerialization.data(withJSONObject: payload) else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
  }
  private func readBody() -> Data? {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return nil }; stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating:0,count:4096)
    while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; data.append(contentsOf:buffer.prefix(n)) }
    return data
  }
  override func stopLoading() {}
}
#endif
