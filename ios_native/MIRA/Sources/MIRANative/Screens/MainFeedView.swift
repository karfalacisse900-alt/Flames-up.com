import SwiftUI
import UIKit

private struct MainFeedMediaPreloadPlan: Sendable {
  var previewURLs: [String] = []
  var feedImageURLs: [String] = []
  var videoPrewarmURLs: [String] = []
  var videoKeepAliveURLs: [String] = []

  var isEmpty: Bool {
    previewURLs.isEmpty && feedImageURLs.isEmpty && videoPrewarmURLs.isEmpty
  }
}

@MainActor
final class MainFeedModel: ObservableObject {
  @Published var posts: [MIRAPost] = []
  @Published var isLoading = true
  @Published var isLoadingMore = false
  @Published var errorMessage: String?
  @Published var currentUserId: String?
  @Published var currentUsername: String?

  let api: MIRAAPIClient
  private let legacyFeedCacheKey = "native.main.feed.v7"
  private let publicFeedCacheKey = "native.main.public.feed.v1"
  private var isGuestFeedMode = false
  private var hasLoadedFreshFeed = false
  private var isLoadingFreshFeed = false
  private var canLoadMore = true
  private var isLoadingCurrentUser = false
  private var mediaPrefetchTask: Task<Void, Never>?
  private var followingAuthorIds = Set<String>()
  private var likeMutationVersions: [String: Int] = [:]
  private let firstPageLimit = 12
  private let paginationTriggerRatio = 0.70
  private let paginationTriggerWindow = 4

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func configureGuestMode(_ isGuest: Bool) {
    guard isGuestFeedMode != isGuest else { return }
    isGuestFeedMode = isGuest
    posts = []
    currentUserId = nil
    currentUsername = nil
    errorMessage = nil
    hasLoadedFreshFeed = false
    isLoadingFreshFeed = false
    canLoadMore = true
    isLoading = true
    mediaPrefetchTask?.cancel()
  }

