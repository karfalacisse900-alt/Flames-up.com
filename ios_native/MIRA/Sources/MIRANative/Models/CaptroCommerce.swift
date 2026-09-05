import Foundation

public struct CaptroCommerceDetails: Codable, Hashable, Identifiable {
  public let id: String
  public let postId: String?
  public let contentType: String
  public let fulfillmentType: String
  public let paymentModel: String
  public let commerceClass: String
  public let title: String
  public let description: String
  public let locationName: String?
  public let address: String?
  public let city: String?
  public let startsAt: String?
  public let endsAt: String?
  public let timeZone: String?
  public let capacity: Int?
  public let joinedCount: Int
  public let remaining: Int?
  public let expiresAt: String?
  public let refundPolicy: String
  public let approvalRequired: Bool
  public let passRequired: Bool
  public let status: String
  public let audience: String
  public let publicData: CaptroCommercePublicData?
  public let prices: [CaptroCommercePrice]
  public let lowestPrice: CaptroCommercePrice?
  public let viewerStatus: String?
  public let viewerPurchaseId: String?
  public let viewerEntitlementId: String?
  public let viewerDestinationId: String?
  public let serviceFeeBasisPoints: Int?
  public let serviceFeeFixedAmount: Int?
  public let serviceFeeMinimumAmount: Int?

  public var isPaid: Bool { paymentModel == "paid" || (lowestPrice?.unitAmount ?? 0) > 0 }
  public var isActiveForViewer: Bool { ["active", "confirmed", "used"].contains(viewerStatus ?? "") }
  public var requiresPaymentContinuation: Bool { viewerStatus == "payment_pending" }
  public var needsApproval: Bool { viewerStatus == "approval_pending" }

  public var displayLocation: String? {
    let value = [locationName, city]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .reduce(into: [String]()) { values, item in
        if !values.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) { values.append(item) }
      }
      .joined(separator: " · ")
    return value.isEmpty ? nil : value
  }

  public var scheduleLabel: String? {
    guard let start = Self.date(startsAt) else { return nil }
    let date = DateFormatter()
    date.locale = .autoupdatingCurrent
    date.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    date.setLocalizedDateFormatFromTemplate("EEE MMM d")
    let time = DateFormatter()
    time.locale = .autoupdatingCurrent
    time.timeZone = date.timeZone
    time.setLocalizedDateFormatFromTemplate("jmm")
    if let end = Self.date(endsAt) {
      return "\(date.string(from: start)) · \(time.string(from: start))–\(time.string(from: end))"
    }
    return "\(date.string(from: start)) · \(time.string(from: start))"
  }

  public var compactAvailabilityLabel: String? {
    if let remaining { return remaining == 0 ? "SOLD OUT" : "\(remaining) LEFT" }
    if capacity != nil { return "\(joinedCount) JOINED" }
    return joinedCount > 0 ? "\(joinedCount) JOINED" : nil
  }

  public var primaryActionTitle: String {
    if isActiveForViewer {
      switch fulfillmentType {
      case "ticket": return "VIEW TICKET"
      case "redemption": return "VIEW DEAL"
      case "membership", "group_access": return "MEMBERSHIP ACTIVE"
      case "attendance": return "GOING"
      case "reservation": return "BOOKING CONFIRMED"
      default: return "ORDER PLACED"
      }
    }
    if needsApproval { return "REQUEST PENDING" }
    if requiresPaymentContinuation { return "CONTINUE CHECKOUT" }
    let verb: String
    switch contentType {
    case "offer": verb = "ORDER"
    case "deal": verb = "GET DEAL"
    case "club": verb = "JOIN CLUB"
    case "group": verb = "JOIN"
    case "meetup": verb = "JOIN"
    case "booking", "reservation": verb = "BOOK"
    default: verb = "GET TICKET"
    }
    guard let lowestPrice, lowestPrice.unitAmount > 0 else { return verb }
    return "\(verb) — \(lowestPrice.money)"
  }

  private static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

public struct CaptroCommercePrice: Codable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let unitAmount: Int
  public let currency: String
  public let billingPeriod: String
  public let capacity: Int?
  public let remaining: Int?
  public let active: Bool
  public let creatorAmount: Int?
  public let serviceFeeAmount: Int?
  public let taxAmount: Int?
  public let buyerTotal: Int?

  public var money: String { CaptroMoney.format(minorUnits: unitAmount, currency: currency) }
}

public struct CaptroCommercePublicData: Codable, Hashable {
  public let ageRequirement: String?
  public let originalPrice: String?
  public let redemptionRules: String?
  public let fulfillmentMethods: [String]?
  public let benefits: [String]?
  public let rules: [String]?
  public let availability: String?
  public let durationMinutes: Int?
}

enum CaptroMoney {
  static func format(minorUnits: Int, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.uppercased()
    formatter.maximumFractionDigits = minorUnits % 100 == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: Double(minorUnits) / 100.0)) ?? "\(currency.uppercased()) \(minorUnits / 100)"
  }
}

public struct CaptroCommerceInput: Encodable {
  public let enabled: Bool
  public let contentType: String
  public let paymentModel: String
  public let commerceClass: String
  public let title: String
  public let description: String
  public let locationName: String?
  public let address: String?
  public let city: String?
  public let startsAt: String?
  public let endsAt: String?
  public let timezone: String?
  public let capacity: Int?
  public let expiresAt: String?
  public let refundPolicy: String
  public let audience: String
  public let approvalRequired: Bool
  public let passRequired: Bool
  public let currency: String
  public let prices: [CaptroCommercePriceInput]
  public let publicData: CaptroCommercePublicDataInput
}

public struct CaptroCommercePriceInput: Encodable {
  public let label: String
  public let unitAmount: Int
  public let capacity: Int?
}

public struct CaptroCommercePublicDataInput: Encodable {
  public let ageRequirement: String?
  public let originalPrice: String?
  public let redemptionRules: String?
  public let fulfillmentMethods: [String]
  public let benefits: [String]
  public let rules: [String]
  public let availability: String?
  public let durationMinutes: Int?
}

struct CaptroCommercePriceDraft: Identifiable, Codable, Hashable {
  var id = UUID()
  var label = "General"
  var price = ""
  var capacity = ""
}

