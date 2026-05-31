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

  func hydrateFromLocalCache() async {
    guard let cached = await MIRAAppCacheStore.shared.loadCachedPost(id: post.id) else { return }
    applyCachedEngagement(from: cached)
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
    if comments.isEmpty, let cached = await MIRAAppCacheStore.shared.loadComments(postId: post.id) {
      comments = cached
      isLoadingComments = false
    }
    isLoadingComments = comments.isEmpty
    defer { isLoadingComments = false }
    do {
      await loadCurrentUserIfNeeded()
      let loaded: [MIRAComment] = try await api.get("/posts/\(post.id)/comments")
      comments = await MIRAAppCacheStore.shared.mergeComments(existing: comments, fresh: loaded)
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
      let nextCount = comments.count
      if post.commentsCount != nextCount {
        post = post.updating(commentsCount: nextCount)
        publishEngagement()
      }
    } catch {
      if comments.isEmpty {
        comments = []
      }
    }
  }

  func applyEngagementUpdate(_ update: MIRAPostEngagementUpdate) {
    guard update.postId == post.id else { return }
    post = post.updating(
      liked: update.liked,
      likesCount: update.likesCount,
      commentsCount: update.commentsCount,
      saved: update.saved,
      savesCount: update.savesCount
    )
  }

  @discardableResult
  func sendComment(_ text: String, parentId: String? = nil) async -> Bool {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    if let comment: MIRAComment = try? await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean, parentId: parentId)) {
      comments.append(comment)
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
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
        await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
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
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
    } catch {}
  }

  func deleteComment(_ comment: MIRAComment) async {
    let previous = comments
    comments.removeAll { $0.id == comment.id }
    do {
      let response: CommentMutationResponse = try await api.delete("/comments/\(comment.id)")
      let nextCount = response.commentsCount ?? max(0, (post.commentsCount ?? previous.count) - 1)
      post = post.updating(commentsCount: nextCount)
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
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
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
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
    Task { await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id) }
  }

  func removeComments(byUserId userId: String) {
    comments.removeAll { $0.userId == userId }
    Task { await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id) }
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

  private func applyCachedEngagement(from cached: MIRAPost) {
    post = post.updating(
      liked: cached.isLiked,
      likesCount: bestCount(post.likesCount, cached.likesCount),
      commentsCount: bestCount(post.commentsCount, cached.commentsCount),
      saved: cached.isSaved ?? cached.saved?.value,
      savesCount: bestCount(post.savesCount, cached.savesCount)
    )
  }

  private func bestCount(_ current: Int?, _ cached: Int?) -> Int? {
    guard current != nil || cached != nil else { return nil }
    return max(current ?? 0, cached ?? 0)
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    .miraHideTabBarOnAppear()
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
      await model.hydrateFromLocalCache()
      await model.refreshPost()
      await model.loadComments()
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
      guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
      model.applyEngagementUpdate(update)
    }
  }

  private func presentReport(for comment: MIRAComment) {
    CaptroHaptics.medium()
    reportComment = comment
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
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
            CaptroHaptics.light()
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
          .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: isCommentFocused)

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
            CaptroHaptics.light()
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
    CaptroHaptics.light()
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