  func prepareForStartup() async {
    MIRAPerformanceTimeline.mark("home_startup_prepare")
    if !isGuestFeedMode && currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
    }
    await hydrateCachedFeedIfNeeded()
    if posts.isEmpty {
      isLoading = true
    }
    Task { await load() }
  }

  func load(forceRefresh: Bool = false) async {
    if !isGuestFeedMode && currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
    }
    if isLoadingFreshFeed && !forceRefresh { return }
    if !forceRefresh && hasLoadedFreshFeed && !posts.isEmpty { return }
    isLoadingFreshFeed = true
    defer {
      isLoading = false
      isLoadingFreshFeed = false
    }
    MIRAPerformanceTimeline.mark("home_load_start", detail: forceRefresh ? "refresh" : "normal")

    await hydrateCachedFeedIfNeeded()

    if posts.isEmpty { isLoading = true }
    hasLoadedFreshFeed = true
    let loaded = await fetchFeedPage(skip: 0)
    guard !loaded.isEmpty else {
      canLoadMore = false
      if posts.isEmpty {
        hasLoadedFreshFeed = false
        errorMessage = "Could not load the feed. Pull back in a moment."
      }
      return
    }
    let sorted = await sortedByNativeScore(loaded)
    let merged: [MIRAPost]
    if isGuestFeedMode {
      merged = mergePublicFirstPage(existing: posts, fresh: sorted)
    } else {
      merged = await MIRAAppCacheStore.shared.mergeFreshFirstPage(
        existing: posts,
        fresh: sorted,
        pageLimit: firstPageLimit
      )
    }
    let mixed = interleavePostFormats(merged)
    if posts != mixed {
      posts = mixed
    }
    canLoadMore = loaded.count >= firstPageLimit
    await persistCurrentFeed()
    MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "network")
    errorMessage = nil
    prefetchInitialMediaWindow()
    prefetchNextPageIfNeeded(afterInitialCount: posts.count)
  }

  private func hydrateCachedFeedIfNeeded() async {
    guard posts.isEmpty else { return }
    let cached: [MIRAPost]?
    if isGuestFeedMode {
      cached = await MIRALocalJSONCache.load(
        [MIRAPost].self,
        key: publicFeedCacheKey,
        maxAge: 60 * 60 * 24
      )
    } else {
      var authenticatedCache = await MIRAAppCacheStore.shared.loadFeed()
      if authenticatedCache == nil {
        authenticatedCache = await MIRALocalJSONCache.load(
          [MIRAPost].self,
          key: legacyFeedCacheKey,
          maxAge: 60 * 60 * 24 * 30
        )
      }
      cached = authenticatedCache
    }
    guard let cached else { return }
    if isGuestFeedMode {
      posts = interleavePostFormats(cached)
    } else {
      posts = interleavePostFormats(await MIRAPostEngagementSync.apply(to: cached))
    }
    MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "cache")
    errorMessage = nil
    isLoading = false
    prefetchInitialMediaWindow()
  }

  func loadMoreIfNeeded(after post: MIRAPost) async {
    guard !isLoading else { return }
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let ratioTriggerIndex = max(0, Int((Double(max(posts.count - 1, 0)) * paginationTriggerRatio).rounded(.down)))
    let isNearEnd = posts.suffix(paginationTriggerWindow).contains(where: { $0.id == post.id })
    guard index >= ratioTriggerIndex || isNearEnd else { return }
    await loadNextPage(reason: "pager")
  }

  func prefetchMedia(around post: MIRAPost) {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let plan = makeMediaPreloadPlan(focusIndex: index)
    guard !plan.isEmpty else { return }

    if !plan.videoPrewarmURLs.isEmpty {
      MIRAVideoPrewarmManager.shared.prewarm(
        urls: plan.videoPrewarmURLs,
        keepOnly: Set(plan.videoKeepAliveURLs)
      )
    }

    mediaPrefetchTask?.cancel()
    mediaPrefetchTask = Task.detached(priority: .utility) {
      if !plan.previewURLs.isEmpty {
        MIRAApplePerformanceLogger.event("media_prefetch_started", detail: "feed_previews=\(plan.previewURLs.count)")
        await MIRAImagePrefetcher.prefetch(urls: plan.previewURLs, maxPixelSize: 560, limit: 28)
        MIRAApplePerformanceLogger.event("media_prefetch_completed", detail: "feed_previews")
      }
      guard !Task.isCancelled else {
        MIRAApplePerformanceLogger.event("media_prefetch_canceled", detail: "feed_full")
        return
      }
      if !plan.feedImageURLs.isEmpty {
        MIRAApplePerformanceLogger.event("media_prefetch_started", detail: "feed_full=\(plan.feedImageURLs.count)")
        await MIRAImagePrefetcher.prefetch(urls: plan.feedImageURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: 22)
        MIRAApplePerformanceLogger.event("media_prefetch_completed", detail: "feed_full")
      }
    }
  }

  private func prefetchInitialMediaWindow() {
    guard let firstPost = posts.first else { return }
    prefetchMedia(around: firstPost)
  }

  private func makeMediaPreloadPlan(focusIndex: Int) -> MainFeedMediaPreloadPlan {
    guard posts.indices.contains(focusIndex) else { return MainFeedMediaPreloadPlan() }

    let orderedIndices = mediaPreloadIndices(from: focusIndex)
    var previewURLs: [String] = []
    var feedImageURLs: [String] = []
    var videoPrewarmURLs: [String] = []
    var videoKeepAliveURLs: [String] = []

    for (rank, index) in orderedIndices.enumerated() {
      let post = posts[index]
      previewURLs.append(contentsOf: post.posterMediaURLs)
      previewURLs.append(contentsOf: post.thumbnailMediaURLs)

      let mediaURLs = post.feedMediaURLs
      let imageURLs = orderedMediaURLs(mediaURLs + post.fallbackMediaURLs).filter { !$0.isVideoURL }
      let videoURLs = mediaURLs.filter { $0.isVideoURL }

      if rank <= 3 {
        // Home renders one cover per post; detail screens own the full media carousel.
        feedImageURLs.append(contentsOf: imageURLs.prefix(1))
        videoPrewarmURLs.append(contentsOf: videoURLs.prefix(1))
      } else if rank <= 6 {
        feedImageURLs.append(contentsOf: imageURLs.prefix(1))
      }

      if rank <= 3 {
        videoKeepAliveURLs.append(contentsOf: videoURLs.prefix(2))
      }
    }

    return MainFeedMediaPreloadPlan(
      previewURLs: orderedMediaURLs(previewURLs),
      feedImageURLs: orderedMediaURLs(feedImageURLs),
      videoPrewarmURLs: orderedMediaURLs(videoPrewarmURLs),
      videoKeepAliveURLs: orderedMediaURLs(videoKeepAliveURLs)
    )
  }

  private func mediaPreloadIndices(from focusIndex: Int) -> [Int] {
    [focusIndex, focusIndex + 1, focusIndex + 2, focusIndex - 1]
      .filter { posts.indices.contains($0) }
  }

  private func orderedMediaURLs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }

  private func loadNextPage(reason: String) async {
    guard canLoadMore, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let skip = posts.count
    MIRAPerformanceTimeline.mark("home_load_more_start", detail: "\(reason) skip=\(skip)")
    let loaded = await fetchFeedPage(skip: skip)
    guard !loaded.isEmpty else {
      canLoadMore = false
      MIRAPerformanceTimeline.mark("home_load_more_empty", detail: "skip=\(skip)")
      return
    }
    let existing = Set(posts.map(\.id))
    var unique = loaded.filter { !existing.contains($0.id) }

    if unique.isEmpty {
      canLoadMore = loaded.count >= firstPageLimit
      MIRAPerformanceTimeline.mark("home_load_more_duplicate_page", detail: "skip=\(skip)")
      return
    }

    posts.append(contentsOf: interleavePostFormats(await sortedByNativeScore(unique)))
    canLoadMore = loaded.count >= firstPageLimit || unique.count >= firstPageLimit
    MIRAPerformanceTimeline.mark("home_load_more_done", detail: "added=\(unique.count) total=\(posts.count)")
    cacheCurrentPosts()
  }

  private func prefetchNextPageIfNeeded(afterInitialCount initialCount: Int) {
    guard canLoadMore, initialCount <= firstPageLimit else { return }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      await self?.prefetchNextPageIfStillCurrent(initialCount)
    }
  }

  private func prefetchNextPageIfStillCurrent(_ initialCount: Int) async {
    guard posts.count == initialCount, !isLoading else { return }
    await loadNextPage(reason: "prefetch")
  }

  func toggleLike(_ post: MIRAPost) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let mutationVersion = beginLikeMutation(for: post.id)
    let previous = posts[index]
    let nextLiked = !previous.viewerLiked
    let nextCount = max(0, (previous.likesCount ?? 0) + (nextLiked ? 1 : -1))
    posts[index] = previous.updating(liked: nextLiked, likesCount: nextCount)
    publishEngagement(for: posts[index])
    cacheCurrentPosts()

    do {
      let response: PostLikeResponse = try await api.post("/posts/\(post.id)/like", body: LikeBody(liked: nextLiked))
      guard isCurrentLikeMutation(mutationVersion, for: post.id) else { return }
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        let reconciledLikesCount = stableEngagementCount(
          current: previous.likesCount,
          incoming: response.likesCount,
          optimistic: nextCount,
          toggledOn: response.liked ?? nextLiked
        )
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked ?? nextLiked,
          likesCount: reconciledLikesCount,
          commentsCount: response.commentsCount,
          saved: response.saved,
          savesCount: response.savesCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      guard isCurrentLikeMutation(mutationVersion, for: post.id) else { return }
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
        publishEngagement(for: previous)
        cacheCurrentPosts()
      }
    }

    finishLikeMutation(mutationVersion, for: post.id)
  }

  func save(_ post: MIRAPost, to collection: String) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    let nextCount = max(0, (previous.savesCount ?? 0) + (previous.viewerSaved ? 0 : 1))
    posts[index] = previous.updating(saved: true, savesCount: nextCount)
    publishEngagement(for: posts[index])
    cacheCurrentPosts()

    do {
      let response: PostSaveResponse = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: collection))
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        let reconciledSavesCount = stableEngagementCount(
          current: previous.savesCount,
          incoming: response.savesCount,
          optimistic: nextCount,
          toggledOn: response.saved ?? true
        )
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked,
          likesCount: response.likesCount,
          commentsCount: response.commentsCount,
          saved: response.saved ?? true,
          savesCount: reconciledSavesCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
        publishEngagement(for: previous)
        cacheCurrentPosts()
      }
    }
  }

  func unsave(_ post: MIRAPost) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    guard previous.viewerSaved else { return }
    let nextCount = max(0, (previous.savesCount ?? 0) - 1)
    posts[index] = previous.updating(saved: false, savesCount: nextCount)
    publishEngagement(for: posts[index])
    cacheCurrentPosts()

    do {
      let response: PostSaveResponse = try await api.delete("/library/save/\(post.id)")
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        let reconciledSavesCount = stableEngagementCount(
          current: previous.savesCount,
          incoming: response.savesCount,
          optimistic: nextCount,
          toggledOn: response.saved ?? false
        )
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked,
          likesCount: response.likesCount,
          commentsCount: response.commentsCount,
          saved: response.saved ?? false,
          savesCount: reconciledSavesCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
        publishEngagement(for: previous)
        cacheCurrentPosts()
      }
    }
  }

  func togglePin(_ post: MIRAPost) async {
    guard canDelete(post), let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    let shouldPin = !previous.isPinned
    posts[index] = previous.updatingPinned(at: shouldPin ? ISO8601DateFormatter().string(from: Date()) : nil)
    do {
      let updated: MIRAPost = try await api.put("/posts/\(post.id)/pin", body: PostPinBody(pinned: shouldPin))
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = updated
      }
      cacheCurrentPosts()
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
      }
      errorMessage = "Could not update pinned post."
    }
  }

  func applyEngagementUpdate(_ update: MIRAPostEngagementUpdate) {
    guard let index = posts.firstIndex(where: { $0.id == update.postId }) else { return }
    posts[index] = posts[index].updating(
      liked: update.liked,
      likesCount: stableEngagementCount(current: posts[index].likesCount, incoming: update.likesCount, toggledOn: update.liked),
      commentsCount: update.commentsCount,
      saved: update.saved,
      savesCount: update.savesCount
    )
    cacheCurrentPosts()
  }

  func followAuthor(_ post: MIRAPost) async -> Bool {
    guard canFollowAuthor(post) else { return false }
    guard let userId = post.userId, !userId.isEmpty else { return false }
    guard !followingAuthorIds.contains(userId) else { return false }
    followingAuthorIds.insert(userId)
    defer { followingAuthorIds.remove(userId) }

    let previous = posts
    posts = posts.map { $0.userId == userId ? $0.updating(following: true) : $0 }

    do {
      let response: FollowResponse = try await api.post("/users/\(userId)/follow", body: FollowBody(following: true))
      let serverFollowing = response.following ?? true
      posts = posts.map { $0.userId == userId ? $0.updating(following: serverFollowing) : $0 }
      cacheCurrentPosts()
      MIRAUserFollowSync.publish(MIRAUserFollowUpdate(userId: userId, following: serverFollowing, followersCount: response.followersCount ?? response.followingCount))
      return serverFollowing
    } catch {
      posts = previous
      errorMessage = "Could not follow this user. Try again in a moment."
      return false
    }
  }

  func canFollowAuthor(_ post: MIRAPost) -> Bool {
    if isGuestFeedMode { return false }
    if post.viewerFollowing { return false }

    if currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
      return false
    }

    let postUserId = post.userId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let ownerUsername = post.userUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard postUserId?.isEmpty == false || ownerUsername?.isEmpty == false else { return false }

    if let currentUserId, let postUserId, !postUserId.isEmpty {
      return currentUserId != postUserId
    }

    let viewerUsername = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let ownerUsername, !ownerUsername.isEmpty, let viewerUsername, !viewerUsername.isEmpty {
      return ownerUsername != viewerUsername
    }

    return false
  }

  func applyFollowUpdate(_ update: MIRAUserFollowUpdate) {
    let updated = posts.map { post in
      post.userId == update.userId ? post.updating(following: update.following) : post
    }
    guard updated != posts else { return }
    posts = updated
    cacheCurrentPosts()
  }

  func hidePost(_ post: MIRAPost) {
    posts.removeAll { $0.id == post.id }
    cacheCurrentPosts()
    MIRAPostRemovalSync.publish(MIRAPostRemovalUpdate(postId: post.id))
  }

  func hidePosts(byUserId userId: String) {
    posts.removeAll { $0.userId == userId }
    cacheCurrentPosts()
  }

  func blockAuthor(_ post: MIRAPost) async {
    guard let userId = post.userId, !userId.isEmpty else { return }
    let previous = posts
    posts.removeAll { $0.userId == userId }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      cacheCurrentPosts()
      errorMessage = nil
    } catch {
      posts = previous
      errorMessage = "Could not block this user. Try again in a moment."
    }
  }

  func reportPost(_ post: MIRAPost) async {
    do {
      let _: EmptyResponse? = try await api.post(
        "/reports",
        body: PostReportBody(
          reportedType: "post",
          reportedId: post.id,
          reason: "other",
          details: "Reported from the Main feed post menu."
        )
      )
    } catch {
      errorMessage = "Could not send report. Try again in a moment."
    }
  }

  func deletePost(_ post: MIRAPost) async {
    let previous = posts
    posts.removeAll { $0.id == post.id }
    do {
      let _: EmptyResponse = try await api.delete("/posts/\(post.id)")
      cacheCurrentPosts()
      MIRAPostRemovalSync.publish(MIRAPostRemovalUpdate(postId: post.id))
      errorMessage = nil
    } catch {
      posts = previous
      errorMessage = "Could not delete this post."
    }
  }

  func updatePostVisibility(_ post: MIRAPost, visibility: String) async {
    guard posts.contains(where: { $0.id == post.id }) else { return }
    do {
      let updated: MIRAPost = try await api.put(
        "/posts/\(post.id)/visibility",
        body: MainPostVisibilityUpdateBody(visibility: visibility)
      )
      if let index = posts.firstIndex(where: { $0.id == post.id }) {
        posts[index] = updated
      }
      cacheCurrentPosts()
      if visibility == "private" {
        MIRAPostRemovalSync.publish(MIRAPostRemovalUpdate(postId: post.id))
      }
      errorMessage = nil
    } catch {
      errorMessage = "Could not update post visibility."
    }
  }

  private func loadCurrentUserIfNeeded() async {
    guard !isGuestFeedMode else { return }
    guard currentUserId == nil && currentUsername == nil else { return }
    guard !isLoadingCurrentUser else { return }
    isLoadingCurrentUser = true
    defer { isLoadingCurrentUser = false }
    let me: MIRAUser? = try? await api.get("/auth/me")
    currentUserId = me?.id
    currentUsername = me?.username
  }

  func canDelete(_ post: MIRAPost) -> Bool {
    if isGuestFeedMode { return false }
    if currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
      return false
    }
    if let currentUserId, let postUserId = post.userId, currentUserId == postUserId {
      return true
    }
    let ownerUsername = post.userUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let viewerUsername = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ownerUsername?.isEmpty == false && ownerUsername == viewerUsername
  }

  private func cacheCurrentPosts() {
    let snapshot = posts
    let isGuest = isGuestFeedMode
    let publicCacheKey = publicFeedCacheKey
    Task {
      if isGuest {
        await MIRALocalJSONCache.save(Array(snapshot.prefix(120)), key: publicCacheKey)
      } else {
        await MIRAAppCacheStore.shared.saveFeed(snapshot)
      }
    }
  }

  private func persistCurrentFeed() async {
    if isGuestFeedMode {
      await MIRALocalJSONCache.save(Array(posts.prefix(120)), key: publicFeedCacheKey)
    } else {
      await MIRAAppCacheStore.shared.saveFeed(posts)
    }
  }

  private func mergePublicFirstPage(existing: [MIRAPost], fresh: [MIRAPost]) -> [MIRAPost] {
    let freshIDs = Set(fresh.map(\.id))
    return Array((fresh + existing.filter { !freshIDs.contains($0.id) }).prefix(120))
  }

  func removePostLocally(id postId: String) {
    guard posts.contains(where: { $0.id == postId }) else { return }
    posts.removeAll { $0.id == postId }
    cacheCurrentPosts()
  }

  private func publishEngagement(for post: MIRAPost) {
    MIRAPostEngagementSync.publish(
      MIRAPostEngagementUpdate(
        postId: post.id,
        liked: post.viewerLiked,
        likesCount: post.likesCount,
        saved: post.viewerSaved,
        savesCount: post.savesCount,
        commentsCount: post.commentsCount
      )
    )
  }

  private func fetchFeedPage(skip: Int) async -> [MIRAPost] {
    if isGuestFeedMode {
      do {
        let publicPosts: [MIRAPost] = try await api.get("/posts/world-board?limit=\(firstPageLimit)&skip=\(skip)")
        MIRAPerformanceTimeline.mark("home_feed_public", detail: "guest skip=\(skip)")
        return publicPosts
      } catch {
        MIRAPerformanceTimeline.mark("home_feed_page_failed", detail: "guest_public skip=\(skip)")
        return []
      }
    }

    do {
      let loaded: [MIRAPost] = try await api.get("/posts/feed?limit=\(firstPageLimit)&skip=\(skip)")
      if !loaded.isEmpty { return loaded }
      MIRAPerformanceTimeline.mark("home_feed_page_empty", detail: "authenticated skip=\(skip)")
    } catch {
      MIRAPerformanceTimeline.mark("home_feed_page_failed", detail: "authenticated skip=\(skip)")
    }

    do {
      let publicPosts: [MIRAPost] = try await api.get("/posts/world-board?limit=\(firstPageLimit)&skip=\(skip)")
      if !publicPosts.isEmpty {
        MIRAPerformanceTimeline.mark("home_feed_public_fallback", detail: "skip=\(skip)")
        return publicPosts
      }
    } catch {
      MIRAPerformanceTimeline.mark("home_feed_page_failed", detail: "public skip=\(skip)")
    }
    return []
  }

  private func stableEngagementCount(current: Int?, incoming: Int?, optimistic: Int? = nil, toggledOn: Bool? = nil) -> Int? {
    let fallback = optimistic ?? current
    guard let incoming else { return fallback }
    return max(0, incoming)
  }

  private func beginLikeMutation(for postId: String) -> Int {
    let next = (likeMutationVersions[postId] ?? 0) + 1
    likeMutationVersions[postId] = next
    return next
  }

  private func isCurrentLikeMutation(_ version: Int, for postId: String) -> Bool {
    likeMutationVersions[postId] == version
  }

  private func finishLikeMutation(_ version: Int, for postId: String) {
    if likeMutationVersions[postId] == version {
      likeMutationVersions[postId] = nil
    }
  }

  private func sortedByNativeScore(_ posts: [MIRAPost]) async -> [MIRAPost] {
    await Task.detached(priority: .userInitiated) {
      let formatter = ISO8601DateFormatter()
      return posts
        .map { post in
          (
            post,
            MIRANativeEngine.scoreFeedItem(
              likes: Double(post.likesCount ?? 0),
              comments: Double(post.commentsCount ?? 0),
              saves: Double(post.savesCount ?? 0),
              shares: Double(post.sharesCount ?? 0),
              views: Double(post.viewsCount ?? 0),
              ageHours: Self.ageHours(from: post.createdAt, formatter: formatter),
              isFollowed: post.isFollowing == true,
              isVideo: post.feedMediaURLs.first?.isVideoURL == true
            )
          )
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }.value
  }

  private func interleavePostFormats(_ rankedPosts: [MIRAPost]) -> [MIRAPost] {
    let mediaPosts = rankedPosts.filter { !$0.feedMediaURLs.isEmpty }
    let textPosts = rankedPosts.filter { $0.feedMediaURLs.isEmpty }
    guard !mediaPosts.isEmpty, !textPosts.isEmpty else { return rankedPosts }

    var mediaIndex = 0
    var textIndex = 0
    var wantsMedia = !rankedPosts[0].feedMediaURLs.isEmpty
    var mixed: [MIRAPost] = []
    mixed.reserveCapacity(rankedPosts.count)

    while mediaIndex < mediaPosts.count || textIndex < textPosts.count {
      if wantsMedia, mediaIndex < mediaPosts.count {
        mixed.append(mediaPosts[mediaIndex])
        mediaIndex += 1
      } else if !wantsMedia, textIndex < textPosts.count {
        mixed.append(textPosts[textIndex])
        textIndex += 1
      } else if mediaIndex < mediaPosts.count {
        mixed.append(mediaPosts[mediaIndex])
        mediaIndex += 1
      } else {
        mixed.append(textPosts[textIndex])
        textIndex += 1
      }
      wantsMedia.toggle()
    }

    return mixed
  }

  nonisolated private static func ageHours(from value: String?, formatter: ISO8601DateFormatter) -> Double {
    guard let value, let date = formatter.date(from: value) else { return 24 }
    return max(0, Date().timeIntervalSince(date) / 3600)
  }
}

