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
    let me: MIRAUser? = try? await api.get("/auth/me")
    currentUserId = me?.id
    currentUsername = me?.username
  }

  func canDelete(_ post: MIRAPost) -> Bool {
    // If auth ownership is still loading, keep Delete visible and let the backend
    // enforce ownership. This avoids hiding the owner action because /auth/me
    // resolved a moment after the menu was opened.
    if currentUserId == nil && currentUsername == nil {
      return true
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
  @StateObject private var model: MainFeedModel
  @State private var activeVideoPostID: String?
  @State private var isHeaderHidden = false
  @State private var previousScrollMinY: CGFloat?
  @State private var scrollIntentDistance: CGFloat = 0
  @State private var scrollIntentDirection = 0
  @State private var isShowingCreatePost = false
  @State private var activeCommentsPost: MIRAPost?
  @State private var activeMediaViewer: MIRAMediaViewerPresentation?

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
                  onComment: { activeCommentsPost = post },
                  onOpenMedia: { index in
                    activeMediaViewer = MIRAMediaViewerPresentation(urls: post.mediaURLs, initialIndex: index)
                  },
                  onFollow: { Task { await model.toggleFollowAuthor(post) } },
                  onNotInterested: { model.hidePost(post) },
                  onReport: { Task { await model.reportPost(post) } },
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
          .offset(y: isHeaderHidden ? -84 : 0)
          .opacity(isHeaderHidden ? 0 : 1)
          .allowsHitTesting(!isHeaderHidden)
          .zIndex(10)
          .animation(.easeInOut(duration: 0.24), value: isHeaderHidden)
      }
      .background(MIRATheme.Color.appBackground)
      .overlay {
        if let viewer = activeMediaViewer {
          MIRAFullScreenMediaViewer(
            urls: viewer.urls,
            initialIndex: viewer.initialIndex,
            onClose: { activeMediaViewer = nil }
          )
          .transition(.opacity)
          .zIndex(50)
        }
      }
      .animation(.easeInOut(duration: 0.24), value: activeMediaViewer?.id)
      .miraScreenEnter(.tab)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(activeMediaViewer == nil ? .visible : .hidden, for: .tabBar)
      .statusBarHidden(true)
      .fullScreenCover(isPresented: $isShowingCreatePost) {
        CreatePostNativeView(api: model.api)
      }
      .sheet(item: $activeCommentsPost) { post in
        MainFeedCommentsSheet(post: post, api: model.api)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
          .presentationCornerRadius(28)
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
}

private struct MainNativePostCard: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  let onLike: () -> Void
  let onSave: () -> Void
  let onComment: () -> Void
  let onOpenMedia: (Int) -> Void
  let onFollow: () -> Void
  let onNotInterested: () -> Void
  let onReport: () -> Void
  let canDelete: Bool
  let onDelete: () -> Void
  let onMakePublic: () -> Void
  let onMakePrivate: () -> Void
  @State private var selectedMediaIndex = 0
  @State private var isShowingCaption = false

  private var mediaHeight: CGFloat {
    return MIRAMediaSizing.mainFeedHeight(
      for: post.mediaURLs,
      aspectRatios: post.mediaHeightToWidthRatios
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

      if isShowingCaption {
        captionBlock
          .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
      }

      HStack(spacing: MIRATheme.Space.md) {
        CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary, action: onLike)
        CompactPostAction(systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0, tint: post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary, action: onSave)
        CompactPostAction(
          systemImage: "bubble.left",
          value: post.commentsCount ?? 0,
          tint: MIRATheme.Color.textSecondary,
          action: onComment
        )
        Spacer()
        if hasCaptionContent {
          CompactTextAction(isShowingCaption ? "Less" : "More", action: toggleCaption)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
      .padding(.bottom, MIRATheme.Space.md)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(MIRATheme.Color.surface)
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: MainPostVisibilityPreferenceKey.self,
          value: [MainPostVisibility(id: post.id, visibleRatio: visibleRatio(in: proxy), hasVideo: post.mediaURLs.contains { $0.isVideoURL })]
        )
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
      .frame(height: mediaHeight)
      .clipped()
      .contentShape(Rectangle())
      .onTapGesture { onOpenMedia(0) }
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
            .contentShape(Rectangle())
            .onTapGesture { onOpenMedia(index) }
            .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(height: mediaHeight)
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

  private var captionBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let headlineText {
        Text(headlineText)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let captionText {
        Text(captionText)
          .font(.system(size: 15, weight: .regular))
          .lineSpacing(3)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.md)
    .padding(.bottom, MIRATheme.Space.xs)
  }

  private var hasCaptionContent: Bool {
    headlineText != nil || captionText != nil || !captionMetadataLines.isEmpty
  }

  private var headlineText: String? {
    let value = post.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private var captionText: String? {
    let base = ((post.caption?.isEmpty == false ? post.caption : post.content) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let values = ([base] + captionMetadataLines).filter { !$0.isEmpty }
    return values.isEmpty ? nil : values.joined(separator: "\n\n")
  }

  private var captionMetadataLines: [String] {
    var lines: [String] = []
    if let place = post.placeDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
      lines.append("At \(place)")
    }
    let people = (post.taggedUsers ?? [])
      .compactMap { taggedUserName($0) }
      .prefix(6)
      .joined(separator: ", ")
    if !people.isEmpty {
      lines.append("With \(people)")
    }
    return lines
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
      Button(action: onFollow) {
        MIRAFollowAvatar(url: post.userProfileImage, size: 42, isFollowing: post.viewerFollowing)
      }
      .buttonStyle(.plain)

      if let userId = post.userId, !userId.isEmpty {
        NavigationLink(destination: UserProfileNativeView(userId: userId, api: api)) {
          Text(post.userUsername ?? post.userFullName ?? "mira")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      } else {
        Text(post.userUsername ?? post.userFullName ?? "mira")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
      }
      Spacer()
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
          .frame(width: 38, height: 38)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, MIRATheme.Space.sm)
  }
}

private struct MainFeedCommentsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  @FocusState private var isReplyFocused: Bool

  init(post: MIRAPost, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  var body: some View {
    VStack(spacing: 0) {
      sheetHeader

      ScrollView {
        LazyVStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          if model.isLoadingComments && model.comments.isEmpty {
            ForEach(0..<5, id: \.self) { _ in
              MainFeedCommentSkeleton()
            }
          } else if model.comments.isEmpty {
            MIRAEmptyState(title: "No comments yet", message: "Be the first to reply.", systemImage: "bubble.left")
              .frame(maxWidth: .infinity)
              .padding(.top, 32)
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
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      commentComposer
    }
    .background(MIRATheme.Color.surface.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 2) {
          Text("Comments")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text("\(model.post.commentsCount ?? model.comments.count)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        Spacer()
        Button {
          dismiss()
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
    HStack(spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: model.post.userProfileImage, size: 34)
      TextField("Add comment...", text: $draft, axis: .vertical)
        .font(.system(size: 15, weight: .regular))
        .focused($isReplyFocused)
        .lineLimit(1...4)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, 10)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .onSubmit(sendComment)

      Button(action: sendComment) {
        Image(systemName: "arrow.up")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(canSend ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.28))
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)
      .disabled(!canSend)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func sendComment() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    Task { await model.sendComment(text) }
  }
}

private struct MainFeedCommentRow: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 34)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(comment.user?.displayName ?? "user")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
          if let createdAt = comment.createdAt {
            Text(mainFeedCommentAge(createdAt))
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.8))
          }
        }
        Text(comment.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      HStack(spacing: 4) {
        Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
          .font(.system(size: 16, weight: .regular))
        Text(compact(comment.likesCount ?? 0))
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundStyle(comment.likedByMe == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary)
      .frame(minWidth: 44, minHeight: 34)
    }
  }
}

private struct MainFeedCommentSkeleton: View {
  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 34, height: 34)
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
        .frame(width: UIScreen.main.bounds.width, height: MIRAMediaSizing.mainFeedHeight(for: []))

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
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 19, weight: .regular))
        Text(compact(value))
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundStyle(tint)
      .frame(minHeight: 36)
    }
    .buttonStyle(.plain)
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
      }
      .foregroundStyle(MIRATheme.Color.forest)
      .frame(height: 34)
      .padding(.horizontal, MIRATheme.Space.md)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
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
  if value >= 1_000_000 { return "\(value / 1_000_000)M" }
  if value >= 1_000 { return "\(value / 1_000)K" }
  return "\(value)"
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

private struct MainFeedScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
