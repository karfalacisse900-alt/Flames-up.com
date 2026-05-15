import SwiftUI
import UIKit

@MainActor
final class PostDetailModel: ObservableObject {
  @Published var post: MIRAPost
  @Published var comments: [MIRAComment] = []
  @Published var isLoadingComments = false

  private let api: MIRAAPIClient

  init(post: MIRAPost, api: MIRAAPIClient) {
    self.post = post
    self.api = api
  }

  func refreshPost() async {
    do {
      post = try await api.get("/posts/\(post.id)")
    } catch {}
  }

  func loadComments() async {
    isLoadingComments = true
    defer { isLoadingComments = false }
    do {
      comments = try await api.get("/posts/\(post.id)/comments")
    } catch {
      comments = []
    }
  }

  func sendComment(_ text: String) async {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if let comment: MIRAComment = try? await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean)) {
      comments.append(comment)
    }
  }

  func toggleLike() async {
    let previous = post
    let nextLiked = !(post.isLiked ?? false)
    let nextCount = max(0, (post.likesCount ?? 0) + (nextLiked ? 1 : -1))
    post = post.updating(liked: nextLiked, likesCount: nextCount)
    do {
      let response: PostLikeResponse = try await api.post("/posts/\(post.id)/like", body: LikeBody(liked: nextLiked))
      post = post.updating(liked: response.liked ?? nextLiked, likesCount: response.likesCount ?? nextCount)
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
      post = post.updating(saved: response.saved ?? nextSaved, savesCount: response.savesCount ?? nextCount)
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
}

public struct PostDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: PostDetailModel
  @State private var draft = ""

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
              maxSingleImageHeight: min(UIScreen.main.bounds.width * 1.18, 560),
              carouselHeight: min(UIScreen.main.bounds.width * 1.08, 520)
            )
          }

          VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
            VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
              Text(model.post.titleText)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .lineSpacing(2)

              if !model.post.bodyText.isEmpty {
                Text(model.post.bodyText)
                  .font(.system(size: 15, weight: .regular))
                  .foregroundStyle(MIRATheme.Color.textSecondary)
                  .lineSpacing(4)
              }
            }

            actionRow

            Divider().overlay(MIRATheme.Color.divider)

            Text("\(model.comments.count) comments")
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
          .padding(MIRATheme.Space.md)
        }
      }

      commentBar
    }
    .background(MIRATheme.Color.appBackground)
    .toolbar(.hidden, for: .navigationBar)
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

      Text(model.post.userUsername ?? model.post.userFullName ?? "mira")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)
      Spacer()
      MIRAIconButton(systemImage: "paperplane") {}
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
    HStack(spacing: MIRATheme.Space.sm) {
      TextField("Add comment...", text: $draft, axis: .vertical)
        .font(.system(size: 16, weight: .regular))
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(minHeight: 46)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
      MIRAIconButton(systemImage: "arrow.up") {
        let text = draft
        draft = ""
        Task { await model.sendComment(text) }
      }
    }
    .padding(MIRATheme.Space.md)
    .background(.ultraThinMaterial)
  }

  private var actionRow: some View {
    HStack(spacing: MIRATheme.Space.lg) {
      MIRAStatButton(systemImage: model.post.isLiked == true ? "heart.fill" : "heart", value: model.post.likesCount ?? 0) {
        Task { await model.toggleLike() }
      }
      MIRAStatButton(systemImage: model.post.viewerSaved ? "bookmark.fill" : "bookmark", value: model.post.savesCount ?? 0) {
        Task { await model.toggleSave() }
      }
      Spacer()
      MIRAIconButton(systemImage: "paperplane") {}
    }
  }
}

private struct CommentRow: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 34)
      VStack(alignment: .leading, spacing: 4) {
        Text(comment.user?.displayName ?? "user")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text(comment.text)
          .font(.system(size: 16, weight: .regular))
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
        .frame(width: 44, height: 44)
    }
  }
}