private struct MainPostVisibilityUpdateBody: Encodable {
  let visibility: String
}
private enum MainFeedPagerDirection {
  case previous
  case next

  var offsetSign: CGFloat {
    switch self {
    case .previous: return 1
    case .next: return -1
    }
  }

  var indexDelta: Int {
    switch self {
    case .previous: return -1
    case .next: return 1
    }
  }
}

private enum MainFeedSection: String {
  case forYou
  case friends
}

private enum MainFeedPagerDragTarget {
  case post(MainFeedPagerDirection)
  case edge(MainFeedPagerDirection)
  case ignored
}

public struct MainFeedView: View {
  @StateObject private var model: MainFeedModel
  private let isTabActive: Bool
  private let isGuest: Bool
  @EnvironmentObject private var localization: MIRALocalization
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var activeVideoPostID: String?
  @State private var selectedPostID: String?
  @State private var selectedPostFallbackIndex = 0
  @State private var selectedFeedSection: MainFeedSection = .forYou
  @AppStorage("captro.home.selectedCity") private var selectedCity = "NYC"
  @State private var postDragOffset: CGFloat = 0
  @State private var pagerDragTarget: MainFeedPagerDragTarget?
  @State private var isPagerTransitioning = false
  @State private var isShowingCreatePost = false
  @State private var detailPost: MIRAPost?
  @State private var postOptionsTarget: MIRAPost?
  @State private var isPostOptionsPresented = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportSourcePost: MIRAPost?
  @State private var isReportSheetPresented = false

  private let homeCities = ["NYC", "LA", "CHI", "MIA", "SF"]

