#if DEBUG
import Foundation

/// Explicit UI-test transport only. Never installed in a production API client.
enum CaptroComposerTestAPI {
  static func make() -> MIRAAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CaptroComposerTestProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://composer-test.invalid/api")!,
      session: URLSession(configuration: config))
  }
}
private final class CaptroComposerTestProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "composer-test.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    let authorized = ProcessInfo.processInfo.arguments.contains("--captro-composer-authorized")
    let body: String
    let status: Int
    if path.hasSuffix("/auth/me") {
      body = #"{"id":"composer-ui-test","full_name":"Test Creator","username":"test_creator","is_private":false}"#
      status = 200
    } else if path.hasSuffix("/posts/creation-capabilities") {
      body = authorized ? #"{"structured_types":["club","event","meetup","deal"]}"# : #"{"structured_types":[]}"#
      status = 200
    } else {
      // Fail submissions honestly to exercise draft retention and retries, never fake success.
      body = #"{"detail":"Test publishing failure. Your draft is still here.","code":"TEST_PUBLISH_FAILURE"}"#
      status = 503
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif

