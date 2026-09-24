import Foundation

extension CaptroCommercePrice {
  var stampPrice: String? {
    guard active, unitAmount >= 0, currency.count == 3 else { return nil }
    if unitAmount == 0 { return "Free" }
    switch billingPeriod.lowercased() {
    case "one_time", "one-time", "once": return "\(money) one time"
    case "month", "monthly": return "\(money)/month"
    case "year", "yearly", "annual": return "\(money)/year"
    case "week", "weekly": return "\(money)/week"
    case "day", "daily": return "\(money)/day"
    default: return nil // Never quietly turn an unknown recurring price into a one-time price.
    }
  }
}

enum CaptroStampAdapter {
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  static func datePart(_ value: String?, timeZone: String?, format: String) -> String? {
    guard let date = date(value) else { return nil }
    let formatter = DateFormatter()
    formatter.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate(format)
    return formatter.string(from: date)
  }
  static func terms(_ commerce: CaptroCommerceDetails?, family: String) -> String? {
    guard let commerce else { return nil }
    if family == "deal" {
      // Backend has free-form redemption rules, not a structured minimum spend.
      // Preserve them verbatim; never extract amounts from title/marketing text.
      let rules = commerce.publicData?.redemptionRules?.trimmingCharacters(in: .whitespacesAndNewlines)
      return rules?.isEmpty == false ? rules : nil
    }
    guard let lowest = commerce.resolvedLowestPrice?.stampPrice else { return "View pricing and terms" }
    let price = commerce.prices.count > 1 ? "From \(lowest)" : lowest
    if family == "club" { return price }
    return [datePart(commerce.startsAt, timeZone: commerce.timeZone, format: "MMM d jmm"), price]
      .compactMap { $0 }.joined(separator: " · ")
  }
  static func availability(_ commerce: CaptroCommerceDetails?, now: Date = Date()) -> String? {
    guard let commerce else { return nil }
    if ["cancelled", "canceled"].contains(commerce.status) { return "Cancelled" }
    if ["removed", "archived", "inactive", "draft"].contains(commerce.status) { return "Unavailable" }
    if commerce.status == "expired" || date(commerce.expiresAt).map({ $0 <= now }) == true { return "Expired" }
    if commerce.status == "sold_out" || commerce.remaining == 0 { return "Full" }
    return nil
  }
  static func relationship(_ commerce: CaptroCommerceDetails?, saved: Bool) -> String? {
    switch commerce?.viewerStatus {
    case "used": return "Used"
    case "claimed": return "Claimed"
    case "active", "confirmed":
      switch commerce?.fulfillmentType {
      case "membership", "group_access": return "Member"
      case "redemption": return "Claimed"
      case "ticket": return "Ticket ready"
      case "reservation": return "Reserved"
      case "attendance": return "Joined"
      default: return "Confirmed"
      }
    case "payment_pending": return "Payment pending"
    case "approval_pending": return "Request pending"
    default: return saved ? "Saved" : nil
    }
  }
}
