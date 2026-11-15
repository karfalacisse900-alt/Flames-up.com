#if DEBUG
import Foundation

/// Isolated URLProtocol fixture only. No sample club, room or invite is published.
final class CaptroTeaClubReviewFixture: @unchecked Sendable {
  static let shared = CaptroTeaClubReviewFixture()
  private let lock = NSLock()
  private let clubID = "00000000-0000-4000-8000-000000000001"
  private var rooms: [[String: Any]] = []
  private var links: [[String: Any]] = []
  private var invites: [[String: Any]] = []
  private var pin: [String: Any]?
  private var version = 1
  private var rules = "Be kind. Keep shared work within the club."
  private var officialLinks = ["https://example.com/club"]
  private var messages: [[String: Any]] = []
  private var role: String { ProcessInfo.processInfo.arguments.contains("--tea-club-owner") ? "owner" : "member" }
  func response(_ path: String, request: URLRequest, body: [String: Any]) -> (Int, Any) {
    lock.withLock {
      guard ProcessInfo.processInfo.arguments.contains("--tea-club-owner") || ProcessInfo.processInfo.arguments.contains("--tea-club-member") else { return (403, ["detail": "Membership required"]) }
      let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
      if messages.isEmpty {
        messages = [
          ["id":"old-1","body":"Welcome to our next photo walk.","createdAt":now,"author":["id":"artist","name":"Maya","username":"mayafilms"]],
          ["id":"old-2","body":"Here is the route: https://example.com/walk","createdAt":now,"author":["id":"artist","name":"Maya","username":"mayafilms"]],
          ["id":"old-3","body":"I’ll bring my camera.","createdAt":now,"author":["id":"member2","name":"Jules","username":"jules"]],
        ]
      }
      let pieces = path.split(separator: "/").map(String.init)
      let action = pieces.count > 3 ? pieces[3] : "overview"
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let room = query.first { $0.name == "room" }?.value
      if pieces.count > 4, action == "messages" {
        return messages.first { $0["id"] as? String == pieces[4] }.map { (200, $0) } ?? (404,["detail":"Message unavailable"])
      }
      switch action {
      case "overview":
        var club: [String: Any] = ["id":clubID,"groupId":"fixture-club","name":"Night Garden","description":"A small space for photographers to share work and plan walks.","role":role,"viewerId":"tea-viewer","memberCount":3,"rules":rules,"officialLinks":officialLinks,"roomsEnabled":!rooms.isEmpty,"version":version,"approvalRequired":false,"postId":"tea-post-1","rooms":rooms]
        club["pin"] = pin; return (200,club)
      case "messages": return (200,["items":messages.filter { $0["room"] as? String == room }])
      case "send":
        if let existing = messages.first(where: { $0["id"] as? String == body["id"] as? String }) { return (200,existing) }
        var message: [String: Any] = ["id":body["id"]!,"body":body["body"]!,"createdAt":ISO8601DateFormatter().string(from: Date()),"author":["id":"tea-viewer","name":"Tea Fixture","username":"tea_fixture"]]
        message["room"] = body["room"]
        if let quote = messages.first(where: { $0["id"] as? String == body["quote"] as? String }) { message["quote"] = quote }
        messages.append(message); return (200,message)
      case "read": return (200,["ok":true])
      case "links": return (200,["items":links])
      case "saveLink":
        if let existing = links.first(where: { $0["id"] as? String == body["id"] as? String }) { return (200,existing) }
        var link: [String: Any] = ["id":body["id"]!,"title":body["title"]!,"url":body["url"]!,"sharedBy":"tea-viewer","version":1,"createdAt":now]
        link["messageId"] = body["message"]; links.append(link); return (200,link)
      case "members": return (200,["items":[["id":"tea-viewer","name":"Tea Fixture","username":"tea_fixture","role":role],["id":"artist","name":"Maya","username":"mayafilms","role":"member"],["id":"member2","name":"Jules","username":"jules","role":"member"]]])
      default: break
      }
      guard role == "owner" else { return (403,["detail":"Organizer required"]) }
      switch action {
      case "pin": pin = messages.first { $0["id"] as? String == body["message"] as? String }; version += 1
      case "createRoom": if !rooms.contains(where: { $0["id"] as? String == body["id"] as? String }) { rooms.append(["id":body["id"]!,"name":body["name"]!,"announcements":body["announcements"]!,"unread":false]) }
      case "settings": rules = body["rules"] as? String ?? ""; officialLinks = body["links"] as? [String] ?? []; version += 1
      case "editLink": if let index = links.firstIndex(where: { $0["id"] as? String == body["id"] as? String }) { links[index]["title"] = body["title"]; links[index]["url"] = body["url"]; links[index]["version"] = 2 }
      case "removeLink": links.removeAll { $0["id"] as? String == body["id"] as? String }
      case "createInvite":
        if !invites.contains(where: { $0["id"] as? String == body["id"] as? String }) { invites.append(["id":body["id"]!,"expiresAt":body["expires"]!,"requiresApproval":body["approval"]!,"url":"https://captro-site.pages.dev/tea-invite/" + String(repeating:"a",count:64)]) }
      case "invites": return (200,["items":invites])
      case "inviteRequests": return (200,["items":[]])
      case "revokeInvite": if let index = invites.firstIndex(where: { $0["id"] as? String == body["id"] as? String }) { invites[index]["revokedAt"] = now }
      default: return (404,["detail":"Unimplemented isolated fixture route"])
      }
      return (200,["ok":true])
    }
  }
}
#endif
