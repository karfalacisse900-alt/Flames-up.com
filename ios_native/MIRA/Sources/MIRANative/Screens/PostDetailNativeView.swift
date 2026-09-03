import SwiftUI
import UIKit

@MainActor
final class PostDetailModel: ObservableObject {
  @Published var post: MIRAPost
  @Published var comments: [MIRAComment] = []
  @Published var isLoadingComments = false
  @Published var currentUserId: String?
  @Published var isSaving = false
  @Published var isUpdatingAttendance = false
  @Published var actionError: String?
  @Published var commentsError: String?
  @Published var privateObject: CaptroPrivatePostObject?
  @Published var isLoadingObject = false
  @Published var objectError: String?

  let api: MIRAAPIClient
  private var likeMutationVersions: [String: Int] = [:]
  private var likingCommentIds = Set<String>()

  init(post: MIRAPost, api: MIRAAPIClient) {
    self.post = post
    self.api = api
  }

  func hydrateFromLocalCache() async {
    post = await MIRAPostEngagementSync.apply(to: post)
    guard let cached = await MIRAAppCacheStore.shared.loadCachedPost(id: post.id) else { return }
    applyCachedEngagement(from: cached)
    if post.detail == nil { post.detail = cached.detail }
  }

  func refreshPost() async {
    do {
      let apiPost: MIRAPost = try await api.get("/posts/\(post.id)")
      let refreshed = await MIRAPostEngagementSync.apply(to: apiPost)
      let current = post
      var merged = refreshed.updating(
        liked: refreshed.viewerLikedValue ?? current.viewerLikedValue,
        likesCount: refreshed.likesCount ?? current.likesCount,
        commentsCount: refreshed.commentsCount ?? current.commentsCount,
        saved: refreshed.viewerSavedValue ?? current.viewerSavedValue,
        savesCount: refreshed.savesCount ?? current.savesCount,
        following: refreshed.isFollowing ?? refreshed.following?.value ?? refreshed.followed?.value ?? current.viewerFollowing
      )
      if merged.detail == nil { merged.detail = current.detail }
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        post = merged
      }
      publishEngagement()
    } catch {}
  }

  func loadPrivateObject() async {
    guard [.event, .travel, .receipt, .invoice].contains(post.detailKind) else { return }
    isLoadingObject = true
    objectError = nil
    defer { isLoadingObject = false }
    do {
      privateObject = try await api.get("/posts/\(post.id)/object")
    } catch {
      privateObject = nil
      objectError = "Couldn't load private details. Try again."
    }
  }

  func loadComments() async {
    commentsError = nil
    if comments.isEmpty, let cached = await MIRAAppCacheStore.shared.loadComments(postId: post.id) {
      comments = cached
      prefetchCommentAvatars(cached)
      isLoadingComments = false
    }
    isLoadingComments = comments.isEmpty
    defer { isLoadingComments = false }
    do {
      await loadCurrentUserIfNeeded()
      let loaded: [MIRAComment] = try await api.get("/posts/\(post.id)/comments")
      comments = await MIRAAppCacheStore.shared.mergeComments(existing: comments, fresh: loaded)
      prefetchCommentAvatars(comments)
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
      let nextCount = comments.count
      if post.commentsCount != nextCount {
        post = post.updating(commentsCount: nextCount)
        publishEngagement()
      }
    } catch {
      commentsError = "Couldn't load comments. Please try again."
      if comments.isEmpty {
        comments = []
      }
    }
  }

  func applyEngagementUpdate(_ update: MIRAPostEngagementUpdate) {
    guard update.postId == post.id else { return }
    post = post.updating(
      liked: update.liked,
      likesCount: stableEngagementCount(current: post.likesCount, incoming: update.likesCount, toggledOn: update.liked),
      commentsCount: update.commentsCount,
      saved: update.saved,
      savesCount: update.savesCount
    )
  }

  @discardableResult
  func sendComment(_ text: String, parentId: String? = nil) async -> Bool {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    do {
      let comment: MIRAComment = try await api.post("/posts/\(post.id)/comments", body: PostCommentBody(content: clean, parentId: parentId))
      comments.append(comment)
      await MIRAAppCacheStore.shared.saveComments(comments, postId: post.id)
      post = post.updating(commentsCount: max(comments.count, (post.commentsCount ?? 0) + 1))
      publishEngagement()
      return true
    } catch {
      actionError = "Couldn't send your comment. Your draft has been kept."
      return false
    }
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

  private func prefetchCommentAvatars(_ rows: [MIRAComment]) {
    let urls = rows.prefix(80)
      .compactMap { $0.user?.profileImage?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !urls.isEmpty else { return }
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 180, limit: 24)
    }
  }

  func toggleLike() async {
    let mutationVersion = beginLikeMutation(for: post.id)
    let previous = post
    let nextLiked = !post.viewerLiked
    let nextCount = max(0, (post.likesCount ?? 0) + (nextLiked ? 1 : -1))
    post = post.updating(liked: nextLiked, likesCount: nextCount)
    publishEngagement()
    do {
      let response: PostLikeResponse = try await api.post("/posts/\(post.id)/like", body: LikeBody(liked: nextLiked))
      guard isCurrentLikeMutation(mutationVersion, for: post.id) else { return }
      let reconciledLikesCount = stableEngagementCount(
        current: previous.likesCount,
        incoming: response.likesCount,
        optimistic: nextCount,
        toggledOn: response.liked ?? nextLiked
      )
      post = post.updating(
        liked: response.liked ?? nextLiked,
        likesCount: reconciledLikesCount,
        commentsCount: response.commentsCount,
        saved: response.saved,
        savesCount: response.savesCount
      )
      publishEngagement()
    } catch {
      guard isCurrentLikeMutation(mutationVersion, for: post.id) else { return }
      post = post.updating(liked: previous.viewerLiked, likesCount: previous.likesCount ?? 0)
      actionError = "Couldn't update your like. Please try again."
      publishEngagement()
    }
    finishLikeMutation(mutationVersion, for: post.id)
  }

  func save(to collection: String) async {
    let previous = post
    let nextCount = max(0, (post.savesCount ?? 0) + (post.viewerSaved ? 0 : 1))
    post = post.updating(saved: true, savesCount: nextCount)
    publishEngagement()
    do {
      let response: PostSaveResponse = try await api.post("/library/save/\(post.id)", body: SaveCollectionBody(collection: collection))
      let reconciledSavesCount = stableEngagementCount(
        current: previous.savesCount,
        incoming: response.savesCount,
        optimistic: nextCount,
        toggledOn: response.saved ?? true
      )
      post = post.updating(
        liked: response.liked,
        likesCount: response.likesCount,
        commentsCount: response.commentsCount,
        saved: response.saved ?? true,
        savesCount: reconciledSavesCount
      )
      publishEngagement()
    } catch {
      post = post.updating(saved: previous.viewerSaved, savesCount: previous.savesCount ?? 0)
      actionError = "Couldn't save this post. Please try again."
      publishEngagement()
    }
  }

  func unsave() async {
    guard post.viewerSaved else { return }
    let previous = post
    let nextCount = max(0, (post.savesCount ?? 0) - 1)
    post = post.updating(saved: false, savesCount: nextCount)
    publishEngagement()
    do {
      let response: PostSaveResponse = try await api.delete("/library/save/\(post.id)")
      let reconciledSavesCount = stableEngagementCount(
        current: previous.savesCount,
        incoming: response.savesCount,
        optimistic: nextCount,
        toggledOn: response.saved ?? false
      )
      post = post.updating(
        liked: response.liked,
        likesCount: response.likesCount,
        commentsCount: response.commentsCount,
        saved: response.saved ?? false,
        savesCount: reconciledSavesCount
      )
      publishEngagement()
    } catch {
      post = post.updating(saved: previous.viewerSaved, savesCount: previous.savesCount ?? 0)
      actionError = "Couldn't remove this saved post. Please try again."
      publishEngagement()
    }
  }

  func toggleSave() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    if post.viewerSaved {
      await unsave()
    } else {
      await save(to: "Inspiration")
    }
  }

  func toggleAttendance() async {
    guard !isUpdatingAttendance, let event = post.detail?.event, event.attendanceEnabled == true else { return }
    isUpdatingAttendance = true
    defer { isUpdatingAttendance = false }
    let going = event.viewerGoing != true
    do {
      let response: CaptroAttendanceResponse = try await api.post(
        "/posts/\(post.id)/attendance", body: CaptroAttendanceBody(going: going)
      )
      guard response.event.viewerGoing == going else {
        actionError = "Couldn't update your RSVP. Please try again."
        return
      }
      var updated = post
      updated.detail?.event = response.event
      post = updated
    } catch {
      actionError = "Couldn't update your RSVP. Please try again."
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
        liked: post.viewerLiked,
        likesCount: post.likesCount,
        saved: post.viewerSaved,
        savesCount: post.savesCount,
        commentsCount: post.commentsCount
      )
    )
  }

  private func applyCachedEngagement(from cached: MIRAPost) {
    post = post.updating(
      liked: post.viewerLikedValue ?? cached.viewerLikedValue,
      likesCount: post.likesCount ?? cached.likesCount,
      commentsCount: post.commentsCount ?? cached.commentsCount,
      saved: post.viewerSavedValue ?? cached.viewerSavedValue,
      savesCount: post.savesCount ?? cached.savesCount
    )
  }

  private func stableEngagementCount(current: Int?, incoming: Int?, optimistic: Int? = nil, toggledOn: Bool? = nil) -> Int? {
    let fallback = optimistic ?? current
    guard let incoming else { return fallback }
    return max(0, incoming)
  }

  private func beginLikeMutation(for postId: String) -> Int {
    let next = (likeMutationVersions[postId] ?? 0) + 1
    likeMutationVersions[postId] = next
    return next
  }

  private func isCurrentLikeMutation(_ version: Int, for postId: String) -> Bool {
    likeMutationVersions[postId] == version
  }

  private func finishLikeMutation(_ version: Int, for postId: String) {
    if likeMutationVersions[postId] == version {
      likeMutationVersions[postId] = nil
    }
  }

  private func loadCurrentUserIfNeeded() async {
    guard currentUserId == nil else { return }
    let me: MIRAUser? = try? await api.get("/auth/me")
    currentUserId = me?.id
  }
}