struct CaptroCommerceDraft: Codable, Hashable {
  var enabled = false
  var isPaid = false
  var isUsedOutsideApp = true
  var approvalRequired = false
  var passRequired = false
  var capacity = ""
  var hasExpiration = false
  var expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 30)
  var refundPolicy = ""
  var audience = "anyone"
  var currency = Locale.current.currency?.identifier ?? "USD"
  var prices = [CaptroCommercePriceDraft()]
  var ageRequirement = ""
  var originalPrice = ""
  var redemptionRules = ""
  var benefits = ""
  var rules = ""
  var availability = ""
  var durationMinutes = ""
  var allowsPickup = false
  var allowsDelivery = false

  mutating func configureDefaults(for kind: CaptroStampKind) {
    guard enabled else { return }
    if [.event, .party, .ticket].contains(kind) { passRequired = true }
    if kind == .deal { passRequired = true }
  }

  var validationError: String? {
    if let capacityValue = positiveInt(capacity), capacityValue < 1 { return "Capacity must be at least 1." }
    if !capacity.trimmingCharacters(in: .whitespaces).isEmpty && positiveInt(capacity) == nil { return "Enter a valid capacity." }
    if isPaid {
      for tier in prices {
        guard minorUnits(tier.price) != nil else { return "Enter a valid price of at least 0.50 for every tier." }
        if !tier.capacity.trimmingCharacters(in: .whitespaces).isEmpty && positiveInt(tier.capacity) == nil {
          return "Enter a valid quantity for every tier."
        }
      }
    }
    return nil
  }

  func input(
    kind: CaptroStampKind,
    title: String,
    description: String,
    event: CaptroEventInput?,
    locationName: String?,
    address: String?,
    city fallbackCity: String?
  ) -> CaptroCommerceInput? {
    guard enabled, let contentType = kind.commerceContentType else { return nil }
    let formatter = ISO8601DateFormatter()
    let priceInputs = (isPaid ? prices : [CaptroCommercePriceDraft(label: "General", price: "0")]).map {
      CaptroCommercePriceInput(
        label: clean($0.label) ?? "General",
        unitAmount: isPaid ? (minorUnits($0.price) ?? 0) : 0,
        capacity: positiveInt($0.capacity)
      )
    }
    return CaptroCommerceInput(
      enabled: true,
      contentType: contentType,
      paymentModel: isPaid ? "paid" : "free",
      commerceClass: isUsedOutsideApp ? "outside_app" : "digital",
      title: clean(title) ?? kind.displayName,
      description: description.trimmingCharacters(in: .whitespacesAndNewlines),
      locationName: clean(event?.venueName ?? locationName),
      address: clean(event?.address ?? address),
      city: clean(event?.city ?? fallbackCity),
      startsAt: event?.startsAt,
      endsAt: event?.endsAt,
      timezone: event?.timeZone,
      capacity: positiveInt(capacity),
      expiresAt: hasExpiration ? formatter.string(from: expiresAt) : nil,
      refundPolicy: refundPolicy.trimmingCharacters(in: .whitespacesAndNewlines),
      audience: audience,
      approvalRequired: approvalRequired,
      passRequired: passRequired,
      currency: currency,
      prices: priceInputs,
      publicData: CaptroCommercePublicDataInput(
        ageRequirement: clean(ageRequirement),
        originalPrice: clean(originalPrice),
        redemptionRules: clean(redemptionRules),
        fulfillmentMethods: [allowsPickup ? "pickup" : nil, allowsDelivery ? "delivery" : nil].compactMap { $0 },
        benefits: lines(benefits),
        rules: lines(rules),
        availability: clean(availability),
        durationMinutes: positiveInt(durationMinutes)
      )
    )
  }

  private func clean(_ value: String?) -> String? {
    let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return result.isEmpty ? nil : result
  }

  private func lines(_ value: String) -> [String] {
    value.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  private func positiveInt(_ value: String) -> Int? {
    let clean = value.trimmingCharacters(in: .whitespaces)
    guard !clean.isEmpty, let result = Int(clean), result > 0 else { return nil }
    return result
  }

  private func minorUnits(_ value: String) -> Int? {
    let clean = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard let decimal = Decimal(string: clean), decimal >= Decimal(string: "0.50")!, decimal <= 50_000 else { return nil }
    return NSDecimalNumber(decimal: decimal * Decimal(100)).intValue
  }
}

public struct CaptroCommercePurchase: Decodable, Hashable, Identifiable {
  public let id: String
  public let postId: String
  public let purchasableId: String
  public let contentType: String
  public let fulfillmentType: String
  public let itemTitle: String
  public let priceLabel: String
  public let quantity: Int
  public let unitAmount: Int
  public let itemAmount: Int?
  public let serviceFeeAmount: Int?
  public let creatorAmount: Int?
  public let platformFeeAmount: Int?
  public let processingAmount: Int?
  public let feeAmount: Int?
  public let taxAmount: Int?
  public let totalAmount: Int
  public let currency: String
  public let status: String
  public let purchasedAt: String?
  public let entitlement: CaptroEntitlementSummary?

  public var totalLabel: String { CaptroMoney.format(minorUnits: totalAmount, currency: currency) }
}

public struct CaptroEntitlementSummary: Decodable, Hashable, Identifiable {
  public let id: String
  public let kind: String
  public let status: String
  public let startsAt: String?
  public let endsAt: String?
  public let destinationId: String?
  public let hasPass: Bool?
}

public struct CaptroCommerceActionResponse: Decodable {
  public let purchase: CaptroCommercePurchase
  public let checkoutUrl: String?
  public let paymentSheet: CaptroPaymentConfiguration?
}

public struct CaptroPaymentConfiguration: Decodable, Identifiable {
  public var id: String { purchaseId }
  public let purchaseId: String
  public let publishableKey: String
  public let paymentIntentClientSecret: String
  public let mode: String
  public let merchantDisplayName: String
  public let returnURL: String
  public let applePayMerchantId: String?
  public let merchantCountryCode: String
}

public struct CaptroCommercePostResponse: Decodable {
  public let commerce: CaptroCommerceDetails
}

public struct CaptroCommercePassResponse: Decodable {
  public let purchase: CaptroCommercePurchase
  public let pass: CaptroCommercePass?
}

