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

struct MIRAVoiceDraftSnapshot: Codable, Hashable {
  let localFilePath: String
  let duration: TimeInterval
  let levels: [Float]
  let disclosureVersion: String
  let disclosureAcceptedAt: Date

  init(_ draft: CaptroVoiceDraft) {
    localFilePath = draft.fileURL.path
    duration = draft.duration
    levels = draft.levels
    disclosureVersion = draft.disclosureVersion
    disclosureAcceptedAt = draft.disclosureAcceptedAt
  }

  func restore() -> CaptroVoiceDraft? {
    guard let directory = postDraftMediaDirectory() else { return nil }
    let url = URL(fileURLWithPath: localFilePath).standardizedFileURL
    guard url.deletingLastPathComponent() == directory.standardizedFileURL,
          FileManager.default.fileExists(atPath: url.path) else { return nil }
    return CaptroVoiceDraft(
      fileURL: url, duration: duration, levels: levels,
      disclosureVersion: disclosureVersion, disclosureAcceptedAt: disclosureAcceptedAt
    )
  }
}

struct MIRAPostDraftSnapshot: Codable, Hashable {
  let title: String
  let bodyText: String
  let stampType: String?
  var stampVariant: String? = nil
  var momentType: String? = nil
  var eventDraft: CaptroEventDraft? = nil
  var commerceDraft: CaptroCommerceDraft? = nil
  let hashtags: [String]
  let selectedDiscoverCategory: String?
  let selectedAudioTrack: MIRAAudiusTrack?
  let place: MIRADraftPlaceSnapshot?
  let broadLocation: MIRADraftBroadLocationSnapshot?
  let showBroadLocation: Bool
  let isEditingPostDetails: Bool?
  let media: [MIRAPostDraftMediaSnapshot]
  var voiceDraft: MIRAVoiceDraftSnapshot? = nil
  let uploadStatus: String
  let errorMessage: String?
  let savedAt: String
}

private struct MIRAAppDataStateSnapshot: Codable, Hashable {
  let database: String?
  let mediaStorage: String?
  let dataGeneration: String?
  let dataResetAt: String?
  let appDataCleared: Bool?
}

