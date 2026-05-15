import SwiftUI

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
}

public struct PostDetailNativeView: View {
  @StateObject private var model: PostDetailModel
  @State private var draft = ""

  public init(post: MIRAPost, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          authorHeader

          if let media = model.post.mediaURLs.first {
            RemoteMediaView(url: media, isVideo: media.isVideoURL)
              .frame(maxWidth: .infinity)
              .aspectRatio(3.0 / 4.0, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
          }

          VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
            Text(model.post.titleText)
              .font(.system(size: 28, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .lineSpacing(2)

            if !model.post.bodyText.isEmpty {
              Text(model.post.bodyText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(MIRATheme.Color.textSecondary)
                .lineSpacing(4)
            }
          }

          actionRow

          Divider().overlay(MIRATheme.Color.divider)

          Text("Comments")
            .font(.system(size: 18, weight: .semibold))
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

      commentBar
    }
    .background(MIRATheme.Color.appBackground)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await model.refreshPost()
      await model.loadComments()
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

  private var authorHeader: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: model.post.userProfileImage, size: 44)
      Text(model.post.userUsername ?? model.post.userFullName ?? "mira")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      MIRAPrimaryButton("Follow") {}
    }
  }

  private var actionRow: some View {
    HStack(spacing: MIRATheme.Space.lg) {
      MIRAStatButton(systemImage: "heart", value: model.post.likesCount ?? 0) {}
      MIRAStatButton(systemImage: "bubble.left", value: model.post.commentsCount ?? 0) {}
      MIRAStatButton(systemImage: "bookmark", value: model.post.savesCount ?? 0) {}
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
