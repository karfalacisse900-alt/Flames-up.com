import Foundation

struct MIRASettingsSnapshot: Codable, Hashable {
  let user: MIRAUser?
  let language: String
  let isPrivate: Bool
  let savedAt: String
}

struct MIRADraftPlaceSnapshot: Codable, Hashable {
  let provider: String
  let providerPlaceId: String?
  let name: String
  let formattedAddress: String?
  let latitude: Double?
  let longitude: Double?
  let category: String?
  let city: String?
  let region: String?
  let country: String?
}

struct MIRADraftBroadLocationSnapshot: Codable, Hashable {
  let city: String?
  let region: String?
  let country: String?
  let label: String?
  let source: String
  let visibility: String
}

struct MIRAPostDraftMediaSnapshot: Codable, Hashable, Identifiable {
  let id: String
  let localFilePath: String
  let kind: String
  let fileName: String
  let mimeType: String
  let editorMetadata: MIRANativeEditedMediaMetadata?
}

struct MIRAPostDraftSnapshot: Codable, Hashable {
  let title: String
  let bodyText: String
  let hashtags: [String]
  let selectedAudioTrack: MIRAAudiusTrack?
  let place: MIRADraftPlaceSnapshot?
  let broadLocation: MIRADraftBroadLocationSnapshot?
  let showBroadLocation: Bool
  let media: [MIRAPostDraftMediaSnapshot]
  let uploadStatus: String
  let errorMessage: String?
  let savedAt: String
}

