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

  @discardableResult
  func sendComment(_ text: String) async -> Bool {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    if let comment: MIRAComment = try? await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean)) {
      comments.append(comment)
      post = post.updating(commentsCount: max(comments.count, (post.commentsCount ?? 0) + 1))
      publishEngagement()
      return true
    }
    return false
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
  @State private var isSendingComment = false
  @FocusState private var isCommentFocused: Bool
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
              LazyVStack(spacing: MIRATheme.Space.md) {
                ForEach(0..<4, id: \.self) { _ in
                  PostDetailCommentSkeleton()
                }
              }
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
    HStack(alignment: .bottom, spacing: MIRATheme.Space.sm) {
      TextField("Add a comment...", text: $draft, axis: .vertical)
        .font(.system(size: 15, weight: .regular))
        .textInputAutocapitalization(.sentences)
        .submitLabel(.send)
        .focused($isCommentFocused)
        .lineLimit(1...5)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(isCommentFocused ? MIRATheme.Color.forest.opacity(0.18) : MIRATheme.Color.hairline, lineWidth: 1)
        }
        .onSubmit(sendDraftComment)
        .animation(.easeOut(duration: 0.18), value: isCommentFocused)

      if canSendComment || isSendingComment {
        Button {
          sendDraftComment()
        } label: {
          Group {
            if isSendingComment {
              ProgressView()
                .tint(.white)
                .frame(width: 18, height: 18)
            } else {
              Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.forest)
          .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .disabled(!canSendComment || isSendingComment)
      }

      if !isCommentFocused && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Button {
          Task { await model.toggleLike() }
        } label: {
          HStack(spacing: 7) {
            Image(systemName: model.post.isLiked == true ? "heart.fill" : "heart")
              .font(.system(size: 22, weight: .semibold))
            Text(compact(model.post.likesCount ?? 0))
              .font(.system(size: 14, weight: .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.76)
          }
          .foregroundStyle(model.post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textSecondary)
          .frame(minWidth: 54, minHeight: 44)
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
              .lineLimit(1)
              .minimumScaleFactor(0.76)
          }
          .foregroundStyle(model.post.viewerSaved ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
          .frame(minWidth: 50, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var canSendComment: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingComment
  }

  private func sendDraftComment() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSendingComment else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    isSendingComment = true
    draft = ""
    Task {
      let didSend = await model.sendComment(text)
      if !didSend {
        draft = text
      }
      isSendingComment = false
    }
  }
}

private struct CommentRow: View {
  let comment: MIRAComment

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 32)
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
              Text(relativeAge(createdAt))
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
          Text("Reply")
          HStack(spacing: 4) {
            Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
              .font(.system(size: 12, weight: .semibold))
            Text(compact(comment.likesCount ?? 0))
          }
          .foregroundStyle(comment.likedByMe == true ? MIRATheme.Color.like : MIRATheme.Color.textMuted)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.leading, MIRATheme.Space.xs)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
    }
  }
}

private struct PostDetailCommentSkeleton: View {
  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      Circle()
        .fill(MIRATheme.Color.surfaceSoft)
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: 128, height: 12)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
      }
    }
    .redacted(reason: .placeholder)
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

private func shareURL(for post: MIRAPost) -> URL {
  MIRAProductionBackend.siteURL("post/\(post.id)")
}
