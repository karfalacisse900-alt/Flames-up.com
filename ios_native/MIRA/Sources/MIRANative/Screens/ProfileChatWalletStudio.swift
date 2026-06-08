import Foundation
import PhotosUI
import SwiftUI
import UIKit

private func profileVisiblePosts(_ posts: [MIRAPost]) -> [MIRAPost] {
  posts.filter {
    ($0.postType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "note"
  }
}

@MainActor
final class ProfileNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var posts: [MIRAPost] = []
  @Published var profileError: String?
  let api: MIRAAPIClient
  private let userCacheKey = "native.profile.me.v2"
  private var isLoadingFreshProfile = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func prepareForStartup(signedInUser: MIRAUser?) async {
    MIRAPerformanceTimeline.mark("profile_startup_prepare")
    primeUser(signedInUser)
    await hydrateCachedProfileIfNeeded()
    Task { await load() }
  }

  func load() async {
    guard !isLoadingFreshProfile else { return }
    isLoadingFreshProfile = true
    defer { isLoadingFreshProfile = false }

    await hydrateCachedProfileIfNeeded()

    guard let freshUser: MIRAUser = try? await api.get("/auth/me") else { return }
    if user != freshUser {
      user = freshUser
    }
    await MIRAAppCacheStore.shared.saveCurrentProfile(freshUser)
    await MIRALocalJSONCache.save(freshUser, key: userCacheKey)
    let freshPosts = profileVisiblePosts((try? await api.get("/users/\(freshUser.id)/posts")) ?? posts)
    if posts != freshPosts {
      posts = freshPosts
    }
    await MIRAAppCacheStore.shared.saveProfilePosts(freshPosts, userId: freshUser.id)
    await MIRALocalJSONCache.save(freshPosts, key: postsCacheKey(for: freshUser.id))
  }

  func primeUser(_ signedInUser: MIRAUser?) {
    guard user == nil, let signedInUser else { return }
    user = signedInUser
  }

  private func hydrateCachedProfileIfNeeded() async {
    guard user == nil else { return }
    var cachedUser = await MIRAAppCacheStore.shared.loadCurrentProfile()
    if cachedUser == nil {
      cachedUser = await MIRALocalJSONCache.load(MIRAUser.self, key: userCacheKey, maxAge: 60 * 60 * 24 * 90)
    }
    guard let cachedUser else { return }
    user = cachedUser
    var cachedPosts = await MIRAAppCacheStore.shared.loadProfilePosts(userId: cachedUser.id)
    if cachedPosts == nil {
      cachedPosts = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: cachedUser.id), maxAge: 60 * 60 * 24 * 90)
    }
    posts = profileVisiblePosts(cachedPosts ?? posts)
  }

  func applyUpdatedUser(_ updated: MIRAUser) async {
    user = updated
    await MIRAAppCacheStore.shared.saveCurrentProfile(updated)
    await MIRALocalJSONCache.save(updated, key: userCacheKey)
  }

  func deletePost(_ post: MIRAPost) async {
    guard let user else { return }
    let previousPosts = posts
    posts.removeAll { $0.id == post.id }
    do {
      let _: EmptyResponse = try await api.delete("/posts/\(post.id)")
      await MIRAAppCacheStore.shared.saveProfilePosts(posts, userId: user.id)
      await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
      MIRAPostRemovalSync.publish(MIRAPostRemovalUpdate(postId: post.id))
      profileError = nil
    } catch {
      posts = previousPosts
      profileError = "Could not delete this post."
    }
  }

  func updatePostVisibility(_ post: MIRAPost, visibility: String) async {
    guard let user else { return }
    do {
      let updated: MIRAPost = try await api.put(
        "/posts/\(post.id)/visibility",
        body: PostVisibilityUpdateBody(visibility: visibility)
      )
      if let index = posts.firstIndex(where: { $0.id == post.id }) {
        posts[index] = updated
      }
      await MIRAAppCacheStore.shared.saveProfilePosts(posts, userId: user.id)
      await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
      if visibility == "private" {
        MIRAPostRemovalSync.publish(MIRAPostRemovalUpdate(postId: post.id))
      }
      profileError = nil
    } catch {
      profileError = "Could not update post visibility."
    }
  }

  func removePostLocally(id postId: String) async {
    guard let user, posts.contains(where: { $0.id == postId }) else { return }
    posts.removeAll { $0.id == postId }
    await MIRAAppCacheStore.shared.saveProfilePosts(posts, userId: user.id)
    await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
  }

  func togglePin(_ post: MIRAPost) async {
    guard let user else { return }
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = posts[index]
    let shouldPin = !previous.isPinned
    posts[index] = previous.updatingPinned(at: shouldPin ? ISO8601DateFormatter().string(from: Date()) : nil)
    do {
      let updated: MIRAPost = try await api.put("/posts/\(post.id)/pin", body: PostPinBody(pinned: shouldPin))
      if let currentIndex = posts.firstIndex(where: { $0.id == post.id }) {
        posts[currentIndex] = updated
      }
      posts.sort { lhs, rhs in
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return (lhs.createdAt ?? "") > (rhs.createdAt ?? "")
      }
      await MIRAAppCacheStore.shared.saveProfilePosts(posts, userId: user.id)
      await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
      profileError = nil
    } catch {
      posts[index] = previous
      profileError = "Could not update pinned post."
    }
  }

  private func postsCacheKey(for userID: String) -> String {
    "native.profile.posts.\(userID).v2"
  }
}

private struct PostVisibilityUpdateBody: Encodable {
  let visibility: String
}

private struct ProfileUpdateBody: Encodable {
  let fullName: String?
  let username: String?
  let profileImage: String?
}

private struct ProfileUsernameAvailabilityResponse: Decodable {
  let available: Bool?
  let reason: String?
  let code: String?
}

private struct ProfileGridSkeleton: View {
  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 1) {
      ForEach(0..<9, id: \.self) { _ in
        Rectangle()
          .fill(MIRATheme.Color.surfaceSoft)
          .aspectRatio(1.0 / MIRAMediaSizing.profileGridRatio, contentMode: .fit)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .redacted(reason: .placeholder)
  }
}