  public init(api: MIRAAPIClient, isGuest: Bool = false) {
    _model = StateObject(wrappedValue: MainFeedModel(api: api))
    self.isTabActive = true
    self.isGuest = isGuest
  }

  init(api: MIRAAPIClient, model: MainFeedModel, isTabActive: Bool = true, isGuest: Bool = false) {
    _model = StateObject(wrappedValue: model)
    self.isTabActive = isTabActive
    self.isGuest = isGuest
  }

  public var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        VStack(spacing: 0) {
          homeTopBar

          GeometryReader { feedProxy in
            feedContent(size: feedProxy.size)
          }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
      }
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(feedTabBarVisibility, for: .tabBar)
      .navigationDestination(item: $detailPost) { post in
        DiscoverPostDetailNativeView(post: post, api: model.api)
          .miraHideTabBarOnAppear()
      }
      .miraActionModal(
        isPresented: $isPostOptionsPresented,
        onDismissed: { postOptionsTarget = nil }
      ) { dismiss in
        if let post = postOptionsTarget {
          MainFeedPostOptionsSheet(
            post: post,
            shareURL: mainFeedShareURL(for: post),
            onReport: { reportPostFromOptions(post, dismiss: dismiss) },
            onNotInterested: {
              CaptroHaptics.light()
              model.hidePost(post)
              dismiss()
            }
          )
        } else {
          Color.clear
        }
      }
      .miraBottomSheet(
        isPresented: $isReportSheetPresented,
        preferredHeightFraction: 0.72,
        maxHeight: 640,
        onDismissed: {
          reportTarget = nil
          reportSourcePost = nil
        }
      ) { dismiss in
        if let target = reportTarget {
          MIRAReportSheet(
            target: target,
            api: model.api,
            onSubmitted: { result in handleReportResult(result) },
            onClose: dismiss
          )
        } else {
          Color.clear
        }
      }
      .fullScreenCover(isPresented: $isShowingCreatePost) {
        CreatePostNativeView(api: model.api, onClose: { isShowingCreatePost = false })
      }
      .task(id: isGuest) {
        model.configureGuestMode(isGuest)
        await model.load()
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
        guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
        model.applyEngagementUpdate(update)
      }
      .onReceive(NotificationCenter.default.publisher(for: .captroPostDetailsUpdated)) { notification in
        guard let post = notification.object as? MIRAPost,
              let index = model.posts.firstIndex(where: { $0.id == post.id }) else { return }
        model.posts[index].detail = post.detail
        Task { await MIRAAppCacheStore.shared.saveFeed(model.posts) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostWasRemoved)) { notification in
        guard let update = MIRAPostRemovalSync.update(from: notification) else { return }
        model.removePostLocally(id: update.postId)
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraUserFollowDidChange)) { notification in
        guard let update = MIRAUserFollowSync.update(from: notification) else { return }
        model.applyFollowUpdate(update)
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active, !model.posts.isEmpty else { return }
        Task { await model.load(forceRefresh: true) }
      }
      .onChange(of: isMediaPlaybackSuppressed) { _, suppressed in
        if suppressed {
          MIRAPlaybackCoordinator.pauseAll(reason: "home_feed_overlay")
        } else {
          activateCurrentPost(reason: "home_feed_overlay_closed")
          MIRAPlaybackCoordinator.resumeVisible(reason: "home_feed_overlay_closed")
        }
      }
      .onChange(of: displayedPosts.map(\.id)) { _, _ in
        reconcileCurrentPostSelection()
      }
      .onChange(of: selectedFeedSection) { _, _ in
        selectedPostID = nil
        selectedPostFallbackIndex = 0
        resetPagerOffsets()
        reconcileCurrentPostSelection()
      }
      .onChange(of: selectedPostID) { _, _ in
        activateCurrentPost(reason: "home_post_changed")
      }
      .onAppear {
        reconcileCurrentPostSelection()
        MIRAApplePerformanceLogger.event("feed_render", detail: model.posts.isEmpty ? "empty" : "posts")
        if !isMediaPlaybackSuppressed {
          activateCurrentPost(reason: "home_feed_appeared")
          MIRAPlaybackCoordinator.resumeVisible(reason: "home_feed_appeared")
        }
      }
      .onDisappear {
        pauseVisibleMedia(reason: "home_feed_disappeared")
      }
    }
  }

  private var homeTopBar: some View {
    HStack(spacing: 0) {
      Menu {
        ForEach(homeCities, id: \.self) { city in
          Button {
            selectedCity = city
          } label: {
            if selectedCity == city {
              Label(city, systemImage: "checkmark")
            } else {
              Text(city)
            }
          }
        }
      } label: {
        HStack(spacing: 4) {
          Text(selectedCity)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)

          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .menuIndicator(.hidden)
      .frame(width: 92, alignment: .leading)
      .accessibilityLabel("Selected city, \(selectedCity)")

      HStack(spacing: 24) {
        homeSectionButton(title: "for you", section: .forYou)
        homeSectionButton(title: "friends", section: .friends)
      }
      .frame(maxWidth: .infinity)

      HStack(spacing: 4) {
        if let currentPost {
          ShareLink(item: mainFeedShareURL(for: currentPost)) {
            Image(systemName: "paperplane")
              .font(.system(size: 21, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(width: 40, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Share post")
        } else {
          Image(systemName: "paperplane")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .frame(width: 40, height: 44)
            .accessibilityHidden(true)
        }

        Button {
          CaptroHaptics.light()
          isShowingCreatePost = true
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create post")
      }
      .frame(width: 92, alignment: .trailing)
    }
    .padding(.horizontal, 14)
    .frame(height: 64)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 0.5)
    }
    .zIndex(10)
  }

  private func homeSectionButton(title: String, section: MainFeedSection) -> some View {
    Button {
      guard selectedFeedSection != section else { return }
      CaptroHaptics.light()
      withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
        selectedFeedSection = section
      }
    } label: {
      VStack(spacing: 8) {
        Text(title)
          .font(.system(size: 17, weight: selectedFeedSection == section ? .bold : .semibold))
          .foregroundStyle(
            selectedFeedSection == section
              ? MIRATheme.Color.textPrimary
              : MIRATheme.Color.textMuted
          )
          .lineLimit(1)

        Capsule()
          .fill(selectedFeedSection == section ? MIRATheme.Color.textPrimary : Color.clear)
          .frame(width: 42, height: 3)
      }
      .frame(minHeight: 44, alignment: .bottom)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selectedFeedSection == section ? .isSelected : [])
  }

  @ViewBuilder
  private func feedContent(size: CGSize) -> some View {
    if model.isLoading && model.posts.isEmpty {
      MainPostSkeleton()
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    } else if displayedPosts.isEmpty {
      MIRAEmptyState(
        title: selectedFeedSection == .friends ? "No friends posts yet" : localization.string("feed.empty.title"),
        message: selectedFeedSection == .friends
          ? "Posts from people you follow will appear here."
          : localization.string("feed.empty.message"),
        systemImage: selectedFeedSection == .friends ? "person.2" : "sparkles"
      )
      .frame(width: size.width, height: size.height)
    } else {
      horizontalPostPager(size: size)
    }
  }

  private func horizontalPostPager(size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(visiblePostIndices, id: \.self) { index in
        let post = displayedPosts[index]
        let isCurrent = index == currentPostIndex

        feedPage(post: post, size: size, isCurrent: isCurrent)
          .frame(width: size.width, height: size.height, alignment: .topLeading)
          .offset(
            x: CGFloat(index - currentPostIndex) * size.width + postDragOffset,
            y: 0
          )
          .zIndex(isCurrent ? 1 : 0)
          .allowsHitTesting(isCurrent && !isPagerTransitioning)
          .accessibilityHidden(!isCurrent)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .background(MIRATheme.Color.appBackground)
    .clipped()
    .contentShape(Rectangle())
    .simultaneousGesture(horizontalPagerGesture(pageWidth: size.width))
  }

  private func feedPage(post: MIRAPost, size: CGSize, isCurrent: Bool) -> some View {
    CaptroFeedPostView(
      post: post,
      api: model.api,
      isVideoActive: isCurrent && post.id == activeVideoPostID && !isMediaPlaybackSuppressed,
      showsFeedControls: false,
      onFollow: { await model.followAuthor(post) },
      onOpenOptions: { presentPostOptions(for: post) },
      onCreate: {
        CaptroHaptics.light()
        isShowingCreatePost = true
      },
      onOpenPost: {
        CaptroHaptics.light()
        detailPost = post
      },
      onSave: {
        Task {
          if post.viewerSaved { await model.unsave(post) }
          else { await model.save(post, to: "saved") }
        }
      },
      canFollowAuthor: !isGuest && model.canFollowAuthor(post),
      pageSize: size,
      selectedMediaIndex: .constant(0),
      showsCoverMediaOnly: true
    )
  }

  private var displayedPosts: [MIRAPost] {
    switch selectedFeedSection {
    case .forYou:
      return model.posts
    case .friends:
      return model.posts.filter(\.viewerFollowing)
    }
  }

  private var currentPostIndex: Int {
    if let selectedPostID,
       let index = displayedPosts.firstIndex(where: { $0.id == selectedPostID }) {
      return index
    }
    return min(max(selectedPostFallbackIndex, 0), max(displayedPosts.count - 1, 0))
  }

  private var currentPost: MIRAPost? {
    guard displayedPosts.indices.contains(currentPostIndex) else { return nil }
    return displayedPosts[currentPostIndex]
  }

  private var visiblePostIndices: [Int] {
    guard !displayedPosts.isEmpty else { return [] }
    return [currentPostIndex - 1, currentPostIndex, currentPostIndex + 1]
      .filter { displayedPosts.indices.contains($0) }
  }

  private func horizontalPagerGesture(pageWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 10, coordinateSpace: .local)
      .onChanged { value in
        handlePagerDragChanged(value, pageWidth: pageWidth)
      }
      .onEnded { value in
        handlePagerDragEnded(value, pageWidth: pageWidth)
      }
  }

  private func handlePagerDragChanged(_ value: DragGesture.Value, pageWidth: CGFloat) {
    guard !isPagerTransitioning else { return }
    let horizontal = value.translation.width
    let vertical = value.translation.height

    if pagerDragTarget == nil {
      guard max(abs(horizontal), abs(vertical)) >= 10 else { return }
      guard abs(horizontal) > abs(vertical) else {
        pagerDragTarget = .ignored
        return
      }
      let direction: MainFeedPagerDirection = horizontal < 0 ? .next : .previous
      pagerDragTarget = dragTarget(for: direction)
      if case .edge(.next)? = pagerDragTarget, let currentPost {
        Task { await model.loadMoreIfNeeded(after: currentPost) }
      }
    }

    guard let pagerDragTarget else { return }
    switch pagerDragTarget {
    case let .post(direction):
      postDragOffset = boundedTranslation(horizontal, direction: direction, pageWidth: pageWidth)
    case let .edge(direction):
      let directional = boundedTranslation(horizontal, direction: direction, pageWidth: pageWidth)
      postDragOffset = min(max(directional * 0.18, -38), 38)
    case .ignored:
      postDragOffset = 0
    }
  }

  private func handlePagerDragEnded(_ value: DragGesture.Value, pageWidth: CGFloat) {
    guard !isPagerTransitioning else { return }
    guard let target = pagerDragTarget else {
      resetPagerOffsets()
      return
    }

    switch target {
    case let .post(direction):
      if shouldCommitSwipe(value, direction: direction, pageWidth: pageWidth) {
        commitPostSwipe(direction: direction, pageWidth: pageWidth)
      } else {
        resetPagerOffsets()
      }
    case .edge(_), .ignored:
      resetPagerOffsets()
    }
  }

  private func dragTarget(for direction: MainFeedPagerDirection) -> MainFeedPagerDragTarget {
    guard currentPost != nil else { return .ignored }
    let nextPostIndex = currentPostIndex + direction.indexDelta
    return displayedPosts.indices.contains(nextPostIndex) ? .post(direction) : .edge(direction)
  }

  private func boundedTranslation(
    _ horizontal: CGFloat,
    direction: MainFeedPagerDirection,
    pageWidth: CGFloat
  ) -> CGFloat {
    let directional: CGFloat
    switch direction {
    case .previous:
      directional = max(0, horizontal)
    case .next:
      directional = min(0, horizontal)
    }
    return min(max(directional, -pageWidth), pageWidth)
  }

  private func shouldCommitSwipe(
    _ value: DragGesture.Value,
    direction: MainFeedPagerDirection,
    pageWidth: CGFloat
  ) -> Bool {
    let distance = direction.offsetSign * value.translation.width
    let predictedDistance = direction.offsetSign * value.predictedEndTranslation.width
    let threshold = min(max(pageWidth * 0.16, 44), 72)
    return distance >= threshold || predictedDistance >= pageWidth * 0.34
  }

  private func commitPostSwipe(direction: MainFeedPagerDirection, pageWidth: CGFloat) {
    let destination = currentPostIndex + direction.indexDelta
    guard displayedPosts.indices.contains(destination) else {
      resetPagerOffsets()
      return
    }
    let destinationPostID = displayedPosts[destination].id

    isPagerTransitioning = true
    withAnimation(pagerSnapAnimation, completionCriteria: .logicallyComplete) {
      postDragOffset = direction.offsetSign * pageWidth
    } completion: {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        selectedPostFallbackIndex = destination
        selectedPostID = destinationPostID
        postDragOffset = 0
        pagerDragTarget = nil
        isPagerTransitioning = false
      }
    }
  }

  private func resetPagerOffsets() {
    withAnimation(pagerReturnAnimation) {
      postDragOffset = 0
    }
    pagerDragTarget = nil
  }

  private var pagerSnapAnimation: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.24)
  }

  private var pagerReturnAnimation: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.18)
  }

  private func reconcileCurrentPostSelection() {
    guard !displayedPosts.isEmpty else {
      selectedPostID = nil
      selectedPostFallbackIndex = 0
      activeVideoPostID = nil
      return
    }

    if let selectedPostID,
       let index = displayedPosts.firstIndex(where: { $0.id == selectedPostID }) {
      selectedPostFallbackIndex = index
    } else {
      let index = min(max(selectedPostFallbackIndex, 0), displayedPosts.count - 1)
      selectedPostID = displayedPosts[index].id
      selectedPostFallbackIndex = index
    }
  }

  private func activateCurrentPost(reason _: String) {
    guard let post = currentPost else {
      activeVideoPostID = nil
      return
    }

    let shouldPlayVideo = !isMediaPlaybackSuppressed && post.feedMediaURLs.first?.isVideoURL == true
    if activeVideoPostID != (shouldPlayVideo ? post.id : nil) {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        activeVideoPostID = shouldPlayVideo ? post.id : nil
      }
      MIRAMemoryMetrics.log("main_feed_video_switch")
    }

    MIRAApplePerformanceLogger.event(
      "post_cell_appear",
      detail: post.feedMediaURLs.first?.isVideoURL == true ? "video" : "image"
    )
    model.prefetchMedia(around: post)
    Task { await model.loadMoreIfNeeded(after: post) }
  }

  private func pauseVisibleMedia(reason: String) {
    MIRAPlaybackCoordinator.pauseAll(reason: reason)
    if activeVideoPostID != nil {
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        activeVideoPostID = nil
      }
    }
  }

  private func presentPostOptions(for post: MIRAPost) {
    CaptroHaptics.light()
    MIRAApplePerformanceLogger.event("modal_open", detail: "post_options")
    postOptionsTarget = post
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isPostOptionsPresented = true
      }
    }
  }

  private func reportPostFromOptions(_ post: MIRAPost, dismiss: @escaping () -> Void) {
    CaptroHaptics.medium()
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
      presentReport(for: post)
    }
  }

  private func presentReport(for post: MIRAPost) {
    CaptroHaptics.medium()
    reportSourcePost = post
    reportTarget = MIRAReportTarget(
      targetType: "post",
      targetId: post.id,
      ownerUserId: post.userId,
      title: "Report post",
      subtitle: post.titleText
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  private func presentReport(for comment: MIRAComment) {
    CaptroHaptics.medium()
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  private func handleReportResult(_ result: MIRAReportResult) {
    guard let post = reportSourcePost else { return }
    if result.blocked, let userId = post.userId {
      model.hidePosts(byUserId: userId)
    } else if result.hidden {
      model.hidePost(post)
    }
  }

  private func blockCommentAuthor(_ comment: MIRAComment) async {
    guard let userId = comment.userId, !userId.isEmpty else { return }
    do {
      let _: EmptyResponse? = try await model.api.post("/users/\(userId)/block", body: EmptyBody())
      model.hidePosts(byUserId: userId)
    } catch {
      model.errorMessage = "Could not block this user. Try again in a moment."
    }
  }

  private var feedTabBarVisibility: Visibility {
    isFeedOverlayPresented ? .hidden : .visible
  }

  private var isMediaPlaybackSuppressed: Bool {
    !isTabActive || scenePhase != .active || detailPost != nil || isFeedOverlayPresented
  }

  private var isFeedOverlayPresented: Bool {
    isPostOptionsPresented ||
      postOptionsTarget != nil ||
      isReportSheetPresented ||
      reportTarget != nil ||
      isShowingCreatePost
  }
}

private struct MainNativePostCard: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let onLike: () -> Void
  let onSave: () -> Void
  let onComment: () -> Void
  let onFollow: () async -> Bool
  let onOpenOptions: () -> Void
  let canFollowAuthor: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedMediaIndex = 0
  @State private var isShowingCaption = false
  @State private var measuredCardWidth = UIScreen.main.bounds.width
  @State private var isSubmittingFollow = false
  @State private var isFollowConfirmationVisible = false

  private var mediaHeight: CGFloat {
    return MIRAMediaSizing.mainFeedHeight(
      for: post.feedMediaURLs,
      aspectRatios: post.mediaHeightToWidthRatios,
      width: measuredCardWidth
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      postHeader
        .zIndex(3)

      if !post.feedMediaURLs.isEmpty {
        mediaCarousel
          .zIndex(1)
      }

      actionRow
        .zIndex(3)

      if hasCaptionContent {
        captionBlock
          .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .contentShape(Rectangle())
    .background(MIRATheme.Color.surface)
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: MainPostWidthPreferenceKey.self, value: proxy.size.width)
      }
    }
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: MainPostVisibilityPreferenceKey.self,
          value: [MainPostVisibility(id: post.id, visibleRatio: visibleRatio(in: proxy), hasVideo: post.feedMediaURLs.contains { $0.isVideoURL })]
        )
      }
    }
    .onPreferenceChange(MainPostWidthPreferenceKey.self) { width in
      guard width.isFinite, width > 0, abs(width - measuredCardWidth) > 0.5 else { return }
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        measuredCardWidth = width
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.75).allowsHitTesting(false)
    }
    .overlay(alignment: .topLeading) {
      followingConfirmationBadge
        .padding(.leading, 58)
        .padding(.top, 50)
        .zIndex(8)
    }
    .onChange(of: post.id) { _, _ in
      selectedMediaIndex = 0
      isSubmittingFollow = false
      isFollowConfirmationVisible = false
    }
    .onAppear {
      prefetchCarouselNeighbors()
    }
    .onChange(of: post.feedMediaURLs) { _, urls in
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: selectedMediaIndex) { _, _ in
      prefetchCarouselNeighbors()
    }
    .onChange(of: post.id) { _, _ in isShowingCaption = false }
    .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: isShowingCaption)
  }

  @ViewBuilder
  private var mediaCarousel: some View {
    let mediaURLs = post.feedMediaURLs
    if mediaURLs.count == 1, let url = mediaURLs.first {
      RemoteMediaView(
        url: url,
        isVideo: url.isVideoURL,
        placeholderURL: mediaPlaceholderURL(for: 0, mediaURL: url),
        fallbackURL: mediaFallbackURL(for: 0, mediaURL: url),
        contentMode: .fill,
        shouldPlay: isVideoActive,
        maxPixelSize: MIRAMediaSizing.feedTargetHeight,
        placeholderColor: MIRATheme.Color.mediaPlaceholder
      )
      .frame(maxWidth: .infinity)
      .frame(minHeight: mediaHeight, maxHeight: mediaHeight)
      .background(MIRATheme.Color.mediaPlaceholder)
      .clipped()
      .allowsHitTesting(false)
    } else {
      VStack(spacing: 7) {
        TabView(selection: $selectedMediaIndex) {
          ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
            RemoteMediaView(
              url: url,
              isVideo: url.isVideoURL,
              placeholderURL: mediaPlaceholderURL(for: index, mediaURL: url),
              fallbackURL: mediaFallbackURL(for: index, mediaURL: url),
              contentMode: .fill,
              shouldPlay: isVideoActive && selectedMediaIndex == index,
              maxPixelSize: MIRAMediaSizing.feedTargetHeight,
              placeholderColor: MIRATheme.Color.mediaPlaceholder
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(minHeight: mediaHeight, maxHeight: mediaHeight)
        .background(MIRATheme.Color.mediaPlaceholder)
        .overlay(alignment: .topTrailing) {
          carouselCounter(current: selectedMediaIndex + 1, total: mediaURLs.count)
            .padding(.top, 12)
            .padding(.trailing, 12)
            .allowsHitTesting(false)
        }

        HStack(spacing: 6) {
          ForEach(mediaURLs.indices, id: \.self) { index in
            Circle()
              .fill(index == selectedMediaIndex ? Color(red: 0.0, green: 0.48, blue: 1.0) : MIRATheme.Color.textMuted.opacity(0.28))
              .frame(width: index == selectedMediaIndex ? 7 : 5, height: index == selectedMediaIndex ? 7 : 5)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 1)
        .padding(.bottom, 2)
        .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: selectedMediaIndex)
      }
      .background(MIRATheme.Color.surface)
    }
  }

  private func carouselCounter(current: Int, total: Int) -> some View {
    Text("\(min(max(current, 1), max(total, 1)))/\(max(total, 1))")
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .frame(height: 28)
      .background(.black.opacity(0.58))
      .clipShape(Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.8))
      .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
  }

  private func prefetchCarouselNeighbors() {
    let mediaURLs = post.feedMediaURLs
    guard mediaURLs.count > 1 else { return }
    let selected = min(max(selectedMediaIndex, 0), mediaURLs.count - 1)

    var previewURLs: [String] = []
    var priorityImageURLs: [String] = []
    var remainingImageURLs: [String] = []
    var videoURLs: [String] = []

    for index in mediaURLs.indices {
      let url = mediaURLs[index]
      if let placeholder = mediaPlaceholderURL(for: index, mediaURL: url) {
        previewURLs.append(placeholder)
      }
      let fallback = mediaFallbackURL(for: index, mediaURL: url)
      if url.isVideoURL {
        if abs(index - selected) <= 1 {
          videoURLs.append(url)
        }
      } else if index >= selected && index <= min(mediaURLs.count - 1, selected + 2) {
        priorityImageURLs.append(url)
        if let fallback = fallback {
          priorityImageURLs.append(fallback)
        }
      } else {
        remainingImageURLs.append(url)
        if let fallback = fallback {
          remainingImageURLs.append(fallback)
        }
      }
    }

    if !videoURLs.isEmpty {
      Task { @MainActor in
        MIRAVideoPrewarmManager.shared.prewarm(urls: videoURLs, keepOnly: Set(videoURLs))
      }
    }

    let fullImageURLs = orderedCarouselURLs(priorityImageURLs + remainingImageURLs)
    let previews = orderedCarouselURLs(previewURLs)
    guard !previews.isEmpty || !fullImageURLs.isEmpty else { return }
    Task.detached(priority: .utility) {
      if !previews.isEmpty {
        MIRAApplePerformanceLogger.event("carousel_media_prefetched", detail: "previews=\(previews.count)")
        await MIRAImagePrefetcher.prefetch(urls: previews, maxPixelSize: 560, limit: 16)
      }
      if !fullImageURLs.isEmpty {
        MIRAApplePerformanceLogger.event("carousel_media_prefetched", detail: "full=\(fullImageURLs.count)")
        await MIRAImagePrefetcher.prefetch(urls: fullImageURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: max(18, fullImageURLs.count))
      }
    }
  }

  private func orderedCarouselURLs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }

  private func mediaPlaceholderURL(for index: Int, mediaURL: String) -> String? {
    let posters = post.posterMediaURLs
    let thumbnails = post.thumbnailMediaURLs
    let poster = posters.indices.contains(index) ? posters[index] : nil
    let thumbnail = thumbnails.indices.contains(index) ? thumbnails[index] : nil
    let candidate = mediaURL.isVideoURL ? (poster ?? thumbnail) : (thumbnail ?? poster)
    let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty, trimmed != mediaURL else { return nil }
    return trimmed
  }

  private func mediaFallbackURL(for index: Int, mediaURL: String) -> String? {
    let originals = post.fallbackMediaURLs
    guard originals.indices.contains(index) else { return nil }
    let trimmed = originals[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != mediaURL, !trimmed.isVideoURL else { return nil }
    return trimmed
  }

  private var actionRow: some View {
    HStack(spacing: 4) {
      engagementButtons
      Spacer(minLength: 4)
      captionExpansionButton
    }
    .lineLimit(1)
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, 2)
    .padding(.bottom, hasCaptionContent ? 0 : 7)
  }

  private var engagementButtons: some View {
    HStack(spacing: 2) {
      CompactPostAction(systemImage: post.viewerLiked ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.viewerLiked ? MIRATheme.Color.like : MIRATheme.Color.textSecondary) {
        debugTap("tap_like")
        onLike()
      }
      CompactPostAction(systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0, tint: post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary) {
        debugTap("tap_save")
        onSave()
      }
      CompactPostAction(
        systemImage: "bubble.left",
        value: post.commentsCount ?? 0,
        tint: MIRATheme.Color.textSecondary
      ) {
        debugTap("tap_comment")
        onComment()
      }
    }
    .layoutPriority(2)
  }

  @ViewBuilder
  private var captionExpansionButton: some View {
    if captionNeedsExpansion {
      CompactTextAction(isShowingCaption ? "Less" : "More", action: toggleCaption)
        .layoutPriority(1)
    }
  }

  private var captionBlock: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let headlineText {
        Text(headlineText)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(isShowingCaption ? nil : 1)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let captionBodyText {
        Text(captionBodyText)
          .font(.system(size: 14, weight: .regular))
          .lineSpacing(2)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(isShowingCaption ? nil : 2)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let placeText {
        HStack(spacing: 6) {
          Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 13, weight: .semibold))
          Text(placeText)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .foregroundStyle(MIRATheme.Color.like.opacity(0.78))
        .padding(.top, 1)
        .accessibilityElement(children: .combine)
      }

      if let taggedPeopleText {
        HStack(spacing: 6) {
          Image(systemName: "person.2.fill")
            .font(.system(size: 12, weight: .semibold))
          Text(taggedPeopleText)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(isShowingCaption ? nil : 1)
            .truncationMode(.tail)
        }
        .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, 0)
    .padding(.bottom, 8)
  }

  private var hasCaptionContent: Bool {
    return headlineText != nil || captionBodyText != nil || placeText != nil || taggedPeopleText != nil
  }

  private var captionNeedsExpansion: Bool {
    if let headlineText, headlineText.count > 58 { return true }
    if let captionBodyText {
      if captionBodyText.count > 118 { return true }
      if captionBodyText.contains("\n") { return true }
    }
    if let taggedPeopleText, taggedPeopleText.count > 64 { return true }
    return false
  }

  private var headlineText: String? {
    let value = post.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private var captionBodyText: String? {
    let base = ((post.caption?.isEmpty == false ? post.caption : post.content) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return base.isEmpty ? nil : base
  }

  private var placeText: String? {
    let value = post.placeDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private var taggedPeopleText: String? {
    let people = (post.taggedUsers ?? [])
      .compactMap { taggedUserName($0) }
      .prefix(6)
      .joined(separator: ", ")
    return people.isEmpty ? nil : "With \(people)"
  }

  private func taggedUserName(_ user: MIRATaggedUserPayload) -> String? {
    let raw = (user.username?.isEmpty == false ? user.username : user.fullName)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !raw.isEmpty else { return nil }
    if raw.hasPrefix("@") { return raw }
    return "@\(raw)"
  }

  private func toggleCaption() {
    debugTap("tap_caption_more")
    CaptroHaptics.light()
    withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
      isShowingCaption.toggle()
    }
  }

  private func visibleRatio(in proxy: GeometryProxy) -> CGFloat {
    let frame = proxy.frame(in: .global)
    let screen = UIScreen.main.bounds
    let visibleHeight = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
    return max(0, min(1, visibleHeight / max(frame.height, 1)))
  }

  private var postHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      authorAvatar

      authorIdentity
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      if post.isPinned {
        Label("Pinned", systemImage: "pin.fill")
          .font(.system(size: 11, weight: .semibold))
          .labelStyle(.iconOnly)
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 28, height: 28)
          .background(MIRATheme.Color.forest.opacity(0.10))
          .clipShape(Circle())
          .accessibilityLabel("Pinned post")
      }

      postMenu
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var authorAvatar: some View {
    if canFollowAuthor || isSubmittingFollow || isFollowConfirmationVisible {
      Button {
        debugTap("tap_follow_avatar")
        followWithConfirmation()
      } label: {
        MIRAFollowAvatar(
          url: post.userProfileImage,
          size: 42,
          isFollowing: post.viewerFollowing || isSubmittingFollow || isFollowConfirmationVisible
        )
        .scaleEffect(isFollowConfirmationVisible ? 1.08 : 1)
      }
      .buttonStyle(.plain)
      .disabled(isSubmittingFollow)
      .accessibilityLabel(isSubmittingFollow || isFollowConfirmationVisible ? "Following" : "Follow")
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    } else if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api).miraHideTabBarOnAppear()) {
        RemoteAvatar(url: post.userProfileImage, size: 42)
      }
      .buttonStyle(.plain)
      .simultaneousGesture(TapGesture().onEnded { debugTap("tap_avatar_profile") })
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    } else {
      RemoteAvatar(url: post.userProfileImage, size: 42)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { debugTap("tap_avatar_missing_author") }
    }
  }

  @ViewBuilder
  private var authorIdentity: some View {
    if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api).miraHideTabBarOnAppear()) {
        authorIdentityLabel
      }
      .buttonStyle(.plain)
      .simultaneousGesture(TapGesture().onEnded { debugTap("tap_username_profile") })
      .frame(minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    } else {
      authorIdentityLabel
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { debugTap("tap_username_missing_author") }
    }
  }

  private var authorIdentityLabel: some View {
    VStack(alignment: .leading, spacing: 2) {
      authorNameLabel
      if let subtitle = authorSubtitle {
        Text(subtitle)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var postMenu: some View {
    Button {
      debugTap("tap_post_menu")
      onOpenOptions()
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
        .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel("Post options")
  }

  private func followWithConfirmation() {
    guard !isSubmittingFollow, canFollowAuthor else { return }
    CaptroHaptics.light()
    isSubmittingFollow = true
    withAnimation(CaptroMotion.buttonPressAnimation(reduceMotion: reduceMotion)) {
      isFollowConfirmationVisible = true
    }

    Task {
      let didFollow = await onFollow()
      let holdNanoseconds: UInt64 = didFollow ? 1_050_000_000 : 180_000_000
      try? await Task.sleep(nanoseconds: holdNanoseconds)
      await MainActor.run {
        withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
          isFollowConfirmationVisible = false
        }
        isSubmittingFollow = false
      }
    }
  }

  @ViewBuilder
  private var followingConfirmationBadge: some View {
    if isFollowConfirmationVisible {
      HStack(spacing: 7) {
        Image(systemName: "checkmark")
          .font(.system(size: 11, weight: .bold))
        Text("Following")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 11)
      .frame(height: 28)
      .background(MIRATheme.Color.forest.opacity(0.94))
      .clipShape(Capsule())
      .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
      .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
      .allowsHitTesting(false)
    }
  }

  private var authorNameLabel: some View {
    Text(post.authorDisplayName)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var authorSubtitle: String? {
    cleanedLocation(post.displayLocationText)
  }

  private func cleanedLocation(_ value: String?) -> String? {
    let clean = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression) ?? ""
    guard !clean.isEmpty else { return nil }
    return clean
  }

  private func debugTap(_ action: String) {
    #if DEBUG
    let author = post.userId?.isEmpty == false ? post.userId! : "missing"
    print("[Captro feed tap] action=\(action) post_id=\(post.id) author_id=\(author)")
    #endif
  }
}

private struct MainFeedPostOptionsSheet: View {
  let post: MIRAPost
  let shareURL: URL
  let onReport: () -> Void
  let onNotInterested: () -> Void

  var body: some View {
    MIRAActionModalCard {
      MIRAActionModalButton(
        title: "Report",
        systemImage: "exclamationmark.triangle",
        staggerIndex: 0,
        action: onReport
      )

      MIRAActionModalButton(
        title: "Not Interested",
        systemImage: "hand.thumbsdown",
        staggerIndex: 1,
        action: onNotInterested
      )

      ShareLink(item: shareURL, subject: Text(post.titleText), message: Text(post.titleText)) {
        MIRAActionModalPillLabel(
          title: "Share",
          systemImage: "square.and.arrow.up"
        )
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel("Share")
    }
  }
}

private struct MainFeedPostOptionRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.10))
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.65))
    }
    .padding(.horizontal, MIRATheme.Space.lg)
    .frame(minHeight: 58)
    .contentShape(Rectangle())
  }
}

