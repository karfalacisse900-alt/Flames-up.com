import Foundation

// Optional server-owned enrichment. Missing facts are not inferred from captions or tags.
public struct CaptroPostDetails: Codable, Hashable {
  public var visitedCount: Int?
  public var creatorVisited: Bool?
  public var event: CaptroEventDetails?
  public var collection: CaptroCollectionDetails?
}

public struct CaptroEventDetails: Codable, Hashable {
  public var startsAt: String?
  public var endsAt: String?
  public var timeZone: String?
  public var venueName: String?
  public var address: String?
  public var latitude: Double?
  public var longitude: Double?
  public var attendeesCount: Int?
  public var attendees: [MIRATaggedUserPayload]?
  public var viewerGoing: Bool?
  public var attendanceEnabled: Bool?
}

public struct CaptroCollectionDetails: Codable, Hashable {
  public var items: [MIRAPost]?
}

enum CaptroPostDetailKind: Equatable {
  case placeReview
  case regular
  case event
  case collection
}

extension MIRAPost {
  var detailKind: CaptroPostDetailKind {
    switch postType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" {
    case "place", "location", "review", "check_in", "checkin": return .placeReview
    case "meetup", "event": return .event
    case "collection", "list", "guide", "album", "collaborative_album", "collaborative-album": return .collection
    case "general", "social", "photo", "image", "video", "note", "text": return .regular
    default: return placeDisplayName == nil ? .regular : .placeReview
    }
  }

  var detailCaption: String {
    let cleanCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleanCaption.isEmpty ? (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : cleanCaption
  }

  var detailCreatorHandle: String {
    let name = userUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? authorDisplayName : "@" + name.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
  }

  var detailCollectionItems: [MIRAPost] {
    var seen = Set<String>()
    return (detail?.collection?.items ?? []).filter { $0.id != id && seen.insert($0.id).inserted }
  }

  var detailMapURL: URL? {
    let event = detail?.event
    let name = event?.venueName ?? placeDisplayName
    let address = event?.address ?? placeDisplaySubtitle
    let latitude = event?.latitude ?? placeLat
    let longitude = event?.longitude ?? placeLng
    let query = [name, address].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }.joined(separator: ", ")
    var components = URLComponents(string: "https://maps.apple.com/")!
    var items: [URLQueryItem] = []
    if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
    if let latitude, let longitude, latitude.isFinite, longitude.isFinite,
       (-90...90).contains(latitude), (-180...180).contains(longitude) {
      items.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
    }
    guard !items.isEmpty else { return nil }
    components.queryItems = items
    return components.url
  }
}

extension CaptroEventDetails {
  var startDate: Date? { Self.date(startsAt) }
  var endDate: Date? { Self.date(endsAt) }

  var calendarDate: String? {
    guard let startDate else { return nil }
    return formatted(startDate, template: "EEEE MMMM d yyyy")
  }

  var timeRange: String? {
    guard let startDate else { return nil }
    let start = formatted(startDate, template: "jmm")
    guard let endDate else { return start }
    return start + " - " + formatted(endDate, template: "jmm")
  }

  var month: String? { startDate.map { formatted($0, template: "MMM").uppercased() } }
  var day: String? { startDate.map { formatted($0, template: "d") } }

  private func formatted(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  private static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}