public struct ProfileNativeView: View {
  @StateObject private var model: ProfileNativeModel
  @State private var showEditProfile = false
  @State private var singlePhotoPreviewPost: MIRAPost?
  @State private var isSinglePhotoPreviewPresented = false
  @State private var profilePostActionTarget: MIRAPost?
  @State private var isProfilePostActionModalPresented = false
  @State private var deletePostTarget: MIRAPost?
  @State private var isDeletePostConfirmationPresented = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var isReportSheetPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let authSession: MIRAAuthSession?
  private var postGridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
  }

  public init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil) {
    self.authSession = authSession
    _model = StateObject(wrappedValue: ProfileNativeModel(api: api))
  }

  init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil, model: ProfileNativeModel) {
    self.authSession = authSession
    _model = StateObject(wrappedValue: model)
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          profileHeader
          if model.posts.isEmpty && model.user == nil {
            ProfileGridSkeleton()
          } else {
            LazyVGrid(columns: postGridColumns, spacing: 1) {
              ForEach(model.posts) { post in
                profilePostTile(post)
              }
            }
            .frame(maxWidth: .infinity, alignment: .center)
          }
          if let profileError = model.profileError {
            Text(profileError)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.red)
              .padding(.horizontal, MIRATheme.Space.md)
          }
        }
      }
      .background(MIRATheme.Color.appBackground)
      .miraScrollFeel(.feed)
      .miraScreenEnter(.tab)
      .navigationTitle("")
      .toolbar(profileTabBarVisibility, for: .tabBar)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          ProfileToolbarDestinationButton(
            systemImage: "bookmark",
            accessibilityLabel: "Bookmarks",
            destination: LibraryNativeView(api: model.api)
          )
          ProfileToolbarDestinationButton(
            systemImage: "checkmark.shield",
            accessibilityLabel: "Verification",
            destination: WalletNativeView(api: model.api)
          )
          ProfileToolbarDestinationButton(
            systemImage: "gearshape",
            accessibilityLabel: "Settings",
            destination: SettingsNativeView(api: model.api, authSession: authSession)
          )
        }
      }
      .task {
        await MainActor.run {
          model.primeUser(authSession?.user)
        }
        await model.load()
      }
      .onReceive(NotificationCenter.default.publisher(for: .miraPostWasRemoved)) { notification in
        guard let update = MIRAPostRemovalSync.update(from: notification) else { return }
        Task { await model.removePostLocally(id: update.postId) }
      }
      .miraBottomSheet(isPresented: $showEditProfile, preferredHeightFraction: 0.86) { dismissEditProfile in
        EditProfileNativeView(user: model.user, api: model.api, onCancel: dismissEditProfile) { updated in
          Task { @MainActor in
            authSession?.replaceUser(updated)
            await model.applyUpdatedUser(updated)
            dismissEditProfile()
          }
        }
      }
      .miraBottomSheet(
        isPresented: $isSinglePhotoPreviewPresented,
        preferredHeightFraction: 0.78,
        maxHeight: 720,
        onDismissed: { singlePhotoPreviewPost = nil }
      ) { dismissPreview in
        if let post = singlePhotoPreviewPost {
          DiscoverSinglePhotoPreviewSheet(
            post: post,
            api: model.api,
            onReportComment: { comment in
              dismissPreview()
              DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
                presentReport(for: comment)
              }
            }
          )
        } else {
          Color.clear
        }
      }
      .miraBottomSheet(
        isPresented: $isReportSheetPresented,
        preferredHeightFraction: 0.72,
        maxHeight: 640,
        onDismissed: { reportTarget = nil }
      ) { dismissReport in
        if let reportTarget {
          MIRAReportSheet(
            target: reportTarget,
            api: model.api,
            onSubmitted: { _ in },
            onClose: dismissReport
          )
        } else {
          Color.clear
        }
      }
      .miraActionModal(
        isPresented: $isProfilePostActionModalPresented,
        onDismissed: { profilePostActionTarget = nil }
      ) { dismissMenu in
        if let post = profilePostActionTarget {
          ProfilePostOwnerActionModal(
            post: post,
            onPin: {
              dismissMenu()
              Task { await model.togglePin(post) }
            },
            onMakePublic: {
              dismissMenu()
              Task { await model.updatePostVisibility(post, visibility: "public") }
            },
            onMakePrivate: {
              dismissMenu()
              Task { await model.updatePostVisibility(post, visibility: "private") }
            },
            onDelete: {
              dismissMenu()
              deletePostTarget = post
              DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.actionModalClose) {
                isDeletePostConfirmationPresented = true
              }
            }
          )
        } else {
          Color.clear
        }
      }
      .confirmationDialog(
        "Are you sure you want to delete this post?",
        isPresented: $isDeletePostConfirmationPresented,
        titleVisibility: .visible
      ) {
        Button("Delete post", role: .destructive) {
          if let deletePostTarget {
            Task { await model.deletePost(deletePostTarget) }
          }
          deletePostTarget = nil
        }
        Button("Cancel", role: .cancel) {
          deletePostTarget = nil
        }
      } message: {
        Text("This post will be removed from your profile.")
      }
    }
  }

  @ViewBuilder
  private func profilePostTile(_ post: MIRAPost) -> some View {
    if miraShouldOpenSinglePhotoPreview(post) {
      Button {
        openSinglePhotoPreview(post)
      } label: {
        ProfilePostTile(post: post)
      }
      .buttonStyle(.plain)
      .highPriorityGesture(LongPressGesture(minimumDuration: 0.38).onEnded { _ in
        presentProfilePostActions(post)
      })
    } else {
      NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: model.api).miraHideTabBarOnAppear()) {
        ProfilePostTile(post: post)
      }
      .buttonStyle(.plain)
      .highPriorityGesture(LongPressGesture(minimumDuration: 0.38).onEnded { _ in
        presentProfilePostActions(post)
      })
    }
  }

  private func openSinglePhotoPreview(_ post: MIRAPost) {
    CaptroHaptics.light()
    singlePhotoPreviewPost = post
    withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
      isSinglePhotoPreviewPresented = true
    }
  }

  private func presentReport(for comment: MIRAComment) {
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

  private func presentProfilePostActions(_ post: MIRAPost) {
    CaptroHaptics.light()
    profilePostActionTarget = post
    withAnimation(CaptroMotion.actionModalAnimation(reduceMotion: reduceMotion)) {
      isProfilePostActionModalPresented = true
    }
  }

  private var profileTabBarVisibility: Visibility {
    showEditProfile ||
    isSinglePhotoPreviewPresented ||
    isReportSheetPresented ||
    isProfilePostActionModalPresented ||
    isDeletePostConfirmationPresented ? .hidden : .visible
  }

  private var profileHeader: some View {
    VStack(spacing: MIRATheme.Space.md) {
      RemoteAvatar(url: model.user?.profileImage, size: 92)
      VStack(spacing: 4) {
        Text(profileTitle)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        if let username = model.user?.username, !username.isEmpty {
          Text("@\(username)")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      HStack(spacing: MIRATheme.Space.xl) {
        profileMetric("Posts", model.user?.postsCount ?? model.posts.count)
        profileMetric("Followers", model.user?.followersCount ?? 0)
        profileMetric("Following", model.user?.followingCount ?? 0)
      }
      MIRAPrimaryButton("Edit profile", systemImage: "pencil") {
        CaptroHaptics.light()
        withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
          showEditProfile = true
        }
      }
    }
    .padding(MIRATheme.Space.xl)
    .frame(maxWidth: .infinity)
    .miraCardSurface()
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private func profileMetric(_ label: String, _ value: Int) -> some View {
    VStack(spacing: 4) {
      Text("\(value)").font(.system(size: 18, weight: .semibold))
      Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(MIRATheme.Color.textMuted)
    }
  }

  private var profileTitle: String {
    if let fullName = model.user?.fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullName
    }
    return model.user?.username ?? "captro"
  }
}

private struct ProfileToolbarDestinationButton<Destination: View>: View {
  let systemImage: String
  let accessibilityLabel: String
  let destination: Destination
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationLink(destination: destination) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
        .overlay(Circle().stroke(MIRATheme.Color.hairline.opacity(0.88), lineWidth: 1))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
    .buttonStyle(.miraPress)
    .simultaneousGesture(
      TapGesture().onEnded {
        CaptroHaptics.light()
        MIRAApplePerformanceLogger.event("profile_route_open", detail: accessibilityLabel)
      }
    )
    .animation(CaptroMotion.buttonPressAnimation(reduceMotion: reduceMotion), value: reduceMotion)
  }
}

