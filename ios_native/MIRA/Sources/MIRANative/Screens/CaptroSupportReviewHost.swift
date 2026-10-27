#if DEBUG
import SwiftUI
import Foundation

/// Real shipping sheet with isolated API and a deliberately failing browser
/// opener. Never contacts Stripe, uses a credential, or fakes payment success.
public struct CaptroSupportReviewHost: View {
  @StateObject private var returns = CaptroSupportReturnStore()
  private let api: MIRAAPIClient
  private let flags = ProcessInfo.processInfo.arguments
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SupportReviewTransport.self]
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9453")!, session: URLSession(configuration: configuration))
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
  }
  public var body: some View {
    Group {
      if flags.contains("--support-profile") {
        NavigationStack { UserProfileNativeView(userId: "fixture-creator", api: api) }
      } else if flags.contains("--support-details") {
        NavigationStack { PostDetailNativeView(post: SupportReviewTransport.post, api: api) }
      } else {
        CaptroSupportSheet(creatorID: "fixture-creator", name: "Fixture Creator", username: "fixture", avatar: nil,
          api: api, originPostID: "fixture-post", checkoutAvailable: !flags.contains("--support-live-disabled"),
          currentStorefront: { "USA" }, openBrowser: { _ in false })
      }
    }
      .environmentObject(returns).environmentObject(MIRALocalization.shared)
      .environment(\.captroSupportViewerID, flags.contains("--support-guest") ? nil : flags.contains("--support-self") ? "fixture-creator" : "fixture-buyer")
      .environment(\.captroSupportRuntime, CaptroSupportRuntime(enabled: !flags.contains("--support-live-disabled"),
        currentStorefront: { flags.contains("--support-non-us") ? "GBR" : "USA" }, openBrowser: { _ in false }))
      .environment(\.dynamicTypeSize, flags.contains("--support-large-text") ? .accessibility3 : .large)
  }
}
private final class SupportReviewTransport: URLProtocol {
  static let postJSON = """
    {"id":"fixture-post","user_id":"fixture-creator","user_username":"fixture","user_full_name":"Fixture Creator","content":"Isolated support interaction fixture","caption":"Isolated support interaction fixture","post_type":"photo"}
    """
  static var post: MIRAPost {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(MIRAPost.self, from: Data(postJSON.utf8))
  }
  private static let lock = NSLock()
  private static var eligibilityCalls = 0
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? "", flags = ProcessInfo.processInfo.arguments
    var status = 200, body = "{}"
    if path == "/creator-support/handoffs" {
      body = "{\"id\":\"12345678-1234-4234-8234-123456789012\",\"url\":\"https://captro-site.pages.dev/support-creator/#handoff=\(String(repeating: "a", count: 64))\"}"
    } else if path == "/creator-support/eligibility/fixture-creator" {
      let attempt = Self.lock.withLock { Self.eligibilityCalls += 1; return Self.eligibilityCalls }
      print("SUPPORT_FIXTURE eligibility request \(attempt)") // DEBUG-only synthetic transport, no URLs/tokens.
      if flags.contains("--support-eligibility-error") && attempt == 1 {
        status = 503; body = "{\"code\":\"CAPTRO_SUPPORT_RETRY\",\"detail\":\"Availability could not be checked\"}"
      } else { body = "{\"enabled\":\(flags.contains("--support-ineligible") ? "false" : "true"),\"mode\":\"live\"}" }
    } else if path == "/users/fixture-creator" {
      body = "{\"id\":\"fixture-creator\",\"username\":\"fixture\",\"full_name\":\"Fixture Creator\",\"bio\":\"Isolated profile fixture\",\"followers_count\":2,\"following_count\":1,\"is_private\":false,\"privacy_locked\":false}"
    } else if path == "/users/fixture-creator/showcase" { body = "{\"clubs\":[]}" }
    else if path == "/posts/fixture-post" { body = Self.postJSON }
    else if path == "/auth/me" { body = "{\"id\":\"fixture-buyer\",\"username\":\"buyer\"}" }
    else if path.hasSuffix("/posts") || path.hasSuffix("/comments") { body = "[]" }
    else { status = 404 }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
      httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif
