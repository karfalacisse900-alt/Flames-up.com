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

private final class MainFeedScrollState {
  var previousMinY: CGFloat?
  var intentDistance: CGFloat = 0
  var intentDirection = 0

  func reset() {
    previousMinY = nil
    intentDistance = 0
    intentDirection = 0
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
  private let feedCacheKey = "native.main.feed.v3"
  private var hasLoadedFreshFeed = false
  private var isLoadingFreshFeed = false
  private var canLoadMore = true
  private var isLoadingCurrentUser = false
  private var mediaPrefetchTask: Task<Void, Never>?
  private var followingAuthorIds = Set<String>()
  private var likingPostIds = Set<String>()
  private let firstPageLimit = 12
  private let paginationTriggerRatio = 0.70
  private let paginationTriggerWindow = 4

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func prepareForStartup() async {
    MIRAPerformanceTimeline.mark("home_startup_prepare")
    if currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
    }
    await hydrateCachedFeedIfNeeded()
    if posts.isEmpty {
      isLoading = true
    }
    Task { await load() }
  }

  func load(forceRefresh: Bool = false) async {
    if currentUserId == nil && currentUsername == nil {
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
    let merged = await MIRAAppCacheStore.shared.mergePostsPreservingVisibleState(existing: posts, fresh: sorted)
    if posts != merged {
      posts = merged
    }
    canLoadMore = loaded.count >= firstPageLimit
    await MIRAAppCacheStore.shared.saveFeed(posts)
    MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "network")
    errorMessage = nil
    prefetchInitialMediaWindow()
    prefetchNextPageIfNeeded(afterInitialCount: posts.count)
  }

  private func hydrateCachedFeedIfNeeded() async {
    guard posts.isEmpty else { return }
    var cached = await MIRAAppCacheStore.shared.loadFeed()
    if cached == nil {
      cached = await MIRALocalJSONCache.load([MIRAPost].self, key: feedCacheKey, maxAge: 60 * 60 * 24 * 30)
    }
    guard let cached else { return }
    // Cached feed is already stored in display order, so show it immediately.
    posts = cached
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
    await loadNextPage(reason: "scroll")
  }

