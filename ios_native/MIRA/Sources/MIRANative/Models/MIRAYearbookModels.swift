import Foundation

public enum MIRAYearbookIntent: String, Codable, CaseIterable, Identifiable {
  case friends
  case dating
  case friendsAndDating = "friends_and_dating"
  case creativeNetworking = "creative_networking"
  case justBrowsing = "just_browsing"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .friends: return "Friends"
    case .dating: return "Dating"
    case .friendsAndDating: return "Friends + Dating"
    case .creativeNetworking: return "Creative / Networking"
    case .justBrowsing: return "Just Browsing"
    }
  }
}

public enum MIRAYearbookTheme: String, Codable, CaseIterable, Identifiable {
  case classicYearbook = "classic_yearbook"
  case notebook
  case y2k
  case film
  case minimal
  case vintage
  case scrapbook

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .classicYearbook: return "Classic Yearbook"
    case .notebook: return "Notebook"
    case .y2k: return "Y2K"
    case .film: return "Film"
    case .minimal: return "Minimal"
    case .vintage: return "Vintage"
    case .scrapbook: return "Scrapbook"
    }
  }
}

public enum MIRAYearbookVisibility: String, Codable, CaseIterable, Identifiable {
  case `public`
  case friends
  case `private`

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .public: return "Everyone"
    case .friends: return "Friends"
    case .private: return "Only me"
    }
  }

  public var systemImage: String {
    switch self {
    case .public: return "globe"
    case .friends: return "person.2"
    case .private: return "lock"
    }
  }
}

public struct MIRAYearbookPrompt: Codable, Identifiable, Hashable {
  public let recordId: String?
  public let promptKey: String
  public let answer: String
  public let position: Int