@MainActor
final class UserProfileNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var posts: [MIRAPost] = []
  @Published var isFollowing = false
  @Published var followersCount = 0
  @Published var isBlocked = false
  @Published var isBlockedBy = false
  @Published var isLoading = false
  @Published var errorMessage: String?
  let userId: String
  let api: MIRAAPIClient
  private var userCacheKey: String { "native.profile.user.\(userId).v2" }
  private var postsCacheKey: String { "native.profile.posts.\(userId).v2" }

  init(userId: String, api: MIRAAPIClient) {
    self.userId = userId
    self.api = api
  }

  func load() async {
    if user == nil {
      var cachedUser = await MIRAAppCacheStore.shared.loadViewedProfile(userId: userId)
      if cachedUser == nil {
        cachedUser = await MIRALocalJSONCache.load(MIRAUser.self, key: userCacheKey, maxAge: 60 * 60 * 24 * 90)
      }
      if let cachedUser {
        apply(user: cachedUser)
        var cachedPosts = await MIRAAppCacheStore.shared.loadProfilePosts(userId: userId)
        if cachedPosts == nil {
          cachedPosts = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey, maxAge: 60 * 60 * 24 * 90)
        }
        posts = profileVisiblePosts(cachedPosts ?? posts)
      }
    }

    isLoading = user == nil && posts.isEmpty
    defer { isLoading = false }

    if let freshUser: MIRAUser = try? await api.get("/users/\(userId)") {
      apply(user: freshUser)
      await MIRAAppCacheStore.shared.saveViewedProfile(freshUser, userId: userId)
      await MIRALocalJSONCache.save(freshUser, key: userCacheKey)
    }
    let freshPosts = profileVisiblePosts((try? await api.get("/users/\(userId)/posts")) ?? posts)
    if posts != freshPosts {
      posts = freshPosts
    }
    await MIRAAppCacheStore.shared.saveProfilePosts(freshPosts, userId: userId)
    await MIRALocalJSONCache.save(freshPosts, key: postsCacheKey)
  }

  func removePostLocally(id postId: String) async {
    guard posts.contains(where: { $0.id == postId }) else { return }
    posts.removeAll { $0.id == postId }
    await MIRAAppCacheStore.shared.saveProfilePosts(posts, userId: userId)
    await MIRALocalJSONCache.save(posts, key: postsCacheKey)
  }

  func toggleFollow() async {
    let previousFollowing = isFollowing
    let previousFollowers = followersCount
    let nextFollowing = !isFollowing
    isFollowing = nextFollowing
    followersCount = max(0, followersCount + (nextFollowing ? 1 : -1))
    do {
      let response: FollowResponse = try await api.post("/users/\(userId)/follow", body: FollowBody(following: nextFollowing))
      isFollowing = response.following ?? nextFollowing
      followersCount = response.followersCount ?? followersCount
      MIRAUserFollowSync.publish(MIRAUserFollowUpdate(userId: userId, following: isFollowing, followersCount: followersCount))
    } catch {
      isFollowing = previousFollowing
      followersCount = previousFollowers
    }
  }

  func blockUser() async -> Bool {
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      isBlocked = true
      isFollowing = false
      posts = []
      MIRAUserFollowSync.publish(MIRAUserFollowUpdate(userId: userId, following: false))
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not block this user. Try again in a moment."
      return false
    }
  }

  func unblockUser() async -> Bool {
    do {
      let _: EmptyResponse? = try await api.delete("/users/\(userId)/block")
      isBlocked = false
      errorMessage = nil
      await load()
      return true
    } catch {
      errorMessage = "Could not unblock this user. Try again in a moment."
      return false
    }
  }

  private func apply(user freshUser: MIRAUser) {
    user = freshUser
    isFollowing = freshUser.viewerFollowing
    followersCount = freshUser.followersCount ?? followersCount
    isBlocked = freshUser.viewerHasBlocked == true
    isBlockedBy = freshUser.viewerBlockedBy == true
  }
}

