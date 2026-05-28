import SwiftUI
import UIKit

@MainActor
final class PostDetailModel: ObservableObject {
  @Published var post: MIRAPost
  @Published var comments: [MIRAComment] = []
  @Published var isLoadingComments = false
  @Published var currentUserId: String?

  let api: MIRAAPIClient
  private var likingPostIds = Set<String>()
  private var likingCommentIds = Set<String>()

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
      await loadCurrentUserIfNeeded()
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
  func sendComment(_ text: String, parentId: String? = nil) async -> Bool {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    if let comment: MIRAComment = try? await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean, parentId: parentId)) {
      comments.append(comment)
      post = post.updating(commentsCount: max(comments.count, (post.commentsCount ?? 0) + 1))
      publishEngagement()
      return true
    }
    return false
  }

  func toggleCommentLike(_ comment: MIRAComment) async {
    guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
    guard !likingCommentIds.contains(comment.id) else { return }
    likingCommentIds.insert(comment.id)
    defer { likingCommentIds.remove(comment.id) }

    let previous = comments[index]
    let nextLiked = !previous.viewerLiked
    let nextCount = max(0, (previous.likesCount ?? 0) + (nextLiked ? 1 : -1))
    comments[index] = previous.updating(liked: nextLiked, likesCount: nextCount)

    do {
      let response: CommentLikeResponse = try await api.post("/comments/\(comment.id)/like", body: LikeBody(liked: nextLiked))
      if let currentIndex = comments.firstIndex(where: { $0.id == comment.id }) {
        comments[currentIndex] = comments[currentIndex].updating(
          liked: response.liked ?? nextLiked,
          likesCount: response.likesCount ?? nextCount
        )
      }
    } catch {
      if let currentIndex = comments.firstIndex(where: { $0.id == comment.id }) {
        comments[currentIndex] = previous
      }
    }
  }

  func toggleCommentPin(_ comment: MIRAComment) async {
    let shouldPin = !comment.pinned
    do {
      let response: CommentPinResponse = try await api.post("/comments/\(comment.id)/pin", body: CommentPinBody(pinned: shouldPin))
      let pinnedAt = response.pinnedAt ?? (shouldPin ? ISO8601DateFormatter().string(from: Date()) : nil)
      comments = comments.map { item in
        guard item.id == comment.id else {
          return shouldPin ? item.updating(clearPin: true) : item
        }
        return item.updating(pinnedAt: response.pinned == false ? nil : pinnedAt, clearPin: response.pinned == false)
      }
      comments.sort { lhs, rhs in
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        return (lhs.createdAt ?? "") < (rhs.createdAt ?? "")
      }
    } catch {}
  }

  func deleteComment(_ comment: MIRAComment) async {
    let previous = comments
    comments.removeAll { $0.id == comment.id }
    do {
      let response: CommentMutationResponse = try await api.delete("/comments/\(comment.id)")
      let nextCount = response.commentsCount ?? max(0, (post.commentsCount ?? previous.count) - 1)
      post = post.updating(commentsCount: nextCount)
      publishEngagement()
    } catch {
      comments = previous
    }
  }

  func hideComment(_ comment: MIRAComment) async {
    let previous = comments
    comments.removeAll { $0.id == comment.id }
    do {
      let response: CommentMutationResponse = try await api.post("/comments/\(comment.id)/hide", body: EmptyBody())
      let nextCount = response.commentsCount ?? max(0, (post.commentsCount ?? previous.count) - 1)
      post = post.updating(commentsCount: nextCount)
      publishEngagement()
    } catch {
      comments = previous
    }
  }

  func reportComment(_ comment: MIRAComment) async {
    do {
      let _: EmptyResponse? = try await api.post(
        "/reports",
        body: PostReportBody(
          reportedType: "comment",
          reportedId: comment.id,
          reason: "other",
          details: "Reported from the comments sheet."
        )
      )
    } catch {}
  }

  func removeCommentLocally(_ comment: MIRAComment) {
    comments.removeAll { $0.id == comment.id }
  }

  func removeComments(byUserId userId: String) {
    comments.removeAll { $0.userId == userId }
  }

  func blockCommentAuthor(_ comment: MIRAComment) async {
    guard let userId = comment.userId, !userId.isEmpty else { return }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      removeComments(byUserId: userId)
    } catch {}
  }

  func toggleLike() async {
    guard !likingPostIds.contains(post.id) else { return }
    likingPostIds.insert(post.id)
    defer { likingPostIds.remove(post.id) }

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

  func save(to collection: String) async {
    let previous = post
    let nextCount = max(0, (post.savesCount ?? 0) + (post.viewerSaved ? 0 : 1))
    post = post.updating(saved: true, savesCount: nextCount)
    do {
      let response: PostSaveResponse = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: collection))
      post = post.updating(
        liked: response.liked,
        likesCount: response.likesCount,
        commentsCount: response.commentsCount,
        saved: response.saved ?? true,
        savesCount: response.savesCount ?? nextCount
      )
      publishEngagement()
    } catch {
      post = previous
    }
  }

  func unsave() async {
    guard post.viewerSaved else { return }
    let previous = post
    let nextCount = max(0, (post.savesCount ?? 0) - 1)
    post = post.updating(saved: false, savesCount: nextCount)
    do {
      let response: PostSaveResponse = try await api.delete("/library/save/\(post.id)")
      post = post.updating(
        liked: response.liked,
        likesCount: response.likesCount,
        commentsCount: response.commentsCount,
        saved: response.saved ?? false,
        savesCount: response.savesCount ?? nextCount
      )
      publishEngagement()
    } catch {
      post = previous
    }
  }

  func toggleSave() async {
    if post.viewerSaved {
      await unsave()
    } else {
      await save(to: "Inspiration")
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

  private func loadCurrentUserIfNeeded() async {
    guard currentUserId == nil else { return }
    let me: MIRAUser? = try? await api.get("/auth/me")
    currentUserId = me?.id
  }
}

public struct PostDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var localization: MIRALocalization
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  @State private var isSendingComment = false
  @State private var replyingTo: MIRAComment?
  @State private var isSaveSheetPresented = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportComment: MIRAComment?
  @State private var isReportSheetPresented = false
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
                  CommentRow(
                    comment: comment,
                    currentUserId: model.currentUserId,
                    postOwnerId: model.post.userId,
                    onReply: {
                      replyingTo = comment
                      isCommentFocused = true
                    },
                    onLike: {
                      Task { await model.toggleCommentLike(comment) }
                    },
                    onPin: {
                      Task { await model.toggleCommentPin(comment) }
                    },
                    onReport: {
                      presentReport(for: comment)
                    },
                    onBlockUser: {
                      Task { await model.blockCommentAuthor(comment) }
                    },
                    onDelete: {
                      Task { await model.deleteComment(comment) }
                    },
                    onHide: {
                      Task { await model.hideComment(comment) }
                    }
                  )
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
    .miraBottomSheet(
      isPresented: $isSaveSheetPresented,
      preferredHeightFraction: 0.46,
      maxHeight: 440
    ) { dismissSheet in
      MIRASaveToCollectionSheet(
        isSaved: model.post.viewerSaved,
        onSelect: { collection in
          Task {
            await model.save(to: collection)
            dismissSheet()
          }
        },
        onRemove: {
          Task {
            await model.unsave()
            dismissSheet()
          }
        },
        onClose: dismissSheet
      )
    }
    .miraBottomSheet(
      isPresented: $isReportSheetPresented,
      preferredHeightFraction: 0.78,
      maxHeight: 700,
      onDismissed: {
        reportTarget = nil
        reportComment = nil
      }
    ) { dismissSheet in
      if let reportTarget {
        MIRAReportSheet(
          target: reportTarget,
          api: model.api,
          onSubmitted: { result in handleReportResult(result) },
          onClose: dismissSheet
        )
      } else {
        Color.clear
      }
    }
    .task {
      await model.refreshPost()
      await model.loadComments()
    }
  }

  private func presentReport(for comment: MIRAComment) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    reportComment = comment
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
        isReportSheetPresented = true
      }
    }
  }

  private func handleReportResult(_ result: MIRAReportResult) {
    guard let reportComment else { return }
    if result.blocked, let userId = reportComment.userId {
      model.removeComments(byUserId: userId)
    } else if result.hidden {
      model.removeCommentLocally(reportComment)
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
          Text(model.post.authorDisplayName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      } else {
        Text(model.post.authorDisplayName)
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
    VStack(spacing: 0) {
      if let replyingTo {
        HStack(spacing: 8) {
          Image(systemName: "arrowshape.turn.up.left")
            .font(.system(size: 12, weight: .semibold))
          Text("Replying to \(replyingTo.user?.displayName ?? "comment")")
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.replyingTo = nil
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .bold))
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.miraPress)
        }
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.sm)
      }

      HStack(alignment: .bottom, spacing: MIRATheme.Space.sm) {
        TextField(replyingTo == nil ? localization.string("comments.add_placeholder") : localization.string("comments.reply_placeholder"), text: $draft, axis: .vertical)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isSaveSheetPresented = true
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
    }
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
      let parentId = replyingTo?.id
      let didSend = await model.sendComment(text, parentId: parentId)
      if !didSend {
        draft = text
      } else {
        replyingTo = nil
      }
      isSendingComment = false
    }
  }
}