private func mainFeedShareURL(for post: MIRAPost) -> URL {
  MIRAProductionBackend.siteURL("post/\(post.id)")
}

private struct MainFeedCommentsSheet: View {
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  @State private var isSending = false
  @State private var replyingTo: MIRAComment?
  @FocusState private var isReplyFocused: Bool
  @EnvironmentObject private var localization: MIRALocalization
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onClose: () -> Void
  let onReportComment: (MIRAComment) -> Void
  let onBlockCommentUser: (MIRAComment) -> Void

  init(
    post: MIRAPost,
    api: MIRAAPIClient,
    onClose: @escaping () -> Void,
    onReportComment: @escaping (MIRAComment) -> Void,
    onBlockCommentUser: @escaping (MIRAComment) -> Void
  ) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
    self.onClose = onClose
    self.onReportComment = onReportComment
    self.onBlockCommentUser = onBlockCommentUser
  }

  var body: some View {
    VStack(spacing: 0) {
      sheetHeader

      ScrollView {
        LazyVStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          if model.isLoadingComments && model.comments.isEmpty {
            ForEach(0..<5, id: \.self) { _ in
              MainFeedCommentSkeleton()
            }
          } else if model.comments.isEmpty {
            MIRAEmptyState(title: localization.string("comments.empty.title"), message: localization.string("comments.empty.message"), systemImage: "bubble.left")
              .frame(maxWidth: .infinity)
              .padding(.top, 28)
          } else {
            ForEach(model.comments) { comment in
              MainFeedCommentRow(
                comment: comment,
                currentUserId: model.currentUserId,
                postOwnerId: model.post.userId,
                onReply: {
                  replyingTo = comment
                  isReplyFocused = true
                },
                onLike: {
                  Task { await model.toggleCommentLike(comment) }
                },
                onPin: {
                  Task { await model.toggleCommentPin(comment) }
                },
                onReport: {
                  onReportComment(comment)
                },
                onBlockUser: {
                  onBlockCommentUser(comment)
                },
                onDelete: {
                  Task { await model.deleteComment(comment) }
                },
                onHide: {
                  Task { await model.hideComment(comment) }
                }
              )
            }
          }
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, 18)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .miraScrollFeel(.sheet)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      commentComposer
    }
    .background(MIRATheme.Color.surface)
    .task {
      await model.loadComments()
    }
  }

  private var sheetHeader: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.22))
        .frame(width: 42, height: 5)
        .padding(.top, 10)

      HStack(spacing: MIRATheme.Space.sm) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(localization.string("comments.title"))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(compact(model.post.commentsCount ?? model.comments.count))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Capsule())
        }
        Spacer()
        Button {
          closeSheet()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
    .padding(.bottom, MIRATheme.Space.sm)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var commentComposer: some View {
    VStack(spacing: 0) {
      if let replyingTo {
        HStack(spacing: 8) {
          Image(systemName: "arrowshape.turn.up.left")
            .font(.system(size: 12, weight: .semibold))
          Text("Replying to \(replyingTo.user?.displayName ?? "comment")")
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          Button {
            CaptroHaptics.light()
            self.replyingTo = nil
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .bold))
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.miraPress)
        }
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.sm)
      }

      HStack(alignment: .bottom, spacing: MIRATheme.Space.sm) {
        RemoteAvatar(url: model.post.userProfileImage, size: 34)
          .padding(.bottom, 2)
        TextField(replyingTo == nil ? localization.string("comments.add_placeholder") : localization.string("comments.reply_placeholder"), text: $draft, axis: .vertical)
          .font(.system(size: 15, weight: .regular))
          .textInputAutocapitalization(.sentences)
          .submitLabel(.send)
          .focused($isReplyFocused)
          .lineLimit(1...5)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.vertical, 11)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
              .stroke(isReplyFocused ? MIRATheme.Color.forest.opacity(0.18) : MIRATheme.Color.hairline, lineWidth: 1)
          }
          .onSubmit(sendComment)
          .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: isReplyFocused)

        Button(action: sendComment) {
          Group {
            if isSending {
              ProgressView()
                .tint(.white)
                .frame(width: 17, height: 17)
            } else {
              Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 40, height: 40)
          .background(canSend ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.28))
          .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .disabled(!canSend || isSending)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
      .padding(.bottom, MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }

  private func sendComment() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSending else { return }
    CaptroHaptics.light()
    isSending = true
    draft = ""
    Task {
      let parentId = replyingTo?.id
      let didSend = await model.sendComment(text, parentId: parentId)
      if !didSend {
        draft = text
      } else {
        replyingTo = nil
      }
      isSending = false
    }
  }

  private func closeSheet() {
    isReplyFocused = false
    onClose()
  }
}