public struct UserProfileNativeView: View {
  @StateObject private var model: UserProfileNativeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var reportTarget: MIRAReportTarget?
  @State private var isReportSheetPresented = false
  @State private var isProfileOptionsPresented = false
  @State private var singlePhotoPreviewPost: MIRAPost?
  @State private var isSinglePhotoPreviewPresented = false
  @State private var isOpeningMessage = false
  @State private var messageRoute: ChatOpenRoute?
  private var postGridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
  }

  public init(userId: String, api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: UserProfileNativeModel(userId: userId, api: api))
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: MIRATheme.Space.lg) {
        profileHeader

        if model.posts.isEmpty && model.isLoading {
          ProfileGridSkeleton()
        } else if model.posts.isEmpty {
          MIRAEmptyState(title: "No posts yet", message: "This profile has not posted yet.", systemImage: "square.grid.3x3")
            .padding(.horizontal, MIRATheme.Space.md)
        } else {
          LazyVGrid(columns: postGridColumns, spacing: 1) {
            ForEach(model.posts) { post in
              userProfilePostTile(post)
            }
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground)
    .miraScrollFeel(.feed)
    .miraScreenEnter(.push)
    .navigationTitle(model.user?.displayName ?? "Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .task { await model.load() }
    .onReceive(NotificationCenter.default.publisher(for: .miraPostWasRemoved)) { notification in
      guard let update = MIRAPostRemovalSync.update(from: notification) else { return }
      Task { await model.removePostLocally(id: update.postId) }
    }
    .background {
      NavigationLink(
        isActive: Binding(
          get: { messageRoute != nil },
          set: { isActive in
            if !isActive { messageRoute = nil }
          }
        )
      ) {
        if let route = messageRoute {
          ConversationNativeView(title: route.title, model: route.model, initialAvatarURL: route.avatarURL)
            .miraHideTabBarOnAppear()
        } else {
          EmptyView()
        }
      } label: {
        EmptyView()
      }
      .hidden()
    }
    .miraBottomSheet(
      isPresented: $isSinglePhotoPreviewPresented,
      preferredHeightFraction: 0.78,
      maxHeight: 720,
      onDismissed: { singlePhotoPreviewPost = nil }
    ) { dismissPreview in
      if let post = singlePhotoPreviewPost {
        DiscoverSinglePhotoPreviewSheet(
          post: post,
          api: model.api,
          onReportComment: { comment in
            dismissPreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
              presentReport(for: comment)
            }
          }
        )
      } else {
        Color.clear
      }
    }
    .miraBottomSheet(
      isPresented: $isReportSheetPresented,
      preferredHeightFraction: 0.72,
      maxHeight: 640,
      onDismissed: { reportTarget = nil }
    ) { dismissReport in
      if let reportTarget {
        MIRAReportSheet(
          target: reportTarget,
          api: model.api,
          onSubmitted: { result in
            if result.blocked {
              model.isBlocked = true
              model.isFollowing = false
              model.posts = []
            }
          },
          onClose: dismissReport
        )
      } else {
        Color.clear
      }
    }
    .miraActionModal(isPresented: $isProfileOptionsPresented) { dismissOptions in
      MIRAActionModalCard {
        MIRAActionModalButton(
          title: model.isBlocked ? "Unblock" : "Block",
          systemImage: model.isBlocked ? "hand.raised.slash" : "nosign",
          isDestructive: !model.isBlocked,
          staggerIndex: 0
        ) {
          dismissOptions()
          Task {
            if model.isBlocked {
              _ = await model.unblockUser()
            } else {
              _ = await model.blockUser()
            }
          }
        }

        MIRAActionModalButton(
          title: "Report",
          systemImage: "exclamationmark.triangle",
          staggerIndex: 1
        ) {
          dismissOptions()
          DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.actionModalClose) {
            presentProfileReport()
          }
        }

        if model.isFollowing {
          MIRAActionModalButton(
            title: "Unfollow",
            systemImage: "person.badge.minus",
            staggerIndex: 2
          ) {
            dismissOptions()
            Task { await model.toggleFollow() }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func userProfilePostTile(_ post: MIRAPost) -> some View {
    if miraShouldOpenSinglePhotoPreview(post) {
      Button {
        openSinglePhotoPreview(post)
      } label: {
        ProfilePostTile(post: post)
      }
      .buttonStyle(.plain)
    } else {
      NavigationLink(destination: DiscoverPostDetailNativeView(post: post, api: model.api).miraHideTabBarOnAppear()) {
        ProfilePostTile(post: post)
      }
      .buttonStyle(.plain)
    }
  }

  private func openSinglePhotoPreview(_ post: MIRAPost) {
    CaptroHaptics.light()
    singlePhotoPreviewPost = post
    withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
      isSinglePhotoPreviewPresented = true
    }
  }

  private func presentReport(for comment: MIRAComment) {
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

  private var profileHeader: some View {
    VStack(spacing: MIRATheme.Space.md) {
      ZStack(alignment: .topTrailing) {
        RemoteAvatar(url: model.user?.profileImage, size: 92)
          .frame(maxWidth: .infinity)
        profileSafetyMenu
      }
      VStack(spacing: 4) {
        Text(profileTitle)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        if let username = model.user?.username, !username.isEmpty {
          Text("@\(username)")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }

      HStack(spacing: MIRATheme.Space.xl) {
        profileMetric("Posts", model.user?.postsCount ?? model.posts.count)
        profileMetric("Followers", model.followersCount)
        profileMetric("Following", model.user?.followingCount ?? 0)
      }

      if model.isBlocked {
        profileStatusNotice("You blocked this user. Unblock them to message or follow again.")
      } else if model.isBlockedBy {
        profileStatusNotice("This profile is unavailable.")
      } else {
        HStack(spacing: MIRATheme.Space.sm) {
          Button {
            Task { await model.toggleFollow() }
          } label: {
            Label(model.isFollowing ? "Following" : "Follow", systemImage: model.isFollowing ? "checkmark" : "plus")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(model.isFollowing ? MIRATheme.Color.textPrimary : .white)
              .frame(maxWidth: .infinity, minHeight: 46)
              .background(model.isFollowing ? MIRATheme.Color.surfaceSoft : MIRATheme.Color.forest)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)

          Button {
            Task { await openMessageChat() }
          } label: {
            Label(isOpeningMessage ? "Opening" : "Message", systemImage: isOpeningMessage ? "hourglass" : "message")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity, minHeight: 46)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isOpeningMessage)
        }
      }
    }
    .padding(MIRATheme.Space.xl)
    .frame(maxWidth: .infinity)
    .miraCardSurface()
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var profileSafetyMenu: some View {
    Button {
      CaptroHaptics.light()
      DispatchQueue.main.async {
        withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
          isProfileOptionsPresented = true
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel("Profile options")
  }

  private func presentProfileReport() {
    CaptroHaptics.medium()
    reportTarget = MIRAReportTarget(
      targetType: "profile",
      targetId: model.userId,
      ownerUserId: model.userId,
      title: "Report profile",
      subtitle: model.user?.displayName ?? model.user?.username
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  @MainActor
  private func openMessageChat() async {
    guard !isOpeningMessage else { return }
    isOpeningMessage = true
    defer { isOpeningMessage = false }

    let roomModel = ConversationNativeModel(kind: .direct(peerId: model.userId), api: model.api, currentUserId: "")
    messageRoute = ChatOpenRoute(
      id: "profile-\(model.userId)",
      title: model.user?.displayName ?? "Chat",
      avatarURL: model.user?.profileImage,
      model: roomModel
    )
  }

  private func profileStatusNotice(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 12)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func profileMetric(_ label: String, _ value: Int) -> some View {
    VStack(spacing: 4) {
      Text("\(value)").font(.system(size: 18, weight: .semibold))
      Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(MIRATheme.Color.textMuted)
    }
  }

  private var profileTitle: String {
    if let fullName = model.user?.fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullName
    }
    return model.user?.username ?? "captro"
  }
}

private struct UserProfileSafetyOptionsSheet: View {
  let isBlocked: Bool
  let onReport: () -> Void
  let onBlock: () -> Void
  let onUnblock: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.28))
        .frame(width: 42, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 16)

      Text("Profile options")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.bottom, 10)

      Button(role: .destructive, action: onReport) {
        UserProfileOptionRow(
          title: "Report profile",
          subtitle: "Send this profile to Captro moderation.",
          systemImage: "flag",
          tint: .red
        )
      }
      .buttonStyle(.miraPress)

      if isBlocked {
        Button(action: onUnblock) {
          UserProfileOptionRow(
            title: "Unblock user",
            subtitle: "Allow this profile to interact again.",
            systemImage: "hand.raised.slash",
            tint: MIRATheme.Color.forest
          )
        }
        .buttonStyle(.miraPress)
      } else {
        Button(role: .destructive, action: onBlock) {
          UserProfileOptionRow(
            title: "Block user",
            subtitle: "Stop messages and unwanted contact.",
            systemImage: "hand.raised.fill",
            tint: .red
          )
        }
        .buttonStyle(.miraPress)
      }

      Spacer(minLength: 0)
    }
    .background(MIRATheme.Color.surface)
  }
}

private struct UserProfileOptionRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.10))
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.65))
    }
    .padding(.horizontal, MIRATheme.Space.lg)
    .frame(minHeight: 58)
    .contentShape(Rectangle())
  }
}

private struct ProfilePostTile: View {
  let post: MIRAPost
  var size: CGFloat? = nil
  var onPin: (() -> Void)? = nil
  var onDelete: (() -> Void)? = nil
  var onMakePublic: (() -> Void)? = nil
  var onMakePrivate: (() -> Void)? = nil
  var onOpenActions: (() -> Void)? = nil

  private var normalizedVisibility: String {
    post.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "public"
  }

  private var isPrivate: Bool {
    normalizedVisibility == "private"
  }

  var body: some View {
    Group {
      if hasOwnerActions {
        tileContent
          .highPriorityGesture(LongPressGesture(minimumDuration: 0.38).onEnded { _ in
            CaptroHaptics.light()
            onOpenActions?()
          })
      } else {
        tileContent
      }
    }
  }

  private var tileContent: some View {
    GeometryReader { proxy in
      let tileWidth = size ?? proxy.size.width
      let tileHeight = tileWidth * MIRAMediaSizing.profileGridRatio
      ZStack(alignment: .topTrailing) {
        Group {
          if let media = post.thumbnailMediaURLs.first {
            RemoteMediaView(
              url: media,
              isVideo: media.isVideoURL,
              shouldPlay: false,
              maxPixelSize: 520,
              showsVideoPlaceholderIcon: false
            )
          } else {
            MIRATheme.Color.surfaceSoft
          }
        }
        .frame(width: tileWidth, height: tileHeight)
        .clipped()

        statusBadges
      }
      .frame(width: tileWidth, height: tileHeight)
    }
    .aspectRatio(1.0 / MIRAMediaSizing.profileGridRatio, contentMode: .fit)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var statusBadges: some View {
    if post.isPinned || isPrivate {
      HStack(spacing: 5) {
        if post.isPinned {
          profileTileBadge(systemImage: "pin.fill", label: "Pinned post")
        }
        if isPrivate {
          profileTileBadge(systemImage: "lock.fill", label: "Private post")
        }
      }
      .padding(.top, 10)
      .padding(.trailing, 10)
      .allowsHitTesting(false)
      .zIndex(2)
    }
  }

  private func profileTileBadge(systemImage: String, label: String) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 24, height: 24)
      .background(.black.opacity(0.58))
      .clipShape(Circle())
      .accessibilityLabel(label)
  }

  private var hasOwnerActions: Bool {
    onOpenActions != nil || onPin != nil || onDelete != nil || onMakePublic != nil || onMakePrivate != nil
  }

}

