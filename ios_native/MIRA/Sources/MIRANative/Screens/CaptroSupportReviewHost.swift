#if DEBUG
import SwiftUI
import Foundation

/// Real shipping sheet with isolated API and a deliberately failing browser
/// opener. Never contacts Stripe, uses a credential, or fakes payment success.
public struct CaptroSupportReviewHost: View {
  @StateObject private var returns = CaptroSupportReturnStore()
  private let api: MIRAAPIClient
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SupportReviewTransport.self]
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9453")!, session: URLSession(configuration: configuration))
  }
  public var body: some View {
    CaptroSupportSheet(creatorID: "fixture-creator", name: "Fixture Creator", username: "fixture", avatar: nil,
      api: api, originPostID: "fixture-post", currentStorefront: { "USA" }, openBrowser: { _ in false })
      .environmentObject(returns).environmentObject(MIRALocalization.shared)
      .environment(\.captroSupportViewerID, "fixture-buyer")
      .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--support-large-text") ? .accessibility3 : .large)
  }
}
private final class SupportReviewTransport: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let valid = request.url?.path == "/creator-support/handoffs"
    let body = valid ? "{\"id\":\"12345678-1234-4234-8234-123456789012\",\"url\":\"https://captro-site.pages.dev/support-creator/#handoff=\(String(repeating: "a", count: 64))\"}" : "{}"
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 404,
      httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif
