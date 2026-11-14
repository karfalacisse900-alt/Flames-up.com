import Foundation

struct CaptroTeaAuthor: Codable, Hashable {
  let id: String
  let name: String
  let username: String
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
}

struct CaptroTeaReply: Codable, Identifiable {
  let id: String
  let body: String
  let author: CaptroTeaAuthor
  let createdAt: String
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
