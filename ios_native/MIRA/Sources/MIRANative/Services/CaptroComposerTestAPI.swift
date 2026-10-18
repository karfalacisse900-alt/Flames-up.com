#if DEBUG
import Foundation

/// Explicit UI-test transport only. Never installed in a production API client.
enum CaptroComposerTestAPI {
  static func make() -> MIRAAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CaptroComposerTestProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://localhost/api")!,
      session: URLSession(configuration: config))
  }
}
private final class CaptroComposerTestProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "localhost" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    let authorized = ProcessInfo.processInfo.arguments.contains("--captro-composer-authorized")
    let body: String
    let status: Int
    if ProcessInfo.processInfo.arguments.contains("--captro-presentation-review"),
       request.httpMethod == "GET", path == "/api/posts/review-post" {
      body = String(data: try! JSONSerialization.data(withJSONObject: CaptroPresentationReviewFixture.postRecord), encoding: .utf8)!
      status = 200
    } else if ProcessInfo.processInfo.arguments.contains("--captro-presentation-review"),
       request.httpMethod == "GET", path.contains("/commerce/posts/"),
       let commerce = CaptroPresentationReviewFixture.commerceRecord {
      body = String(data: try! JSONSerialization.data(withJSONObject: ["commerce": commerce]), encoding: .utf8)!
      status = 200
    } else if ProcessInfo.processInfo.arguments.contains("--captro-presentation-review"),
       request.httpMethod == "GET", path.hasSuffix("/comments") {
      body = "[]"; status = 200
    } else if ProcessInfo.processInfo.arguments.contains("--captro-presentation-review"),
       request.httpMethod == "GET", path.hasSuffix("/posts/review-post/object") {
      body = "{}"; status = 200 // This viewer has no private ticket/document.
    } else if path.hasSuffix("/auth/me") || path.hasSuffix("/users/profile-visitor-fixture") {
      if ProcessInfo.processInfo.arguments.contains("--captro-profile-private") && path.hasSuffix("profile-visitor-fixture") {
        body = #"{"id":"profile-visitor-fixture","full_name":"Private Creator","username":"private_creator","is_private":true,"privacy_locked":true}"#
      } else {
        body = #"{"id":"composer-ui-test","full_name":"Test Creator","username":"test_creator","is_private":false,"bio":"City walks, photography and finding good coffee.","city":"New York","open_to":"Photo walks · Creative projects","followers_count":128,"following_count":86}"#
      }
      status = 200
    } else if path.hasSuffix("/showcase") {
      body = #"{"pinned":null,"clubs":[]}"#; status = 200
    } else if path.hasSuffix("/posts/creation-capabilities") {
      body = authorized ? #"{"structured_types":["club","event","meetup","deal"]}"# : #"{"structured_types":[]}"#
      status = 200
    } else if path.hasSuffix("/users/composer-ui-test/posts") || path.hasSuffix("/users/profile-visitor-fixture/posts") || path.hasSuffix("/statuses") || path.hasSuffix("/conversations") || path.hasSuffix("/follow-requests") {
      body = "[]"
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

