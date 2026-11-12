import Foundation

struct CaptroBusiness: Codable, Identifiable {
  var id = UUID().uuidString.lowercased()
  var name = ""
  var category = "coffee_bakery"
  var pickupAddress = ""
  var latitude = 0.0
  var longitude = 0.0
  var hours = ""
  var paused = true
  var published = false
  var avatarUrl: String?
  var photos: [String] = []
  var distanceMiles: Double?
  var locationUpdatedAt: String?

  var categoryName: String { category == "street_food" ? "Street food vendor" : "Coffee shop & bakery" }
}

struct CaptroBusinessOption: Codable, Identifiable, Hashable {
  var id = UUID().uuidString.lowercased()
  var name = ""
  var extra = 0
  var imageUrl: String?
}

struct CaptroBusinessGroup: Codable, Identifiable, Hashable {
  var id = UUID().uuidString.lowercased()
  var name = ""
  var minimum = 0
  var maximum = 1
  var options: [CaptroBusinessOption] = []
}

struct CaptroBusinessProduct: Codable, Identifiable {
  var id = UUID().uuidString.lowercased()
  var name = ""
  var category = ""
  var unitAmount = 0
  var mode = "QUICK_ADD"
  var imageUrl: String?
  var available = true
  var groups: [CaptroBusinessGroup] = []
  var isCustom: Bool { mode == "CUSTOMIZE" }

  func isValid(_ selections: Set<String>) -> Bool {
    let options = groups.flatMap(\.options)
    return selections.isSubset(of: Set(options.map(\.id))) && groups.allSatisfy { group in
      let count = group.options.filter { selections.contains($0.id) }.count
      return count >= group.minimum && count <= group.maximum
    }
  }

  func price(_ selections: Set<String>) -> Int {
    unitAmount + groups.flatMap(\.options).filter { selections.contains($0.id) }.reduce(0) { $0 + $1.extra }
  }
}

struct CaptroBusinessBag: Codable {
  struct Line: Codable, Identifiable {
    var id = UUID()
    let product: CaptroBusinessProduct
    var selection: Set<String>
    var quantity: Int
  }

  var lines: [Line] = []
  var requestId = UUID().uuidString.lowercased()
  var quantity: Int { lines.reduce(0) { $0 + $1.quantity } }
  var subtotal: Int { lines.reduce(0) { $0 + $1.product.price($1.selection) * $1.quantity } }

  mutating func set(product: CaptroBusinessProduct, selection: Set<String>, quantity: Int, editing id: UUID? = nil) {
    guard (0...20).contains(quantity), product.isValid(selection) else { return }
    let previousIndex = lines.firstIndex { $0.id == id }
    let matchIndex = lines.firstIndex { $0.id != id && $0.product.id == product.id && $0.selection == selection }
    var updated = lines
    if let matchIndex {
      let combined = id == nil ? quantity : updated[matchIndex].quantity + quantity
      guard combined <= 20 else { return }
      updated[matchIndex] = Line(id: updated[matchIndex].id, product: product, selection: selection, quantity: combined)
      if let previousIndex { updated.remove(at: previousIndex) }
    } else if let previousIndex {
      updated[previousIndex] = Line(id: updated[previousIndex].id, product: product, selection: selection, quantity: quantity)
    } else if quantity > 0 && updated.count < 40 {
      updated.append(Line(product: product, selection: selection, quantity: quantity))
    }
    updated.removeAll { $0.quantity == 0 }
    guard updated.reduce(0, { $0 + $1.quantity }) <= 60 else { return }
    lines = updated
    requestId = UUID().uuidString.lowercased()
  }

  struct Input: Encodable {
    let productId: String
    let quantity: Int
    let optionIds: [String]
  }
  var inputs: [Input] {
    lines.map { Input(productId: $0.product.id, quantity: $0.quantity, optionIds: $0.selection.sorted()) }
  }
}

struct CaptroBusinessQuote: Decodable {
  let subtotal, tax, fee, total: Int
}

struct CaptroBusinessOrder: Decodable, Identifiable {
  struct Line: Decodable {
    let productId, name: String
    let imageUrl: String?
    let quantity, unitAmount: Int
    let options: [String]
  }

  let id, businessId, businessName, pickupAddress, status: String
  let latitude, longitude: Double
  let locationUpdatedAt: String
  let subtotal, tax, fee, total, refundedAmount: Int
  let processingFee: Int?
  let pickupToken: String?
  let lines: [Line]

  var number: String { String(id.prefix(8)).uppercased() }
  var statusLabel: String {
    switch status {
    case "awaiting_payment": return "Awaiting payment"
    case "received": return "Order received"
    case "accepted": return "Accepted"
    case "preparing": return "Preparing"
    case "ready": return "Ready for pickup"
    case "completed": return "Picked up"
    case "cancelled": return "Cancelled"
    case "refund_pending": return "Refund pending"
    case "refunded": return "Refunded"
    default: return "Payment under review"
    }
  }
  var hasConfirmedOrder: Bool { ["received", "accepted", "preparing", "ready", "completed"].contains(status) }
}

struct CaptroBusinessCheckout: Decodable {
  struct Payment: Decodable { let publishableKey, clientSecret: String }
  let order: CaptroBusinessOrder
  let payment: Payment?
}

struct CaptroBusinessCheckoutInput: Encodable {
  let lines: [CaptroBusinessBag.Input]
  let requestId: String
  let total: Int
}

struct CaptroBusinessAction: Encodable { let action: String }
struct CaptroBusinessPickup: Encodable { let code: String }
struct CaptroBusinessEmpty: Encodable {}