private struct ProfilePostOwnerActionModal: View {
  let post: MIRAPost
  let onPin: () -> Void
  let onMakePublic: () -> Void
  let onMakePrivate: () -> Void
  let onDelete: () -> Void

  private var normalizedVisibility: String {
    post.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "public"
  }

  var body: some View {
    MIRAActionModalCard {
      MIRAActionModalButton(
        title: post.isPinned ? "Unpin post" : "Pin post",
        systemImage: post.isPinned ? "pin.slash" : "pin",
        staggerIndex: 0,
        action: onPin
      )

      if normalizedVisibility == "private" {
        MIRAActionModalButton(
          title: "Make post public",
          systemImage: "globe",
          staggerIndex: 1,
          action: onMakePublic
        )
      } else {
        MIRAActionModalButton(
          title: "Make post private",
          systemImage: "lock",
          staggerIndex: 1,
          action: onMakePrivate
        )
      }

      MIRAActionModalButton(
        title: "Delete post",
        systemImage: "trash",
        isDestructive: true,
        staggerIndex: 2,
        action: onDelete
      )
    }
  }
}

private struct EditProfileNativeView: View {
  let user: MIRAUser?
  let api: MIRAAPIClient
  let onCancel: (() -> Void)?
  let onSaved: (MIRAUser) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var fullName: String
  @State private var username: String
  @State private var profileImage: String?
  @State private var originalUsername: String
  @State private var pickerItem: PhotosPickerItem?
  @State private var pickedImageData: Data?
  @State private var pickedUIImage: UIImage?
  @State private var isSaving = false
  @State private var didHydrateMissingUser = false
  @State private var errorMessage: String?

  init(user: MIRAUser?, api: MIRAAPIClient, onCancel: (() -> Void)? = nil, onSaved: @escaping (MIRAUser) -> Void) {
    self.user = user
    self.api = api
    self.onCancel = onCancel
    self.onSaved = onSaved
    _fullName = State(initialValue: user?.fullName ?? "")
    _username = State(initialValue: user?.username ?? "")
    _profileImage = State(initialValue: user?.profileImage)
    _originalUsername = State(initialValue: MIRAUsernameRules.normalized(user?.username))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.xl) {
          editSheetHandle

          VStack(spacing: MIRATheme.Space.md) {
            profilePhoto
            PhotosPicker(selection: $pickerItem, matching: .images) {
              Text("Change profile picture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.forest)
            }
            .disabled(isSaving)
            .buttonStyle(.miraPress)
          }
          .padding(.top, MIRATheme.Space.sm)

          VStack(spacing: MIRATheme.Space.md) {
            editField(title: "Name", text: $fullName, placeholder: "Your name")
            editField(title: "Username", text: $username, placeholder: "username")
            Text("Use 3-20 lowercase letters, numbers, underscores, or periods. Do not include @.")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(MIRATheme.Space.lg)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .miraScrollFeel(.sheet)
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.modal)
      .navigationTitle("Edit profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") {
            CaptroHaptics.light()
            close()
          }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            CaptroHaptics.light()
            Task { await save() }
          } label: {
            if isSaving {
              ProgressView()
            } else {
              Text("Save").fontWeight(.semibold)
            }
          }
          .disabled(isSaving)
        }
      }
      .onChange(of: pickerItem) { item in
        guard let item else { return }
        Task {
          guard let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
          else {
            errorMessage = "Could not read this photo."
            return
          }
          pickedUIImage = image
          pickedImageData = await preparedProfileImageData(from: image) ?? data
          errorMessage = nil
        }
      }
      .task { await hydrateMissingUserIfNeeded() }
    }
  }

  private var editSheetHandle: some View {
    Capsule()
      .fill(MIRATheme.Color.textMuted.opacity(0.22))
      .frame(width: 42, height: 5)
      .padding(.top, 2)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var profilePhoto: some View {
    if let pickedUIImage {
      Image(uiImage: pickedUIImage)
        .resizable()
        .scaledToFill()
        .frame(width: 104, height: 104)
        .clipShape(Circle())
    } else {
      RemoteAvatar(url: profileImage, size: 104)
    }
  }

  private func editField(title: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      TextField(placeholder, text: text)
        .font(.system(size: 17, weight: .semibold))
        .textInputAutocapitalization(title == "Username" ? .never : .words)
        .autocorrectionDisabled(title == "Username")
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(height: 52)
        .background(MIRATheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
    }
  }

  private func save() async {
    guard !isSaving else { return }
    let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanUsername = MIRAUsernameRules.normalized(username)
    let usernameToSave = cleanUsername.isEmpty ? nil : cleanUsername
    if let usernameToSave, !MIRAUsernameRules.isValidPublicUsername(usernameToSave) {
      errorMessage = "Choose a username with 3-20 letters, numbers, underscores, or periods."
      return
    }
    isSaving = true
    defer { isSaving = false }
    do {
      if let usernameToSave,
         usernameToSave != originalUsername {
        try await verifyUsernameAvailability(usernameToSave)
      }
      var uploadedImage = profileImage
      if let pickedImageData {
        uploadedImage = try await MIRAMediaUploadService(api: api).upload(
          MIRAPickedMedia(
            data: pickedImageData,
            kind: .image,
            fileName: "profile-\(UUID().uuidString).jpg",
            mimeType: "image/jpeg"
          )
        )
        if let uploadedImage, !uploadedImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          await MIRAImagePrefetcher.prefetch(urls: [uploadedImage], maxPixelSize: 420, limit: 1)
        }
      }
      let updated: MIRAUser = try await api.put(
        "/users/me",
        body: ProfileUpdateBody(
          fullName: cleanName.isEmpty ? nil : cleanName,
          username: usernameToSave,
          profileImage: uploadedImage
        )
      )
      if let freshProfileImage = updated.profileImage, !freshProfileImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        await MIRAImagePrefetcher.prefetch(urls: [freshProfileImage], maxPixelSize: 420, limit: 1)
      }
      CaptroHaptics.success()
      onSaved(updated)
    } catch {
      errorMessage = profileSaveErrorMessage(for: error)
    }
  }

  private func verifyUsernameAvailability(_ username: String) async throws {
    let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
    let response: ProfileUsernameAvailabilityResponse = try await api.get("/users/check-username/\(encoded)")
    if response.available == false {
      throw MIRAAPIError.server(
        status: 409,
        code: response.code,
        detail: response.reason ?? "Username is not available."
      )
    }
  }

  private func profileSaveErrorMessage(for error: Error) -> String {
    if let apiError = error as? MIRAAPIError,
       let message = apiError.errorDescription,
       !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return message
    }
    let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty ? "Could not save your profile." : message
  }

  private func preparedProfileImageData(from image: UIImage) async -> Data? {
    await Task.detached(priority: .userInitiated) {
      let maxSide: CGFloat = 1024
      let side = min(image.size.width, image.size.height)
      guard side > 0 else { return nil }
      let origin = CGPoint(
        x: max(0, (image.size.width - side) / 2),
        y: max(0, (image.size.height - side) / 2)
      )
      let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
      let targetSide = min(maxSide, side)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
      let rendered = renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: CGSize(width: targetSide, height: targetSide))).fill()
        image.draw(
          in: CGRect(x: -cropRect.minX * targetSide / side, y: -cropRect.minY * targetSide / side, width: image.size.width * targetSide / side, height: image.size.height * targetSide / side)
        )
      }
      return rendered.jpegData(compressionQuality: 0.88)
    }.value
  }

  private func close() {
    if let onCancel {
      onCancel()
    } else {
      dismiss()
    }
  }

  private func hydrateMissingUserIfNeeded() async {
    guard user == nil, !didHydrateMissingUser else { return }
    didHydrateMissingUser = true
    guard let me: MIRAUser = try? await api.get("/auth/me") else { return }
    if fullName.isEmpty {
      fullName = me.fullName ?? ""
    }
    if username.isEmpty {
      username = me.username ?? ""
    }
    if originalUsername.isEmpty {
      originalUsername = MIRAUsernameRules.normalized(me.username)
    }
    if profileImage == nil {
      profileImage = me.profileImage
    }
  }
}