  func prefetchMedia(around post: MIRAPost, scrollDirection: Int = 1) {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let plan = makeMediaPreloadPlan(focusIndex: index, scrollDirection: scrollDirection)
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
        await MIRAImagePrefetcher.prefetch(urls: plan.feedImageURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: 12)
        MIRAApplePerformanceLogger.event("media_prefetch_completed", detail: "feed_full")
      }
    }
  }

  private func prefetchInitialMediaWindow() {
    guard let firstPost = posts.first else { return }
    prefetchMedia(around: firstPost, scrollDirection: 1)
  }

  private func makeMediaPreloadPlan(focusIndex: Int, scrollDirection: Int) -> MainFeedMediaPreloadPlan {
    guard posts.indices.contains(focusIndex) else { return MainFeedMediaPreloadPlan() }

    let direction = scrollDirection < 0 ? -1 : 1
    let orderedIndices = mediaPreloadIndices(from: focusIndex, direction: direction, limit: 16)
    var previewURLs: [String] = []
    var feedImageURLs: [String] = []
    var videoPrewarmURLs: [String] = []
    var videoKeepAliveURLs: [String] = []

    for (rank, index) in orderedIndices.enumerated() {
      let post = posts[index]
      previewURLs.append(contentsOf: post.posterMediaURLs)
      previewURLs.append(contentsOf: post.thumbnailMediaURLs)

      let mediaURLs = post.feedMediaURLs
      let imageURLs = mediaURLs.filter { !$0.isVideoURL }
      let videoURLs = mediaURLs.filter { $0.isVideoURL }

      if rank == 0 {
        // Visible carousel: all previews, current/next optimized images, then remaining images if the cache has room.
        feedImageURLs.append(contentsOf: imageURLs.prefix(3))
        feedImageURLs.append(contentsOf: imageURLs.dropFirst(3).prefix(5))
        videoPrewarmURLs.append(contentsOf: videoURLs.prefix(2))
      } else if rank <= 3 {
        feedImageURLs.append(contentsOf: imageURLs.prefix(2))
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

  private func mediaPreloadIndices(from focusIndex: Int, direction: Int, limit: Int) -> [Int] {
    var result: [Int] = [focusIndex]
    var cursor = focusIndex + direction
    while posts.indices.contains(cursor), result.count < limit {
      result.append(cursor)
      cursor += direction
    }

    let oppositeDirection = -direction
    cursor = focusIndex + oppositeDirection
    while posts.indices.contains(cursor), result.count < min(limit + 3, posts.count) {
      result.append(cursor)
      cursor += oppositeDirection
    }
    return result
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
      let fallback = await fetchPublicFeedPage(skip: skip)
      unique = fallback.filter { !existing.contains($0.id) }
      if unique.isEmpty {
        canLoadMore = fallback.count >= firstPageLimit
        MIRAPerformanceTimeline.mark("home_load_more_duplicate_page", detail: "skip=\(skip)")
        return
      }
    }

    posts.append(contentsOf: await sortedByNativeScore(unique))
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
    guard !likingPostIds.contains(post.id) else { return }
    likingPostIds.insert(post.id)
    defer { likingPostIds.remove(post.id) }

    let previous = posts[index]
    let nextLiked = !(previous.isLiked ?? false)
    let nextCount = max(0, (previous.likesCount ?? 0) + (nextLiked ? 1 : -1))
    posts[index] = previous.updating(liked: nextLiked, likesCount: nextCount)

    do {
      let response: PostLikeResponse = try await api.post("/posts/\(post.id)/like", body: LikeBody(liked: nextLiked))
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked ?? nextLiked,
          likesCount: response.likesCount ?? nextCount,
          commentsCount: response.commentsCount,
          saved: response.saved,
          savesCount: response.savesCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
      }
    }
  }

  func save(_ post: MIRAPost, to collection: String) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    let nextCount = max(0, (previous.savesCount ?? 0) + (previous.viewerSaved ? 0 : 1))
    posts[index] = previous.updating(saved: true, savesCount: nextCount)

    do {
      let response: PostSaveResponse = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: collection))
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked,
          likesCount: response.likesCount,
          commentsCount: response.commentsCount,
          saved: response.saved ?? true,
          savesCount: response.savesCount ?? nextCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
      }
    }
  }

  func unsave(_ post: MIRAPost) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    guard previous.viewerSaved else { return }
    let nextCount = max(0, (previous.savesCount ?? 0) - 1)
    posts[index] = previous.updating(saved: false, savesCount: nextCount)

    do {
      let response: PostSaveResponse = try await api.delete("/library/save/\(post.id)")
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked,
          likesCount: response.likesCount,
          commentsCount: response.commentsCount,
          saved: response.saved ?? false,
          savesCount: response.savesCount ?? nextCount
        )
        publishEngagement(for: posts[currentIndex])
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
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
      likesCount: update.likesCount,
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
      errorMessage = nil
    } catch {
      errorMessage = "Could not update post visibility."
    }
  }

  private func loadCurrentUserIfNeeded() async {
    guard currentUserId == nil && currentUsername == nil else { return }
    guard !isLoadingCurrentUser else { return }
    isLoadingCurrentUser = true
    defer { isLoadingCurrentUser = false }
    let me: MIRAUser? = try? await api.get("/auth/me")
    currentUserId = me?.id
    currentUsername = me?.username
  }

  func canDelete(_ post: MIRAPost) -> Bool {
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
    Task { await MIRAAppCacheStore.shared.saveFeed(snapshot) }
  }

  private func publishEngagement(for post: MIRAPost) {
    MIRAPostEngagementSync.publish(
      MIRAPostEngagementUpdate(
        postId: post.id,
        liked: post.isLiked,
        likesCount: post.likesCount,
        saved: post.viewerSaved,
        savesCount: post.savesCount,
        commentsCount: post.commentsCount
      )
    )
  }

  private func fetchFeedPage(skip: Int) async -> [MIRAPost] {
    do {
      let loaded: [MIRAPost] = try await api.get("/posts/feed?limit=\(firstPageLimit)&skip=\(skip)")
      if !loaded.isEmpty { return loaded }
      MIRAPerformanceTimeline.mark("home_feed_page_empty", detail: "authenticated skip=\(skip)")
    } catch {
      MIRAPerformanceTimeline.mark("home_feed_page_failed", detail: "authenticated skip=\(skip)")
    }
    return await fetchPublicFeedPage(skip: skip)
  }

  private func fetchPublicFeedPage(skip: Int) async -> [MIRAPost] {
    do {
      let loaded: [MIRAPost] = try await api.get("/posts/world-board?limit=\(firstPageLimit)&skip=\(skip)")
      return loaded
    } catch {
      MIRAPerformanceTimeline.mark("home_feed_page_failed", detail: "public skip=\(skip)")
      return []
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

  nonisolated private static func ageHours(from value: String?, formatter: ISO8601DateFormatter) -> Double {
    guard let value, let date = formatter.date(from: value) else { return 24 }
    return max(0, Date().timeIntervalSince(date) / 3600)
  }
}

private struct MainPostVisibilityUpdateBody: Encodable {
  let visibility: String
}

public struct MainFeedView: View {
  @StateObject private var model: MainFeedModel
  private let isTabActive: Bool
  @EnvironmentObject private var localization: MIRALocalization
  @State private var scrollState = MainFeedScrollState()
  @State private var activeVideoPostID: String?
  @State private var isHeaderHidden = false
  @State private var isShowingCreatePost = false
  @State private var activeCommentsPost: MIRAPost?
  @State private var isCommentsPresented = false
  @State private var saveTargetPost: MIRAPost?
  @State private var isSaveSheetPresented = false
  @State private var postOptionsTarget: MIRAPost?
  @State private var isPostOptionsPresented = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportSourcePost: MIRAPost?
  @State private var isReportSheetPresented = false

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: MainFeedModel(api: api))
    self.isTabActive = true
  }

  init(api: MIRAAPIClient, model: MainFeedModel, isTabActive: Bool = true) {
    _model = StateObject(wrappedValue: model)
    self.isTabActive = isTabActive
  }

  public var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        ScrollView {
          GeometryReader { proxy in
            Color.clear.preference(key: MainFeedScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("mainFeedScroll")).minY)
          }
          .frame(height: 1)

          LazyVStack(spacing: 0) {
            if model.isLoading && model.posts.isEmpty {
              ForEach(0..<4, id: \.self) { _ in MainPostSkeleton() }
            } else if model.posts.isEmpty {
              MIRAEmptyState(title: localization.string("feed.empty.title"), message: localization.string("feed.empty.message"), systemImage: "sparkles")
                .padding(.top, 80)
            } else {
              ForEach(model.posts) { post in
                MainNativePostCard(
                  post: post,
                  api: model.api,
                  isVideoActive: post.id == activeVideoPostID && !isMediaPlaybackSuppressed,
                  onLike: { Task { await model.toggleLike(post) } },
                  onSave: { presentSaveSheet(for: post) },
                  onComment: { presentComments(for: post) },
                  onFollow: { await model.followAuthor(post) },
                  onOpenOptions: { presentPostOptions(for: post) },
                  canFollowAuthor: model.canFollowAuthor(post)
                )
                .onAppear {
                  MIRAApplePerformanceLogger.event("post_cell_appear", detail: post.feedMediaURLs.first?.isVideoURL == true ? "video" : "image")
                  Task { await model.loadMoreIfNeeded(after: post) }
                  model.prefetchMedia(around: post, scrollDirection: scrollState.intentDirection)
                }
              }
              if model.isLoadingMore {
                MainPostSkeleton()
              }
              if !model.isLoading, let lastPost = model.posts.last {
                Color.clear
                  .frame(height: 1)
                  .task(id: "\(lastPost.id)-\(model.posts.count)") {
                    await model.loadMoreIfNeeded(after: lastPost)
                  }
              }
            }
          }
          .padding(.bottom, MIRATheme.Space.xxl)
        }
        .coordinateSpace(name: "mainFeedScroll")
        .miraScrollFeel(.feed)
        .simultaneousGesture(
          DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged(handleScrollDrag)
        )

        mainHeader
          .offset(y: isFeedChromeHidden ? -84 : 0)
          .opacity(isFeedChromeHidden ? 0 : 1)
          .allowsHitTesting(!isFeedChromeHidden)
          .zIndex(10)
          .animation(.easeInOut(duration: 0.24), value: isFeedChromeHidden)
      }
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(feedTabBarVisibility, for: .tabBar)
      .statusBarHidden(true)
      .miraBottomSheet(
        isPresented: $isCommentsPresented,
        onDismissed: { activeCommentsPost = nil }
      ) { dismiss in
        if let post = activeCommentsPost {
          MainFeedCommentsSheet(
            post: post,
            api: model.api,
            onClose: dismiss,
            onReportComment: { comment in
              dismiss()
              DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
                presentReport(for: comment)
              }
            },
            onBlockCommentUser: { comment in
              dismiss()
              Task { await blockCommentAuthor(comment) }
            }
          )
        } else {
          Color.clear
        }
      }
      .miraBottomSheet(
        isPresented: $isSaveSheetPresented,
        preferredHeightFraction: 0.46,
        maxHeight: 440,
        onDismissed: { saveTargetPost = nil }
      ) { dismiss in
        if let post = saveTargetPost {
          MIRASaveToCollectionSheet(
            isSaved: post.viewerSaved,
            onSelect: { collection in
              Task {
                await model.save(post, to: collection)
                dismiss()
              }
            },
            onRemove: {
              Task {
                await model.unsave(post)
                dismiss()
              }
            },
            onClose: dismiss
          )
        } else {
          Color.clear
        }
      }
      .miraBottomSheet(
        isPresented: $isPostOptionsPresented,
        preferredHeightFraction: 0.32,
        maxHeight: 320,
        onDismissed: { postOptionsTarget = nil }
      ) { dismiss in
        if let post = postOptionsTarget {
          MainFeedPostOptionsSheet(
            post: post,
            shareURL: mainFeedShareURL(for: post),
            onReport: { reportPostFromOptions(post, dismiss: dismiss) },
            onNotInterested: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        preferredHeightFraction: 0.78,
        maxHeight: 700,
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
      .miraFullScreenOverlay(isPresented: $isShowingCreatePost, background: .black) { dismiss in
        CreatePostNativeView(api: model.api, onClose: dismiss)
      }
      .task { await model.load() }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
        guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
        model.applyEngagementUpdate(update)
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraUserFollowDidChange)) { notification in
        guard let update = MIRAUserFollowSync.update(from: notification) else { return }
        model.applyFollowUpdate(update)
      }
      .onPreferenceChange(MainFeedScrollOffsetPreferenceKey.self, perform: handleScroll)
      .onPreferenceChange(MainPostVisibilityPreferenceKey.self, perform: updateActiveVideo)
      .onChange(of: isMediaPlaybackSuppressed) { _, suppressed in
        if suppressed {
          MIRAPlaybackCoordinator.pauseAll(reason: "home_feed_overlay")
        } else {
          MIRAPlaybackCoordinator.resumeVisible(reason: "home_feed_overlay_closed")
        }
      }
      .onAppear {
        MIRAApplePerformanceLogger.event("feed_render", detail: model.posts.isEmpty ? "empty" : "posts")
        if !isMediaPlaybackSuppressed {
          MIRAPlaybackCoordinator.resumeVisible(reason: "home_feed_appeared")
        }
      }
      .onDisappear {
        pauseVisibleMedia(reason: "home_feed_disappeared")
      }
    }
  }

  private func handleScroll(_ minY: CGFloat) {
    guard let previousMinY = scrollState.previousMinY else {
      scrollState.previousMinY = minY
      return
    }

    let delta = minY - previousMinY
    scrollState.previousMinY = minY
    guard abs(delta) > 1 else { return }

    if minY > -6 {
      if isHeaderHidden {
        withAnimation(.easeOut(duration: 0.14)) {
          isHeaderHidden = false
        }
      }
      scrollState.intentDistance = 0
      scrollState.intentDirection = 0
      return
    }

    let direction = delta < 0 ? 1 : -1
    if direction != scrollState.intentDirection {
      scrollState.intentDirection = direction
      scrollState.intentDistance = abs(delta)
    } else {
      scrollState.intentDistance += abs(delta)
    }

    if direction == 1 && minY < -8 && scrollState.intentDistance > 5 {
      if !isHeaderHidden {
        withAnimation(.easeOut(duration: 0.14)) {
          isHeaderHidden = true
        }
      }
      scrollState.intentDistance = 0
    } else if direction == -1 && scrollState.intentDistance > 10 {
      if isHeaderHidden {
        withAnimation(.easeOut(duration: 0.18)) {
          isHeaderHidden = false
        }
      }
      scrollState.intentDistance = 0
    }
  }

  private func updateActiveVideo(_ visibility: [MainPostVisibility]) {
    guard !isMediaPlaybackSuppressed else { return }
    let candidate = visibility
      .filter { $0.hasVideo && $0.visibleRatio >= 0.60 }
      .max { $0.visibleRatio < $1.visibleRatio }
    let nextID = candidate?.id
    if activeVideoPostID != nextID {
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        activeVideoPostID = nextID
      }
      MIRAMemoryMetrics.log("main_feed_video_switch")
    }
  }

  private func handleScrollDrag(_ value: DragGesture.Value) {
    let vertical = value.translation.height
    let horizontal = abs(value.translation.width)
    guard abs(vertical) > max(8, horizontal * 0.65) else { return }
    if vertical < -8 {
      if !isHeaderHidden {
        withAnimation(.easeOut(duration: 0.16)) {
          isHeaderHidden = true
        }
      }
    } else if vertical > 10 {
      if isHeaderHidden {
        withAnimation(.easeOut(duration: 0.18)) {
          isHeaderHidden = false
        }
      }
    }
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

  private func presentComments(for post: MIRAPost) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    MIRAPerformanceTimeline.mark("comments_open", detail: "post")
    activeCommentsPost = post
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.32, dampingFraction: 0.92)) {
        isCommentsPresented = true
      }
    }
  }

  private func presentSaveSheet(for post: MIRAPost) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    MIRAApplePerformanceLogger.event("modal_open", detail: "save_sheet")
    saveTargetPost = post
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
        isSaveSheetPresented = true
      }
    }
  }

  private func presentPostOptions(for post: MIRAPost) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    MIRAApplePerformanceLogger.event("modal_open", detail: "post_options")
    postOptionsTarget = post
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
        isPostOptionsPresented = true
      }
    }
  }

  private func reportPostFromOptions(_ post: MIRAPost, dismiss: @escaping () -> Void) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
      presentReport(for: post)
    }
  }

  private func presentReport(for post: MIRAPost) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    reportSourcePost = post
    reportTarget = MIRAReportTarget(
      targetType: "post",
      targetId: post.id,
      ownerUserId: post.userId,
      title: "Report post",
      subtitle: post.titleText
    )
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
        isReportSheetPresented = true
      }
    }
  }

  private func presentReport(for comment: MIRAComment) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
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

  private var mainHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Spacer()
      Button {
        isShowingCreatePost = true
      } label: {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
      .buttonStyle(.plain)
      NavigationLink(destination: NotificationNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "bell")
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, 0)
  }

  private var isFeedChromeHidden: Bool {
    isHeaderHidden || isFeedOverlayPresented
  }

  private var feedTabBarVisibility: Visibility {
    isFeedOverlayPresented ? .hidden : .visible
  }

  private var isMediaPlaybackSuppressed: Bool {
    !isTabActive || isFeedOverlayPresented
  }

  private var isFeedOverlayPresented: Bool {
    isCommentsPresented ||
      activeCommentsPost != nil ||
      isSaveSheetPresented ||
      saveTargetPost != nil ||
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
    .animation(.easeInOut(duration: 0.24), value: isShowingCaption)
  }

  @ViewBuilder
  private var mediaCarousel: some View {
    let mediaURLs = post.feedMediaURLs
    if mediaURLs.count == 1, let url = mediaURLs.first {
      RemoteMediaView(
        url: url,
        isVideo: url.isVideoURL,
        placeholderURL: mediaPlaceholderURL(for: 0, mediaURL: url),
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
        .animation(.easeInOut(duration: 0.16), value: selectedMediaIndex)
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
      if url.isVideoURL {
        if abs(index - selected) <= 1 {
          videoURLs.append(url)
        }
      } else if index >= selected && index <= min(mediaURLs.count - 1, selected + 2) {
        priorityImageURLs.append(url)
      } else {
        remainingImageURLs.append(url)
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
        await MIRAImagePrefetcher.prefetch(urls: fullImageURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: 10)
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
      CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary) {
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
    headlineText != nil || captionBodyText != nil || placeText != nil || taggedPeopleText != nil
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
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    withAnimation(.easeInOut(duration: 0.24)) {
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
        .overlay(alignment: .bottom) {
          if isFollowConfirmationVisible {
            Text("Following")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .frame(height: 20)
              .background(MIRATheme.Color.textPrimary.opacity(0.86))
              .clipShape(Capsule())
              .offset(y: 24)
              .transition(.opacity.combined(with: .scale(scale: 0.92)))
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(isSubmittingFollow)
      .accessibilityLabel(isSubmittingFollow || isFollowConfirmationVisible ? "Following" : "Follow")
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    } else if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api)) {
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
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api)) {
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
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    isSubmittingFollow = true
    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
      isFollowConfirmationVisible = true
    }

    Task {
      let didFollow = await onFollow()
      let holdNanoseconds: UInt64 = didFollow ? 700_000_000 : 180_000_000
      try? await Task.sleep(nanoseconds: holdNanoseconds)
      await MainActor.run {
        withAnimation(.easeInOut(duration: 0.18)) {
          isFollowConfirmationVisible = false
        }
        isSubmittingFollow = false
      }
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
    VStack(alignment: .leading, spacing: 0) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.28))
        .frame(width: 42, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 16)

      Text("Post options")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.bottom, 10)

      Button(action: onReport) {
        MainFeedPostOptionRow(
          title: "Report",
          subtitle: "Send this post to Captro moderation.",
          systemImage: "flag",
          tint: MIRATheme.Color.like
        )
      }
      .buttonStyle(.miraPress)

      Button(action: onNotInterested) {
        MainFeedPostOptionRow(
          title: "Not Interested",
          subtitle: "Hide this post and tune your feed.",
          systemImage: "hand.thumbsdown",
          tint: MIRATheme.Color.textSecondary
        )
      }
      .buttonStyle(.miraPress)

      ShareLink(item: shareURL, subject: Text(post.titleText), message: Text(post.titleText)) {
        MainFeedPostOptionRow(
          title: "Share",
          subtitle: "Share this Captro post.",
          systemImage: "square.and.arrow.up",
          tint: MIRATheme.Color.forest
        )
      }
      .buttonStyle(.miraPress)

      Spacer(minLength: 0)
    }
    .background(MIRATheme.Color.surface)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
          .animation(.easeOut(duration: 0.18), value: isReplyFocused)

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
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onReply()
          }
          .buttonStyle(.plain)

          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 42, height: 42)
        RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(width: 150, height: 16)
        Spacer()
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, MIRATheme.Space.sm)

      RoundedRectangle(cornerRadius: 0)
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(maxWidth: .infinity)
        .frame(height: MIRAMediaSizing.mainFeedHeight(for: []))

      HStack {
        RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(width: 60, height: 18)
        RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(width: 54, height: 18)
        Spacer()
        RoundedRectangle(cornerRadius: 16).fill(MIRATheme.Color.surfaceSoft).frame(width: 74, height: 34)
        RoundedRectangle(cornerRadius: 16).fill(MIRATheme.Color.surfaceSoft).frame(width: 92, height: 34)
      }
      .padding(MIRATheme.Space.md)
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
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

private struct MainFeedScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
