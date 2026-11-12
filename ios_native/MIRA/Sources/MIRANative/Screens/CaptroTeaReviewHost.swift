#if DEBUG
import Foundation
import SwiftUI

struct CaptroTeaReviewHost: View {
  @StateObject private var session: MIRAAuthSession
  private let api: MIRAAPIClient

  init() {
    let storage = TeaReviewStorage()
    let defaults = UserDefaults(suiteName: "captro.tea.review")!
    defaults.removePersistentDomain(forName: "captro.tea.review")
    let auth = MIRAAuthSession(keychain: storage, defaults: defaults)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TeaReviewProtocol.self]
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    _session = StateObject(wrappedValue: auth)
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost/api")!, sessionProvider: auth,
                       session: URLSession(configuration: config))
  }

  var body: some View {
    MIRANativeRootView(reviewSession: session, api: api)
      .environment(\.captroStartupReducedMotion, true)
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
      if number == 4 {
        payload = ["item": entry(number), "business": [
          "id": id(number), "name": "Sample Bakery", "category": "coffee_bakery", "pickupAddress": "Sample pickup",
          "latitude": 40.72, "longitude": -74.0, "hours": "8 am–4 pm", "paused": false, "published": true, "photos": [],
        ]]
      } else {
        payload = ["item": entry(number), "post": ["id": "tea-post-\(number)", "userId": "tea-fixture-owner"],
                   "commerce": commerce(number)]
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
    reply(status, payload)
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
  override func stopLoading() {}
}
#endif
