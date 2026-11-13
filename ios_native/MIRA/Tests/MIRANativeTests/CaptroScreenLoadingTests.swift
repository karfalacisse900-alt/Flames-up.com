import XCTest
import UIKit
@testable import MIRANative

@MainActor
final class CaptroScreenLoadingTests: XCTestCase {
  private func api() -> MIRAAPIClient {
    PolishLoadingProtocol.reset()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PolishLoadingProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://localhost")!, session: URLSession(configuration: config))
  }
  func testEmptyInboxIsAValidFreshResponse() async {
    let model = ChatNativeModel(api: api())
    model.configure(currentUserId: "polish-\(UUID())")
    await model.load(); await model.load()
    XCTAssertEqual(PolishLoadingProtocol.count("/conversations"), 1)
    XCTAssertTrue(model.conversations.isEmpty)
    XCTAssertNil(model.loadError)
    await model.load(forceRefresh: true)
    XCTAssertEqual(PolishLoadingProtocol.count("/conversations"), 2)
  }
  func testChatReopenDoesNotRepeatInitialSyncAndFailureCanRecover() async {
    let client = api()
    let model = ConversationNativeModel(kind: .direct(peerId: "polish-peer"), api: client, currentUserId: "polish-\(UUID())")
    PolishLoadingProtocol.fail = true
    await model.load()
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.isLoading)
    PolishLoadingProtocol.fail = false
    await model.load(); await model.load()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(PolishLoadingProtocol.count("/messages/polish-peer"), 2)
  }
  func testNotificationFreshnessAndExplicitRefreshFailure() async {
    MIRALocalJSONCache.setAccountScope(userId: "polish-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let model = NotificationNativeModel(api: api())
    await model.load(); await model.load()
    XCTAssertEqual(PolishLoadingProtocol.count("/notifications"), 1)
    PolishLoadingProtocol.fail = true
    await model.load(force: true)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.isLoading)
    PolishLoadingProtocol.fail = false
    await model.load(force: true)
    XCTAssertNil(model.errorMessage)
  }
  func testSettingsReturnUsesFreshDataAndRefreshKeepsUserOnFailure() async {
    MIRALocalJSONCache.setAccountScope(userId: "polish-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let model = SettingsNativeModel(api: api(), authSession: nil)
    await model.load(); await model.load()
    XCTAssertEqual(PolishLoadingProtocol.count("/auth/me"), 1)
    XCTAssertEqual(model.user?.id, "polish-user")
    PolishLoadingProtocol.fail = true
    await model.load(force: true)
    XCTAssertEqual(model.user?.id, "polish-user")
    XCTAssertNotNil(model.loadError)
    XCTAssertFalse(model.isLoading)
    MIRALocalJSONCache.setAccountScope(userId: "polish-other-\(UUID())")
    await model.load()
    XCTAssertNil(model.user, "The previous account's fresh settings must not survive a scope change")
    XCTAssertEqual(PolishLoadingProtocol.count("/auth/me"), 3)
  }
  func testThemeCanvasAndTextContrastInBothAppearances() {
    for style: UIUserInterfaceStyle in [.light, .dark] {
      let traits = UITraitCollection(userInterfaceStyle: style)
      let canvas = UIColor(MIRATheme.Color.appBackground).resolvedColor(with: traits)
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      canvas.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      XCTAssertEqual(red, style == .light ? 1 : 0, accuracy: 0.001)
      XCTAssertEqual(red, green, accuracy: 0.001); XCTAssertEqual(green, blue, accuracy: 0.001)
      func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
      }
      for (text, background) in [(MIRATheme.Color.textPrimary, MIRATheme.Color.appBackground),
                                 (MIRATheme.Color.textSecondary, MIRATheme.Color.appBackground),
                                 (MIRATheme.Color.onPrimary, MIRATheme.Color.forest)] {
        let a = luminance(UIColor(text)), b = luminance(UIColor(background))
        XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
      }
    }
  }
}

private final class PolishLoadingProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var counts: [String: Int] = [:]
  private static var failed = false
  static var fail: Bool {
    get { lock.withLock { failed } }
    set { lock.withLock { failed = newValue } }
  }
  static func reset() { lock.withLock { counts = [:]; failed = false } }
  static func count(_ path: String) -> Int { lock.withLock { counts[path, default: 0] } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    Self.lock.withLock { Self.counts[url.path, default: 0] += 1 }
    let failed = Self.fail
    let body = failed ? #"{"detail":"Isolated failure"}"# : url.path == "/auth/me" ? #"{"id":"polish-user","username":"fixture"}"# : "[]"
    let response = HTTPURLResponse(url: url, statusCode: failed ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
