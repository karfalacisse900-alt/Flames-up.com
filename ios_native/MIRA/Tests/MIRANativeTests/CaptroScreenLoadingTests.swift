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
  func testVisitorSectionsOnlyCollapseAfterConfirmedEmptyLoad() async {
    let model = UserProfileNativeModel(userId: "polish-visitor", api: api())
    XCTAssertEqual(model.visibleSections, CaptroProfileSection.allCases)
    await model.load()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.visibleSections, [.moments])
    model.canLoadMore = true
    XCTAssertTrue(model.visibleSections.contains(.plans), "Later pages may contain plans")
    model.errorMessage = "Offline"
    XCTAssertEqual(model.visibleSections, CaptroProfileSection.allCases)
  }

  func testPresentationReusePreservesChatDraftAndViewportAndClearsOnAccountSwitch() {
    MIRALocalJSONCache.setAccountScope(userId: "presentation-a")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let client = api()
    let room = client.presentations.room(.direct(peerId: "friend"), userID: "presentation-a")
    room.draft = "Keep my unfinished message"
    let reopened = client.presentations.room(.direct(peerId: "friend"), userID: "presentation-a")
    XCTAssertTrue(room === reopened); XCTAssertTrue(room.viewport === reopened.viewport)
    XCTAssertEqual(reopened.draft, "Keep my unfinished message")
    let other = client.presentations.room(.direct(peerId: "other"), userID: "presentation-a")
    XCTAssertEqual(other.draft, "")
    MIRALocalJSONCache.setAccountScope(userId: "presentation-b")
    let switched = client.presentations.room(.direct(peerId: "friend"), userID: "presentation-b")
    XCTAssertFalse(room === switched); XCTAssertFalse(room.valid)
    XCTAssertEqual(room.draft, ""); XCTAssertEqual(switched.draft, "")
  }
  func testCancelledChatReadDoesNotBecomeReconnectErrorAndRetryRecovers() async {
    let client = api()
    let model = ConversationNativeModel(kind: .direct(peerId: "polish-peer"), api: client, currentUserId: "polish-\(UUID())")
    PolishLoadingProtocol.cancelNextRead()
    await model.load()
    XCTAssertNil(model.errorMessage); XCTAssertNil(model.syncNotice)
    XCTAssertFalse(model.isLoading)
    await model.load()
    XCTAssertEqual(PolishLoadingProtocol.count("/messages/polish-peer"), 2)
    XCTAssertNil(model.errorMessage)
  }
  func testRetryCannotResendAnAcknowledgedMessageFromAnOldButton() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "send-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let client = api()
    let model = ConversationNativeModel(kind: .direct(peerId: "polish-peer"), api: client, currentUserId: "polish-user")
    model.draft = "One message"
    await model.sendText()
    let failed = try XCTUnwrap(model.messages.first)
    XCTAssertEqual(failed.status, "failed")
    await model.retry(failed)
    XCTAssertEqual(model.messages.count, 1)
    XCTAssertEqual(model.messages.first?.status, "sent")
    await model.retry(failed)
    let ids = PolishLoadingProtocol.sendIDs
    XCTAssertEqual(ids.count, 2)
    XCTAssertFalse(ids.first?.isEmpty ?? true)
    XCTAssertEqual(ids.first, ids.last, "Ambiguous delivery retries must keep their durable identity")
  }
  func testPrivateProfileIsFreshWithoutFetchingRestrictedContent() async {
    let client = api()
    PolishLoadingProtocol.privateProfile = true
    let model = client.presentations.profile("polish-visitor")
    await model.revalidateIfStale(); await model.revalidateIfStale()
    XCTAssertEqual(model.user?.privacyLocked, true)
    XCTAssertTrue(model.posts.isEmpty)
    XCTAssertEqual(PolishLoadingProtocol.count("/users/polish-visitor"), 1)
    XCTAssertEqual(PolishLoadingProtocol.count("/users/polish-visitor/posts"), 0)
  }
  func testPaginationDenialClearsPreviouslyAuthorizedProfileContent() async {
    let client = api()
    PolishLoadingProtocol.fullProfilePage = true
    let model = client.presentations.profile("polish-visitor")
    await model.load()
    XCTAssertNotNil(model.user); XCTAssertTrue(model.canLoadMore)
    PolishLoadingProtocol.denyProfilePosts = true
    await model.loadMore()
    XCTAssertNil(model.user); XCTAssertTrue(model.posts.isEmpty)
    XCTAssertFalse(model.canLoadMore); XCTAssertNotNil(model.errorMessage)
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

  func testProfileIdentityMismatchEndsLoadingInsteadOfSpinningBesideError() async throws {
    MIRALocalJSONCache.setAccountScope(userId: "polish-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let model = ProfileNativeModel(api: api())
    let previous = try JSONDecoder().decode(MIRAUser.self, from: Data(#"{"id":"different-account","username":"previous"}"#.utf8))
    model.primeUser(previous)
    await model.load()
    XCTAssertTrue(model.hasLoadedProfile)
    XCTAssertNil(model.user)
    XCTAssertNotNil(model.profileError)
  }

  func testDiscoverFailureIsNotEmptySuccessAndRetryBecomesFresh() async {
    MIRALocalJSONCache.setAccountScope(userId: "polish-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let model = DiscoverNativeModel(api: api())
    PolishLoadingProtocol.fail = true
    await model.refreshVisiblePosts()
    XCTAssertNotNil(model.postsLoadError)
    XCTAssertFalse(model.isLoadingPosts)
    PolishLoadingProtocol.fail = false
    await model.refreshVisiblePosts()
    XCTAssertNil(model.postsLoadError)
    XCTAssertFalse(model.isLoadingPosts)
    let requests = PolishLoadingProtocol.count("/discover")
    await model.refreshVisiblePosts(force: false)
    XCTAssertEqual(PolishLoadingProtocol.count("/discover"), requests)
  }

  func testVisitorProfileRejectsOldAccountCompletionAndFreshReopenDoesNotRefetch() async {
    MIRALocalJSONCache.setAccountScope(userId: "polish-a-\(UUID())")
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let client = api()
    let model = client.presentations.profile("polish-visitor")
    let started = expectation(description: "Old account profile read held")
    PolishLoadingProtocol.holdProfile { started.fulfill() }
    let old = Task { await model.revalidateIfStale() }
    await fulfillment(of: [started], timeout: 2)
    MIRALocalJSONCache.setAccountScope(userId: "polish-b-\(UUID())")
    PolishLoadingProtocol.releaseProfile()
    await old.value
    XCTAssertNil(model.user, "An old viewer's response must never populate the new scope")
    XCTAssertFalse(model.isLoading)
    XCTAssertFalse(model.valid)
    let next = client.presentations.profile("polish-visitor")
    XCTAssertFalse(next === model)
    await next.revalidateIfStale()
    XCTAssertEqual(next.user?.id, "polish-visitor")
    XCTAssertNil(next.errorMessage)
    await next.revalidateIfStale()
    XCTAssertEqual(PolishLoadingProtocol.count("/users/polish-visitor"), 2)
    XCTAssertEqual(PolishLoadingProtocol.count("/users/polish-visitor/posts"), 1)
  }
}

private final class PolishLoadingProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var counts: [String: Int] = [:]
  private static var failed = false
  private static var lockedProfile = false, fullPage = false, deniedPosts = false
  static var privateProfile: Bool { get { lock.withLock { lockedProfile } } set { lock.withLock { lockedProfile = newValue } } }
  static var fullProfilePage: Bool { get { lock.withLock { fullPage } } set { lock.withLock { fullPage = newValue } } }
  static var denyProfilePosts: Bool { get { lock.withLock { deniedPosts } } set { lock.withLock { deniedPosts = newValue } } }
  private static var cancelRead = false
  private static var sentIDs: [String] = []
  static var sendIDs: [String] { lock.withLock { sentIDs } }
  static func cancelNextRead() { lock.withLock { cancelRead = true } }
  private static var heldProfile: PolishLoadingProtocol?
  private static var onProfileHeld: (() -> Void)?
  static var fail: Bool {
    get { lock.withLock { failed } }
    set { lock.withLock { failed = newValue } }
  }
  static func reset() { lock.withLock { counts = [:]; failed = false; cancelRead = false; sentIDs = []; lockedProfile = false; fullPage = false; deniedPosts = false } }
  static func count(_ path: String) -> Int { lock.withLock { counts[path, default: 0] } }
  static func holdProfile(_ started: @escaping () -> Void) { lock.withLock { onProfileHeld = started } }
  static func releaseProfile() {
    let held = lock.withLock { let value = heldProfile; heldProfile = nil; return value }
    held?.respond()
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    if request.httpMethod == "POST", url.path == "/messages" {
      var data = request.httpBody ?? Data()
      if data.isEmpty, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&bytes, maxLength: bytes.count)
          if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
        }
      }
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
      let id = body["client_request_id"] as? String ?? ""
      let attempt = Self.lock.withLock { Self.sentIDs.append(id); return Self.sentIDs.count }
      if attempt == 1 { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(#"{"id":"acknowledged","sender_id":"polish-user","receiver_id":"polish-peer","content":"One message","created_at":"2026-11-15T12:00:00Z","status":"sent"}"#.utf8))
      client?.urlProtocolDidFinishLoading(self); return
    }
    let canceled = Self.lock.withLock { let value = Self.cancelRead; Self.cancelRead = false; return value }
    Self.lock.withLock { Self.counts[url.path, default: 0] += 1 }
    if canceled { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return }
    if url.path == "/users/polish-visitor" {
      let started: (() -> Void)? = Self.lock.withLock {
        guard let callback = Self.onProfileHeld else { return nil }
        Self.onProfileHeld = nil; Self.heldProfile = self; return callback
      }
      if let started { started(); return }
    }
    respond()
  }
  private func respond() {
    let url = request.url!
    let denied = Self.denyProfilePosts && url.path.hasSuffix("/posts")
    let failed = Self.fail || denied
    let body: String
    if failed { body = #"{"detail":"Isolated failure"}"# }
    else if url.path == "/auth/me" { body = #"{"id":"polish-user","username":"fixture"}"# }
    else if url.path == "/users/polish-visitor" { body = Self.privateProfile ? #"{"id":"polish-visitor","username":"visitor","privacyLocked":true}"# : #"{"id":"polish-visitor","username":"visitor"}"# }
    else if url.path.hasSuffix("/posts"), Self.fullProfilePage {
      let rows = (0..<60).map { ["id": "profile-fixture-\($0)", "images": ["https://example.invalid/image.jpg"]] as [String: Any] }
      body = String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
    }
    else if url.path.hasSuffix("/showcase") { body = #"{"pinned":null,"clubs":[]}"# }
    else { body = "[]" }
    let response = HTTPURLResponse(url: url, statusCode: denied ? 403 : failed ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
