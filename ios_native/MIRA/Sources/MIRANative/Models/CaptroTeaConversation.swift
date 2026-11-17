import Foundation

struct CaptroTeaAuthor: Codable, Hashable {
  let id: String
  let name: String
  let username: String
  var photoURL: String? = nil
}

struct CaptroTeaConversation: Codable, Identifiable, Hashable {
  let id: String
  var title: String
  var body: String
  var links: [String]
  let author: CaptroTeaAuthor
  let createdAt: String
  var version: Int
  var isAuthor: Bool
  var following: Bool
  var sentences: [CaptroTeaReplyTarget]? = nil
  var replyTargets: [CaptroTeaReplyCount]? = nil
  var replyCount: Int? = nil
  var borough: String? = nil
  var primaryAction: CaptroTeaNoteAction? = nil
  var applicationSubmitted: Bool? = nil
  var canManageApplications: Bool? = nil
}

struct CaptroTeaNoteAction: Codable, Hashable {
  var kind: String
  var label: String
  var url: String? = nil
  var listingId: String? = nil
  var listingSource: String? = nil
  var heightRequested: Bool? = nil
  var accepting: Bool? = nil
  var state: String? = nil
  var input: Self { var copy = self; copy.state = nil; return copy }
  var valid: Bool {
    guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.count <= 40 else { return false }
    switch kind {
    case "external": return url.flatMap(CaptroTeaLink.init) != nil
    case "listing": return listingId.flatMap(UUID.init(uuidString:)) != nil && (listingSource == nil || ["activity","post"].contains(listingSource!))
    case "application": return heightRequested != nil && accepting != nil
    default: return false
    }
  }
  var statusLabel: String {
    switch state {
    case "ended": return "Ended"
    case "closed": return "Applications closed"
    case "unavailable": return "Unavailable"
    default: return label
    }
  }
}

struct CaptroTeaNoteActionResolution: Decodable {
  let note: CaptroTeaConversation
  let listing: CaptroTeaEntry?
}

struct CaptroTeaNotePayload: Encodable {
  let title, body: String
  let links: [String]
  let requestID: String?
  let version: Int?
  let borough: String?
  let primaryAction: CaptroTeaNoteAction?
  enum CodingKeys: String, CodingKey { case title, body, links, requestID, version, borough, primaryAction }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(title, forKey: .title); try c.encode(body, forKey: .body); try c.encode(links, forKey: .links)
    try c.encodeIfPresent(requestID, forKey: .requestID); try c.encodeIfPresent(version, forKey: .version)
    // Explicit null removes an optional field; absence belongs to legacy clients.
    try c.encode(borough, forKey: .borough); try c.encode(primaryAction?.input, forKey: .primaryAction)
  }
}

struct CaptroTeaApplicationPayload: Encodable {
  let requestID: String
  let version: Int
  let fullName, availability: String
  let height, portfolio: String?
}
struct CaptroTeaApplicationReceipt: Decodable { let id: String; let confirmed: Bool; let submittedAt: String }
struct CaptroTeaApplication: Decodable, Identifiable {
  let id, createdAt: String
  let answers: Answers
  struct Answers: Decodable { let fullName, availability: String; let height, portfolio: String? }
}

struct CaptroTeaReplyTarget: Codable, Identifiable, Hashable {
  let id: String
  let version: Int
  let start: Int
  let end: Int
  let quote: String
}
struct CaptroTeaReplyCount: Codable, Hashable {
  let target: CaptroTeaReplyTarget
  let count: Int
}

struct CaptroTeaReply: Codable, Identifiable {
  let id: String
  let body: String
  let author: CaptroTeaAuthor
  let createdAt: String
  var target: CaptroTeaReplyTarget? = nil
}

struct CaptroTeaReplyGroup: Identifiable {
  var id: String { replies[0].id }
  var replies: [CaptroTeaReply]
  static func consecutive(_ replies: [CaptroTeaReply]) -> [Self] {
    replies.reduce(into: []) { groups, reply in
      if groups.last?.replies.last?.author.id == reply.author.id {
        groups[groups.count - 1].replies.append(reply)
      } else { groups.append(Self(replies: [reply])) }
    }
  }
}

struct CaptroTeaConversationPage<Item: Decodable>: Decodable {
  let items: [Item]
  let nextCursor: String?
}

struct CaptroTeaLink: Identifiable, Hashable {
  let url: URL
  let hostname: String
  let platform: String?
  var id: String { url.absoluteString }

  init?(_ raw: String) {
    guard raw.count <= 2048, !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
          let url = URL(string: raw), url.scheme?.lowercased() == "https",
          url.user == nil, url.password == nil, url.port == nil,
          let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix("."),
          !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.contains(":"),
          !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
    self.url = url
    hostname = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    func belongs(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
    if belongs("youtube.com") || host == "youtu.be" { platform = "YouTube" }
    else if belongs("tiktok.com") { platform = "TikTok" }
    else { platform = nil }
  }

  // Only routes already supported by Captro. Unknown paths remain web links.
  var profile: CaptroProfileLink? {
    guard ["captro.app", "www.captro.app", "captro-site.pages.dev"].contains(url.host?.lowercased() ?? ""),
          url.query == nil, url.fragment == nil else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count == 2, parts[0] == "profile",
          let candidate = URL(string: "captro://profile/" + parts[1]) else { return nil }
    return CaptroProfileLink.parse(candidate)
  }
}

func captroTeaDate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: value) { return date }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: value)
}