private struct MainFeedCommentRow: View {
  let comment: MIRAComment
  let currentUserId: String?
  let postOwnerId: String?
  let onReply: () -> Void
  let onLike: () -> Void
  let onPin: () -> Void
  let onReport: () -> Void
  let onBlockUser: () -> Void
  let onDelete: () -> Void
  let onHide: () -> Void

  private var isOwnComment: Bool {
    guard let currentUserId, let userId = comment.userId else { return false }
    return currentUserId == userId
  }

  private var isPostCreator: Bool {
    guard let currentUserId, let postOwnerId else { return false }
    return currentUserId == postOwnerId
  }

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 34)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 7) {
        if comment.pinned {
          Label("Pinned by creator", systemImage: "pin.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }

        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(comment.user?.displayName ?? "user")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .layoutPriority(1)
            if let createdAt = comment.createdAt {
              Text(mainFeedCommentAge(createdAt))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
          }
          Text(comment.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, 10)
        .background(MIRATheme.Color.surfaceSoft.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        HStack(spacing: MIRATheme.Space.lg) {
          Button("Reply") {
            CaptroHaptics.light()
            onReply()
          }
          .buttonStyle(.plain)

          Button {
            CaptroHaptics.light()
            onLike()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: comment.viewerLiked ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
              Text(compact(comment.likesCount ?? 0))
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(comment.viewerLiked ? MIRATheme.Color.like : MIRATheme.Color.textMuted)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.leading, MIRATheme.Space.xs)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
    }
    .padding(.leading, comment.isReply ? 42 : 0)
    .contextMenu {
      Button(action: onReply) {
        Label("Reply", systemImage: "arrowshape.turn.up.left")
      }
      Button(action: onLike) {
        Label(comment.viewerLiked ? "Unlike comment" : "Like comment", systemImage: comment.viewerLiked ? "heart.slash" : "heart")
      }
      if isPostCreator {
        Button(action: onPin) {
          Label(comment.pinned ? "Unpin comment" : "Pin comment", systemImage: comment.pinned ? "pin.slash" : "pin")
        }
        if !isOwnComment {
          Button(role: .destructive, action: onHide) {
            Label("Hide comment", systemImage: "eye.slash")
          }
        }
      }
      if isOwnComment {
        Button(role: .destructive, action: onDelete) {
          Label("Delete comment", systemImage: "trash")
        }
      } else {
        Button(role: .destructive, action: onBlockUser) {
          Label("Block user", systemImage: "hand.raised")
        }
        Button(role: .destructive, action: onReport) {
          Label("Report comment", systemImage: "flag")
        }
      }
    }
  }
}

private struct MainFeedCommentSkeleton: View {
  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 5)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: 120, height: 12)
        RoundedRectangle(cornerRadius: 6)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
      }
    }
    .redacted(reason: .placeholder)
  }
}

