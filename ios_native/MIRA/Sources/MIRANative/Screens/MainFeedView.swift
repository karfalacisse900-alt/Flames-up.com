import SwiftUI
import UIKit

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
  private var canLoadMore = true
  private var isLoadingCurrentUser = false
  private let firstPageLimit = 8
  private let paginationTriggerWindow = 5

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load(forceRefresh: Bool = false) async {
    if currentUserId == nil && currentUsername == nil {
      Task { await loadCurrentUserIfNeeded() }
    }
    if !forceRefresh && hasLoadedFreshFeed && !posts.isEmpty { return }
    MIRAPerformanceTimeline.mark("home_load_start", detail: forceRefresh ? "refresh" : "normal")

    if posts.isEmpty, let cached: [MIRAPost] = await MIRALocalJSONCache.load([MIRAPost].self, key: feedCacheKey) {
      // Cached feed is already stored in display order, so show it immediately.
      posts = cached
      MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "cache")
      errorMessage = nil
      isLoading = false
    }

    if posts.isEmpty { isLoading = true }
    hasLoadedFreshFeed = true
    defer { isLoading = false }
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
    posts = sorted
    canLoadMore = loaded.count >= firstPageLimit
    await MIRALocalJSONCache.save(sorted, key: feedCacheKey)
    MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "network")
    errorMessage = nil
    prefetchNextPageIfNeeded(afterInitialCount: sorted.count)
  }

  func loadMoreIfNeeded(after post: MIRAPost) async {
    guard !isLoading else { return }
    guard posts.suffix(paginationTriggerWindow).contains(where: { $0.id == post.id }) else { return }
    await loadNextPage(reason: "scroll")
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

  func toggleSave(_ post: MIRAPost) async {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    let nextSaved = !previous.viewerSaved
    let nextCount = max(0, (previous.savesCount ?? 0) + (nextSaved ? 1 : -1))
    posts[index] = previous.updating(saved: nextSaved, savesCount: nextCount)

    do {
      let response: PostSaveResponse
      if nextSaved {
        response = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: "My Library"))
      } else {
        response = try await api.delete("/library/save/\(post.id)")
      }
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = posts[currentIndex].updating(
          liked: response.liked,
          likesCount: response.likesCount,
          commentsCount: response.commentsCount,
          saved: response.saved ?? nextSaved,
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

  func toggleFollowAuthor(_ post: MIRAPost) async {
    guard canFollowAuthor(post) else { return }
    guard let userId = post.userId, !userId.isEmpty else { return }
    let previous = posts
    let current = posts.first(where: { $0.id == post.id }) ?? post
    let nextFollowing = !current.viewerFollowing
    posts = posts.map { $0.userId == userId ? $0.updating(following: nextFollowing) : $0 }

    do {
      let response: FollowResponse = try await api.post("/users/\(userId)/follow", body: FollowBody(following: nextFollowing))
      let serverFollowing = response.following ?? nextFollowing
      posts = posts.map { $0.userId == userId ? $0.updating(following: serverFollowing) : $0 }
      cacheCurrentPosts()
    } catch {
      posts = previous
    }
  }

  func canFollowAuthor(_ post: MIRAPost) -> Bool {
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

  func hidePost(_ post: MIRAPost) {
    posts.removeAll { $0.id == post.id }
    cacheCurrentPosts()
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
    Task { await MIRALocalJSONCache.save(snapshot, key: feedCacheKey) }
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
              isVideo: post.mediaURLs.first?.isVideoURL == true
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var model: MainFeedModel
  @State private var activeVideoPostID: String?
  @State private var isHeaderHidden = false
  @State private var previousScrollMinY: CGFloat?
  @State private var scrollIntentDistance: CGFloat = 0
  @State private var scrollIntentDirection = 0
  @State private var isShowingCreatePost = false
  @State private var activeCommentsPost: MIRAPost?
  @State private var isCommentsPresented = false

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: MainFeedModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        ScrollView {
          GeometryReader { proxy in
            Color.clear.preference(key: MainFeedScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("mainFeedScroll")).minY)
          }
          .frame(height: 0)

          LazyVStack(spacing: 0) {
            if model.isLoading && model.posts.isEmpty {
              ForEach(0..<4, id: \.self) { _ in MainPostSkeleton() }
            } else if model.posts.isEmpty {
              MIRAEmptyState(title: "No posts yet", message: "Fresh moments will show here when they are ready.", systemImage: "sparkles")
                .padding(.top, 80)
            } else {
              ForEach(model.posts) { post in
                MainNativePostCard(
                  post: post,
                  api: model.api,
                  isVideoActive: post.id == activeVideoPostID,
                  onLike: { Task { await model.toggleLike(post) } },
                  onSave: { Task { await model.toggleSave(post) } },
                  onComment: { presentComments(for: post) },
                  onFollow: { Task { await model.toggleFollowAuthor(post) } },
                  onNotInterested: { model.hidePost(post) },
                  onReport: { Task { await model.reportPost(post) } },
                  canFollowAuthor: model.canFollowAuthor(post),
                  canDelete: model.canDelete(post),
                  onDelete: { Task { await model.deletePost(post) } },
                  onMakePublic: { Task { await model.updatePostVisibility(post, visibility: "public") } },
                  onMakePrivate: { Task { await model.updatePostVisibility(post, visibility: "private") } }
                )
                .onAppear {
                  Task { await model.loadMoreIfNeeded(after: post) }
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
        .simultaneousGesture(
          DragGesture(minimumDistance: 8)
            .onChanged(handleFeedDrag)
        )

        mainHeader
          .offset(y: isFeedChromeHidden ? -84 : 0)
          .opacity(isFeedChromeHidden ? 0 : 1)
          .allowsHitTesting(!isFeedChromeHidden)
          .zIndex(10)
          .animation(.easeInOut(duration: 0.24), value: isFeedChromeHidden)
      }
      .background(MIRATheme.Color.appBackground)
      .overlay {
        if let post = activeCommentsPost {
          MainFeedCommentsOverlay(
            post: post,
            api: model.api,
            isPresented: isCommentsPresented,
            onClose: closeComments
          )
          .zIndex(40)
        }
      }
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(feedTabBarVisibility, for: .tabBar)
      .statusBarHidden(true)
      .fullScreenCover(isPresented: $isShowingCreatePost) {
        CreatePostNativeView(api: model.api)
      }
      .task { await model.load() }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
        guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
        model.applyEngagementUpdate(update)
      }
      .onPreferenceChange(MainFeedScrollOffsetPreferenceKey.self, perform: handleScroll)
      .onPreferenceChange(MainPostVisibilityPreferenceKey.self, perform: updateActiveVideo)
    }
  }

  private func handleScroll(_ minY: CGFloat) {
    guard let previousScrollMinY else {
      previousScrollMinY = minY
      return
    }

    let delta = minY - previousScrollMinY
    self.previousScrollMinY = minY
    guard abs(delta) > 1 else { return }

    if minY > -10 {
      isHeaderHidden = false
      scrollIntentDistance = 0
      scrollIntentDirection = 0
      return
    }

    let direction = delta < 0 ? 1 : -1
    if direction != scrollIntentDirection {
      scrollIntentDirection = direction
      scrollIntentDistance = abs(delta)
    } else {
      scrollIntentDistance += abs(delta)
    }

    if direction == 1 && minY < -18 && scrollIntentDistance > 10 {
      isHeaderHidden = true
      scrollIntentDistance = 0
    } else if direction == -1 && scrollIntentDistance > 10 {
      isHeaderHidden = false
      scrollIntentDistance = 0
    }
  }

  private func handleFeedDrag(_ value: DragGesture.Value) {
    guard abs(value.translation.height) > abs(value.translation.width) else { return }
    if value.translation.height < -14 {
      isHeaderHidden = true
    } else if value.translation.height > 10 {
      isHeaderHidden = false
    }
  }

  private func updateActiveVideo(_ visibility: [MainPostVisibility]) {
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

  private var commentSheetAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.02)
  }

  private var commentSheetDismissDelay: Double {
    reduceMotion ? 0.08 : 0.28
  }

  private func presentComments(for post: MIRAPost) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    activeCommentsPost = post
    DispatchQueue.main.async {
      withAnimation(self.commentSheetAnimation) {
        self.isCommentsPresented = true
      }
    }
  }

  private func closeComments() {
    guard activeCommentsPost != nil else { return }
    let closingPostID = activeCommentsPost?.id
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    withAnimation(commentSheetAnimation) {
      isCommentsPresented = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + commentSheetDismissDelay) {
      guard !self.isCommentsPresented, self.activeCommentsPost?.id == closingPostID else { return }
      self.activeCommentsPost = nil
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
    isHeaderHidden || isCommentsPresented || activeCommentsPost != nil
  }

  private var feedTabBarVisibility: Visibility {
    (isCommentsPresented || activeCommentsPost != nil) ? .hidden : .visible
  }
}

private struct MainNativePostCard: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let onLike: () -> Void
  let onSave: () -> Void
  let onComment: () -> Void
  let onFollow: () -> Void
  let onNotInterested: () -> Void
  let onReport: () -> Void
  let canFollowAuthor: Bool
  let canDelete: Bool
  let onDelete: () -> Void
  let onMakePublic: () -> Void
  let onMakePrivate: () -> Void
  @State private var selectedMediaIndex = 0
  @State private var isShowingCaption = false
  @State private var measuredCardWidth = UIScreen.main.bounds.width
  @GestureState private var isPostMenuPressed = false

  private var mediaHeight: CGFloat {
    return MIRAMediaSizing.mainFeedHeight(
      for: post.mediaURLs,
      aspectRatios: post.mediaHeightToWidthRatios,
      width: measuredCardWidth
    )
  }

  private var normalizedVisibility: String {
    post.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "public"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      postHeader

      if !post.mediaURLs.isEmpty {
        mediaCarousel
      }

      actionRow

      if hasCaptionContent {
        captionBlock
          .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
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
          value: [MainPostVisibility(id: post.id, visibleRatio: visibleRatio(in: proxy), hasVideo: post.mediaURLs.contains { $0.isVideoURL })]
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
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.75)
    }
    .onChange(of: post.id) { _, _ in selectedMediaIndex = 0 }
    .onChange(of: post.mediaURLs) { _, urls in
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: post.id) { _, _ in isShowingCaption = false }
    .animation(.easeInOut(duration: 0.24), value: isShowingCaption)
  }

  @ViewBuilder
  private var mediaCarousel: some View {
    if post.mediaURLs.count == 1, let url = post.mediaURLs.first {
      RemoteMediaView(
        url: url,
        isVideo: url.isVideoURL,
        contentMode: .fill,
        shouldPlay: isVideoActive
      )
      .frame(maxWidth: .infinity)
      .frame(minHeight: mediaHeight, maxHeight: mediaHeight)
      .background(MIRATheme.Color.surfaceSoft)
      .clipped()
    } else {
      VStack(spacing: 7) {
        TabView(selection: $selectedMediaIndex) {
          ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { index, url in
            RemoteMediaView(
              url: url,
              isVideo: url.isVideoURL,
              contentMode: .fill,
              shouldPlay: isVideoActive && selectedMediaIndex == index
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(minHeight: mediaHeight, maxHeight: mediaHeight)
        .background(MIRATheme.Color.surfaceSoft)

        HStack(spacing: 6) {
          ForEach(post.mediaURLs.indices, id: \.self) { index in
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

  private var actionRow: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: MIRATheme.Space.sm) {
        engagementButtons
        Spacer(minLength: MIRATheme.Space.xs)
        captionExpansionButton
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: MIRATheme.Space.sm) {
          engagementButtons
          Spacer(minLength: 0)
        }
        captionExpansionButton
      }
    }
    .lineLimit(1)
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, hasCaptionContent ? MIRATheme.Space.xs : MIRATheme.Space.md)
  }

  private var engagementButtons: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary, action: onLike)
      CompactPostAction(systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0, tint: post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary, action: onSave)
      CompactPostAction(
        systemImage: "bubble.left",
        value: post.commentsCount ?? 0,
        tint: MIRATheme.Color.textSecondary,
        action: onComment
      )
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
    VStack(alignment: .leading, spacing: 6) {
      if let headlineText {
        Text(headlineText)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(isShowingCaption ? nil : 1)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let captionBodyText {
        Text(captionBodyText)
          .font(.system(size: 15, weight: .regular))
          .lineSpacing(3)
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
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, MIRATheme.Space.md)
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

      postMenu
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var authorAvatar: some View {
    if canFollowAuthor {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onFollow()
      } label: {
        MIRAFollowAvatar(url: post.userProfileImage, size: 42, isFollowing: post.viewerFollowing)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(post.viewerFollowing ? "Following" : "Follow")
    } else if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api)) {
        RemoteAvatar(url: post.userProfileImage, size: 42)
      }
      .buttonStyle(.plain)
    } else {
      RemoteAvatar(url: post.userProfileImage, size: 42)
    }
  }

  @ViewBuilder
  private var authorIdentity: some View {
    if let userId = post.userId, !userId.isEmpty {
      NavigationLink(destination: UserProfileNativeView(userId: userId, api: api)) {
        authorIdentityLabel
      }
      .buttonStyle(.plain)
    } else {
      authorIdentityLabel
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
    Menu {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onNotInterested()
      } label: {
        Label("Not interested", systemImage: "eye.slash")
      }

      if canDelete {
        if normalizedVisibility != "public" {
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMakePublic()
          } label: {
            Label("Make post public", systemImage: "globe")
          }
        }

        if normalizedVisibility != "private" {
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMakePrivate()
          } label: {
            Label("Make post private", systemImage: "lock")
          }
        }

        Button(role: .destructive) {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          onDelete()
        } label: {
          Label("Delete post", systemImage: "trash")
        }
      }

      Button(role: .destructive) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onReport()
      } label: {
        Label("Report", systemImage: "flag")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 36, height: 36)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
        .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
        .contentShape(Circle())
        .scaleEffect(isPostMenuPressed ? 0.90 : 1)
        .rotationEffect(.degrees(isPostMenuPressed ? 8 : 0))
        .shadow(color: .black.opacity(isPostMenuPressed ? 0.10 : 0.03), radius: isPostMenuPressed ? 8 : 4, x: 0, y: isPostMenuPressed ? 3 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.68), value: isPostMenuPressed)
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .updating($isPostMenuPressed) { _, state, _ in
          state = true
        }
    )
    .buttonStyle(.miraPress)
  }

  private var authorNameLabel: some View {
    Text(post.userUsername ?? post.userFullName ?? "mira")
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var authorSubtitle: String? {
    let username = post.userUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let subtitle = post.userFullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !subtitle.isEmpty, subtitle != username else { return nil }
    return subtitle
  }
}

