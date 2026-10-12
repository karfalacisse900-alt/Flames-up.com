import Foundation

/// Presentation only. A Story link is not an entitlement or a purchase request.
struct CaptroStoryStampPresentation {
  let label: String
  let title: String?
  let context: String?
  let action: String?

  static func make(story: MIRAStatusPreview?) -> Self? {
    guard let story else { return nil }
    func clean(_ value: String?) -> String? {
      let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return text.isEmpty ? nil : text
    }
    if let linked = story.linkedItem, let title = clean(linked.title) {
      let label: String
      switch linked.type.lowercased() {
      case "club": label = "Club"
      case "group", "group_access", "access": label = "Group"
      case "event", "concert", "show": label = "Event"
      case "party": label = "Party"
      case "meetup": label = "Meetup"
      case "deal": label = "Deal"
      case "offer", "local_offer", "local-offer": label = "Offer"
      case "ticket", "access_pass": label = "Ticket"
      case "booking", "reservation": label = "Booking"
      case "place", "review", "check_in", "checkin", "location": label = "Place"
      case "guide", "collection", "list", "album", "collaborative_album": label = "Collection"
      case "travel", "trip", "boarding_pass", "train", "flight", "bus": label = "Trip"
      case "receipt": label = "Receipt"
      case "invoice": label = "Invoice"
      default: label = "Post"
      }
      return Self(label: label.uppercased(), title: title,
        context: clean(story.locationName), action: "View " + label.lowercased())
    }
    // Only explicitly shared Story context; never reverse-geocode coordinates.
    let date = CaptroStampAdapter.datePart(story.createdAt, timeZone: nil, format: "MMM d")
    let context = [clean(story.locationName), date].compactMap { $0 }.joined(separator: " · ")
    guard !context.isEmpty else { return nil }
    return Self(label: "CAPTURED", title: nil, context: context, action: nil)
  }
}
