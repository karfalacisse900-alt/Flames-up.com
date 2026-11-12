#if DEBUG
import Foundation

enum CaptroBusinessReviewAPI {
  static func make() -> MIRAAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CaptroBusinessReviewProtocol.self]
    return MIRAAPIClient(baseURL: URL(string: "https://business-fixture.invalid/api")!, session: URLSession(configuration: config))
  }
}

private final class CaptroBusinessReviewProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "business-fixture.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let coffee = "20000000-0000-4000-8000-000000000001"
    let vendor = "20000000-0000-4000-8000-000000000002"
    let coffeePhoto = "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?fit=crop&w=640&q=80"
    let coffeeShop = "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?fit=crop&w=560&q=80"
    let dogPhoto = "https://images.unsplash.com/photo-1612392062422-ef19b42f74df?fit=crop&w=500&q=80"
    let path = url.path
    let status: Int
    let payload: Any
    func shop(_ id: String, _ name: String, _ category: String, _ photos: [String]) -> [String: Any] {
      ["id": id, "name": name, "category": category, "pickup_address": "Sample pickup location",
       "latitude": 40.73, "longitude": -73.99, "hours": "Development sample", "paused": false, "published": true,
       "photos": photos, "distance_miles": 0.3]
    }
    func product(_ id: String, _ name: String, _ price: Int, _ image: String, _ groups: [[String: Any]] = []) -> [String: Any] {
      ["id": id, "name": name, "category": groups.isEmpty ? "Food" : "Coffee", "unit_amount": price,
       "image_url": image, "mode": groups.isEmpty ? "QUICK_ADD" : "CUSTOMIZE", "available": true, "groups": groups]
    }
    switch path {
    case "/api/businesses":
      status = 200
      payload = [shop(coffee, "Captro Coffee", "coffee_bakery", [coffeeShop, coffeePhoto]),
                 shop(vendor, "NYC Hot Dogs", "street_food", [])]
    case "/api/businesses/\(coffee)/menu":
      status = 200
      payload = [product("latte", "Iced Latte", 490, coffeePhoto, [
        ["id": "size", "name": "Size", "minimum": 1, "maximum": 1, "options": [
          ["id": "small", "name": "Small", "extra": 0], ["id": "medium", "name": "Medium", "extra": 0],
          ["id": "large", "name": "Large", "extra": 100]]],
        ["id": "milk", "name": "Milk", "minimum": 0, "maximum": 1, "options": [
          ["id": "whole", "name": "Whole milk", "extra": 0], ["id": "oat", "name": "Oat milk", "extra": 50],
          ["id": "almond", "name": "Almond milk", "extra": 50], ["id": "soy", "name": "Soy milk", "extra": 50]]],
      ])]
    case "/api/businesses/\(vendor)/menu":
      status = 200
      payload = [product("dog", "Hotdog", 400, dogPhoto)]
    case "/api/businesses/\(coffee)/quote", "/api/businesses/\(vendor)/quote":
      status = 200
      let lines = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
      let items = lines?["lines"] as? [[String: Any]] ?? []
      let subtotal = items.reduce(0) { subtotal, line in
        let options = line["option_ids"] as? [String] ?? []
        let unit = path.contains(coffee) ? 490 + (options.contains("oat") ? 50 : 0) + (options.contains("large") ? 100 : 0) : 400
        return subtotal + unit * (line["quantity"] as? Int ?? 0)
      }
      let tax = (subtotal * 8 + 50) / 100
      payload = ["subtotal": subtotal, "tax": tax, "fee": 0, "total": subtotal + tax]
    default:
      status = 503
      payload = ["detail": "Payments are disabled in this UI fixture."]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                         headerFields: ["Content-Type": "application/json"]) else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif
