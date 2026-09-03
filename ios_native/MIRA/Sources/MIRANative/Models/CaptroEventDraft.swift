import Foundation

extension Notification.Name {
  static let captroPostDetailsUpdated = Notification.Name("captro.post.detailsUpdated")
}

// Creator-entered public event facts, never an issued ticket or an attendance count.
public struct CaptroEventInput: Codable, Hashable {
  public var startsAt: String?
  public var endsAt: String?
  public var timeZone: String
  public var venueName: String?
  public var address: String?
  public var city: String?
  public var price: String?
  public var currency: String?
  public var attendanceEnabled: Bool
}

struct CaptroEventDraft: Codable, Hashable {
  var hasSchedule = false
  var startsAt = Date()
  var endsAt = Date().addingTimeInterval(3600)
  var hasEndTime = false
  var timeZone = TimeZone.current.identifier
  var venueName = ""
  var address = ""
  var city = ""
  var hasPrice = false
  var price = ""
  var currency = Locale.current.currency?.identifier ?? "USD"
  var attendanceEnabled = true

  init(event: CaptroEventDetails? = nil) {
    guard let event else { return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func parse(_ value: String?) -> Date? {
      guard let value else { return nil }
      return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    if let start = parse(event.startsAt) { startsAt = start; hasSchedule = true }
    if let end = parse(event.endsAt) { endsAt = end; hasEndTime = true }
    else { endsAt = startsAt.addingTimeInterval(3600) }
    timeZone = event.timeZone ?? TimeZone.current.identifier
    venueName = event.venueName ?? ""
    address = event.address ?? ""
    city = event.city ?? ""
    hasPrice = event.price != nil
    price = event.price ?? ""
    currency = event.currency ?? currency
    attendanceEnabled = event.attendanceEnabled ?? true
  }

  var validationError: String? {
    if hasSchedule && hasEndTime && endsAt <= startsAt { return "End time must be after the start time." }
    if hasPrice && !normalizedPrice.isEmpty {
      guard normalizedPrice.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil else {
        return "Enter a valid price, with up to two decimal places."
      }
    } else if hasPrice { return "Enter a price, or 0 for free entry." }
    return nil
  }

  private var normalizedPrice: String { price.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".") }

  var input: CaptroEventInput {
    let formatter = ISO8601DateFormatter()
    func clean(_ value: String) -> String? {
      let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return result.isEmpty ? nil : result
    }
    return CaptroEventInput(
      startsAt: hasSchedule ? formatter.string(from: startsAt) : nil,
      endsAt: hasSchedule && hasEndTime ? formatter.string(from: endsAt) : nil,
      timeZone: timeZone, venueName: clean(venueName), address: clean(address), city: clean(city),
      price: hasPrice ? normalizedPrice : nil, currency: hasPrice ? currency : nil,
      attendanceEnabled: attendanceEnabled
    )
  }
}