@MainActor
final class ChatNativeModel: ObservableObject {
  @Published var conversations: [MIRAConversation] = []
  @Published var isLoading = false
  let api: MIRAAPIClient
  private let localStore = MIRAChatLocalStore.shared
  private var currentUserId = ""
  private var hasLoadedFreshConversations = false
  private var isLoadingFreshConversations = false

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func configure(currentUserId: String) {
    let clean = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean != self.currentUserId else { return }
    self.currentUserId = clean
    hasLoadedFreshConversations = false
    if !conversations.isEmpty {
      conversations = []
    }
  }

  func prepareForStartup() async {
    MIRAPerformanceTimeline.mark("chat_startup_prepare")
    await hydrateCachedConversationsIfNeeded()
    if conversations.isEmpty {
      isLoading = true
    }
    Task { await load() }
  }

  func load(forceRefresh: Bool = false) async {
    if isLoadingFreshConversations && !forceRefresh { return }
    if !forceRefresh && hasLoadedFreshConversations && !conversations.isEmpty { return }
    isLoadingFreshConversations = true
    await hydrateCachedConversationsIfNeeded()
    if conversations.isEmpty { isLoading = true }
    defer {
      isLoading = false
      isLoadingFreshConversations = false
    }

    guard let fresh: [MIRAConversation] = try? await api.get("/conversations") else {
      if conversations.isEmpty {
        hasLoadedFreshConversations = false
      }
      return
    }
    hasLoadedFreshConversations = true
    if conversations != fresh {
      conversations = fresh
    }
    prefetchConversationAvatars(fresh)
    await localStore.saveConversations(fresh, userId: currentUserId)
  }

  private func hydrateCachedConversationsIfNeeded() async {
    guard conversations.isEmpty,
          let cached = await localStore.loadConversations(userId: currentUserId)
    else { return }
    conversations = cached.conversations
    prefetchConversationAvatars(cached.conversations)
    isLoading = false
    MIRAPerformanceTimeline.markOnce("chat_first_content", detail: "cache")
  }

  private func prefetchConversationAvatars(_ rows: [MIRAConversation]) {
    let urls = rows.prefix(40)
      .compactMap { $0.otherProfileImage?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !urls.isEmpty else { return }
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 220, limit: 24)
    }
  }
}

public struct ChatNativeView: View {
  @StateObject private var model: ChatNativeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showCreateGroup = false
  @State private var openingConversationId: String?
  @State private var activeConversationRoute: ChatOpenRoute?
  private let currentUserId: String

  public init(api: MIRAAPIClient, currentUserId: String = "") {
    self.currentUserId = currentUserId
    _model = StateObject(wrappedValue: ChatNativeModel(api: api))
  }

  init(api: MIRAAPIClient, currentUserId: String = "", model: ChatNativeModel) {
    self.currentUserId = currentUserId
    _model = StateObject(wrappedValue: model)
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          chatHeader

          if model.conversations.isEmpty && model.isLoading {
            chatListSkeleton
          } else if model.conversations.isEmpty {
            MIRAEmptyState(title: "No chats yet", message: "Friends and replies will appear here.", systemImage: "bubble.left.and.bubble.right")
          } else {
            LazyVStack(spacing: MIRATheme.Space.sm) {
              ForEach(model.conversations) { conversation in
                conversationCard(conversation)
              }
            }
            .padding(.horizontal, MIRATheme.Space.md)
          }
        }
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
      .miraScrollFeel(.chat)
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .task {
        model.configure(currentUserId: currentUserId)
        await model.load()
      }
      .background {
        NavigationLink(
          isActive: Binding(
            get: { activeConversationRoute != nil },
            set: { isActive in
              if !isActive { activeConversationRoute = nil }
            }
          )
        ) {
          if let route = activeConversationRoute {
            ConversationNativeView(title: route.title, model: route.model, initialAvatarURL: route.avatarURL)
              .miraHideTabBarOnAppear()
          } else {
            EmptyView()
          }
        } label: {
          EmptyView()
        }
        .hidden()
      }
      .miraBottomSheet(isPresented: $showCreateGroup, preferredHeightFraction: 0.76) { dismissCreateGroup in
        CreateGroupChatSheet(api: model.api, currentUserId: currentUserId, onCancel: dismissCreateGroup) {
          dismissCreateGroup()
          Task { await model.load() }
        }
      }
    }
  }

  private var chatHeader: some View {
    HStack(alignment: .center, spacing: MIRATheme.Space.md) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Messages")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("\(model.conversations.count) chats")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      Button { showCreateGroup = true } label: {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.surface)
          .clipShape(Circle())
          .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  @ViewBuilder
  private func conversationCard(_ conversation: MIRAConversation) -> some View {
    Button {
      CaptroHaptics.light()
      Task { await openConversation(conversation) }
    } label: {
      ZStack(alignment: .trailing) {
        ChatConversationRow(conversation: conversation)
        if openingConversationId == conversation.id {
          ProgressView()
            .tint(MIRATheme.Color.textPrimary)
            .padding(.trailing, MIRATheme.Space.md)
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(openingConversationId != nil)
    .padding(.horizontal, MIRATheme.Space.sm)
    .padding(.vertical, 8)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  @MainActor
  private func openConversation(_ conversation: MIRAConversation) async {
    guard openingConversationId == nil else { return }
    openingConversationId = conversation.id

    let roomModel: ConversationNativeModel?
    if let groupId = conversation.groupId {
      roomModel = ConversationNativeModel(kind: .group(groupId: groupId), api: model.api, currentUserId: currentUserId)
    } else if let peerId = conversation.otherUserId {
      roomModel = ConversationNativeModel(kind: .direct(peerId: peerId), api: model.api, currentUserId: currentUserId)
    } else {
      roomModel = nil
    }

    guard let roomModel else {
      openingConversationId = nil
      return
    }

    withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
      activeConversationRoute = ChatOpenRoute(
        id: conversation.id,
        title: conversation.displayName,
        avatarURL: conversation.otherProfileImage,
        model: roomModel
      )
      openingConversationId = nil
    }
  }

  private var chatListSkeleton: some View {
    VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in
        HStack(spacing: MIRATheme.Space.md) {
          Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 56, height: 56)
          VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 150, height: 16)
            RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 220, height: 13)
          }
          Spacer()
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, MIRATheme.Space.md)
      }
    }
    .redacted(reason: .placeholder)
  }
}

private struct ChatOpenRoute: Identifiable {
  let id: String
  let title: String
  let avatarURL: String?
  let model: ConversationNativeModel
}

private struct ChatConversationRow: View {
  let conversation: MIRAConversation