public struct DiscoverPostDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var model: PostDetailModel
  @State private var isCaptionExpanded = false
  @State private var isCommentsPresented = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportComment: MIRAComment?
  @State private var isReportSheetPresented = false

  public init(post: MIRAPost, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  public var body: some View {
    ZStack {
      MIRATheme.Color.surface.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          topBar
          captionBlock
          mediaCarousel
          actionRow
          postContext
        }
        .padding(.bottom, 32)
      }
      .scrollIndicators(.hidden)
    }
    .background(MIRATheme.Color.surface)
    .miraScreenEnter(.push)
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .miraBottomSheet(
      isPresented: $isCommentsPresented,
      preferredHeightFraction: 0.72,
      maxHeight: 640
    ) { dismissComments in
      DiscoverDetailCommentsSheet(
        model: model,
        onClose: dismissComments,
        onReportComment: { comment in
          dismissComments()
          DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
            presentReport(for: comment)
          }
        },
        onBlockCommentUser: { comment in
          dismissComments()
          Task { await model.blockCommentAuthor(comment) }
        }
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
    ) { dismissReport in
      if let reportTarget {
        MIRAReportSheet(
          target: reportTarget,
          api: model.api,
          onSubmitted: { result in handleReportResult(result) },
          onClose: dismissReport
        )
      } else {
        Color.clear
      }
    }
    .task {
      await model.hydrateFromLocalCache()
      await model.refreshPost()
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
      guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
      model.applyEngagementUpdate(update)
    }
  }

  private var topBar: some View {
    HStack {
      Button {
        CaptroHaptics.light()
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)

      Spacer()

      if let place = model.post.placeDisplayName {
        Label(place, systemImage: "mappin.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest.opacity(0.82))
          .lineLimit(1)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(MIRATheme.Color.forestSoft.opacity(0.92))
          .clipShape(Capsule())
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
  }

  private var captionBlock: some View {
    Button {
      guard shouldCollapseCaption else { return }
      CaptroHaptics.light()
      withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
        isCaptionExpanded.toggle()
      }
    } label: {
      captionLabel
        .font(.system(size: 19, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineSpacing(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MIRATheme.Space.md)
    .accessibilityLabel(captionText)
  }

  private var captionLabel: Text {
    guard shouldCollapseCaption else {
      return Text(captionText)
    }
    if isCaptionExpanded {
      return Text(captionText) + Text("  Read less").foregroundColor(MIRATheme.Color.textSecondary).fontWeight(.semibold)
    }
    return Text(captionPreviewText) + Text("...Read more").foregroundColor(MIRATheme.Color.textSecondary).fontWeight(.semibold)
  }

  private var mediaCarousel: some View {
    Group {
      if displayMediaURLs.isEmpty {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(MIRATheme.Color.mediaPlaceholder)
          .overlay {
            VStack(spacing: 8) {
              Image(systemName: "photo")
                .font(.system(size: 26, weight: .light))
              Text("No media")
                .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(MIRATheme.Color.textSecondary.opacity(0.72))
          }
          .frame(width: carouselCardWidth, height: carouselHeight)
          .padding(.horizontal, MIRATheme.Space.md)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 12) {
            ForEach(Array(displayMediaURLs.enumerated()), id: \.offset) { index, url in
              DiscoverDetailMediaCard(
                url: url,
                isVideo: isVideo(at: index, url: url),
                placeholderURL: placeholderURL(at: index),
                fallbackURL: fallbackURL(at: index, url: url),
                index: index,
                totalCount: displayMediaURLs.count
              )
              .frame(width: carouselCardWidth, height: carouselHeight)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
        }
      }
    }
    .frame(height: carouselHeight)
  }

  private var actionRow: some View {
    HStack(alignment: .center, spacing: 0) {
      Button {
        CaptroHaptics.light()
        Task { await model.toggleLike() }
      } label: {
        HStack(spacing: 12) {
          Image(systemName: model.post.isLiked == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            .font(.system(size: 34, weight: .regular))
          Text(compact(model.post.likesCount ?? 0))
            .font(.system(size: 24, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .foregroundStyle(model.post.isLiked == true ? MIRATheme.Color.like : MIRATheme.Color.textPrimary)
        .frame(minWidth: 112, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)

      Spacer(minLength: 24)

      Button {
        CaptroHaptics.light()
        isCommentsPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "bubble.right")
            .font(.system(size: 34, weight: .regular))
          Text(compact(model.post.commentsCount ?? model.comments.count))
            .font(.system(size: 24, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minWidth: 92, minHeight: 54, alignment: .trailing)
        .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var postContext: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        if let userId = model.post.userId, !userId.isEmpty {
          NavigationLink(destination: UserProfileNativeView(userId: userId, api: model.api)) {
            authorSummary
          }
          .buttonStyle(.plain)
        } else {
          authorSummary
        }
        Spacer()
      }

      if let subtitle = model.post.placeDisplaySubtitle {
        Text(subtitle)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var authorSummary: some View {
    HStack(spacing: 10) {
      RemoteAvatar(url: model.post.userProfileImage, size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.post.authorDisplayName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Text(relativeAge(model.post.createdAt))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
      }
    }
  }

  private var displayMediaURLs: [String] {
    let feed = model.post.feedMediaURLs
    return feed.isEmpty ? model.post.mediaURLs : feed
  }

  private var carouselCardWidth: CGFloat {
    max(280, UIScreen.main.bounds.width - 66)
  }

  private var carouselHeight: CGFloat {
    min(carouselCardWidth * 1.03, UIScreen.main.bounds.height * 0.58)
  }

  private var captionText: String {
    let title = model.post.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = model.post.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.isEmpty { return title }
    return "\(title) \(body)"
  }

  private var shouldCollapseCaption: Bool {
    captionText.count > 82 || captionText.contains("\n")
  }

  private var captionPreviewText: String {
    let clean = captionText.replacingOccurrences(of: "\n", with: " ")
    guard clean.count > 82 else { return clean }
    return String(clean.prefix(82)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func isVideo(at index: Int, url: String) -> Bool {
    let types = model.post.mediaTypes?.values ?? []
    if types.indices.contains(index) {
      return types[index].lowercased().contains("video")
    }
    return url.isVideoURL
  }

  private func placeholderURL(at index: Int) -> String? {
    let posters = model.post.posterMediaURLs
    if posters.indices.contains(index) { return posters[index] }
    let thumbnails = model.post.thumbnailMediaURLs
    if thumbnails.indices.contains(index) { return thumbnails[index] }
    return thumbnails.first ?? posters.first
  }

  private func fallbackURL(at index: Int, url: String) -> String? {
    let originals = model.post.mediaURLs
    guard originals.indices.contains(index) else { return nil }
    let fallback = originals[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fallback.isEmpty, fallback != url, !fallback.isVideoURL else { return nil }
    return fallback
  }

  private func presentReport(for comment: MIRAComment) {
    CaptroHaptics.medium()
    reportComment = comment
    reportTarget = MIRAReportTarget(
      targetType: "comment",
      targetId: comment.id,
      ownerUserId: comment.userId,
      title: "Report comment",
      subtitle: comment.text
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
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
}

private struct DiscoverDetailMediaCard: View {
  let url: String
  let isVideo: Bool
  let placeholderURL: String?
  let fallbackURL: String?
  let index: Int
  let totalCount: Int

  var body: some View {
    ZStack(alignment: .topTrailing) {
      RemoteMediaView(
        url: url,
        isVideo: isVideo,
        placeholderURL: placeholderURL,
        fallbackURL: fallbackURL,
        contentMode: .fill,
        shouldPlay: false,
        maxPixelSize: MIRAMediaSizing.feedTargetHeight,
        showsVideoPlaceholderIcon: isVideo
      )
      .allowsHitTesting(false)

      if totalCount > 1 {
        Text("\(index + 1)/\(totalCount)")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 17)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.78))
          .clipShape(Capsule())
          .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
          .padding(16)
      }
    }
    .background(MIRATheme.Color.mediaPlaceholder)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private struct DiscoverDetailCommentsSheet: View {
  @ObservedObject var model: PostDetailModel
  @State private var draft = ""
  @State private var isSending = false
  @State private var replyingTo: MIRAComment?
  @FocusState private var isReplyFocused: Bool
  @EnvironmentObject private var localization: MIRALocalization
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onClose: () -> Void
  let onReportComment: (MIRAComment) -> Void
  let onBlockCommentUser: (MIRAComment) -> Void

  var body: some View {
    VStack(spacing: 0) {
      sheetHeader

      ScrollView {
        LazyVStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          if model.isLoadingComments && model.comments.isEmpty {
            ForEach(0..<5, id: \.self) { _ in
              PostDetailCommentSkeleton()
            }
          } else if model.comments.isEmpty {
            MIRAEmptyState(title: localization.string("comments.empty.title"), message: localization.string("comments.empty.message"), systemImage: "bubble.left")
              .frame(maxWidth: .infinity)
              .padding(.top, 28)
          } else {
            ForEach(model.comments) { comment in
              CommentRow(
                comment: comment,
                currentUserId: model.currentUserId,
                postOwnerId: model.post.userId,
                onReply: {
                  replyingTo = comment
                  isReplyFocused = true
                },
                onLike: {
                  Task { await model.toggleCommentLike(comment) }
                },
                onPin: {
                  Task { await model.toggleCommentPin(comment) }
                },
                onReport: {
                  onReportComment(comment)
                },
                onBlockUser: {
                  onBlockCommentUser(comment)
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
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, 18)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .miraScrollFeel(.sheet)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      commentComposer
    }
    .background(MIRATheme.Color.surface)
    .task {
      await model.loadComments()
    }
  }

  private var sheetHeader: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.22))
        .frame(width: 42, height: 5)
        .padding(.top, 10)

      HStack(spacing: MIRATheme.Space.sm) {
        Text(localization.string("comments.title"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(compact(model.post.commentsCount ?? model.comments.count))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Capsule())
        Spacer()
        Button {
          isReplyFocused = false
          onClose()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
    .padding(.bottom, MIRATheme.Space.sm)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
  }

  private var commentComposer: some View {
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
            CaptroHaptics.light()
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
          .focused($isReplyFocused)
          .lineLimit(1...5)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.vertical, 11)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
              .stroke(isReplyFocused ? MIRATheme.Color.forest.opacity(0.18) : MIRATheme.Color.hairline, lineWidth: 1)
          }
          .onSubmit(sendComment)
          .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: isReplyFocused)

        Button(action: sendComment) {
          Group {
            if isSending {
              ProgressView()
                .tint(.white)
                .frame(width: 17, height: 17)
            } else {
              Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 40, height: 40)
          .background(canSend ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.28))
          .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .disabled(!canSend || isSending)
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

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }

  private func sendComment() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSending else { return }
    CaptroHaptics.light()
    isSending = true
    draft = ""
    Task {
      let parentId = replyingTo?.id
      let didSend = await model.sendComment(text, parentId: parentId)
      if !didSend {
        draft = text
      } else {
        replyingTo = nil
      }
      isSending = false
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
            CaptroHaptics.light()
            onReply()
          }
          .buttonStyle(.plain)
          Button {
            CaptroHaptics.light()
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