private struct MainFeedCommentsOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let post: MIRAPost
  let api: MIRAAPIClient
  let isPresented: Bool
  let onClose: () -> Void
  @GestureState private var dragOffset: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let height = sheetHeight(for: proxy)
      ZStack(alignment: .bottom) {
        Color.black
          .opacity(isPresented ? 0.18 : 0)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture {
            guard isPresented else { return }
            onClose()
          }

        MainFeedCommentsSheet(post: post, api: api, onClose: onClose)
          .frame(maxWidth: .infinity)
          .frame(height: height)
          .background(MIRATheme.Color.surface)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.sheet, style: .continuous))
          .shadow(color: .black.opacity(isPresented ? 0.16 : 0), radius: 24, x: 0, y: -8)
          .padding(.horizontal, proxy.size.width > 700 ? 76 : 0)
          .offset(y: sheetOffset(height: height, safeAreaBottom: proxy.safeAreaInsets.bottom))
          .simultaneousGesture(sheetDragGesture(threshold: min(180, height * 0.24)))
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    .allowsHitTesting(isPresented)
    .animation(sheetAnimation, value: isPresented)
    .animation(sheetAnimation, value: dragOffset)
  }

  private var sheetAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.02)
  }

  private func sheetHeight(for proxy: GeometryProxy) -> CGFloat {
    let available = max(320, proxy.size.height - 10)
    let preferred = proxy.size.height * 0.76
    return min(max(360, preferred), min(720, available))
  }

  private func sheetOffset(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
    guard isPresented else { return height + safeAreaBottom + 56 }
    return max(0, dragOffset)
  }

  private func sheetDragGesture(threshold: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 18, coordinateSpace: .global)
      .updating($dragOffset) { value, state, _ in
        guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
        state = value.translation.height
      }
      .onEnded { value in
        let downward = value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 1.35
        if downward {
          onClose()
        }
      }
  }
}

