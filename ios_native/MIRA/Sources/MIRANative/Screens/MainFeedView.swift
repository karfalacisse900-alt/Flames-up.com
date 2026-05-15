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
      let loaded: [MIRAPost] = try await api.get("/posts/world-board?limit=36")
      posts = loaded.sorted { nativeScore($0) > nativeScore($1) }
      errorMessage = nil
    } catch {
      errorMessage = "Could not load the feed. Pull back in a moment."
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

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: MainFeedModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        mainHeader

        ScrollView {
          LazyVStack(spacing: 0) {
            if model.isLoading && model.posts.isEmpty {
              ForEach(0..<4, id: \.self) { _ in MainPostSkeleton() }
            } else if model.posts.isEmpty {
              MIRAEmptyState(title: "No posts yet", message: "Fresh moments will show here when they are ready.", systemImage: "sparkles")
                .padding(.top, 80)
            } else {
              ForEach(model.posts) { post in
                NavigationLink(value: post) {
                  MainNativePostCard(post: post)
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(.bottom, MIRATheme.Space.xxl)
        }
      }
      .background(MIRATheme.Color.appBackground)
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: MIRAPost.self) { post in
        PostDetailNativeView(post: post, api: model.api)
      }
      .task { await model.load() }
    }
  }

  private var mainHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Text("Main")
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      NavigationLink(destination: CreatePostNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "plus")
      }
      NavigationLink(destination: NotificationNativeView(api: model.api)) {
        MIRAHeaderCircleButton(systemImage: "bell")
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, 6)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }
}

private struct MainNativePostCard: View {
  let post: MIRAPost

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      postHeader

      if !post.mediaURLs.isEmpty {
        MediaCarouselNative(urls: post.mediaURLs)
      }

      HStack(spacing: MIRATheme.Space.md) {
        CompactPostAction(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0) {}
        CompactPostAction(systemImage: post.isSaved == true ? "bookmark.fill" : "bookmark", value: post.savesCount ?? 0) {}
        Spacer()
        CompactTextAction("View") {}
        CompactTextAction("Share", systemImage: "paperplane") {}
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.sm)
      .padding(.bottom, MIRATheme.Space.xs)

      if !post.titleText.isEmpty {
        Text(post.titleText)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, post.bodyText.isEmpty ? MIRATheme.Space.md : MIRATheme.Space.xs)
      }

      if !post.bodyText.isEmpty {
        Text(post.bodyText)
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(3)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, MIRATheme.Space.md)
      }
    }
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.75)
    }
  }

  private var postHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(url: post.userProfileImage, size: 42)
        Circle()
          .fill(MIRATheme.Color.forest)
          .frame(width: 19, height: 19)
          .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
          .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
          .offset(x: 2, y: 2)
      }
      Text(post.userUsername ?? post.userFullName ?? "mira")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
      Spacer()
      Button("Follow") {}
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(height: 36)
        .padding(.horizontal, MIRATheme.Space.md)
        .background(MIRATheme.Color.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MIRATheme.Color.hairline, lineWidth: 1))
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 22, weight: .regular))
        Text(compact(value))
          .font(.system(size: 13, weight: .semibold))
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(minHeight: 38)
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
            .font(.system(size: 13, weight: .semibold))
        }
        Text(title)
          .font(.system(size: 14, weight: .semibold))
      }
      .foregroundStyle(MIRATheme.Color.forest)
      .frame(height: 36)
      .padding(.horizontal, MIRATheme.Space.md)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

private func compact(_ value: Int) -> String {
  if value >= 1_000_000 { return "\(value / 1_000_000)M" }
  if value >= 1_000 { return "\(value / 1_000)K" }
  return "\(value)"
}