private struct MainPostSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: MIRATheme.Space.sm) {
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 46, height: 46)
        VStack(alignment: .leading, spacing: 6) {
          RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 132, height: 15)
          RoundedRectangle(cornerRadius: 5).fill(MIRATheme.Color.surfaceSoft).frame(width: 86, height: 11)
        }
        Spacer()
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 44, height: 44)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 10)

      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .padding(.horizontal, MIRATheme.Space.md)

      VStack(alignment: .leading, spacing: 5) {
        RoundedRectangle(cornerRadius: 5).fill(MIRATheme.Color.surfaceSoft).frame(width: 196, height: 20)
        RoundedRectangle(cornerRadius: 4).fill(MIRATheme.Color.surfaceSoft).frame(maxWidth: .infinity).frame(height: 12)
        RoundedRectangle(cornerRadius: 4).fill(MIRATheme.Color.surfaceSoft).frame(width: 226, height: 12)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, 6)

      RoundedRectangle(cornerRadius: 4)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 118, height: 14)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, 6)
        .padding(.bottom, 18)

      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 0.5)
        .padding(.horizontal, MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.surface)
    .redacted(reason: .placeholder)
    .onAppear {
      MIRAPerformanceTimeline.markOnce("time_to_first_home_skeleton")
    }
  }
}

