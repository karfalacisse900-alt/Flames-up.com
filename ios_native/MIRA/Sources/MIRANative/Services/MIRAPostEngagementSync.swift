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

public struct MIRAUserFollowUpdate {
  public let userId: String
  public let following: Bool
  public let followersCount: Int?

  public init(userId: String, following: Bool, followersCount: Int? = nil) {
    self.userId = userId
    self.following = following
    self.followersCount = followersCount
  }
}

public struct MIRAPostRemovalUpdate {
  public let postId: String

  public init(postId: String) {
    self.postId = postId
  }
}

public extension Notification.Name {
  static let miraPostEngagementDidChange = Notification.Name("mira.post.engagement.didChange")
  static let miraUserFollowDidChange = Notification.Name("mira.user.follow.didChange")
  static let miraPostWasRemoved = Notification.Name("mira.post.wasRemoved")
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

@MainActor
public enum MIRAUserFollowSync {
  public static func publish(_ update: MIRAUserFollowUpdate) {
    NotificationCenter.default.post(name: .miraUserFollowDidChange, object: update)
  }

  public static func update(from notification: Notification) -> MIRAUserFollowUpdate? {
    notification.object as? MIRAUserFollowUpdate
  }
}

@MainActor
public enum MIRAPostRemovalSync {
  public static func publish(_ update: MIRAPostRemovalUpdate) {
    NotificationCenter.default.post(name: .miraPostWasRemoved, object: update)
  }

  public static func update(from notification: Notification) -> MIRAPostRemovalUpdate? {
    notification.object as? MIRAPostRemovalUpdate
  }
}
