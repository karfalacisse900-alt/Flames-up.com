import Foundation

enum CaptroNotificationTarget: Hashable {
  case post(String), profile(String), direct(String), group(String)
  static func resolve(_ notification: MIRANotification) -> Self? {
    guard let raw = notification.data?.raw.data(using: .utf8),
          let data = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return nil }
    func id(_ names: String...) -> String? {
      for name in names {
        if let value = data[name] as? String, !value.isEmpty, value.count <= 120,
           value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) { return value }
      }
      return nil
    }
    switch notification.type {
    case "message":
      if let group = id("group_id", "groupId") { return .group(group) }
      return id("sender_id", "senderId", "conversation_id").map(Self.direct)
    case "group_message": return id("group_id", "groupId").map(Self.group)
    case "follow", "follow_request", "follow_approved": return id("follower_id", "from_user_id", "user_id", "sender_id").map(Self.profile)
    default: return id("post_id", "postId").map(Self.post)
    }
  }
}
