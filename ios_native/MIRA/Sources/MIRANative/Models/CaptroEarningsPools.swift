import Foundation

struct CaptroEarningsPool: Decodable, Identifiable, Hashable {
  let category: String
  let currency: String
  let transactions: Int
  let grossReceived: Int
  let refunded: Int
  let captroFee: Int
  let processingFees: Int?
  let creatorNet: Int?
  let pending: Int
  let available: Int
  let paidOut: Int
  let held: Int
  var id: String { category + ":" + currency }
  var title: String {
    switch category {
    case "creator_support": return "Support"
    case "event": return "Event"
    case "club": return "Club"
    case "meetup": return "Meetup"
    case "group_access": return "Group access"
    case "local_offer": return "Offers & bookings"
    case "unassigned": return "Other earnings"
    default: return category.capitalized
    }
  }
  func money(_ value: Int?) -> String {
    value.map { CaptroMoney.format(minorUnits: $0, currency: currency) } ?? "Awaiting Stripe fees"
  }
}

struct CaptroSupportReadiness: Decodable {
  struct Blocker: Decodable, Identifiable {
    let source: String
    let code: String
    let message: String
    var id: String { source + ":" + code + ":" + message }
    var sourceLabel: String { source == "stripe" ? "Stripe" : source == "captro" ? "Captro" : "Verification" }
  }
  let status: String
  let retryable: Bool
  let blockers: [Blocker]
}

struct CaptroEarningsPoolsResponse: Decodable {
  let mode: String
  let payoutScope: String
  let pools: [CaptroEarningsPool]
}

struct CaptroPoolTransaction: Decodable, Identifiable {
  let id: String
  let purchaseId: String
  let title: String?
  let status: String
  let createdAt: String?
  let grossReceived: Int
  let creatorNet: Int?
}

struct CaptroPoolPayout: Decodable, Identifiable {
  let id: String
  let status: String
  let createdAt: String?
  let paidAt: String?
  let arrivalAt: String?
  let attributedAmount: Int
  let payoutAmount: Int
  let payoutFee: Int?
  let currency: String
}

struct CaptroEarningsPoolPage<Item: Decodable>: Decodable {
  let category: String
  let currency: String
  let section: String
  let items: [Item]
  let nextOffset: Int?
}

extension MIRAAPIClient {
  func loadSupportReadiness() async throws -> CaptroSupportReadiness {
    try await getFresh("/commerce/earnings/support-readiness")
  }
  func loadCreatorEarningsPools() async throws -> CaptroEarningsPoolsResponse {
    try await getFresh("/commerce/earnings/pools")
  }
  func loadCreatorPoolPage<T: Decodable>(_ pool: CaptroEarningsPool, section: String, offset: Int) async throws -> CaptroEarningsPoolPage<T> {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#&="))
    guard let category = pool.category.addingPercentEncoding(withAllowedCharacters: allowed),
          let currency = pool.currency.addingPercentEncoding(withAllowedCharacters: allowed),
          ["transactions", "payouts"].contains(section), offset >= 0 else { throw URLError(.badURL) }
    return try await getFresh("/commerce/earnings/pools/\(category)?currency=\(currency)&section=\(section)&offset=\(offset)&limit=25")
  }
}
