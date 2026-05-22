import SwiftUI
import UIKit

@MainActor
final class PostDetailModel: ObservableObject {
  @Published var post: MIRAPost
  @Published var comments: [MIRAComment] = []
  @Published var isLoadingComments = false

  let api: MIRAAPIClient

  init(post: MIRAPost, api: MIRAAPIClient) {
    self.post = post
    self.api = api
  }

  func refreshPost() async {
    do {
      let refreshed: MIRAPost = try await api.get("/posts/\(post.id)")
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        post = refreshed
      }
      publishEngagement()
    } catch {}
  }

  func loadComments() async {
    isLoadingComments = true
    defer { isLoadingComments = false }
    do {
      let loaded: [MIRAComment] = try await api.get("/posts/\(post.id)/comments")
      comments = loaded
      let nextCount = loaded.count
      if post.commentsCount != nextCount {
        post = post.updating(commentsCount: nextCount)
        publishEngagement()
      }
    } catch {
      comments = []
    }
  }

  func sendComment(_ text: String) async {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if let comment: MIRAComment = try? await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean)) {
      comments.append(comment)
      post = post.updating(commentsCount: max(comments.count, (post.commentsCount ?? 0) + 1))
      publishEngagement()
    }
  }

  func toggleLike() async {
    let previous = post
    let nextLiked = !(post.isLiked ?? false)
    let nextCount = max(0, (post.likesCount ?? 0) + (nextLiked ? 1 : -1))
    post = post.updating(liked: nextLiked, likesCount: nextCount)
    do {
      let response: PostLikeResponse = try await api.post("/posts/\(post.id)/like", body: LikeBody(liked: nextLiked))
      post = post.updating(
        liked: response.liked ?? nextLiked,
        likesCount: response.likesCount ?? nextCount,
        commentsCount: response.commentsCount,
        saved: response.saved,
        savesCount: response.savesCount
      )
      publishEngagement()
    } catch {
      post = previous
    }
  }

  func toggleSave() async {
    let previous = post
    let nextSaved = !post.viewerSaved
    let nextCount = max(0, (post.savesCount ?? 0) + (nextSaved ? 1 : -1))
    post = post.updating(saved: nextSaved, savesCount: nextCount)
    do {
      let response: PostSaveResponse
      if nextSaved {
        response = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: "My Library"))
      } else {
        response = try await api.delete("/library/save/\(post.id)")
      }
      post = post.updating(
        liked: response.liked,
        likesCount: response.likesCount,
        commentsCount: response.commentsCount,
        saved: response.saved ?? nextSaved,
        savesCount: response.savesCount ?? nextCount
      )
      publishEngagement()
    } catch {
      post = previous
    }
  }

  func toggleFollowAuthor() async {
    guard let userId = post.userId, !userId.isEmpty else { return }
    let previous = post
    let nextFollowing = !post.viewerFollowing
    post = post.updating(following: nextFollowing)
    do {
      let response: FollowResponse = try await api.post("/users/\(userId)/follow", body: FollowBody(following: nextFollowing))
      post = post.updating(following: response.following ?? nextFollowing)
    } catch {
      post = previous
    }
  }

  private func publishEngagement() {
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
}

