import Foundation

struct CaptroTeaClub: Decodable, Identifiable {
  let id, groupId, name, role, viewerId: String
  let description: String?
  let memberCount: Int
  let rules: String
  let officialLinks: [String]
  let roomsEnabled: Bool
  let generalUnread: Bool?
  let version: Int
  let approvalRequired: Bool
  let postId: String?
  let image: String?
  let pin: CaptroClubQuote?
  let rooms: [CaptroClubRoom]
  var canManage: Bool { ["owner", "admin"].contains(role) }
}
struct CaptroClubRoom: Decodable, Identifiable {
  let id, name: String
  let announcements: Bool
  let unread: Bool?
}
struct CaptroClubQuote: Codable, Identifiable, Hashable {
  let id, body: String
  let room: String?
}
struct CaptroClubMessage: Decodable, Identifiable {
  let id, body, createdAt: String
  let room: String?
  let author: CaptroTeaAuthor
  let quote: CaptroClubQuote?
  let mediaURL, mediaType: String?
  var reference: CaptroClubQuote { .init(id: id, body: body, room: room) }
  var links: [CaptroTeaLink] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
    var seen = Set<String>()
    return detector.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap {
      guard let raw = $0.url?.absoluteString, let link = CaptroTeaLink(raw), seen.insert(link.id).inserted else { return nil }
      return link
    }
  }
}
struct CaptroClubLink: Decodable, Identifiable {
  let id, title, url, createdAt: String
  let sharedBy, sharedName, messageId: String?
  let version: Int
}
struct CaptroClubMember: Decodable, Identifiable {
  let id, name, username, role: String
}
struct CaptroClubInvite: Decodable, Identifiable {
  let id, expiresAt: String
  let requiresApproval: Bool
  let revokedAt, url: String?
  var active: Bool { revokedAt == nil && (captroTeaDate(expiresAt) ?? .distantPast) > Date() }
}
struct CaptroClubInviteRequest: Decodable, Identifiable {
  let id, inviteId, userId, name, status: String
}
struct CaptroClubInvitation: Decodable {
  let state, clubId, name: String
  let postId: String?
}
/// Nil fields are omitted, so each endpoint receives only its allowlisted input.
struct CaptroClubAction: Encodable {
  var id: String? = nil
  var body: String? = nil
  var room: String? = nil
  var quote: String? = nil
  var message: String? = nil
  var title: String? = nil
  var url: String? = nil
  var version: Int? = nil
  var name: String? = nil
  var announcements: Bool? = nil
  var rules: String? = nil
  var links: [String]? = nil
  var expires: String? = nil
  var approval: Bool? = nil
  var user: String? = nil
  var role: String? = nil
  var approve: Bool? = nil
}

struct CaptroTeaInviteRoute: Identifiable {
  let id: String
  static func parse(_ url: URL) -> Self? {
    let parts = url.pathComponents.filter { $0 != "/" }
    let token: String?
    if url.scheme == "captro", url.host == "tea-invite", parts.count == 1 { token = parts[0] }
    else if url.scheme == "https", ["captro.app", "www.captro.app", "captro-site.pages.dev"].contains(url.host?.lowercased() ?? ""), parts.count == 2, parts[0] == "tea-invite" { token = parts[1] }
    else { token = nil }
    guard url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
          let token, token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
    return .init(id: token)
  }
}
