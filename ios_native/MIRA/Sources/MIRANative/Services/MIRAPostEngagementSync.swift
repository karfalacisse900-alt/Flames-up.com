import Foundation

public struct MIRAPostEngagementUpdate {
  public let postId: String
  public let liked: Bool?
  public let likesCount: Int?
  public let saved: Bool?
  public let savesCount: Int?
  public let commentsCount: Int?

  public init(
    postId: String,
    liked: Bool? = nil,
    likesCount: Int? = nil,
    saved: Bool? = nil,
    savesCount: Int? = nil,
    commentsCount: Int? = nil
  ) {
    self.postId = postId
    self.liked = liked
    self.likesCount = likesCount
    self.saved = saved
    self.savesCount = savesCount
    self.commentsCount = commentsCount
  }
}

public extension Notification.Name {
  static let miraPostEngagementDidChange = Notification.Name("mira.post.engagement.didChange")
}

@MainActor
public enum MIRAPostEngagementSync {
  public static func publish(_ update: MIRAPostEngagementUpdate) {
    NotificationCenter.default.post(name: .miraPostEngagementDidChange, object: update)
  }

  public static func update(from notification: Notification) -> MIRAPostEngagementUpdate? {
    notification.object as? MIRAPostEngagementUpdate
  }
}