  var body: some View {
    HStack(spacing: 14) {
      avatar
      VStack(alignment: .leading, spacing: 6) {
        Text(conversation.displayName)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(rowPreview)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      VStack(alignment: .trailing, spacing: 8) {
        Text(chatTime(conversation.lastMessageTime ?? conversation.updatedAt))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
        if let unread = conversation.unreadCount, unread > 0 {
          Text("\(min(unread, 99))")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 22, minHeight: 22)
            .background(MIRATheme.Color.forest)
            .clipShape(Capsule())
        } else if conversation.otherIsOnline == true {
          Text("online")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var avatar: some View {
    ZStack(alignment: .bottomTrailing) {
      if conversation.isGroup {
        ZStack {
          Circle().fill(MIRATheme.Color.forestSoft)
          Image(systemName: "person.2.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
        .frame(width: 58, height: 58)
      } else {
        RemoteAvatar(url: conversation.otherProfileImage, size: 58)
      }
      if conversation.otherIsOnline == true && !conversation.isGroup {
        Circle()
          .fill(MIRATheme.Color.forest)
          .frame(width: 14, height: 14)
          .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
      }
    }
  }

  private var rowPreview: String {
    if conversation.otherIsTyping == true { return "typing..." }
    if let last = conversation.lastMessage, !last.isEmpty { return last }
    if conversation.isGroup, let count = conversation.memberCount { return "\(count) members" }
    return "Start chat"
  }
}

@MainActor
private final class CreateGroupChatModel: ObservableObject {
  @Published var groupName = ""
  @Published var query = ""
  @Published var results: [MIRAUser] = []
  @Published var selected: [MIRAUser] = []
  @Published var isSearching = false
  @Published var isCreating = false
  @Published var errorMessage: String?

  let api: MIRAAPIClient
  let currentUserId: String

  init(api: MIRAAPIClient, currentUserId: String) {
    self.api = api
    self.currentUserId = currentUserId
  }

  func search() async {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else {
      results = []
      return
    }
    isSearching = true
    defer { isSearching = false }
    let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean
    do {
      let users: [MIRAUser] = try await api.get("/users/search/\(encoded)")
      let selectedIds = Set(selected.map(\.id))
      results = users.filter { $0.id != currentUserId && !selectedIds.contains($0.id) }
      errorMessage = nil
    } catch {
      errorMessage = "Could not search users."
    }
  }

  func toggle(_ user: MIRAUser) {
    if selected.contains(where: { $0.id == user.id }) {
      selected.removeAll { $0.id == user.id }
    } else {
      selected.append(user)
    }
  }

  func create() async -> Bool {
    guard !selected.isEmpty else {
      errorMessage = "Choose at least one person."
      return false
    }
    guard !isCreating else { return false }
    isCreating = true
    defer { isCreating = false }
    do {
      let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
      let _: MIRAGroupChatCreatedResponse = try await api.post(
        "/group-chats",
        body: CreateGroupChatBody(name: name.isEmpty ? "New group" : name, memberIds: selected.map(\.id))
      )
      return true
    } catch {
      errorMessage = "Could not create this group."
      return false
    }
  }
}

private struct CreateGroupChatSheet: View {
  @StateObject private var model: CreateGroupChatModel
  @Environment(\.dismiss) private var dismiss
  let onCancel: (() -> Void)?
  let onCreated: () -> Void

  init(api: MIRAAPIClient, currentUserId: String, onCancel: (() -> Void)? = nil, onCreated: @escaping () -> Void) {
    self.onCancel = onCancel
    self.onCreated = onCreated
    _model = StateObject(wrappedValue: CreateGroupChatModel(api: api, currentUserId: currentUserId))
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
        TextField("Group name", text: $model.groupName)
          .font(.system(size: 16, weight: .semibold))
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 48)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .padding(.horizontal, MIRATheme.Space.md)

        if !model.selected.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MIRATheme.Space.sm) {
              ForEach(model.selected) { user in
                Button { model.toggle(user) } label: {
                  HStack(spacing: 6) {
                    RemoteAvatar(url: user.profileImage, size: 24)
                    Text(user.displayName).lineLimit(1)
                    Image(systemName: "xmark")
                  }
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                  .padding(.horizontal, 10)
                  .frame(height: 34)
                  .background(MIRATheme.Color.surfaceSoft)
                  .clipShape(Capsule())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, MIRATheme.Space.md)
          }
        }

        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(MIRATheme.Color.textMuted)
          TextField("Search people", text: $model.query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { Task { await model.search() } }
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(height: 48)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .padding(.horizontal, MIRATheme.Space.md)

        if let error = model.errorMessage {
          Text(error)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, MIRATheme.Space.md)
        }

        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.results) { user in
              Button { model.toggle(user) } label: {
                HStack(spacing: MIRATheme.Space.md) {
                  RemoteAvatar(url: user.profileImage, size: 44)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                      .font(.system(size: 15, weight: .semibold))
                      .foregroundStyle(MIRATheme.Color.textPrimary)
                    if let fullName = user.fullName, !fullName.isEmpty {
                      Text(fullName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MIRATheme.Color.textMuted)
                    }
                  }
                  Spacer()
                  Image(systemName: "plus.circle.fill")
                    .foregroundStyle(MIRATheme.Color.forest)
                }
                .padding(.horizontal, MIRATheme.Space.md)
                .padding(.vertical, MIRATheme.Space.sm)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .navigationTitle("New group")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(model.isCreating ? "Creating" : "Create") {
            Task {
              if await model.create() {
                onCreated()
              }
            }
          }
          .font(.system(size: 15, weight: .semibold))
          .disabled(model.isCreating || model.selected.isEmpty)
        }
      }
      .task(id: model.query) {
        try? await Task.sleep(nanoseconds: 300_000_000)
        await model.search()
      }
    }
  }

  private func close() {
    if let onCancel {
      onCancel()
    } else {
      dismiss()
    }
  }
}

private func chatTime(_ value: String?) -> String {
  guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "" }
  let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  if hours < 24 { return "\(hours)h" }
  let days = hours / 24
  if days < 7 { return "\(days)d" }
  return "\(max(1, days / 7))w"
}

@MainActor
final class WalletNativeModel: ObservableObject {
  @Published var wallet: MIRAWallet?
  private let api: MIRAAPIClient
  private let walletCacheKey = "native.wallet.v2"

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    if wallet == nil {
      wallet = await MIRALocalJSONCache.load(MIRAWallet.self, key: walletCacheKey)
    }
    guard let fresh: MIRAWallet = try? await api.get("/wallet") else { return }
    wallet = fresh
    await MIRALocalJSONCache.save(fresh, key: walletCacheKey)
  }
}

