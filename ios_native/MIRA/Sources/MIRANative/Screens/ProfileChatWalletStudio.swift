import Foundation
import PhotosUI
import SwiftUI
import UIKit

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
    await MIRALocalJSONCache.save(freshUser, key: userCacheKey)
    let freshPosts: [MIRAPost] = (try? await api.get("/users/\(freshUser.id)/posts")) ?? posts
    if posts != freshPosts {
      posts = freshPosts
    }
    await MIRALocalJSONCache.save(freshPosts, key: postsCacheKey(for: freshUser.id))
  }

  func primeUser(_ signedInUser: MIRAUser?) {
    guard user == nil, let signedInUser else { return }
    user = signedInUser
  }

  private func hydrateCachedProfileIfNeeded() async {
    guard user == nil, let cachedUser: MIRAUser = await MIRALocalJSONCache.load(MIRAUser.self, key: userCacheKey) else { return }
    user = cachedUser
    posts = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: cachedUser.id)) ?? posts
  }

  func applyUpdatedUser(_ updated: MIRAUser) async {
    user = updated
    await MIRALocalJSONCache.save(updated, key: userCacheKey)
  }

  func deletePost(_ post: MIRAPost) async {
    guard let user else { return }
    let previousPosts = posts
    posts.removeAll { $0.id == post.id }
    do {
      let _: EmptyResponse = try await api.delete("/posts/\(post.id)")
      await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
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
      await MIRALocalJSONCache.save(posts, key: postsCacheKey(for: user.id))
      profileError = nil
    } catch {
      profileError = "Could not update post visibility."
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

private struct ProfileGridSkeleton: View {
  private var gridTileSize: CGFloat {
    floor((UIScreen.main.bounds.width - 2) / 3)
  }
  private var gridTileHeight: CGFloat {
    gridTileSize * MIRAMediaSizing.profileGridRatio
  }
  private var columns: [GridItem] {
    Array(repeating: GridItem(.fixed(gridTileSize), spacing: 1), count: 3)
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 1) {
      ForEach(0..<9, id: \.self) { _ in
        Rectangle()
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: gridTileSize, height: gridTileHeight)
      }
    }
    .frame(width: UIScreen.main.bounds.width, alignment: .center)
    .redacted(reason: .placeholder)
  }
}

public struct ProfileNativeView: View {
  @StateObject private var model: ProfileNativeModel
  @State private var showEditProfile = false
  private let authSession: MIRAAuthSession?
  private var gridTileSize: CGFloat {
    floor((UIScreen.main.bounds.width - 2) / 3)
  }
  private var postGridColumns: [GridItem] {
    Array(repeating: GridItem(.fixed(gridTileSize), spacing: 1), count: 3)
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
                ProfilePostTile(
                  post: post,
                  size: gridTileSize,
                  onDelete: { Task { await model.deletePost(post) } },
                  onMakePublic: { Task { await model.updatePostVisibility(post, visibility: "public") } },
                  onMakePrivate: { Task { await model.updatePostVisibility(post, visibility: "private") } }
                )
              }
            }
            .frame(width: UIScreen.main.bounds.width, alignment: .center)
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
      .miraScreenEnter(.tab)
      .navigationTitle("")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink(destination: LibraryNativeView(api: model.api)) {
            Image(systemName: "bookmark")
          }
          NavigationLink(destination: WalletNativeView(api: model.api)) {
            Image(systemName: "wallet.pass")
          }
          NavigationLink(destination: SettingsNativeView(api: model.api, authSession: authSession)) {
            Image(systemName: "gearshape")
          }
        }
      }
      .task {
        await MainActor.run {
          model.primeUser(authSession?.user)
        }
        await model.load()
      }
      .miraBottomSheet(isPresented: $showEditProfile, preferredHeightFraction: 0.86) { dismissEditProfile in
        EditProfileNativeView(user: model.user, api: model.api, onCancel: dismissEditProfile) { updated in
          dismissEditProfile()
          Task { @MainActor in
            authSession?.replaceUser(updated)
            await model.applyUpdatedUser(updated)
          }
        }
      }
    }
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
        showEditProfile = true
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
    return model.user?.username ?? "mira"
  }
}