private struct MainFeedCommentsSheet: View {
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  @State private var isSending = false
  @FocusState private var isReplyFocused: Bool
  let onClose: () -> Void

  init(post: MIRAPost, api: MIRAAPIClient, onClose: @escaping () -> Void) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
    self.onClose = onClose
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
            MIRAEmptyState(title: "No comments yet", message: "Start the conversation.", systemImage: "bubble.left")
              .frame(maxWidth: .infinity)
              .padding(.top, 28)
          } else {
            ForEach(model.comments) { comment in
              MainFeedCommentRow(comment: comment)
            }
          }
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, 18)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
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
          Text("Comments")
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
      HStack(alignment: .bottom, spacing: MIRATheme.Space.sm) {
        RemoteAvatar(url: model.post.userProfileImage, size: 34)
          .padding(.bottom, 2)
        TextField("Add a comment...", text: $draft, axis: .vertical)
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
      let didSend = await model.sendComment(text)
      if !didSend {
        draft = text
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

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 34)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 7) {
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
          }
          .buttonStyle(.plain)

          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
              Text(compact(comment.likesCount ?? 0))
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(comment.likedByMe == true ? MIRATheme.Color.like : MIRATheme.Color.textMuted)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.leading, MIRATheme.Space.xs)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
    }
    .padding(.leading, comment.parentId == nil ? 0 : 42)
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
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 19, weight: .regular))
        Text(compact(value))
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundStyle(tint)
      .frame(minHeight: 36)
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
      .frame(height: 34)
      .padding(.horizontal, MIRATheme.Space.md)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
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
