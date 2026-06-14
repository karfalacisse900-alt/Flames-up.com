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

private struct MIRAPostEngagementSnapshot: Codable, Hashable {
  var postId: String
  var liked: Bool?
  var likesCount: Int?
  var saved: Bool?
  var savesCount: Int?
  var commentsCount: Int?
  var updatedAt: Date

  mutating func merge(_ update: MIRAPostEngagementUpdate, now: Date) {
    if update.liked != nil { liked = update.liked }
    if update.likesCount != nil { likesCount = update.likesCount }
    if update.saved != nil { saved = update.saved }
    if update.savesCount != nil { savesCount = update.savesCount }
    if update.commentsCount != nil { commentsCount = update.commentsCount }
    updatedAt = now
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
  private static let cacheKey = "native.post.engagement.confirmed.v1"
  private static let maxSnapshotAge: TimeInterval = 60 * 60 * 24 * 365
  private static let maxSnapshots = 1_000

  public static func publish(_ update: MIRAPostEngagementUpdate) {
    NotificationCenter.default.post(name: .miraPostEngagementDidChange, object: update)
    Task {
      await persist(update)
    }
  }

  public static func update(from notification: Notification) -> MIRAPostEngagementUpdate? {
    notification.object as? MIRAPostEngagementUpdate
  }

  public static func apply(to post: MIRAPost) async -> MIRAPost {
    guard let snapshot = await snapshot(for: post.id) else { return post }
    return apply(snapshot, to: post)
  }

  public static func apply(to posts: [MIRAPost]) async -> [MIRAPost] {
    guard !posts.isEmpty else { return posts }
    let snapshots = await snapshotsByPostId()
    guard !snapshots.isEmpty else { return posts }
    return posts.map { post in
      guard let snapshot = snapshots[post.id] else { return post }
      return apply(snapshot, to: post)
    }
  }

  public static func clearCachedState() async {
    await MIRALocalJSONCache.remove(key: cacheKey)
  }

  private static func persist(_ update: MIRAPostEngagementUpdate) async {
    guard !update.postId.isEmpty else { return }
    var snapshots = await snapshotsByPostId()
    let now = Date()
    if var existing = snapshots[update.postId] {
      existing.merge(update, now: now)
      snapshots[update.postId] = existing
    } else {
      snapshots[update.postId] = MIRAPostEngagementSnapshot(
        postId: update.postId,
        liked: update.liked,
        likesCount: update.likesCount,
        saved: update.saved,
        savesCount: update.savesCount,
        commentsCount: update.commentsCount,
        updatedAt: now
      )
    }

    let cutoff = now.addingTimeInterval(-maxSnapshotAge)
    let compacted = snapshots.values
      .filter { $0.updatedAt >= cutoff }
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(maxSnapshots)
    await MIRALocalJSONCache.save(Array(compacted), key: cacheKey)
  }

  private static func snapshot(for postId: String) async -> MIRAPostEngagementSnapshot? {
    await snapshotsByPostId()[postId]
  }

  private static func snapshotsByPostId() async -> [String: MIRAPostEngagementSnapshot] {
    let values = await MIRALocalJSONCache.load(
      [MIRAPostEngagementSnapshot].self,
      key: cacheKey,
      maxAge: maxSnapshotAge
    ) ?? []
    let cutoff = Date().addingTimeInterval(-maxSnapshotAge)
    var snapshots: [String: MIRAPostEngagementSnapshot] = [:]
    for value in values where value.updatedAt >= cutoff {
      if let existing = snapshots[value.postId], existing.updatedAt >= value.updatedAt {
        continue
      }
      snapshots[value.postId] = value
    }
    return snapshots
  }

  private static func apply(_ snapshot: MIRAPostEngagementSnapshot, to post: MIRAPost) -> MIRAPost {
    post.updating(
      liked: mergedViewerFlag(cached: snapshot.liked, fresh: post.viewerLikedValue, cachedCount: snapshot.likesCount, freshCount: post.likesCount),
      likesCount: mergedCount(cached: snapshot.likesCount, fresh: post.likesCount, cachedFlag: snapshot.liked, freshFlag: post.viewerLikedValue),
      commentsCount: maxKnown(snapshot.commentsCount, post.commentsCount),
      saved: mergedViewerFlag(cached: snapshot.saved, fresh: post.viewerSavedValue, cachedCount: snapshot.savesCount, freshCount: post.savesCount),
      savesCount: mergedCount(cached: snapshot.savesCount, fresh: post.savesCount, cachedFlag: snapshot.saved, freshFlag: post.viewerSavedValue)
    )
  }

  private static func mergedViewerFlag(cached: Bool?, fresh: Bool?, cachedCount: Int?, freshCount: Int?) -> Bool? {
    guard let fresh else { return cached }
    guard let cached else { return fresh }
    if cached == true,
       fresh == false,
       let freshCount,
       freshCount >= (cachedCount ?? 0) {
      return true
    }
    return fresh
  }

  private static func mergedCount(cached: Int?, fresh: Int?, cachedFlag: Bool?, freshFlag: Bool?) -> Int? {
    guard cached != nil || fresh != nil else { return nil }
    let freshValue = max(0, fresh ?? 0)
    let cachedValue = max(0, cached ?? 0)
    if cachedFlag == true, freshFlag == false {
      return max(freshValue, cachedValue)
    }
    return fresh ?? cached
  }

  private static func maxKnown(_ lhs: Int?, _ rhs: Int?) -> Int? {
    guard lhs != nil || rhs != nil else { return nil }
    return max(0, max(lhs ?? 0, rhs ?? 0))
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
