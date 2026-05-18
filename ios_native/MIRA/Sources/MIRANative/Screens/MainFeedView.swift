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
    do {
      var loaded: [MIRAPost] = try await api.get("/posts/feed?limit=\(firstPageLimit)")
      if loaded.isEmpty {
        loaded = (try? await api.get("/posts/world-board?limit=\(firstPageLimit)")) ?? []
      }
      let sorted = await sortedByNativeScore(loaded)
      posts = sorted
      canLoadMore = loaded.count >= firstPageLimit
      await MIRALocalJSONCache.save(sorted, key: feedCacheKey)
      MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "network")
      errorMessage = nil
    } catch {
      if let fallback: [MIRAPost] = try? await api.get("/posts/world-board?limit=\(firstPageLimit)"), !fallback.isEmpty {
        let sorted = await sortedByNativeScore(fallback)
        posts = sorted
        canLoadMore = fallback.count >= firstPageLimit
        await MIRALocalJSONCache.save(sorted, key: feedCacheKey)
        MIRAPerformanceTimeline.markOnce("time_to_first_real_home_item", detail: "fallback")
        errorMessage = nil
      } else {
        if posts.isEmpty { hasLoadedFreshFeed = false }
        errorMessage = "Could not load the feed. Pull back in a moment."
      }
    }
  }

  func loadMoreIfNeeded(after post: MIRAPost) async {
    guard canLoadMore, !isLoading, !isLoadingMore else { return }
    guard posts.suffix(3).contains(where: { $0.id == post.id }) else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let skip = posts.count
    do {
      var loaded: [MIRAPost] = try await api.get("/posts/feed?limit=\(firstPageLimit)&skip=\(skip)")
      if loaded.isEmpty {
        loaded = (try? await api.get("/posts/world-board?limit=\(firstPageLimit)&skip=\(skip)")) ?? []
      }
      guard !loaded.isEmpty else {
        canLoadMore = false
        return
      }
      let existing = Set(posts.map(\.id))
      let unique = loaded.filter { !existing.contains($0.id) }
      guard !unique.isEmpty else {
        canLoadMore = false
        return
      }
      posts.append(contentsOf: await sortedByNativeScore(unique))
      canLoadMore = loaded.count >= firstPageLimit
      cacheCurrentPosts()
    } catch {
      // Keep the visible feed stable; pagination can retry on the next near-bottom cell.
    }
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
          likesCount: response.likesCount ?? nextCount
        )
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
          saved: response.saved ?? nextSaved,
          savesCount: response.savesCount ?? nextCount
        )
        cacheCurrentPosts()
      }
    } catch {
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = previous
      }
    }
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
  @State private var selectedPost: MIRAPost?
  @State private var activeVideoPostID: String?
  @State private var isHeaderHidden = false
  @State private var previousScrollMinY: CGFloat?
  @State private var scrollIntentDistance: CGFloat = 0
  @State private var scrollIntentDirection = 0

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
                  isVideoActive: post.id == activeVideoPostID,
                  onOpen: { selectedPost = post },
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
            }
          }
          .padding(.bottom, MIRATheme.Space.xxl)
        }
        .coordinateSpace(name: "mainFeedScroll")

        if !isHeaderHidden {
          mainHeader
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(10)
        }
      }
      .background(MIRATheme.Color.appBackground)
      .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: isHeaderHidden)
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(item: $selectedPost) { post in
        PostDetailNativeView(post: post, api: model.api)
      }
      .task { await model.load() }
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
    guard abs(delta) > 2 else { return }

    if minY > -10 {
      isHeaderHidden = false
      scrollIntentDistance = 0
      scrollIntentDirection = 0
      return
    }

    let direction = delta < 0 ? 1 : -1
    if direction != scrollIntentDirection {
      scrollIntentDirection = direction
      scrollIntentDistance = 0
    }
    scrollIntentDistance += abs(delta)

    if direction == 1 && scrollIntentDistance > 18 {
      isHeaderHidden = true
    } else if direction == -1 && scrollIntentDistance > 44 {
      isHeaderHidden = false
    }
  }

  private func updateActiveVideo(_ visibility: [MainPostVisibility]) {
    let candidate = visibility
      .filter { $0.hasVideo && $0.visibleRatio >= 0.60 }
      .max { $0.visibleRatio < $1.visibleRatio }
    let nextID = candidate?.id
    if activeVideoPostID != nextID {
      activeVideoPostID = nextID
      MIRAMemoryMetrics.log("main_feed_video_switch")
    }
  }

  private var mainHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Spacer()
      NavigationLink(destination: CreatePostNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
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
  let isVideoActive: Bool
  let onOpen: () -> Void
  let onLike: () -> Void
  let onSave: () -> Void
  let onFollow: () -> Void

  private var mediaHeight: CGFloat {
    MIRAMediaSizing.mainFeedHeight(for: post.mediaURLs, aspectRatios: post.mediaHeightToWidthRatios)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      postHeader

      if !post.mediaURLs.isEmpty {
        MIRAAdaptiveMediaView(
          urls: post.mediaURLs,
          maxSingleImageHeight: mediaHeight,
          carouselHeight: mediaHeight,
          singleImageContentMode: .fill,
          shouldPlay: isVideoActive
        )
        .frame(maxWidth: .infinity)
        .frame(height: mediaHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
      }

      HStack(spacing: MIRATheme.Space.md) {
        CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0, tint: post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary, action: onLike)
        CompactPostAction(systemImage: post.viewerSaved ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0, tint: post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary, action: onSave)
        Spacer()
        CompactTextAction("View", action: onOpen)
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

      Text(post.userUsername ?? post.userFullName ?? "mira")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
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
