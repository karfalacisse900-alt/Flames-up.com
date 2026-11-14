#if DEBUG
import Foundation
import SwiftUI

struct CaptroTeaReviewHost: View {
  @StateObject private var context = TeaReviewContext()

  var body: some View {
    MIRANativeRootView(reviewSession: context.session, api: context.api)
      .environment(\.captroStartupReducedMotion, true)
      .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--captro-quality-large-text") ? .accessibility2 : .large)
  }
}

/// Keep the transport and account namespace stable through scene updates,
/// just as the production App owns its API client across foreground resumes.
@MainActor
private final class TeaReviewContext: ObservableObject {
  let session: MIRAAuthSession
  let api: MIRAAPIClient

  init() {
    // This host mounts the real root, which reads the persisted appearance.
    // Keep it consistent with the fixture's requested mode, including covers.
    UserDefaults.standard.set(
      ProcessInfo.processInfo.arguments.contains("--captro-quality-dark")
        ? MIRAAppearance.dark.rawValue : MIRAAppearance.light.rawValue,
      forKey: MIRAAppearanceResolver.preferenceKey)
    let storage = TeaReviewStorage()
    let defaults = UserDefaults(suiteName: "captro.tea.review")!
    defaults.removePersistentDomain(forName: "captro.tea.review")
    let auth = MIRAAuthSession(keychain: storage, defaults: defaults)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TeaReviewProtocol.self]
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    session = auth
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost/api")!, sessionProvider: auth,
                       session: URLSession(configuration: config))
  }

}

private final class TeaReviewStorage: MIRAAuthSessionStorage, @unchecked Sendable {
  func accessToken() async -> String? { "tea-fixture-token" }
  func refreshToken() async -> String? { "tea-fixture-refresh" }
  func saveSession(accessToken: String, refreshToken: String?) {}
  func clearSession() {}
}