actor MIRAAppCacheStore {
  static let shared = MIRAAppCacheStore()

  private let shortCacheAge: TimeInterval = 60 * 60 * 24 * 7
  private let contentCacheAge: TimeInterval = 60 * 60 * 24 * 30
  private let profileCacheAge: TimeInterval = 60 * 60 * 24 * 90
  private let maxFeedPosts = 80
  private let maxDiscoverPosts = 90
  private let maxProfilePosts = 120
  private let maxCachedComments = 80
  private let maxNotifications = 120

  func loadFeed() async -> [MIRAPost]? {
    await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.feed, maxAge: contentCacheAge)
  }

  func saveFeed(_ posts: [MIRAPost]) async {
    await MIRALocalJSONCache.save(Array(posts.prefix(maxFeedPosts)), key: CacheKey.feed)
  }

  func mergePostsPreservingVisibleState(existing: [MIRAPost], fresh: [MIRAPost], preferFreshOrderWhenEmpty: Bool = true) -> [MIRAPost] {
    guard !existing.isEmpty else { return Array(fresh.prefix(maxFeedPosts)) }
    guard !fresh.isEmpty else { return existing }

    let freshById = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
    var seen = Set<String>()
    var merged = existing.map { cached -> MIRAPost in
      seen.insert(cached.id)
      return freshById[cached.id] ?? cached
    }

    let newItems = fresh.filter { seen.insert($0.id).inserted }
    if preferFreshOrderWhenEmpty, existing.isEmpty {
      merged = fresh
    } else {
      merged.append(contentsOf: newItems)
    }
    return Array(merged.prefix(maxFeedPosts))
  }

  func loadDiscoverPosts(category: String) async -> [MIRAPost]? {
    await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.discoverPosts(category), maxAge: contentCacheAge)
  }

  func saveDiscoverPosts(_ posts: [MIRAPost], category: String) async {
    await MIRALocalJSONCache.save(Array(posts.prefix(maxDiscoverPosts)), key: CacheKey.discoverPosts(category))
  }

  func loadCachedPost(id postId: String) async -> MIRAPost? {
    var best: MIRAPost?
    if let feed = await loadFeed() {
      best = preferredPost(best, feed.first { $0.id == postId })
    }
    for category in CacheKey.discoverCategoryIds {
      if let posts = await loadDiscoverPosts(category: category) {
        best = preferredPost(best, posts.first { $0.id == postId })
      }
    }
    return best
  }

  func loadDiscoverStories() async -> [MIRAStoryGroup]? {
    await MIRALocalJSONCache.load([MIRAStoryGroup].self, key: CacheKey.discoverStories, maxAge: contentCacheAge)
  }

  func saveDiscoverStories(_ stories: [MIRAStoryGroup]) async {
    await MIRALocalJSONCache.save(stories, key: CacheKey.discoverStories)
  }

  func loadCurrentProfile() async -> MIRAUser? {
    await MIRALocalJSONCache.load(MIRAUser.self, key: CacheKey.currentProfile, maxAge: profileCacheAge)
  }

  func saveCurrentProfile(_ user: MIRAUser) async {
    await MIRALocalJSONCache.save(user, key: CacheKey.currentProfile)
  }

  func loadProfilePosts(userId: String) async -> [MIRAPost]? {
    await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.profilePosts(userId), maxAge: profileCacheAge)
  }

  func saveProfilePosts(_ posts: [MIRAPost], userId: String) async {
    await MIRALocalJSONCache.save(Array(posts.prefix(maxProfilePosts)), key: CacheKey.profilePosts(userId))
  }

  func loadViewedProfile(userId: String) async -> MIRAUser? {
    await MIRALocalJSONCache.load(MIRAUser.self, key: CacheKey.viewedProfile(userId), maxAge: profileCacheAge)
  }

  func saveViewedProfile(_ user: MIRAUser, userId: String) async {
    await MIRALocalJSONCache.save(user, key: CacheKey.viewedProfile(userId))
  }

  func loadComments(postId: String) async -> [MIRAComment]? {
    await MIRALocalJSONCache.load([MIRAComment].self, key: CacheKey.comments(postId), maxAge: shortCacheAge)
  }

  func saveComments(_ comments: [MIRAComment], postId: String) async {
    await MIRALocalJSONCache.save(Array(sortComments(comments).prefix(maxCachedComments)), key: CacheKey.comments(postId))
  }

  func mergeComments(existing: [MIRAComment], fresh: [MIRAComment]) -> [MIRAComment] {
    let merged = Dictionary(grouping: existing + fresh, by: \.id).compactMap { $0.value.last }
    return sortComments(merged)
  }

  func loadNotifications() async -> [MIRANotification]? {
    await MIRALocalJSONCache.load([MIRANotification].self, key: CacheKey.notifications, maxAge: shortCacheAge)
  }

  func saveNotifications(_ notifications: [MIRANotification]) async {
    await MIRALocalJSONCache.save(Array(notifications.prefix(maxNotifications)), key: CacheKey.notifications)
  }

  func markNotificationsRead(_ notifications: [MIRANotification]) async -> [MIRANotification] {
    let updated = notifications.map { $0.updatingRead(true) }
    await saveNotifications(updated)
    return updated
  }

  func loadSettings() async -> MIRASettingsSnapshot? {
    await MIRALocalJSONCache.load(MIRASettingsSnapshot.self, key: CacheKey.settings, maxAge: profileCacheAge)
  }

  func saveSettings(user: MIRAUser?, language: String, isPrivate: Bool) async {
    let snapshot = MIRASettingsSnapshot(user: user, language: language, isPrivate: isPrivate, savedAt: nowISO())
    await MIRALocalJSONCache.save(snapshot, key: CacheKey.settings)
  }

  func loadPostDraft() async -> MIRAPostDraftSnapshot? {
    await MIRALocalJSONCache.load(MIRAPostDraftSnapshot.self, key: CacheKey.postDraft, maxAge: profileCacheAge)
  }

  func savePostDraft(_ draft: MIRAPostDraftSnapshot) async {
    await MIRALocalJSONCache.save(draft, key: CacheKey.postDraft)
  }

  func storePostDraftMedia(_ mediaItems: [MIRAPickedMedia]) async -> [MIRAPostDraftMediaSnapshot] {
    guard let directory = postDraftMediaDirectory() else { return [] }
    clearDirectory(directory)
    return mediaItems.compactMap { item in
      let safeName = item.fileName
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
      let fileURL = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
      do {
        try item.data.write(to: fileURL, options: [.atomic])
        return MIRAPostDraftMediaSnapshot(
          id: UUID().uuidString,
          localFilePath: fileURL.path,
          kind: item.kind.rawValue,
          fileName: item.fileName,
          mimeType: item.mimeType,
          editorMetadata: item.editorMetadata
        )
      } catch {
        return nil
      }
    }
  }

  func loadPostDraftMedia(_ draft: MIRAPostDraftSnapshot) async -> [MIRAPickedMedia] {
    draft.media.compactMap { item in
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.localFilePath)),
            let kind = MIRAPickedMediaKind(rawValue: item.kind)
      else { return nil }
      return MIRAPickedMedia(
        data: data,
        kind: kind,
        fileName: item.fileName,
        mimeType: item.mimeType,
        editorMetadata: item.editorMetadata
      )
    }
  }

  func clearPostDraft() async {
    await MIRALocalJSONCache.remove(key: CacheKey.postDraft)
    guard let directory = postDraftMediaDirectory() else { return }
    clearDirectory(directory)
  }

  func cleanup() async {
    await MIRALocalJSONCache.trim(maxAge: contentCacheAge)
    await MIRAImageDiskCache.trim()
  }

  private func sortComments(_ comments: [MIRAComment]) -> [MIRAComment] {
    comments.sorted { lhs, rhs in
      if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
      return (lhs.createdAt ?? "") < (rhs.createdAt ?? "")
    }
  }

  private func preferredPost(_ lhs: MIRAPost?, _ rhs: MIRAPost?) -> MIRAPost? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    let lhsScore = (lhs.likesCount ?? 0) + (lhs.commentsCount ?? 0) + (lhs.savesCount ?? 0)
    let rhsScore = (rhs.likesCount ?? 0) + (rhs.commentsCount ?? 0) + (rhs.savesCount ?? 0)
    return rhsScore >= lhsScore ? rhs : lhs
  }

  private func nowISO() -> String {
    ISO8601DateFormatter.miraCacheStore.string(from: Date())
  }
}

