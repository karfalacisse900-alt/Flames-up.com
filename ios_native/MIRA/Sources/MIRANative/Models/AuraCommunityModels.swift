import Foundation

public enum AuraCommunityFeedScope: String, CaseIterable, Identifiable {
  case friends
  case city

  public var id: String { rawValue }
}

public enum AuraCommunityPostMode: String, CaseIterable, Codable, Identifiable {
  case smallPost = "small_post"
  case meetup

  public var id: String { rawValue }
  public var title: String { self == .smallPost ? "Small Post" : "Meetup" }
}

public enum AuraSmallPostCategory: String, CaseIterable, Codable, Identifiable {
  case question
  case idea
  case concern
  case recommendation
  case update

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
  public var symbol: String {
    switch self {
    case .question: return "questionmark.bubble"
    case .idea: return "lightbulb"
    case .concern: return "exclamationmark.triangle"
    case .recommendation: return "hand.thumbsup"
    case .update: return "megaphone"
    }
  }
}

public enum AuraCommunityAudience: String, CaseIterable, Codable, Identifiable {
  case `public`
  case friends

  public var id: String { rawValue }
  public var title: String { self == .public ? "Public" : "Friends" }
}

public enum AuraMeetupEntryType: String, CaseIterable, Codable, Identifiable {
  case free
  case aur

  public var id: String { rawValue }
  public var title: String { self == .free ? "Free" : "Paid in AUR" }
}

public struct AuraCommunityPost: Decodable, Identifiable, Hashable {
  public let id: String
  public let userId: String?
  public let userUsername: String?
  public let userFullName: String?
  public let userProfileImage: String?
  public let title: String?
  public let content: String?
  public let image: String?
  public let images: [String]?
  public let feedMediaUrls: [String]?
  public let location: String?
  public let displayCity: String?
  public let displayRegion: String?
  public let displayCountry: String?
  public let displayLocationLabel: String?
  public let postType: String?
  public let communityCategory: String?
  public let communityAudience: String?
  public let communityAllowReplies: Bool?
  public let placeName: String?
  public let placeFormattedAddress: String?
  public let placeCity: String?
  public let placeRegion: String?
  public let meetupNeighborhood: String?
  public let meetupStartsAt: String?
  public let meetupEndsAt: String?
  public let meetupEntryType: String?
  public let meetupEntryAmountAtoms: String?
  public let meetupMaxPeople: Int?
  public let meetupStateAvailable: Bool?
  public let meetupJoinedCount: Int?
  public let meetupViewerJoined: Bool?
  public let commentsCount: Int?
  public let createdAt: String?

  public var mode: AuraCommunityPostMode? {
    AuraCommunityPostMode(rawValue: postType?.lowercased() ?? "")
  }

  public var titleText: String {
    title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  public var bodyText: String {
    content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  public var authorHandle: String {
    if MIRAUsernameRules.isValidPublicUsername(userUsername) {
      return "@\(MIRAUsernameRules.normalized(userUsername))"
    }
    let name = userFullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? "Aura member" : name
  }

  public var primaryImageURL: String? {
    for value in (feedMediaUrls ?? []) + (images ?? []) + [image ?? ""] {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !clean.isEmpty { return clean }
    }
    return nil
  }

  public var locationLine: String {
    let values = [placeName, meetupNeighborhood]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return values.isEmpty ? "Place unavailable" : values.joined(separator: " · ")
  }

  public var entryLabel: String {
    guard meetupEntryType?.lowercased() == AuraMeetupEntryType.aur.rawValue else { return "FREE" }
    guard let atoms = meetupEntryAmountAtoms, let amount = AuraAmountCodec.aur(fromAtoms: atoms) else {
      return "AUR unavailable"
    }
    return "\(amount) AUR"
  }
}

public struct AuraMeetupParticipantsResponse: Decodable {
  public let joinedCount: Int
  public let viewerJoined: Bool
  public let participants: [MIRAUser]
}

public struct AuraMeetupJoinResponse: Decodable {
  public let joined: Bool
  public let joinId: String?
  public let joinedAt: String?
}

struct AuraCommunityPostCreateBody: Encodable {
  let title: String
  let content: String
  let image: String?
  let images: [String]
  let mediaTypes: [String]
  let mediaDimensions: [MIRAMediaDimension]
  let mediaAssetIds: [String]?
  let location: String?
  let displayCity: String?
  let displayRegion: String?
  let displayCountry: String?
  let displayLocationLabel: String?
  let displayLocationSource: String?
  let displayLocationVisibility: String?
  let postType: String
  let placeId: String?
  let placeName: String?
  let placeProvider: String?
  let placeProviderId: String?
  let placeFormattedAddress: String?
  let placeCategory: String?
  let placeCity: String?
  let placeRegion: String?
  let placeCountry: String?
  let placeLat: Double?
  let placeLng: Double?
  let primaryCategory: String
  let communityCategory: String?
  let allowReplies: Bool?
  let audience: String
  let meetupNeighborhood: String?
  let meetupStartsAt: String?
  let meetupEndsAt: String?
  let meetupEntryType: String?
  let meetupEntryAmountAtoms: String?
  let meetupMaxPeople: Int?
  let visibility: String
  let clientRequestId: String
}

struct AuraCommunityDraft: Codable {
  var mode: AuraCommunityPostMode
  var title: String
  var bodyText: String
  var category: AuraSmallPostCategory
  var audience: AuraCommunityAudience
  var allowReplies: Bool
  var neighborhood: String
  var startsAt: Date
  var endsAt: Date
  var entryType: AuraMeetupEntryType
  var entryAmountAUR: String
  var maxPeople: Int
  var placeProvider: String?
  var placeProviderId: String?
  var placeName: String?
  var placeFormattedAddress: String?
  var placeLatitude: Double?
  var placeLongitude: Double?
  var placeCategory: String?
  var placeCity: String?
  var placeRegion: String?
  var placeCountry: String?
  var hasPhoto: Bool
}

enum AuraCommunityDraftStore {
  private static let folderName = "AuraCommunityDraft"
  private static let draftFileName = "draft.json"
  private static let photoFileName = "photo.bin"

  static func save(_ draft: AuraCommunityDraft, photoData: Data?) throws {
    let directory = try directoryURL()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(draft).write(to: directory.appendingPathComponent(draftFileName), options: [.atomic, .completeFileProtection])
    let photoURL = directory.appendingPathComponent(photoFileName)
    if let photoData, !photoData.isEmpty {
      try photoData.write(to: photoURL, options: [.atomic, .completeFileProtection])
    } else if FileManager.default.fileExists(atPath: photoURL.path) {
      try FileManager.default.removeItem(at: photoURL)
    }
  }

  static func load() throws -> (AuraCommunityDraft, Data?)? {
    let directory = try directoryURL()
    let draftURL = directory.appendingPathComponent(draftFileName)
    guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let draft = try decoder.decode(AuraCommunityDraft.self, from: Data(contentsOf: draftURL))
    let photoURL = directory.appendingPathComponent(photoFileName)
    let photo = draft.hasPhoto && FileManager.default.fileExists(atPath: photoURL.path)
      ? try Data(contentsOf: photoURL, options: .mappedIfSafe)
      : nil
    return (draft, photo)
  }

  static func clear() throws {
    let directory = try directoryURL()
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  private static func directoryURL() throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = root.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    return directory
  }
}