private struct CaptroAttendanceBody: Encodable {
  let going: Bool
}

private struct CaptroAttendanceResponse: Decodable {
  let event: CaptroEventDetails
}

public struct PostDetailNativeView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: PostDetailModel
  @State private var draft = ""
  @State private var isSendingComment = false
  @State private var replyingTo: MIRAComment?
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportComment: MIRAComment?
  @State private var isReportSheetPresented = false
  @State private var isPostOptionsPresented = false
  @FocusState private var isCommentFocused: Bool

  public init(post: MIRAPost, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: PostDetailModel(post: post, api: api))
  }

  private var detailMediaURLs: [String] {
    let originals = model.post.mediaURLs
    return originals.isEmpty ? model.post.feedMediaURLs : originals
  }

  public var body: some View {
    GeometryReader { layout in
      VStack(spacing: 0) {
        detailHeader
        ScrollViewReader { scroll in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              if let document = model.privateObject?.document {
                CaptroPrivateReceiptOriginal(receiptID: document.receiptId, api: model.api)
              } else if !detailMediaURLs.isEmpty {
                PostDetailOptimizedMediaCarousel(
                  urls: detailMediaURLs,
                  post: model.post,
                  height: layout.size.width * MIRAMediaSizing.mainFeedDisplayRatio(
                    for: detailMediaURLs, aspectRatios: model.post.mediaHeightToWidthRatios
                  )
                )
              }

              CaptroPostDetailSections(model: model, onOpenOptions: { isPostOptionsPresented = true })
              if model.isLoadingObject {
                ProgressView().frame(maxWidth: .infinity).padding(16)
              } else if let error = model.objectError {
                Button { Task { await model.loadPrivateObject() } } label: {
                  Label(error, systemImage: "arrow.clockwise").font(.system(size: 13)).padding(16)
                }
              }
              reactionRow {
                withAnimation { scroll.scrollTo("post-comments", anchor: .top) }
                isCommentFocused = true
              }

              if model.post.detailKind == .placeReview || model.post.detailKind == .regular {
                CaptroDetailLocationSection(post: model.post)
                  .padding(.horizontal, 16)
                  .padding(.bottom, 16)
              }

              commentsSection
                .id("post-comments")
            }
            .padding(.bottom, 24)
          }
          .scrollIndicators(.hidden)
          .scrollDismissesKeyboard(.interactively)
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { commentBar }
    .background(Color.white)
    .foregroundStyle(CaptroDetailStyle.ink)
    .tint(CaptroDetailStyle.accent)
    .environment(\.colorScheme, .light)
    .miraScreenEnter(.push)
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
    .confirmationDialog("Post", isPresented: $isPostOptionsPresented, titleVisibility: .hidden) {
      Button("Report post", role: .destructive) { presentPostReport() }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Couldn't complete that action", isPresented: Binding(
      get: { model.actionError != nil },
      set: { if !$0 { model.actionError = nil } }
    )) {
      Button("OK", role: .cancel) { model.actionError = nil }
    } message: {
      Text(model.actionError ?? "")
    }
    .miraBottomSheet(
      isPresented: $isReportSheetPresented,
      preferredHeightFraction: 0.78,
      maxHeight: 700,
      onDismissed: { reportTarget = nil; reportComment = nil }
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
      await model.loadPrivateObject()
      await model.loadComments()
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPostEngagementDidChange)) { notification in
      guard let update = MIRAPostEngagementSync.update(from: notification) else { return }
      model.applyEngagementUpdate(update)
    }
  }

  private var detailHeader: some View {
    ZStack {
      Text("Post")
        .font(.system(size: 17, weight: .semibold))
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 0) {
        Button { dismiss() } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 19, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Back")
        Spacer(minLength: 0)
        ShareLink(item: captroDetailShareURL(model.post)) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 19))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Share post")
        Button {
          Task { await model.toggleSave() }
        } label: {
          Image(systemName: model.post.viewerSaved ? "bookmark.fill" : "bookmark")
            .font(.system(size: 19))
            .foregroundStyle(model.post.viewerSaved ? CaptroDetailStyle.accent : CaptroDetailStyle.ink)
            .frame(width: 44, height: 44)
        }
        .disabled(model.isSaving)
        .accessibilityLabel(model.post.viewerSaved ? "Unsave post" : "Save post")
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 8)
    }
    .frame(height: 52)
    .background(Color.white)
    .overlay(alignment: .bottom) {
      Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
    }
  }

  private func reactionRow(onComment: @escaping () -> Void) -> some View {
    HStack(spacing: 0) {
      Button {
        Task { await model.toggleLike() }
      } label: {
        reactionLabel(model.post.viewerLiked ? "heart.fill" : "heart", text: compact(model.post.likesCount ?? 0))
          .foregroundStyle(model.post.viewerLiked ? CaptroDetailStyle.accent : CaptroDetailStyle.ink)
      }
      .accessibilityLabel(model.post.viewerLiked ? "Unlike post" : "Like post")
      Button(action: onComment) {
        reactionLabel("bubble.right", text: compact(model.post.commentsCount ?? model.comments.count))
      }
      .accessibilityLabel("Comments")
      ShareLink(item: captroDetailShareURL(model.post)) {
        reactionLabel("square.and.arrow.up", text: "Share")
      }
      Button {
        Task { await model.toggleSave() }
      } label: {
        reactionLabel(model.post.viewerSaved ? "bookmark.fill" : "bookmark", text: model.post.viewerSaved ? "Saved" : "Save")
          .foregroundStyle(model.post.viewerSaved ? CaptroDetailStyle.accent : CaptroDetailStyle.ink)
      }
      .disabled(model.isSaving)
    }
    .buttonStyle(.plain)
    .foregroundStyle(CaptroDetailStyle.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func reactionLabel(_ icon: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon).font(.system(size: 18))
      Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
  }

  private var commentsSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
      Text("Comments \(model.post.commentsCount ?? model.comments.count)")
        .font(.system(size: 15, weight: .semibold))
        .accessibilityAddTraits(.isHeader)

      if model.isLoadingComments && model.comments.isEmpty {
        ForEach(0..<3, id: \.self) { _ in PostDetailCommentSkeleton() }
      } else if let error = model.commentsError {
        VStack(alignment: .leading, spacing: 8) {
          Text(error).font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary)
          Button("Try Again") { Task { await model.loadComments() } }
            .font(.system(size: 13, weight: .semibold))
            .frame(minHeight: 44)
        }
      } else if model.comments.isEmpty {
        Text("No comments yet.")
          .font(.system(size: 14))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .padding(.vertical, 12)
      }

      LazyVStack(spacing: 20) {
        ForEach(model.comments) { comment in
          CommentRow(
            comment: comment,
            currentUserId: model.currentUserId,
            postOwnerId: model.post.userId,
            onReply: { replyingTo = comment; isCommentFocused = true },
            onLike: { Task { await model.toggleCommentLike(comment) } },
            onPin: { Task { await model.toggleCommentPin(comment) } },
            onReport: { presentReport(for: comment) },
            onBlockUser: { Task { await model.blockCommentAuthor(comment) } },
            onDelete: { Task { await model.deleteComment(comment) } },
            onHide: { Task { await model.hideComment(comment) } },
            editorial: true
          )
        }
      }
    }
    .padding(.horizontal, 16)
  }

  private var commentBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let replyingTo {
        HStack {
          Text("Replying to \(replyingTo.user?.displayName ?? "comment")")
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
          Spacer(minLength: 0)
          Button { self.replyingTo = nil } label: {
            Image(systemName: "xmark").font(.system(size: 12)).frame(width: 32, height: 32)
          }
          .accessibilityLabel("Cancel reply")
        }
        .foregroundStyle(CaptroDetailStyle.secondary)
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Add a comment...", text: $draft, axis: .vertical)
          .font(.system(size: 14))
          .textInputAutocapitalization(.sentences)
          .submitLabel(.send)
          .focused($isCommentFocused)
          .lineLimit(1...5)
          .padding(.horizontal, 12)
          .padding(.vertical, 12)
          .frame(minHeight: 44)
          .background(Color.black.opacity(0.025))
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(CaptroDetailStyle.divider, lineWidth: 0.75))
          .onSubmit(sendDraftComment)
          .accessibilityLabel("Add a comment")
        Button(action: sendDraftComment) {
          Group {
            if isSendingComment {
              ProgressView().tint(CaptroDetailStyle.accent)
            } else {
              Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
            }
          }
          .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSendComment ? CaptroDetailStyle.accent : CaptroDetailStyle.secondary)
        .disabled(!canSendComment)
        .accessibilityLabel("Send comment")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.white)
    .overlay(alignment: .top) {
      Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
    }
  }

  private var canSendComment: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingComment
  }

  private func sendDraftComment() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSendComment else { return }
    let parentId = replyingTo?.id
    isSendingComment = true
    Task {
      let didSend = await model.sendComment(text, parentId: parentId)
      if didSend {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        replyingTo = nil
      }
      isSendingComment = false
    }
  }

  private func presentPostReport() {
    reportComment = nil
    reportTarget = MIRAReportTarget(
      targetType: "post", targetId: model.post.id, ownerUserId: model.post.userId,
      title: "Report post", subtitle: model.post.titleText
    )
    isReportSheetPresented = true
  }

  private func presentReport(for comment: MIRAComment) {
    reportComment = comment
    reportTarget = MIRAReportTarget(
      targetType: "comment", targetId: comment.id, ownerUserId: comment.userId,
      title: "Report comment", subtitle: comment.text
    )
    isReportSheetPresented = true
  }

  private func handleReportResult(_ result: MIRAReportResult) {
    guard let reportComment else {
      if result.hidden || result.blocked { dismiss() }
      return
    }
    if result.blocked, let userId = reportComment.userId {
      model.removeComments(byUserId: userId)
    } else if result.hidden {
      model.removeCommentLocally(reportComment)
    }
  }
}