private enum CacheKey {
  static let feed = "native.main.feed.v4.cache_first"
  static let discoverStories = "native.discover.stories.v4.cache_first"
  static let currentProfile = "native.profile.me.v3.cache_first"
  static let notifications = "native.notifications.v2.cache_first"
  static let settings = "native.settings.v1.cache_first"
  static let postDraft = "native.post_draft.v1.cache_first"
  static let discoverCategoryIds = [
    "all",
    "photography",
    "outdoors",
    "outfits",
    "food",
    "travel",
    "events",
    "nightlife",
    "art",
    "lifestyle",
    "fitness"
  ]

  static func discoverPosts(_ category: String) -> String {
    "native.discover.posts.v4.cache_first.\(category)"
  }

  static func profilePosts(_ userId: String) -> String {
    "native.profile.posts.v3.cache_first.\(userId)"
  }

  static func viewedProfile(_ userId: String) -> String {
    "native.profile.user.v3.cache_first.\(userId)"
  }

  static func comments(_ postId: String) -> String {
    "native.comments.v1.cache_first.\(postId)"
  }
}

private extension ISO8601DateFormatter {
  static let miraCacheStore: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

private func postDraftMediaDirectory() -> URL? {
  guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
  let directory = caches.appendingPathComponent("MIRAPostDraftMedia", isDirectory: true)
  if !FileManager.default.fileExists(atPath: directory.path) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  return directory
}

private func clearDirectory(_ directory: URL) {
  guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
  for file in files {
    try? FileManager.default.removeItem(at: file)
  }
}
