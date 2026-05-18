import SwiftUI
import UIKit

@MainActor
final class MainFeedModel: ObservableObject {
  @Published var posts: [MIRAPost] = []
  @Published var isLoading = false
  @Published var errorMessage: String?

  let api: MIRAAPIClient
  private let isoDateFormatter = ISO8601DateFormatter()

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    if posts.isEmpty { isLoading = true }
    defer { isLoading = false }
    do {
      var loaded: [MIRAPost] = try await api.get("/posts/feed?limit=36")
      if loaded.isEmpty {
        loaded = (try? await api.get("/posts/world-board?limit=36")) ?? []
      }
      posts = loaded.sorted { nativeScore($0) > nativeScore($1) }
      errorMessage = nil
    } catch {
      if let fallback: [MIRAPost] = try? await api.get("/posts/world-board?limit=36"), !fallback.isEmpty {
        posts = fallback.sorted { nativeScore($0) > nativeScore($1) }
        errorMessage = nil
      } else {
        errorMessage = "Could not load the feed. Pull back in a moment."
      }
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
    } catch {
      posts = previous
    }
  }

  private func nativeScore(_ post: MIRAPost) -> Double {
    MIRANativeEngine.scoreFeedItem(
      likes: Double(post.likesCount ?? 0),
      comments: Double(post.commentsCount ?? 0),
      saves: Double(post.savesCount ?? 0),
      shares: Double(post.sharesCount ?? 0),
      views: Double(post.viewsCount ?? 0),
      ageHours: ageHours(from: post.createdAt),
      isFollowed: post.isFollowing == true,
      isVideo: post.mediaURLs.first?.isVideoURL == true
    )
  }

  private func ageHours(from value: String?) -> Double {
    guard let value, let date = isoDateFormatter.date(from: value) else { return 24 }
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
    MIRAMediaSizing.mainFeedHeight(for: post.mediaURLs)
  }

  private var cardWidth: CGFloat {
    UIScreen.main.bounds.width
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
        .frame(width: cardWidth, height: mediaHeight)
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
    .frame(width: cardWidth, alignment: .topLeading)
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
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 42, height: 42)
        RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(width: 160, height: 18)
      }
      RoundedRectangle(cornerRadius: 0)
        .fill(MIRATheme.Color.surfaceSoft)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .redacted(reason: .placeholder)
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