private struct PostDetailOptimizedMediaCarousel: View {
  let urls: [String]
  let post: MIRAPost
  let height: CGFloat
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedIndex = 0
  @State private var isVisible = false
  @State private var isVideoPaused = false
  @State private var isMuted = true

  private var visibleDots: [Int] {
    let start = min(max(0, selectedIndex - 3), max(0, urls.count - 7))
    return Array(start..<min(urls.count, start + 7))
  }

  var body: some View {
    Group {
      if urls.count == 1 {
        mediaSlide(index: 0, url: urls[0])
      } else {
        TabView(selection: $selectedIndex) {
          ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
            mediaSlide(index: index, url: url).tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
      }
    }
    .frame(height: height)
    .frame(maxWidth: .infinity)
    .background(Color.black.opacity(0.03))
    .clipped()
    .overlay(alignment: .topTrailing) {
      if urls.count > 1 {
        Text("\(selectedIndex + 1) / \(urls.count)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(Color.black.opacity(0.55))
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .padding(12)
          .allowsHitTesting(false)
      }
    }
    .overlay(alignment: .bottom) {
      if urls.count > 1 {
        HStack(spacing: 5) {
          ForEach(visibleDots, id: \.self) { index in
            Circle()
              .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.45))
              .frame(width: 6, height: 6)
          }
        }
        .padding(7)
        .background(Color.black.opacity(0.22))
        .clipShape(Capsule())
        .padding(.bottom, 18)
        .accessibilityHidden(true)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if urls.indices.contains(selectedIndex), isVideo(at: selectedIndex, url: urls[selectedIndex]) {
        HStack(spacing: 4) {
          Button { isVideoPaused.toggle() } label: {
            Image(systemName: isVideoPaused ? "play.fill" : "pause.fill")
              .frame(width: 40, height: 44)
          }
          .accessibilityLabel(isVideoPaused ? "Play video" : "Pause video")
          Button { isMuted.toggle() } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
              .frame(width: 40, height: 44)
          }
          .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
        }
        .font(.system(size: 15))
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .buttonStyle(.plain)
        .padding(12)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Post media, \(selectedIndex + 1) of \(urls.count)")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: selectedIndex = min(urls.count - 1, selectedIndex + 1)
      case .decrement: selectedIndex = max(0, selectedIndex - 1)
      @unknown default: break
      }
    }
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
    .onChange(of: selectedIndex) { _, _ in isVideoPaused = false }
    .onChange(of: urls) { _, _ in selectedIndex = 0 }
    .task(id: urls.joined(separator: "|")) { await prefetchNearbyMedia() }
  }