private struct CompactPostAction: View {
  let systemImage: String
  let value: Int
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button {
      CaptroHaptics.light()
      action()
    } label: {
      HStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .regular))
        Text(compact(value))
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundStyle(tint)
      .frame(minWidth: 40, minHeight: 38)
      .padding(.horizontal, 1)
      .contentShape(Rectangle())
    }
    .buttonStyle(.miraPress)
  }
}

private struct CompactTextAction: View {
  let title: String
  let systemImage: String?
  let action: () -> Void

  init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
        }
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }
      .foregroundStyle(MIRATheme.Color.forest)
      .frame(minWidth: 40, minHeight: 34)
      .padding(.horizontal, 10)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
      .contentShape(Rectangle())
    }
    .buttonStyle(.miraPress)
  }
}

private func mainFeedCommentAge(_ value: String) -> String {
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: value) else { return "" }
  let seconds = max(0, Date().timeIntervalSince(date))
  if seconds < 60 { return "now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h" }
  let days = Int(seconds / 86_400)
  if days < 30 { return "\(days)d" }
  let months = Int(seconds / 2_592_000)
  return "\(max(1, months))mo"
}

private func compact(_ value: Int) -> String {
  if value >= 1_000_000 { return compactDecimal(Double(value) / 1_000_000, suffix: "M") }
  if value >= 1_000 { return compactDecimal(Double(value) / 1_000, suffix: "K") }
  return "\(value)"
}

private func compactDecimal(_ value: Double, suffix: String) -> String {
  let rounded = value >= 100 ? floor(value) : floor(value * 10) / 10
  if rounded.truncatingRemainder(dividingBy: 1) == 0 {
    return "\(Int(rounded))\(suffix)"
  }
  return String(format: "%.1f%@", rounded, suffix)
}

private struct MainPostVisibility: Equatable {
  let id: String
  let visibleRatio: CGFloat
  let hasVideo: Bool
}

private struct MainPostVisibilityPreferenceKey: PreferenceKey {
  static var defaultValue: [MainPostVisibility] = []

  static func reduce(value: inout [MainPostVisibility], nextValue: () -> [MainPostVisibility]) {
    value.append(contentsOf: nextValue())
  }
}

private struct MainPostWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = UIScreen.main.bounds.width

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
