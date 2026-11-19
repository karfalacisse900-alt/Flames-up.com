#if DEBUG
import Foundation

/// Replay of one read-only public snapshot through the production root and API.
/// Requests cannot write to Captro: this transport has no production credentials.
enum CaptroPolishReviewSnapshot {
  static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--captro-consistency-review") }
  private static let snapshot = (try? JSONSerialization.jsonObject(with: CaptroPolishSnapshotPayload.data)) as? [String:Any] ?? [:]
  static var notes: [[String:Any]] { snapshot["notes"] as? [[String:Any]] ?? [] }
  private static var replies: [[String:Any]] { snapshot["replies"] as? [[String:Any]] ?? [] }
  static func image(_ url: String) -> Data? {
    guard let encoded = (snapshot["images"] as? [String:String])?[url] else { return nil }
    return Data(base64Encoded: encoded)
  }
  static func response(_ path: String, request: URLRequest) -> (Int, Any)? {
    guard enabled else { return nil }
    guard request.httpMethod == nil || request.httpMethod == "GET" else {
      return (503, ["detail":"Review is read-only. Your draft is still here."])
    }
    let home = snapshot["home"] as? [[String:Any]] ?? []
    let owner = snapshot["profile"] as? [String:Any] ?? [:]
    if path == "/auth/me" { return (200,owner) }
    if path == "/posts/feed" || path == "/posts/world-board" {
      return (200,["posts":home,"hasMore":false])
    }
    if path == "/users/" + (owner["id"] as? String ?? "") + "/posts" {
      return (200,home.filter { $0["userId"] as? String == owner["id"] as? String })
    }
    if path.hasSuffix("/showcase") { return (200,["clubs":[],"plans":[]]) }
    if path == "/conversations" { return (200,[["id":"review-chat","other_user_id":"review-peer","other_username":"alex","last_message":"See you at the photo walk.","unread_count":1]]) }
    if path == "/messages/review-peer" {
      return (200,[["id":"review-incoming","sender_id":"review-peer","receiver_id":owner["id"] ?? "","content":"Are you joining the photo walk?","created_at":"2026-11-19T12:00:00Z","status":"read"],
        ["id":"review-outgoing","sender_id":owner["id"] ?? "","receiver_id":"review-peer","content":"See you at the photo walk.","created_at":"2026-11-19T12:01:00Z","status":"sent"]])
    }
    if path.hasPrefix("/posts/"), let post = home.first(where: { path == "/posts/" + ($0["id"] as? String ?? "") }) { return (200,post) }
    if path == "/tea/conversations" { return (200,["items":notes]) }
    if path == "/tea/conversations/capabilities" { return (200,["canCreateForms":false]) }
    if path.hasPrefix("/tea/conversations/") {
      let parts = path.split(separator:"/")
      guard parts.count >= 3, let note = notes.first(where: { $0["id"] as? String == String(parts[2]) }) else { return (404,["detail":"Unavailable"]) }
      if parts.last == "replies" {
        let target = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "target" }?.value
        let result = replies.filter { row in
          guard row["conversationID"] as? String == note["id"] as? String else { return false }
          if target == "general" { return !(row["target"] is [String:Any]) }
          if let target { return (row["target"] as? [String:Any])?["id"] as? String == target }
          return true
        }
        return (200,["items":result])
      }
      return (200,note)
    }
    if path.hasPrefix("/users/"), let author = notes.compactMap({$0["author"] as? [String:Any]}).first(where: { path == "/users/" + ($0["id"] as? String ?? "") }) {
      return (200,["id":author["id"]!,"username":author["username"]!,"fullName":author["name"]!,"profileImage":author["photoURL"] ?? NSNull(),"isVerified":author["isVerified"] ?? false,"isFollowing":false])
    }
    return nil
  }
}
#endif
