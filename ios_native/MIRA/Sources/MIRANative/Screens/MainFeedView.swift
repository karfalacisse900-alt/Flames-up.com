import SwiftUI
import UIKit

@MainActor
final class MainFeedModel: ObservableObject {
  @Published var posts: [MIRAPost] = []
  @Published var isLoading = true
  @Published var isLoadingMore = false
  @Published var errorMessage: String?

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

public struct MainFeedView: View {
  @StateObject private var model: MainFeedModel
  @State private var activeVideoPostID: String?
  @State private var isHeaderHidden = false
  @State private var previousScrollMinY: CGFloat?
  @State private var scrollIntentDistance: CGFloat = 0
  @State private var scrollIntentDirection = 0
  @State private var isShowingCreatePost = false

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
                  onFollow: { Task { await model.toggleFollowAuthor(post) } }
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
      .toolbar(.hidden, for: .navigationBar)
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
  let onFollow: () -> Void
  @State private var measuredRatios: [String: CGFloat] = [:]
  @State private var selectedMediaIndex = 0
  @State private var isShowingCaption = false

  private var mediaHeight: CGFloat {
    let liveRatios = post.mediaURLs.compactMap { measuredRatios[$0] }
    return MIRAMediaSizing.mainFeedHeight(
      for: post.mediaURLs,
      aspectRatios: liveRatios + post.mediaHeightToWidthRatios
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      postHeader

      if !post.mediaURLs.isEmpty {
        mediaCarousel
      }

      if isShowingCaption {
        captionBlock
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      HStack(spacing: MIRATheme.Space.md) {
        CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary, action: onLike)
        CompactPostAction(systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0, tint: post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary, action: onSave)
        Spacer()
        if hasCaptionContent {
          CompactTextAction(isShowingCaption ? "Less" : "More", action: toggleCaption)
        }
        CompactShareAction(post: post)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
      .padding(.bottom, MIRATheme.Space.md)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .clipped()
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
    .transaction { transaction in
      transaction.animation = nil
    }
    .onChange(of: post.id) { _, _ in selectedMediaIndex = 0 }
    .onChange(of: post.mediaURLs) { _, urls in
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: post.id) { _, _ in isShowingCaption = false }
  }

  @ViewBuilder
  private var mediaCarousel: some View {
    if post.mediaURLs.count == 1, let url = post.mediaURLs.first {
      RemoteMediaView(
        url: url,
        isVideo: url.isVideoURL,
        contentMode: .fill,
        shouldPlay: isVideoActive,
        onMeasuredRatio: { recordMeasuredRatio(url: url, ratio: $0) }
      )
      .frame(maxWidth: .infinity)
      .frame(height: mediaHeight)
      .clipped()
      .contentShape(Rectangle())
    } else {
      VStack(spacing: 7) {
        TabView(selection: $selectedMediaIndex) {
          ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { index, url in
            RemoteMediaView(
              url: url,
              isVideo: url.isVideoURL,
              contentMode: .fill,
              shouldPlay: isVideoActive && selectedMediaIndex == index,
              onMeasuredRatio: { recordMeasuredRatio(url: url, ratio: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
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
    headlineText != nil || captionText != nil
  }

  private var headlineText: String? {
    let value = post.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private var captionText: String? {
    let value = ((post.caption?.isEmpty == false ? post.caption : post.content) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private func toggleCaption() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    withAnimation(.easeInOut(duration: 0.2)) {
      isShowingCaption.toggle()
    }
  }

  private func visibleRatio(in proxy: GeometryProxy) -> CGFloat {
    let frame = proxy.frame(in: .global)
    let screen = UIScreen.main.bounds
    let visibleHeight = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
    return max(0, min(1, visibleHeight / max(frame.height, 1)))
  }

  private func recordMeasuredRatio(url: String, ratio: CGFloat) {
    guard ratio.isFinite, ratio > 0 else { return }
    let clamped = min(max(ratio, 1.0 / 1.91), 16.0 / 9.0)
    if abs((measuredRatios[url] ?? 0) - clamped) > 0.01 {
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        measuredRatios[url] = clamped
      }
    }
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
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, MIRATheme.Space.sm)
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

private struct MediaCarouselNative: View {
  let urls: [String]

  var body: some View {
    TabView {
      ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
        RemoteMediaView(url: url, isVideo: url.isVideoURL)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
    .frame(maxWidth: .infinity)
    .frame(height: min(UIScreen.main.bounds.width * 1.25, 620))
    .background(MIRATheme.Color.surfaceSoft)
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

private struct CompactShareAction: View {
  let post: MIRAPost

  var body: some View {
    ShareLink(item: shareURL(for: post), subject: Text(post.titleText), message: Text(post.titleText)) {
      HStack(spacing: 6) {
        Image(systemName: "paperplane")
          .font(.system(size: 12, weight: .semibold))
        Text("Share")
          .font(.system(size: 13, weight: .semibold))
      }
      .foregroundStyle(.white)
      .frame(height: 34)
      .padding(.horizontal, MIRATheme.Space.md)
      .background(MIRATheme.Color.forest)
      .clipShape(Capsule())
    }
  }
}

private func compact(_ value: Int) -> String {
  if value >= 1_000_000 { return "\(value / 1_000_000)M" }
  if value >= 1_000 { return "\(value / 1_000)K" }
  return "\(value)"
}

private func shareURL(for post: MIRAPost) -> URL {
  MIRAProductionBackend.siteURL("post/\(post.id)")
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