actor MIRAAppCacheStore {
  static let shared = MIRAAppCacheStore()

  private static let dataGenerationDefaultsKey = "native.app.data_generation.v1"

  private var didClearPostDraftFromPreviousProcess = false

  private let shortCacheAge: TimeInterval = 60 * 60 * 24 * 7
  private let contentCacheAge: TimeInterval = 60 * 60 * 24 * 30
  private let profileCacheAge: TimeInterval = 60 * 60 * 24 * 90
  private let maxFeedPosts = 80
  private let maxDiscoverPosts = 90
  private let maxProfilePosts = 120
  private let maxCachedComments = 80
  private let maxNotifications = 120

  @discardableResult
  func reconcileServerDataState(api: MIRAAPIClient) async -> Bool {
    let accountScope = MIRALocalJSONCache.currentScopeIdentifier
    do {
      let snapshot: MIRAAppDataStateSnapshot = try await api.get("system/data-state")
      guard accountScope == MIRALocalJSONCache.currentScopeIdentifier else { return false }
      guard let generation = snapshot.dataGeneration?.trimmingCharacters(in: .whitespacesAndNewlines),
            !generation.isEmpty
      else { return false }

      let defaults = UserDefaults.standard
      let stored = defaults.string(forKey: Self.dataGenerationDefaultsKey)
      if stored == nil {
        // Establish the baseline without treating an app upgrade as a server
        // reset. Normal stale-while-revalidate reads still refresh snapshots.
        defaults.set(generation, forKey: Self.dataGenerationDefaultsKey)
        return false
      }
      guard stored != generation else { return false }

      await purgeContentCaches()
      defaults.set(generation, forKey: Self.dataGenerationDefaultsKey)
      MIRAPerformanceTimeline.mark("app_data_generation_reconciled", detail: snapshot.dataResetAt ?? "unknown")
      return true
    } catch {
      MIRAPerformanceTimeline.mark("app_data_generation_check_failed", detail: "will_keep_existing_cache")
      return false
    }
  }

  func purgeContentCaches() async {
    let preservedDraft = await loadPostDraft()
    await MIRALocalJSONCache.removeAll()
    if let preservedDraft {
      await savePostDraft(preservedDraft)
    }
    await MIRAImageDiskCache.clear()
    MIRAAPIClient.productionSession.configuration.urlCache?.removeAllCachedResponses()
  }

  func loadFeed() async -> [MIRAPost]? {
    guard let posts = await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.feed, maxAge: contentCacheAge) else {
      return nil
    }
    return await MIRAPostEngagementSync.apply(to: posts)
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
      guard let freshPost = freshById[cached.id] else { return cached }
      return mergedPostPreservingViewerState(cached: cached, fresh: freshPost)
    }

    let newItems = fresh.filter { seen.insert($0.id).inserted }
    if preferFreshOrderWhenEmpty, existing.isEmpty {
      merged = fresh
    } else {
      merged.append(contentsOf: newItems)
    }
    return Array(merged.prefix(maxFeedPosts))
  }

  func mergeFreshFirstPage(existing: [MIRAPost], fresh: [MIRAPost], pageLimit: Int) async -> [MIRAPost] {
    guard !existing.isEmpty else {
      return await MIRAPostEngagementSync.apply(to: Array(fresh.prefix(maxFeedPosts)))
    }
    guard !fresh.isEmpty else {
      return await MIRAPostEngagementSync.apply(to: existing)
    }

    let freshIds = Set(fresh.map(\.id))
    let preservedTail = existing.enumerated().compactMap { index, post -> MIRAPost? in
      if freshIds.contains(post.id) { return nil }
      if index < pageLimit { return nil }
      return post
    }
    let mergedFresh = await mergeFreshPostsPreservingViewerState(existing: existing, fresh: fresh)
    return await MIRAPostEngagementSync.apply(to: Array((mergedFresh + preservedTail).prefix(maxFeedPosts)))
  }

  func mergeFreshPostsPreservingViewerState(existing: [MIRAPost], fresh: [MIRAPost], maxCount: Int? = nil) async -> [MIRAPost] {
    guard !existing.isEmpty, !fresh.isEmpty else {
      return await MIRAPostEngagementSync.apply(to: Array(fresh.prefix(maxCount ?? fresh.count)))
    }
    var existingById: [String: MIRAPost] = [:]
    for post in existing {
      existingById[post.id] = post
    }
    let merged = fresh.map { freshPost -> MIRAPost in
      guard let cached = existingById[freshPost.id] else { return freshPost }
      return mergedPostPreservingViewerState(cached: cached, fresh: freshPost)
    }
    return await MIRAPostEngagementSync.apply(to: Array(merged.prefix(maxCount ?? merged.count)))
  }

  func loadDiscoverPosts(category: String) async -> [MIRAPost]? {
    guard let posts = await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.discoverPosts(category), maxAge: contentCacheAge) else {
      return nil
    }
    return await MIRAPostEngagementSync.apply(to: posts)
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
    guard let best else { return nil }
    return await MIRAPostEngagementSync.apply(to: best)
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
    guard let posts = await MIRALocalJSONCache.load([MIRAPost].self, key: CacheKey.profilePosts(userId), maxAge: profileCacheAge) else {
      return nil
    }
    return await MIRAPostEngagementSync.apply(to: posts)
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
    // Never delete the prior media until the new snapshot can be read back.
    guard let verified = await loadPostDraft(), verified == draft,
          let directory = postDraftMediaDirectory() else { return }
    let retained = Set(draft.media.map(\.localFilePath))
    pruneStoredPostDraftMedia(in: directory, keeping: retained)
  }

  func clearPostDraftFromPreviousProcessIfNeeded() async {
    guard !didClearPostDraftFromPreviousProcess else { return }
    didClearPostDraftFromPreviousProcess = true
    // Keep the existing entry point, but do not silently discard a saved composer
    // attachment on relaunch. An explicit discard or completed post clears it.
  }

  func storePostDraftMedia(_ mediaItems: [MIRAPickedMedia]) async throws -> [MIRAPostDraftMediaSnapshot] {
    guard let directory = postDraftMediaDirectory() else { throw MIRAAPIError.emptyResponse }
    var written: [URL] = []
    var snapshots: [MIRAPostDraftMediaSnapshot] = []
    do {
      for item in mediaItems {
        let safeName = item.fileName
          .replacingOccurrences(of: "/", with: "-")
          .replacingOccurrences(of: "\\", with: "-")
          .replacingOccurrences(of: ":", with: "-")
        let fileURL = directory.appendingPathComponent("captro-post-draft-\(UUID().uuidString)-\(safeName)")
        try item.data.write(to: fileURL, options: [.atomic])
        written.append(fileURL)
        snapshots.append(MIRAPostDraftMediaSnapshot(
          id: UUID().uuidString,
          localFilePath: fileURL.path,
          kind: item.kind.rawValue,
          fileName: item.fileName,
          mimeType: item.mimeType,
          editorMetadata: item.editorMetadata
        ))
      }
      return snapshots
    } catch {
      for url in written { try? FileManager.default.removeItem(at: url) }
      throw error
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
    let draft = await loadPostDraft()
    await MIRALocalJSONCache.remove(key: CacheKey.postDraft)
    guard let directory = postDraftMediaDirectory() else { return }
    pruneStoredPostDraftMedia(in: directory, keeping: [])
    // Comment recordings use the same durable directory. Delete only the
    // recording attached to this post draft, never another composer’s audio.
    if let voice = draft?.voiceDraft?.restore() {
      try? FileManager.default.removeItem(at: voice.fileURL)
    }
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
    return mergedPostPreservingViewerState(cached: lhs, fresh: rhs)
  }

  private func mergedPostPreservingViewerState(cached: MIRAPost, fresh: MIRAPost) -> MIRAPost {
    fresh.updating(
      liked: mergedViewerFlag(cached: cached.viewerLikedValue, fresh: fresh.viewerLikedValue, cachedCount: cached.likesCount, freshCount: fresh.likesCount),
      likesCount: mergedEngagementCount(
        cached: cached.likesCount,
        fresh: fresh.likesCount,
        cachedFlag: cached.viewerLikedValue,
        freshFlag: fresh.viewerLikedValue
      ),
      commentsCount: fresh.commentsCount ?? cached.commentsCount,
      saved: mergedViewerFlag(cached: cached.viewerSavedValue, fresh: fresh.viewerSavedValue, cachedCount: cached.savesCount, freshCount: fresh.savesCount),
      savesCount: mergedEngagementCount(
        cached: cached.savesCount,
        fresh: fresh.savesCount,
        cachedFlag: cached.viewerSavedValue,
        freshFlag: fresh.viewerSavedValue
      )
    )
  }

  private func mergedViewerFlag(cached: Bool?, fresh: Bool?, cachedCount _: Int?, freshCount _: Int?) -> Bool? {
    if let fresh { return fresh }
    return cached
  }

  private func mergedEngagementCount(cached: Int?, fresh: Int?, cachedFlag _: Bool?, freshFlag _: Bool?) -> Int? {
    guard cached != nil || fresh != nil else { return nil }
    if let fresh { return max(0, fresh) }
    return max(0, cached ?? 0)
  }

  private func nowISO() -> String {
    ISO8601DateFormatter.miraCacheStore.string(from: Date())
  }
}