  public var id: String { recordId ?? promptKey }
  public var displayPrompt: String {
    switch promptKey {
    case "most_likely_to": return "Most likely to..."
    case "perfect_day": return "My perfect day"
    case "always_carry": return "I always carry"
    case "little_joy": return "A small thing I love"
    case "meet_me_at": return "Meet me at"
    default: return promptKey.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  private enum CodingKeys: String, CodingKey {
    case recordId = "id"
    case promptKey
    case answer
    case position
  }
}

public struct MIRAYearbookSignature: Codable, Identifiable, Hashable {
  public let id: String
  public let signerUserId: String
  public let username: String?
  public let displayName: String?
  public let profilePhoto: String?
  public let message: String?
  public let createdAt: String?
}

public struct MIRAYearbookProfile: Codable, Identifiable, Hashable {
  public let userId: String
  public let username: String?
  public let displayName: String?
  public let profilePhoto: String?
  public let discoveryIntent: String
  public let datingEnabled: Bool
  public let age: Int?
  public let heightCm: Int?
  public let city: String?
  public let country: String?
  public let job: String?
  public let school: String?
  public let shortBio: String?
  public let currentMood: String?
  public let languages: [String]?
  public let interests: [String]?
  public let hobbies: [String]?
  public let favorites: [String: String]?
  public let fieldVisibility: [String: String]?
  public let sectionOrder: [String]?
  public let themeId: String
  public let status: String
  public let viewerIsOwner: Bool
  public let connectionStatus: String?
  public let connectionRequestId: String?
  public let interestSent: Bool
  public let interestMutual: Bool
  public let interestAvailable: Bool?
  public let signatureCount: Int
  public let signatures: [MIRAYearbookSignature]?
  public let prompts: [MIRAYearbookPrompt]?
  public let updatedAt: String?

  public var id: String { userId }
  public var name: String {
    let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !display.isEmpty { return display }
    let handle = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return handle.isEmpty ? "Captro member" : handle
  }
  public var handle: String {
    let value = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? "" : "@\(value)"
  }
  public var locationLine: String {
    [city, country]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }
  public var intent: MIRAYearbookIntent {
    MIRAYearbookIntent(rawValue: discoveryIntent) ?? .friends
  }
  public var theme: MIRAYearbookTheme {
    MIRAYearbookTheme(rawValue: themeId) ?? .classicYearbook
  }
}

public struct MIRAYearbookDiscoverResponse: Decodable {
  public let profiles: [MIRAYearbookProfile]
  public let hasMore: Bool
  public let nextOffset: Int
  public let datingUnavailable: Bool?
}

public struct MIRAYearbookProfileResponse: Decodable {
  public let profile: MIRAYearbookProfile?
  public let saved: Bool?
}

public struct MIRAYearbookSignaturesResponse: Decodable {
  public let count: Int
  public let signatures: [MIRAYearbookSignature]
}

public struct MIRAYearbookActionResponse: Decodable {
  public let signed: Bool?
  public let signatureId: String?
  public let interested: Bool?
  public let mutual: Bool?
  public let status: String?
  public let requestId: String?
  public let detail: String?
  public let blocked: Bool?
  public let removed: Bool?
  public let reported: Bool?
}

public struct MIRAYearbookPromptDraft: Codable, Hashable, Identifiable {
  public var promptKey: String
  public var answer: String
  public var position: Int
  public var id: String { promptKey }
}

public struct MIRAYearbookProfileDraft: Encodable {
  public var discoveryIntent: String
  public var datingEnabled: Bool
  public var age: Int?
  public var heightCm: Int?
  public var city: String
  public var country: String
  public var job: String
  public var school: String
  public var shortBio: String
  public var currentMood: String
  public var languages: [String]
  public var interests: [String]
  public var hobbies: [String]
  public var favorites: [String: String]
  public var fieldVisibility: [String: String]
  public var sectionOrder: [String]
  public var themeId: String
  public var status: String
  public var prompts: [MIRAYearbookPromptDraft]

  public static let defaultSectionOrder = ["about", "details", "interests", "prompts", "favorites"]

  public static func empty(from user: MIRAUser?) -> MIRAYearbookProfileDraft {
    MIRAYearbookProfileDraft(
      discoveryIntent: MIRAYearbookIntent.friends.rawValue,
      datingEnabled: false,
      age: nil,
      heightCm: nil,
      city: user?.city ?? "",
      country: "",
      job: "",
      school: "",
      shortBio: user?.bio ?? "",
      currentMood: "",
      languages: [],
      interests: user?.interests?.values ?? [],
      hobbies: [],
      favorites: [:],
      fieldVisibility: MIRAYearbookProfileDraft.defaultVisibility,
      sectionOrder: defaultSectionOrder,
      themeId: MIRAYearbookTheme.classicYearbook.rawValue,
      status: "active",
      prompts: []
    )
  }

  public static func from(_ profile: MIRAYearbookProfile, user: MIRAUser?) -> MIRAYearbookProfileDraft {
    MIRAYearbookProfileDraft(
      discoveryIntent: profile.discoveryIntent,
      datingEnabled: profile.datingEnabled,
      age: profile.age,
      heightCm: profile.heightCm,
      city: profile.city ?? user?.city ?? "",
      country: profile.country ?? "",
      job: profile.job ?? "",
      school: profile.school ?? "",
      shortBio: profile.shortBio ?? user?.bio ?? "",
      currentMood: profile.currentMood ?? "",
      languages: profile.languages ?? [],
      interests: profile.interests ?? user?.interests?.values ?? [],
      hobbies: profile.hobbies ?? [],
      favorites: profile.favorites ?? [:],
      fieldVisibility: profile.fieldVisibility ?? defaultVisibility,
      sectionOrder: profile.sectionOrder ?? defaultSectionOrder,
      themeId: profile.themeId,
      status: profile.status,
      prompts: (profile.prompts ?? []).map { .init(promptKey: $0.promptKey, answer: $0.answer, position: $0.position) }
    )
  }

  public static let defaultVisibility: [String: String] = [
    "display_name": "public", "profile_photo": "public", "age": "friends", "height_cm": "friends",
    "city": "public", "country": "public", "job": "friends", "school": "friends",
    "short_bio": "public", "current_mood": "public", "languages": "friends",
    "interests": "public", "hobbies": "public", "favorites": "public", "prompts": "public",
  ]
}
