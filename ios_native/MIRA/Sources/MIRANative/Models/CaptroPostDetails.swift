import Foundation

// Optional server-owned enrichment. Missing facts are not inferred from captions or tags.
public struct CaptroPostDetails: Codable, Hashable {
  public var visitedCount: Int?
  public var creatorVisited: Bool?
  public var event: CaptroEventDetails?
  public var collection: CaptroCollectionDetails?
  public var travel: CaptroTravelDetails?
  public var document: CaptroDocumentPreview?
}

public struct CaptroEventDetails: Codable, Hashable {
  public var startsAt: String?
  public var endsAt: String?
  public var timeZone: String?
  public var venueName: String?
  public var address: String?
  public var city: String?
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
  case travel
  case receipt
  case invoice
}

extension MIRAPost {
  var detailKind: CaptroPostDetailKind {
    switch postType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" {
    case "place", "location", "review", "check_in", "checkin": return .placeReview
    case "meetup", "event", "concert", "show": return .event
    case "travel", "trip", "ticket", "boarding_pass", "train", "flight", "bus": return .travel
    case "receipt": return .receipt
    case "invoice": return .invoice
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

public struct CaptroTravelDetails: Codable, Hashable {
  public var `operator`: String?
  public var originCode: String?
  public var destinationCode: String?
  public var originCity: String?
  public var destinationCity: String?
  public var duration: String?
  public var departure: String?
  public var arrival: String?
  public var serviceNumber: String?
  public var travelClass: String?
  public var price: String?
  public var currency: String?

  var route: String? {
    guard let origin = originCode ?? originCity, let destination = destinationCode ?? destinationCity else { return nil }
    return origin + " → " + destination
  }
}

public struct CaptroDocumentPreview: Codable, Hashable {
  public var documentType: String?
  public var merchantName: String?
  public var total: String?
  public var currency: String?
  public var verdict: String?
}

// Never cached in MIRAPost or the feed. Loaded from an owner-authorized endpoint.
struct CaptroPrivatePostObject: Decodable {
  let ticket: CaptroOwnedTicket?
  let document: CaptroReceiptReview?
}

struct CaptroOwnedTicket: Decodable {
  let id: String
  let tier: String?
  let seat: String?
  let section: String?
  let passengerName: String?
  let passengerEmail: String?
  let terminal: String?
  let gate: String?
  let serviceNumber: String?
  let travelClass: String?
  let departure: String?
  let arrival: String?
  let code: String?
  let codeFormat: String?
  let downloadable: Bool
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