public struct WalletNativeView: View {
  private let api: MIRAAPIClient
  @State private var user: MIRAUser?
  @State private var phoneInput = ""
  @State private var phoneCode = ""
  @State private var emailCode = ""
  @State private var emailCodeSent = false
  @State private var phoneCodeSent = false
  @State private var isLoading = false
  @State private var activeAction: VerificationAction?
  @State private var successMessage: String?
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 16) {
        verificationHero
        statusRow
        emailCard
        phoneCard

        if let successMessage {
          verificationBanner(successMessage, systemImage: "checkmark.circle.fill", color: MIRATheme.Color.forest)
        }

        if let errorMessage {
          verificationBanner(errorMessage, systemImage: "exclamationmark.triangle.fill", color: .red)
        }
      }
      .padding(MIRATheme.Space.md)
    }
    .navigationTitle("Verification")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .background(MIRATheme.Color.appBackground)
    .miraScrollFeel(.feed)
    .miraScreenEnter(.push)
    .miraHideTabBarOnAppear()
    .task { await loadAccount() }
  }

  private var verificationHero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 58, height: 58)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      Text("Verify your account")
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("Confirm your email and phone number to protect your Captro account and make recovery easier.")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .modifier(MIRATheme.softShadow())
  }

  private var statusRow: some View {
    HStack(spacing: 10) {
      verificationStatusPill(title: "Email", verified: emailVerified)
      verificationStatusPill(title: "Phone", verified: phoneVerified)
      if isLoading {
        ProgressView()
          .tint(MIRATheme.Color.forest)
          .frame(width: 34, height: 34)
      }
    }
  }

  private var emailCard: some View {
    verificationCard(
      title: "Email",
      subtitle: emailAddress.isEmpty ? "No email address is attached to this account." : emailAddress,
      systemImage: "envelope.fill",
      verified: emailVerified
    ) {
      if emailVerified {
        verifiedMessage("Email verified")
      } else if emailAddress.isEmpty {
        Text("Add an email address in account settings first.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      } else {
        verificationButton(
          title: emailCodeSent ? "Resend code" : "Send email code",
          systemImage: "paperplane.fill",
          isBusy: activeAction == .emailStart,
          isDisabled: activeAction != nil
        ) {
          Task { await sendEmailCode() }
        }
        if emailCodeSent {
          codeField(title: "Email code", text: $emailCode)
          verificationButton(
            title: "Verify email",
            systemImage: "checkmark",
            isBusy: activeAction == .emailVerify,
            isDisabled: activeAction != nil || emailCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6
          ) {
            Task { await verifyEmailCode() }
          }
        }
      }
    }
  }

  private var phoneCard: some View {
    verificationCard(
      title: "Phone",
      subtitle: phoneVerified ? cleanPhoneLabel : "Use country code, example +1 555 123 4567.",
      systemImage: "phone.fill",
      verified: phoneVerified
    ) {
      if phoneVerified {
        verifiedMessage("Phone verified")
      } else {
        TextField("+1 555 123 4567", text: $phoneInput)
          .keyboardType(.phonePad)
          .textInputAutocapitalization(.never)
          .padding(.horizontal, 14)
          .frame(height: 48)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Capsule())

        verificationButton(
          title: phoneCodeSent ? "Resend code" : "Send SMS code",
          systemImage: "message.fill",
          isBusy: activeAction == .phoneStart,
          isDisabled: activeAction != nil || phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) {
          Task { await sendPhoneCode() }
        }
        if phoneCodeSent {
          codeField(title: "SMS code", text: $phoneCode)
          verificationButton(
            title: "Verify phone",
            systemImage: "checkmark",
            isBusy: activeAction == .phoneVerify,
            isDisabled: activeAction != nil || phoneCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6
          ) {
            Task { await verifyPhoneCode() }
          }
        }
      }
    }
  }

  private func verificationCard<Content: View>(
    title: String,
    subtitle: String,
    systemImage: String,
    verified: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(verified ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
          .frame(width: 42, height: 42)
          .background(verified ? MIRATheme.Color.forestSoft : MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: verified ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(verified ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.5))
      }

      content()
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
  }

  private func verificationStatusPill(title: String, verified: Bool) -> some View {
    HStack(spacing: 7) {
      Image(systemName: verified ? "checkmark.circle.fill" : "circle")
      Text(verified ? "\(title) verified" : "\(title) pending")
    }
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(verified ? MIRATheme.Color.forest : MIRATheme.Color.textSecondary)
    .padding(.horizontal, 12)
    .frame(height: 36)
    .background(verified ? MIRATheme.Color.forestSoft : MIRATheme.Color.surfaceRaised)
    .clipShape(Capsule())
  }

  private func verifiedMessage(_ text: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
      Text(text)
    }
    .font(.system(size: 14, weight: .semibold))
    .foregroundStyle(MIRATheme.Color.forest)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(MIRATheme.Color.forestSoft)
    .clipShape(Capsule())
  }

  private func codeField(title: String, text: Binding<String>) -> some View {
    TextField(title, text: text)
      .keyboardType(.numberPad)
      .textContentType(.oneTimeCode)
      .padding(.horizontal, 14)
      .frame(height: 48)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
  }

  private func verificationButton(
    title: String,
    systemImage: String,
    isBusy: Bool,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if isBusy {
          ProgressView()
            .tint(.white)
        } else {
          Image(systemName: systemImage)
        }
        Text(title)
      }
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(isDisabled ? MIRATheme.Color.textMuted.opacity(0.45) : MIRATheme.Color.forest)
      .clipShape(Capsule())
    }
    .disabled(isDisabled)
    .buttonStyle(.plain)
  }

  private func verificationBanner(_ text: String, systemImage: String, color: Color) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(color)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func loadAccount() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let fresh: MIRAUser = try await api.get("/auth/me")
      applyUser(fresh)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sendEmailCode() async {
    successMessage = nil
    errorMessage = nil
    activeAction = .emailStart
    defer { activeAction = nil }
    do {
      let _: VerificationStartResponse = try await api.post(
        "/users/me/email/start",
        body: VerificationStartBody(email: emailAddress.isEmpty ? nil : emailAddress, phone: nil)
      )
      emailCodeSent = true
      successMessage = "Check your email for a 6-digit code."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func verifyEmailCode() async {
    successMessage = nil
    errorMessage = nil
    activeAction = .emailVerify
    defer { activeAction = nil }
    do {
      let updated: MIRAUser = try await api.post(
        "/users/me/email/verify",
        body: VerificationCodeBody(email: emailAddress.isEmpty ? nil : emailAddress, phone: nil, code: emailCode)
      )
      applyUser(updated)
      emailCode = ""
      emailCodeSent = false
      successMessage = "Email verified."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sendPhoneCode() async {
    successMessage = nil
    errorMessage = nil
    activeAction = .phoneStart
    defer { activeAction = nil }
    do {
      let _: VerificationStartResponse = try await api.post(
        "/users/me/phone/start",
        body: VerificationStartBody(email: nil, phone: phoneInput)
      )
      phoneCodeSent = true
      successMessage = "Check your phone for a 6-digit code."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func verifyPhoneCode() async {
    successMessage = nil
    errorMessage = nil
    activeAction = .phoneVerify
    defer { activeAction = nil }
    do {
      let updated: MIRAUser = try await api.post(
        "/users/me/phone/verify",
        body: VerificationCodeBody(email: nil, phone: phoneInput, code: phoneCode)
      )
      applyUser(updated)
      phoneCode = ""
      phoneCodeSent = false
      successMessage = "Phone verified."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyUser(_ fresh: MIRAUser) {
    user = fresh
    if phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      phoneInput = fresh.phone ?? ""
    }
  }

  private var emailAddress: String {
    user?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private var cleanPhoneLabel: String {
    let phone = user?.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
    return phone.isEmpty ? "No phone number verified yet." : phone
  }

  private var emailVerified: Bool {
    user?.emailVerified == true
  }

  private var phoneVerified: Bool {
    user?.phoneVerified == true
  }
}

private enum VerificationAction: Equatable {
  case emailStart
  case emailVerify
  case phoneStart
  case phoneVerify
}

private struct VerificationStartBody: Encodable {
  let email: String?
  let phone: String?
}

private struct VerificationCodeBody: Encodable {
  let email: String?
  let phone: String?
  let code: String
}

private struct VerificationStartResponse: Decodable {
  let detail: String?
  let delivery: String?
}