  private func mediaSlide(index: Int, url: String) -> some View {
    RemoteMediaView(
      url: url,
      isVideo: isVideo(at: index, url: url),
      placeholderURL: placeholderURL(at: index, mediaURL: url),
      fallbackURL: fallbackURL(at: index, mediaURL: url),
      contentMode: .fill,
      shouldPlay: isVisible && scenePhase == .active && selectedIndex == index && !isVideoPaused,
      videoMuted: isMuted,
      maxPixelSize: MIRAMediaSizing.feedTargetHeight,
      placeholderColor: Color.black.opacity(0.03)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private func isVideo(at index: Int, url: String) -> Bool {
    let types = post.mediaTypes?.values ?? []
    if types.indices.contains(index) {
      return types[index].lowercased().contains("video")
    }
    return url.isVideoURL
  }

  private func placeholderURL(at index: Int, mediaURL: String) -> String? {
    let posters = post.posterMediaURLs
    if posters.indices.contains(index), posters[index] != mediaURL { return posters[index] }
    let thumbnails = post.thumbnailMediaURLs
    if thumbnails.indices.contains(index), thumbnails[index] != mediaURL { return thumbnails[index] }
    return (post.posterMediaURLs + post.thumbnailMediaURLs)
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != mediaURL && !$0.isVideoURL }
  }

  private func fallbackURL(at index: Int, mediaURL: String) -> String? {
    let originals = post.fallbackMediaURLs
    guard originals.indices.contains(index) else { return nil }
    let original = originals[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !original.isEmpty, original != mediaURL, !original.isVideoURL else { return nil }
    return original
  }

  private func prefetchNearbyMedia() async {
    let previewURLs = (post.posterMediaURLs + post.thumbnailMediaURLs)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let fallbackURLs = post.fallbackMediaURLs
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.isVideoURL }
    let imageURLs = urls.filter { !$0.isVideoURL }
    await MIRAImagePrefetcher.prefetch(urls: previewURLs, maxPixelSize: 560, limit: max(12, previewURLs.count))
    await MIRAImagePrefetcher.prefetch(urls: imageURLs + fallbackURLs, maxPixelSize: MIRAMediaSizing.feedTargetHeight, limit: max(18, imageURLs.count + fallbackURLs.count))
    await MainActor.run {
      MIRAVideoPrewarmManager.shared.prewarm(urls: urls.filter(\.isVideoURL), keepOnly: Set(urls.filter(\.isVideoURL).prefix(2)))
    }
  }
}

public struct DiscoverPostDetailNativeView: View {
  private let post: MIRAPost
  private let api: MIRAAPIClient

