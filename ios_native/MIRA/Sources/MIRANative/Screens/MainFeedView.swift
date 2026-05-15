import SwiftUI

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
      ScrollView {
        LazyVStack(spacing: 1) {
          if model.isLoading && model.posts.isEmpty {
            ForEach(0..<4, id: \.self) { _ in MainPostSkeleton() }
          } else if model.posts.isEmpty {
            MIRAEmptyState(title: "No posts yet", message: "Fresh moments will show here when they are ready.", systemImage: "sparkles")
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
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("MIRA")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink(destination: CreatePostNativeView(api: model.api)) {
            Image(systemName: "plus")
          }
          NavigationLink(destination: NotificationNativeView(api: model.api)) {
            Image(systemName: "bell")
          }
        }
      }
      .navigationDestination(for: MIRAPost.self) { post in
        PostDetailNativeView(post: post, api: model.api)
      }
      .task { await model.load() }
      .refreshable { await model.load() }
    }
  }
}

private struct MainNativePostCard: View {
  let post: MIRAPost

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: MIRATheme.Space.sm) {
        RemoteAvatar(url: post.userProfileImage, size: 42)
        Text(post.userUsername ?? post.userFullName ?? "mira")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Spacer()
        Button("Follow") {}
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(height: 38)
          .padding(.horizontal, MIRATheme.Space.lg)
          .background(MIRATheme.Color.surface)
          .clipShape(Capsule())
          .overlay(Capsule().stroke(MIRATheme.Color.divider, lineWidth: 1))
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, MIRATheme.Space.md)

      if let media = post.mediaURLs.first {
        RemoteMediaView(url: media, isVideo: media.isVideoURL)
          .frame(maxWidth: .infinity)
          .aspectRatio(3.0 / 4.0, contentMode: .fit)
      }

      HStack(spacing: MIRATheme.Space.lg) {
        MIRAStatButton(systemImage: post.isLiked == true ? "heart.fill" : "heart", value: post.likesCount ?? 0) {}
        MIRAStatButton(systemImage: "bookmark", value: post.savesCount ?? 0) {}
        Spacer()
        MIRAPrimaryButton("Share", systemImage: "paperplane") {}
      }
      .padding(MIRATheme.Space.md)

      if !post.titleText.isEmpty {
        Text(post.titleText)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, MIRATheme.Space.xs)
      }
    }
    .background(MIRATheme.Color.surface)
  }
}

private struct MainPostSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 42, height: 42)
        RoundedRectangle(cornerRadius: 8).fill(MIRATheme.Color.surfaceSoft).frame(width: 160, height: 18)
      }
      RoundedRectangle(cornerRadius: MIRATheme.Radius.large)
        .fill(MIRATheme.Color.surfaceSoft)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .redacted(reason: .placeholder)
  }
}