@MainActor
final class UserProfileNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var posts: [MIRAPost] = []
  @Published var isFollowing = false
  @Published var followersCount = 0
  @Published var isLoading = false
  let userId: String
  let api: MIRAAPIClient
  private var userCacheKey: String { "native.profile.user.\(userId).v2" }
  private var postsCacheKey: String { "native.profile.posts.\(userId).v2" }

  init(userId: String, api: MIRAAPIClient) {
    self.userId = userId
    self.api = api
  }

  func load() async {
    if user == nil, let cachedUser: MIRAUser = await MIRALocalJSONCache.load(MIRAUser.self, key: userCacheKey) {
      apply(user: cachedUser)
      posts = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey) ?? posts
    }

    isLoading = user == nil && posts.isEmpty
    defer { isLoading = false }

    if let freshUser: MIRAUser = try? await api.get("/users/\(userId)") {
      apply(user: freshUser)
      await MIRALocalJSONCache.save(freshUser, key: userCacheKey)
    }
    let freshPosts: [MIRAPost] = (try? await api.get("/users/\(userId)/posts")) ?? posts
    if posts != freshPosts {
      posts = freshPosts
    }
    await MIRALocalJSONCache.save(freshPosts, key: postsCacheKey)
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
    } catch {
      isFollowing = previousFollowing
      followersCount = previousFollowers
    }
  }

  private func apply(user freshUser: MIRAUser) {
    user = freshUser
    isFollowing = freshUser.viewerFollowing
    followersCount = freshUser.followersCount ?? followersCount
  }
}

public struct UserProfileNativeView: View {
  @StateObject private var model: UserProfileNativeModel
  private var gridTileSize: CGFloat {
    floor((UIScreen.main.bounds.width - 2) / 3)
  }
  private var postGridColumns: [GridItem] {
    Array(repeating: GridItem(.fixed(gridTileSize), spacing: 1), count: 3)
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
              ProfilePostTile(
                post: post,
                size: gridTileSize
              )
            }
          }
          .frame(width: UIScreen.main.bounds.width, alignment: .center)
        }
      }
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground)
    .miraScreenEnter(.push)
    .navigationTitle(model.user?.displayName ?? "Profile")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
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
        profileMetric("Followers", model.followersCount)
        profileMetric("Following", model.user?.followingCount ?? 0)
      }

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

        NavigationLink(destination: ConversationNativeView(peerId: model.userId, title: model.user?.displayName ?? "Chat", api: model.api)) {
          Label("Message", systemImage: "message")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
    return model.user?.username ?? "mira"
  }
}

private struct ProfilePostTile: View {
  let post: MIRAPost
  let size: CGFloat
  var onDelete: (() -> Void)? = nil
  var onMakePublic: (() -> Void)? = nil
  var onMakePrivate: (() -> Void)? = nil

  private var height: CGFloat {
    size * MIRAMediaSizing.profileGridRatio
  }

  private var normalizedVisibility: String {
    post.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "public"
  }

  @ViewBuilder
  var body: some View {
    if hasOwnerActions {
      tileContent
        .contextMenu {
          ownerContextMenu
        }
    } else {
      tileContent
    }
  }

  private var tileContent: some View {
    ZStack {
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
    .frame(width: size, height: height)
    .clipped()
    .contentShape(Rectangle())
  }

  private var hasOwnerActions: Bool {
    onDelete != nil || onMakePublic != nil || onMakePrivate != nil
  }

  @ViewBuilder
  private var ownerContextMenu: some View {
    if normalizedVisibility != "private", let onMakePrivate {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onMakePrivate()
      } label: {
        Label("Make post private", systemImage: "lock")
      }
    }

    if normalizedVisibility != "public", let onMakePublic {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onMakePublic()
      } label: {
        Label("Make post public", systemImage: "globe")
      }
    }