public struct CaptroCommercePass: Decodable, Hashable, Identifiable {
  public let id: String
  public let kind: String
  public let code: String
  public let tier: String?
  public let status: String
  public let token: String
  public let usedAt: String?
}

public struct CaptroCommerceDashboard: Decodable {
  public let myStuff: [CaptroCommercePurchase]
  public let created: [CaptroCreatedCommerce]
  public let pendingRequests: [CaptroCommercePurchase]
}

public struct CaptroCreatedCommerce: Decodable, Identifiable {
  public var id: String { commerce.id }
  public let commerce: CaptroCommerceDetails
  public let sold: Int
  public let grossAmount: Int
  public let creatorEarningsAmount: Int?
  public let availableEarningsAmount: Int?
  public let currency: String
  public let pendingApprovals: Int
  public let checkedIn: Int?
  public let redeemed: Int?
  public let paidMembers: Int?
}

private struct CaptroCommercePurchaseRequest: Encodable {
  let postId: String
  let purchasableId: String
  let priceId: String
  let quantity: Int
  let idempotencyKey: String
  let selection: CaptroCommerceSelection
}

public struct CaptroCommerceSelection: Encodable, Hashable {
  public var fulfillmentMethod: String?
  public var startsAt: String?
  public var endsAt: String?
  public var option: String?

  public init(fulfillmentMethod: String? = nil, startsAt: String? = nil, endsAt: String? = nil, option: String? = nil) {
    self.fulfillmentMethod = fulfillmentMethod
    self.startsAt = startsAt
    self.endsAt = endsAt
    self.option = option
  }
}

public struct CaptroCommerceConsumeResponse: Decodable {
  public let status: String
}

public struct CaptroPayoutAccount: Decodable, Hashable {
  public let stripeConfigured: Bool
  public let status: String
  public let ready: Bool
  public let detailsSubmitted: Bool
  public let chargesEnabled: Bool
  public let payoutsEnabled: Bool
  public let payoutCard: CaptroPayoutCard?
  public let identityRequirementsComplete: Bool?
  public let payoutSchedule: String?
  public let requirementsCount: Int
}

public struct CaptroPayoutCard: Decodable, Hashable {
  public let id: String
  public let brand: String
  public let last4: String
  public let expirationMonth: Int
  public let expirationYear: Int
  public let instantPayoutEligible: Bool
}

public struct CaptroPayoutAccountResponse: Decodable {
  public let account: CaptroPayoutAccount
}

public struct CaptroHostedAccountLinkResponse: Decodable, Identifiable {
  public var id: String { url }
  public let account: CaptroPayoutAccount
  public let url: String
  public let expiresAt: String?
}

public struct CaptroEarningsBalance: Decodable, Hashable {
  public let status: String
  public let currency: String
  public let available: Int?
  public let pending: Int?
  public let instantAvailable: Int?
}

public struct CaptroPayoutQuote: Decodable, Identifiable {
  public let id: String
  public let amount: Int
  public let fee: Int
  public let netAmount: Int
  public let currency: String
  public let card: CaptroPayoutCard
  public let expiresAt: String
}

public struct CaptroPayoutResult: Decodable { public let payout: CaptroPayout }

public struct CaptroCreatorEarning: Decodable, Hashable, Identifiable {
  public let id: String
  public let purchaseId: String
  public let postId: String
  public let contentType: String
  public let title: String
  public let priceLabel: String?
  public let buyerHandle: String?
  public let currency: String
  public let itemAmount: Int
  public let creatorAmount: Int
  public let platformFee: Int
  public let processingAmount: Int
  public let taxAmount: Int
  public let buyerTotal: Int
  public let refundedAmount: Int
  public let status: String
  public let createdAt: String?
  public let availableAt: String?
  public let purchasedAt: String?

  public var netCreatorAmount: Int { max(0, creatorAmount - refundedAmount) }
}

public struct CaptroEarningsResponse: Decodable {
  public let account: CaptroPayoutAccount
  public let balance: CaptroEarningsBalance
  public let recent: [CaptroCreatorEarning]
}