public struct PostDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  private var mediaHeight: CGFloat {
    let maxHeight = max(300, UIScreen.main.bounds.height * 0.48)
    return min(
      MIRAMediaSizing.detailHeight(for: model.post.mediaURLs, aspectRatios: model.post.mediaHeightToWidthRatios),
      maxHeight
    )
  }

  public init(post: MIRAPost, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      detailHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if !model.post.mediaURLs.isEmpty {
            MIRAAdaptiveMediaView(
              urls: model.post.mediaURLs,
              maxSingleImageHeight: mediaHeight,
              carouselHeight: mediaHeight,
              singleImageContentMode: .fill
            )
            .frame(maxWidth: .infinity, minHeight: mediaHeight, maxHeight: mediaHeight)
          }

          VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
            VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
              Text(model.post.titleText)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .lineSpacing(2)

              if !model.post.bodyText.isEmpty {
                Text(model.post.bodyText)
                  .font(.system(size: 16, weight: .regular))
                  .foregroundStyle(MIRATheme.Color.textPrimary.opacity(0.88))
                  .lineSpacing(4)
              }

              Text(relativeAge(model.post.createdAt))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MIRATheme.Color.textMuted)

              if let placeName = model.post.placeDisplayName {
                HStack(alignment: .top, spacing: 8) {
                  Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MIRATheme.Color.forest)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(placeName)
                      .font(.system(size: 14, weight: .semibold))
                      .foregroundStyle(MIRATheme.Color.forest)
                      .lineLimit(1)
                    if let subtitle = model.post.placeDisplaySubtitle {
                      Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MIRATheme.Color.textMuted)
                        .lineLimit(1)
                    }
                  }
                  Spacer()
                }
                .padding(.top, 2)
              }
            }

            Text("\(model.post.commentsCount ?? model.comments.count) comments")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)

            if model.isLoadingComments && model.comments.isEmpty {
              ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if model.comments.isEmpty {
              MIRAEmptyState(title: "No comments yet", message: "Be the first to reply.", systemImage: "bubble.left")
            } else {
              LazyVStack(spacing: MIRATheme.Space.md) {
                ForEach(model.comments) { comment in
                  CommentRow(comment: comment)
                }
              }
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.md)
          .padding(.bottom, 24)
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      commentBar
    }
    .background(MIRATheme.Color.surface)
    .miraScreenEnter(.push)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .task {
      await model.refreshPost()
      await model.loadComments()
    }
  }

  private var detailHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Button(action: { dismiss() }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)

      Button(action: { Task { await model.toggleFollowAuthor() } }) {
        MIRAFollowAvatar(url: model.post.userProfileImage, size: 44, isFollowing: model.post.viewerFollowing)
      }
      .buttonStyle(.plain)

      if let userId = model.post.userId, !userId.isEmpty {
        NavigationLink(destination: UserProfileNativeView(userId: userId, api: model.api)) {
          Text(model.post.userUsername ?? model.post.userFullName ?? "mira")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      } else {
        Text(model.post.userUsername ?? model.post.userFullName ?? "mira")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
      }
      Spacer()
      ShareLink(item: shareURL(for: model.post), subject: Text(model.post.titleText), message: Text(model.post.titleText)) {
        Image(systemName: "arrowshape.turn.up.right")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var commentBar: some View {
    HStack(spacing: MIRATheme.Space.md) {
      TextField("Add comment...", text: $draft, axis: .vertical)
        .font(.system(size: 15, weight: .regular))
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(minHeight: 48)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .onSubmit {
          let text = draft
          draft = ""
          Task { await model.sendComment(text) }
        }

      if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Button {
          let text = draft
          draft = ""
          Task { await model.sendComment(text) }
        } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(MIRATheme.Color.forest)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      Button {
        Task { await model.toggleLike() }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: model.post.isLiked == true ? "heart.fill" : "heart")
            .font(.system(size: 22, weight: .semibold))
          Text(compact(model.post.likesCount ?? 0))
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(model.post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary)
        .frame(minWidth: 58, minHeight: 48)
      }
      .buttonStyle(.plain)

      Button {
        Task { await model.toggleSave() }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: model.post.viewerSaved ? "bookmark.fill" : "bookmark")
            .font(.system(size: 22, weight: .semibold))
          Text(compact(model.post.savesCount ?? 0))
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(model.post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
        .frame(minWidth: 54, minHeight: 48)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }
}

private struct CommentRow: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 32)
      VStack(alignment: .leading, spacing: 4) {
        Text(comment.user?.displayName ?? "user")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text(comment.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        HStack(spacing: MIRATheme.Space.lg) {
          Text("Reply")
          Text("\(comment.likesCount ?? 0)")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 40, height: 40)
    }
  }
}

private func relativeAge(_ value: String?) -> String {
  guard let value else { return "" }
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: value) else { return "" }
  let seconds = max(0, Date().timeIntervalSince(date))
  if seconds < 60 { return "now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m ago" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h ago" }
  let days = Int(seconds / 86_400)
  if days < 30 { return "\(days) days ago" }
  let months = Int(seconds / 2_592_000)
  if months < 12 { return "\(months) month\(months == 1 ? "" : "s") ago" }
  let years = Int(seconds / 31_536_000)
  return "\(years) year\(years == 1 ? "" : "s") ago"
}

private func compact(_ value: Int) -> String {
  if value >= 1_000_000 { return "\(value / 1_000_000)M" }
  if value >= 1_000 { return "\(value / 1_000)K" }
  return "\(value)"
}

private func shareURL(for post: MIRAPost) -> URL {
  MIRAProductionBackend.siteURL("post/\(post.id)")
}