private final class TeaReviewProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var purchases: Set<Int> = []
  private static var deliveredError = false
  private static var detailRequests: [Int: Int] = [:]
  private static var conversations: [String: [String: Any]] = [:]
  private static var discussionReplies: [String: [[String: Any]]] = [:]
  private var delivery: DispatchWorkItem?

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "localhost" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  private func id(_ number: Int) -> String {
    "00000000-0000-4000-8000-" + String(format: "%012d", number)
  }

  private func entry(_ number: Int) -> [String: Any] {
    let fixtures = [
      ("Night Garden", "club", "sage", "people"),
      ("Photo Walk", "meetup", "navy", "people"),
      ("Rooftop Session", "event", "lilac", "calendar"),
      ("Sample Bakery", "business", "sand", "storefront"),
      ("Weekend Pastry Offer", "offer", "sky", "ticket"),
      ("Studio Reservation", "reservation", "lilac", "calendar"),
    ]
    let selected = fixtures.indices.contains(number - 1) ? fixtures[number - 1] : ("Neighborhood event \(number)", "event", "lilac", "calendar")
    let source = selected.1 == "business" ? "business" : "activity"
    let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(number * 180)))
    return ["id": "\(source):\(id(number))", "name": selected.0, "kind": selected.1,
      "color": selected.2, "icon": selected.3, "timestamp": timestamp, "status": "active",
      "destination": ["id": id(number), "source": source]]
  }

  private func commerce(_ number: Int) -> [String: Any] {
    let item = entry(number)
    let isPaid = number == 3
    let kind = item["kind"] as? String ?? "event"
    let fulfillment: String
    switch number {
    case 1: fulfillment = "membership"
    case 2: fulfillment = "attendance"
    case 5: fulfillment = "redemption"
    case 6: fulfillment = "reservation"
    default: fulfillment = "ticket"
    }
    let date = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
    let active = Self.lock.withLock { Self.purchases.contains(number) }
    var result: [String: Any] = [
      "id": id(number), "contentType": number == 5 ? "deal" : kind, "fulfillmentType": fulfillment,
      "paymentModel": isPaid ? "paid" : "free", "commerceClass": "physical",
      "title": item["name"] ?? "", "description": "An independent neighborhood activity.",
      "city": "New York", "joinedCount": 8, "remaining": 12, "status": "active",
      "refundPolicy": "", "approvalRequired": false, "passRequired": isPaid, "audience": "anyone",
      "prices": [["id": "price-\(number)", "label": "General", "unitAmount": isPaid ? 2000 : 0,
                  "currency": "USD", "billingPeriod": "one_time", "active": true]],
    ]
    if [2, 3].contains(number) { result["startsAt"] = date }
    if number == 5 { result["expiresAt"] = date }
    if active { result["viewerStatus"] = "active" }
    return result
  }

  override func startLoading() {
    guard let url = request.url else { return }
    let path = String(url.path.dropFirst(4))
    var status = 200
    var payload: Any = [String: Any]()
    if path.hasPrefix("/tea/conversations") { discussion(path); return }
    if path == "/auth/me" {
      payload = ["id": "tea-viewer", "username": "tea_fixture", "city": "New York", "status": "active"]
    } else if path == "/tea" {
      let shouldFail = ProcessInfo.processInfo.arguments.contains("--tea-initial-error")
        && Self.lock.withLock {
          if Self.deliveredError { return false }
          Self.deliveredError = true
          return true
        }
      if shouldFail {
        status = 503
      } else if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "cursor" }) == true {
        payload = ["items": (21...26).map(entry)]
      } else {
        payload = ["items": (1...20).map(entry), "nextCursor": "tea-fixture-second-page"]
      }
    } else if path.hasPrefix("/tea/"), let number = Int(url.lastPathComponent.suffix(12)) {
      let count = Self.lock.withLock {
        Self.detailRequests[number, default: 0] += 1
        return Self.detailRequests[number]!
      }
      DispatchQueue.main.async { TeaReviewMetrics.shared.counts[number] = count }
      let flags = ProcessInfo.processInfo.arguments
      if number == 3 && ((flags.contains("--tea-detail-retry") && count == 1)
                         || (flags.contains("--tea-refresh-failure") && count == 2)) {
        reply(503, ["detail": "Isolated network failure"]); return
      }
      if number == 4 {
        payload = ["item": entry(number), "business": [
          "id": id(number), "name": "Sample Bakery", "category": "coffee_bakery", "pickupAddress": "Sample pickup",
          "latitude": 40.72, "longitude": -74.0, "hours": "8 am–4 pm", "paused": false, "published": true, "photos": [],
        ]]
      } else {
        payload = ["item": entry(number), "post": ["id": "tea-post-\(number)", "userId": "tea-fixture-owner"],
                   "commerce": commerce(number), "linkedEvents": number == 1 ? [entry(3)] : []]
      }
    } else if path.hasPrefix("/commerce/posts/"), let number = Int(url.lastPathComponent.split(separator: "-").last ?? "") {
      payload = ["commerce": commerce(number)]
    } else if path == "/payments/create" {
      guard let body = readBody(),
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            let post = json["post_id"] as? String, let number = Int(post.split(separator: "-").last ?? ""),
            json["purchasable_id"] as? String == id(number), json["price_id"] as? String == "price-\(number)",
            json["idempotency_key"] as? String != nil else {
        reply(400, ["detail": "The fixture received an incorrect commerce request."])
        return
      }
      let paid = number == 3
      let record = commerce(number)
      var response: [String: Any] = ["purchase": [
        "id": "purchase-\(number)", "postId": post, "purchasableId": id(number), "contentType": record["contentType"] ?? "",
        "fulfillmentType": record["fulfillmentType"] ?? "", "itemTitle": record["title"] ?? "",
        "priceLabel": paid ? "$20" : "Free", "quantity": 1, "unitAmount": paid ? 2000 : 0,
        "totalAmount": paid ? 2000 : 0, "currency": "USD", "status": paid ? "payment_pending" : "confirmed",
      ]]
      if paid {
        response["paymentSheet"] = [
          "purchaseId": "purchase-\(number)", "mode": "test", "publishableKey": "pk_test_tea_fixture",
          "paymentIntentClientSecret": "pi_fixture_secret_fixture", "merchantDisplayName": "Captro",
          "returnURL": "captro://stripe-redirect", "merchantCountryCode": "US",
        ]
      } else {
        _ = Self.lock.withLock { Self.purchases.insert(number) }
      }
      payload = response
    } else if path.hasPrefix("/feed") || path.contains("posts") || path.contains("statuses") || path.hasSuffix("/menu") {
      payload = [] as [String]
    }
    if path.hasPrefix("/tea/"), ProcessInfo.processInfo.arguments.contains("--tea-slow") {
      let work = DispatchWorkItem { [weak self] in self?.reply(status, payload) }
      delivery = work
      DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: work)
    } else { reply(status, payload) }
  }

  private func discussion(_ path: String) {
    let method = request.httpMethod ?? "GET"
    let body = readBody().flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    let result: (Int, Any) = Self.lock.withLock {
      if Self.conversations.isEmpty {
        for n in 101...104 {
          let links: [String] = n == 101 ? ["https://www.youtube.com/watch?v=fixture", "https://www.tiktok.com/@fixture", "https://example.com/intro?tracking=hidden"] : n == 103 ? ["https://example.com/one"] : []
          Self.conversations[id(n)] = ["id": id(n), "title": n == 101 ? "Which music video intro works better?" : n == 102 ? "Where do you find creative inspiration?" : n == 103 ? "A useful website" : "My next project",
            "body": "I’m trying two openings for a new music video. What holds your attention, and why?", "links": links,
            "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1800)), "version": 1,
            "author": ["id": n == 104 ? "tea-viewer" : "artist", "name": n == 104 ? "Tea Fixture" : "Alex", "username": n == 104 ? "tea_fixture" : "alex"],
            "isAuthor": n == 104, "following": false]
        }
      }
      if path == "/tea/conversations" {
        if method == "POST", let key = body["request_id"] as? String {
          var post = Self.conversations[id(104)]!
          post["id"] = key; post["title"] = body["title"]; post["body"] = body["body"]; post["links"] = body["links"]
          Self.conversations[key] = post; return (200, post)
        }
        return (200, ["items": Self.conversations.values.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }])
      }
      let parts = path.split(separator: "/")
      guard parts.count >= 3, var post = Self.conversations[String(parts[2])] else { return (404, ["detail":"Unavailable"]) }
      let key = String(parts[2])
      if parts.last == "replies" {
        if method == "POST", let replyID = body["request_id"] as? String {
          let reply: [String: Any] = ["id":replyID,"body":body["body"] ?? "", "createdAt":ISO8601DateFormatter().string(from: Date()),
            "author":["id":"tea-viewer","name":"Tea Fixture","username":"tea_fixture"]]
          if !(Self.discussionReplies[key] ?? []).contains(where: { $0["id"] as? String == replyID }) { Self.discussionReplies[key, default: []].append(reply) }
          return (200, reply)
        }
        return (200,["items":Self.discussionReplies[key] ?? []])
      }
      if parts.last == "follow" { post["following"] = body["following"] }
      else if method == "PUT" {
        guard post["isAuthor"] as? Bool == true else { return (403,["detail":"Not your post"]) }
        post["title"] = body["title"]; post["body"] = body["body"]; post["links"] = body["links"]
        post["version"] = (post["version"] as? Int ?? 1) + 1
      } else {
        let n = Int(key.suffix(12)) ?? 0
        Self.detailRequests[n, default: 0] += 1
        let counts = Self.detailRequests
        DispatchQueue.main.async { TeaReviewMetrics.shared.counts = counts }
        if ProcessInfo.processInfo.arguments.contains("--discussion-refresh-error"), Self.detailRequests[n] == 2 { return (503,["detail":"Fixture offline"]) }
      }
      Self.conversations[key] = post
      return (200,post)
    }
    reply(result.0, result.1)
  }

  private func readBody() -> Data? {
    if let data = request.httpBody, !data.isEmpty { return data }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    let capacity = 4096
    var bytes = [UInt8](repeating: 0, count: capacity)
    var data = Data()
    while true {
      let count = stream.read(&bytes, maxLength: capacity)
      if count < 0 { return nil }
      if count == 0 { return data }
      data.append(contentsOf: bytes.prefix(count))
    }
  }

  private func reply(_ status: Int, _ payload: Any) {
    guard let url = request.url, let body = try? JSONSerialization.data(withJSONObject: payload),
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                         headerFields: ["Content-Type": "application/json"]) else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() { delivery?.cancel() }
}

@MainActor
final class TeaReviewMetrics: ObservableObject {
  static let shared = TeaReviewMetrics()
  @Published var counts: [Int: Int] = [:]
}

struct TeaReviewRequestCounter: View {
  @ObservedObject private var metrics = TeaReviewMetrics.shared
  var body: some View {
    if ProcessInfo.processInfo.arguments.contains("--tea-request-counts") {
      Text("Isolated request counts")
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityIdentifier("tea.test.requests")
        .accessibilityValue(metrics.counts.keys.sorted().map { "\($0)=\(metrics.counts[$0]!)" }.joined(separator: ";"))
    }
  }
}
#endif