public struct CaptroPayout: Decodable, Hashable, Identifiable {
  public let id: String
  public let amount: Int
  public let currency: String
  public let status: String
  public let arrivalAt: String?
  public let paidAt: String?
  public let failureMessage: String?
  public let createdAt: String?
  public let card: CaptroPayoutCard?
  public let fee: Int?
  public let netAmount: Int?
  public let failedAt: String?
}

public struct CaptroPayoutsResponse: Decodable {
  public let account: CaptroPayoutAccount
  public let payouts: [CaptroPayout]
}

public struct CaptroEarningRefund: Decodable, Hashable, Identifiable {
  public let id: String
  public let amount: Int
  public let creatorReversalAmount: Int
  public let status: String
  public let createdAt: String?
}

public struct CaptroEarningDetailResponse: Decodable {
  public let earning: CaptroCreatorEarning
  public let purchase: CaptroCommercePurchase
  public let purchaseReference: String
  public let refunds: [CaptroEarningRefund]
}

extension MIRAAPIClient {
  public func beginCommercePurchase(
    postId: String,
    commerce: CaptroCommerceDetails,
    priceId: String,
    quantity: Int = 1,
    selection: CaptroCommerceSelection = CaptroCommerceSelection(),
    idempotencyKey: String
  ) async throws -> CaptroCommerceActionResponse {
    try await post("/payments/create", body: CaptroCommercePurchaseRequest(
      postId: postId,
      purchasableId: commerce.id,
      priceId: priceId,
      quantity: quantity,
      idempotencyKey: idempotencyKey,
      selection: selection
    ))
  }

  public func continueCommerceCheckout(purchaseId: String) async throws -> CaptroCommerceActionResponse {
    try await post("/commerce/purchases/\(purchaseId)/checkout", body: EmptyBody())
  }

  public func loadCommerce(postId: String) async throws -> CaptroCommercePostResponse {
    try await get("/commerce/posts/\(postId)")
  }

  public func loadCommercePass(entitlementId: String) async throws -> CaptroCommercePassResponse {
    try await get("/commerce/entitlements/\(entitlementId)/pass")
  }

  public func loadCommerceDashboard() async throws -> CaptroCommerceDashboard {
    try await get("/commerce/me")
  }

  public func loadPayoutAccount() async throws -> CaptroPayoutAccountResponse {
    try await get("/commerce/payout-account")
  }

  public func createPayoutOnboardingLink() async throws -> CaptroHostedAccountLinkResponse {
    try await post("/commerce/payout-account/onboarding-link", body: EmptyBody())
  }

  public func createPayoutManagementLink() async throws -> CaptroHostedAccountLinkResponse {
    try await post("/commerce/payout-account/manage-link", body: EmptyBody())
  }

  public func loadCreatorEarnings() async throws -> CaptroEarningsResponse {
    try await get("/commerce/earnings")
  }

  public func loadCreatorEarning(id: String) async throws -> CaptroEarningDetailResponse {
    try await get("/commerce/earnings/\(id)")
  }

  public func loadCreatorPayouts() async throws -> CaptroPayoutsResponse {
    try await get("/commerce/payouts")
  }

  public func quotePayout(amount: Int, requestId: String) async throws -> CaptroPayoutQuote {
    struct Input: Encodable { let amount: Int; let requestId: String }
    return try await post("/creator/payouts/quote", body: Input(amount: amount, requestId: requestId))
  }

  public func withdraw(quoteId: String) async throws -> CaptroPayoutResult {
    struct Input: Encodable { let quoteId: String }
    return try await post("/creator/payouts", body: Input(quoteId: quoteId))
  }

  public func decideCommercePurchase(purchaseId: String, approved: Bool) async throws -> CaptroCommerceActionResponse {
    try await post("/commerce/purchases/\(purchaseId)/decision", body: CaptroCommerceDecisionRequest(approved: approved))
  }

  public func consumeCommercePass(token: String) async throws -> CaptroCommerceConsumeResponse {
    try await post("/commerce/passes/consume", body: CaptroCommerceConsumeRequest(token: token))
  }
}

private struct CaptroCommerceDecisionRequest: Encodable {
  let approved: Bool
}

private struct CaptroCommerceConsumeRequest: Encodable {
  let token: String
}