private struct CommentRow: View {
  let comment: MIRAComment
  let currentUserId: String?
  let postOwnerId: String?
  let onReply: () -> Void
  let onLike: () -> Void
  let onPin: () -> Void
  let onReport: () -> Void
  let onBlockUser: () -> Void
  let onDelete: () -> Void
  let onHide: () -> Void

  private var isOwnComment: Bool {
    guard let currentUserId, let userId = comment.userId else { return false }
    return currentUserId == userId
  }

  private var isPostCreator: Bool {
    guard let currentUserId, let postOwnerId else { return false }
    return currentUserId == postOwnerId
  }

  var body: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: comment.user?.profileImage, size: 32)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 7) {
        if comment.pinned {
          Label("Pinned by creator", systemImage: "pin.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
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
          Button("Reply") {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onReply()
          }
          .buttonStyle(.plain)
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onLike()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: comment.viewerLiked ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
              Text(compact(comment.likesCount ?? 0))
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(comment.viewerLiked ? MIRATheme.Color.like : MIRATheme.Color.textMuted)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.leading, MIRATheme.Space.xs)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
    }
    .padding(.leading, comment.isReply ? 36 : 0)
    .contextMenu {
      Button(action: onReply) {
        Label("Reply", systemImage: "arrowshape.turn.up.left")
      }
      Button(action: onLike) {
        Label(comment.viewerLiked ? "Unlike comment" : "Like comment", systemImage: comment.viewerLiked ? "heart.slash" : "heart")
      }
      if isPostCreator {
        Button(action: onPin) {
          Label(comment.pinned ? "Unpin comment" : "Pin comment", systemImage: comment.pinned ? "pin.slash" : "pin")
        }
        if !isOwnComment {
          Button(role: .destructive, action: onHide) {
            Label("Hide comment", systemImage: "eye.slash")
          }
        }
      }
      if isOwnComment {
        Button(role: .destructive, action: onDelete) {
          Label("Delete comment", systemImage: "trash")
        }
      } else {
        Button(role: .destructive, action: onBlockUser) {
          Label("Block user", systemImage: "hand.raised")
        }
        Button(role: .destructive, action: onReport) {
          Label("Report comment", systemImage: "flag")
        }
      }
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