private enum CacheKey {
  static let feed = "native.main.feed.v7.cache_first"
  static let discoverStories = "native.discover.stories.v6.cache_first"
  static let currentProfile = "native.profile.me.v5.cache_first"
  static let notifications = "native.notifications.v4.cache_first"
  static let settings = "native.settings.v1.cache_first"
  static let postDraft = "native.post_draft.v1.cache_first"
  static let discoverCategoryIds = [
    "all",
    "photography",
    "outdoors",
    "art",
    "nightlife",
    "outfits",
    "events"
  ]

  static func discoverPosts(_ category: String) -> String {
    "native.discover.posts.v7.cache_first.\(category)"
  }

  static func profilePosts(_ userId: String) -> String {
    "native.profile.posts.v6.cache_first.\(userId)"
  }

  static func viewedProfile(_ userId: String) -> String {
    "native.profile.user.v5.cache_first.\(userId)"
  }

  static func comments(_ postId: String) -> String {
    "native.comments.v3.cache_first.\(postId)"
  }
}

private extension ISO8601DateFormatter {
  static let miraCacheStore: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

func postDraftMediaDirectory() -> URL? {
  guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
  var directory = support
    .appendingPathComponent("MIRAPostDraftMedia", isDirectory: true)
    .appendingPathComponent(MIRALocalJSONCache.currentScopeIdentifier, isDirectory: true)
  if !FileManager.default.fileExists(atPath: directory.path) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
  var values = URLResourceValues()
  values.isExcludedFromBackup = true
  try? directory.setResourceValues(values)
  return directory
}

private func pruneStoredPostDraftMedia(in directory: URL, keeping paths: Set<String>) {
  guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
  for file in files where file.lastPathComponent.hasPrefix("captro-post-draft-") && !paths.contains(file.path) {
    try? FileManager.default.removeItem(at: file)
  }
}