  public init(post: MIRAPost, api: MIRAAPIClient) {
    self.post = post
    self.api = api
  }

  public var body: some View {
    PostDetailNativeView(post: post, api: api)
  }
}

struct DiscoverDetailCommentsSheet: View {
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
  var editorial = false

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
            .foregroundStyle(editorial ? CaptroDetailStyle.accent : MIRATheme.Color.forest)
        }
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(comment.user?.displayName ?? "user")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(editorial ? CaptroDetailStyle.ink : MIRATheme.Color.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .layoutPriority(1)
            if let createdAt = comment.createdAt {
              Text(relativeAge(createdAt))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(editorial ? CaptroDetailStyle.secondary : MIRATheme.Color.textMuted.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
          }
          Text(comment.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(editorial ? CaptroDetailStyle.ink : MIRATheme.Color.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .padding(.horizontal, editorial ? 0 : MIRATheme.Space.md)
        .padding(.vertical, editorial ? 0 : 10)
        .background(editorial ? Color.clear : MIRATheme.Color.surfaceSoft.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: editorial ? 0 : 16, style: .continuous))

        HStack(spacing: MIRATheme.Space.lg) {
          Button("Reply") {
            CaptroHaptics.light()
            onReply()
          }
          .buttonStyle(.plain)
          .frame(minHeight: editorial ? 32 : 0)
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
          .frame(minWidth: editorial ? 44 : 0, minHeight: editorial ? 32 : 0)
          .foregroundStyle(comment.viewerLiked ? MIRATheme.Color.like : (editorial ? CaptroDetailStyle.secondary : MIRATheme.Color.textMuted))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(editorial ? CaptroDetailStyle.secondary : MIRATheme.Color.textMuted)
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

func relativeAge(_ value: String?) -> String {
  guard let value else { return "" }
  let formatter = ISO8601DateFormatter()
  let standardDate = formatter.date(from: value)
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  guard let date = standardDate ?? formatter.date(from: value) else { return "" }
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