    if let onDelete {
      Button(role: .destructive) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onDelete()
      } label: {
        Label("Delete post", systemImage: "trash")
      }
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
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.xl) {
          VStack(spacing: MIRATheme.Space.md) {
            profilePhoto
            PhotosPicker(selection: $pickerItem, matching: .images) {
              Text("Change profile picture")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.forest)
            }
            .disabled(isSaving)
          }
          .padding(.top, MIRATheme.Space.lg)

          VStack(spacing: MIRATheme.Space.md) {
            editField(title: "Name", text: $fullName, placeholder: "Your name")
            editField(title: "Username", text: $username, placeholder: "username")
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
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Edit profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
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
          pickedImageData = data
          pickedUIImage = image
        }
      }
      .task { await hydrateMissingUserIfNeeded() }
    }
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
    let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let usernameToSave = cleanUsername.isEmpty ? nil : cleanUsername
    if let usernameToSave, usernameToSave.count < 3 {
      errorMessage = "Username must be at least 3 characters."
      return
    }
    isSaving = true
    defer { isSaving = false }
    do {
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
      }
      let updated: MIRAUser = try await api.put(
        "/users/me",
        body: ProfileUpdateBody(
          fullName: cleanName.isEmpty ? nil : cleanName,
          username: usernameToSave,
          profileImage: uploadedImage
        )
      )
      onSaved(updated)
    } catch {
      errorMessage = "Could not save your profile."
    }
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
  private let conversationsCacheKey = "native.chat.conversations.v2"
  private var hasLoadedFreshConversations = false
  private var isLoadingFreshConversations = false

  init(api: MIRAAPIClient) {
    self.api = api
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
    await MIRALocalJSONCache.save(fresh, key: conversationsCacheKey)
  }

  private func hydrateCachedConversationsIfNeeded() async {
    guard conversations.isEmpty,
          let cached: [MIRAConversation] = await MIRALocalJSONCache.load([MIRAConversation].self, key: conversationsCacheKey)
    else { return }
    conversations = cached
    isLoading = false
    MIRAPerformanceTimeline.markOnce("chat_first_content", detail: "cache")
  }
}

public struct ChatNativeView: View {
  @StateObject private var model: ChatNativeModel
  @State private var showCreateGroup = false
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
      .background(MIRATheme.Color.appBackground)
      .miraScreenEnter(.tab)
      .task { await model.load() }
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
      MIRAHeaderCircleButton(systemImage: "magnifyingglass", size: 44)
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  @ViewBuilder
  private func conversationCard(_ conversation: MIRAConversation) -> some View {
    NavigationLink {
      conversationDestination(conversation)
    } label: {
      ChatConversationRow(conversation: conversation)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MIRATheme.Space.sm)
    .padding(.vertical, 8)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private func conversationDestination(_ conversation: MIRAConversation) -> some View {
    if let groupId = conversation.groupId {
      ConversationNativeView(groupId: groupId, title: conversation.displayName, api: model.api, currentUserId: currentUserId)
    } else if let peerId = conversation.otherUserId {
      ConversationNativeView(peerId: peerId, title: conversation.displayName, api: model.api, currentUserId: currentUserId)
    } else {
      MIRAEmptyState(title: "Chat unavailable", message: "This conversation cannot be opened right now.", systemImage: "exclamationmark.bubble")
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
    guard selected.count >= 2 else {
      errorMessage = "Choose at least two people."
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
          .disabled(model.isCreating || model.selected.count < 2)
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
  @StateObject private var model: WalletNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: WalletNativeModel(api: api))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          Text("Wallet")
            .font(.system(size: 24, weight: .semibold))
          Text("\(model.wallet?.balance ?? 0)")
            .font(.system(size: 42, weight: .semibold))
          Text("MIRA coins")
            .foregroundStyle(MIRATheme.Color.textSecondary)
          MIRAPrimaryButton("Buy coins", systemImage: "plus") {}
        }
        .padding(MIRATheme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.sheet, style: .continuous))
        .modifier(MIRATheme.softShadow())

        VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
          Text("Premium")
            .font(.system(size: 18, weight: .semibold))
          Text(model.wallet?.premiumActive == true ? "Premium is active" : "$4.99/month")
            .foregroundStyle(MIRATheme.Color.textSecondary)
          MIRAPrimaryButton("Manage premium", systemImage: "crown") {}
        }
        .padding(MIRATheme.Space.xl)
        .miraCardSurface()
      }
      .padding(MIRATheme.Space.md)
    }
    .navigationTitle("Wallet")
    .background(MIRATheme.Color.appBackground)
    .miraScreenEnter(.push)
    .task { await model.load() }
  }
}
