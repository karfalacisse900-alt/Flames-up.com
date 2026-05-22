import Foundation
import SwiftUI
import UIKit

@MainActor
final class ProfileNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var posts: [MIRAPost] = []
  let api: MIRAAPIClient
  private let userCacheKey = "native.profile.me.v2"

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    if user == nil, let cachedUser: MIRAUser = await MIRALocalJSONCache.load(MIRAUser.self, key: userCacheKey) {
      user = cachedUser
      posts = await MIRALocalJSONCache.load([MIRAPost].self, key: postsCacheKey(for: cachedUser.id)) ?? posts
    }

    guard let freshUser: MIRAUser = try? await api.get("/auth/me") else { return }
    user = freshUser
    await MIRALocalJSONCache.save(freshUser, key: userCacheKey)
    let freshPosts: [MIRAPost] = (try? await api.get("/users/\(freshUser.id)/posts")) ?? posts
    posts = freshPosts
    await MIRALocalJSONCache.save(freshPosts, key: postsCacheKey(for: freshUser.id))
  }

  private func postsCacheKey(for userID: String) -> String {
    "native.profile.posts.\(userID).v2"
  }
}

private struct ProfileGridSkeleton: View {
  private var gridTileSize: CGFloat {
    floor((UIScreen.main.bounds.width - 2) / 3)
  }
  private var columns: [GridItem] {
    Array(repeating: GridItem(.fixed(gridTileSize), spacing: 1), count: 3)
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 1) {
      ForEach(0..<9, id: \.self) { _ in
        Rectangle()
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: gridTileSize, height: gridTileSize)
      }
    }
    .frame(width: UIScreen.main.bounds.width, alignment: .center)
    .redacted(reason: .placeholder)
  }
}

public struct ProfileNativeView: View {
  @StateObject private var model: ProfileNativeModel
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
                ProfilePostTile(post: post, size: gridTileSize)
              }
            }
            .frame(width: UIScreen.main.bounds.width, alignment: .center)
          }
        }
      }
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Profile")
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
      .task { await model.load() }
    }
  }

  private var profileHeader: some View {
    VStack(spacing: MIRATheme.Space.md) {
      RemoteAvatar(url: model.user?.profileImage, size: 92)
      Text(model.user?.displayName ?? "mira")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      HStack(spacing: MIRATheme.Space.xl) {
        profileMetric("Posts", model.user?.postsCount ?? model.posts.count)
        profileMetric("Followers", model.user?.followersCount ?? 0)
        profileMetric("Following", model.user?.followingCount ?? 0)
      }
      MIRAPrimaryButton("Edit profile", systemImage: "pencil") {}
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
    posts = freshPosts
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
              ProfilePostTile(post: post, size: gridTileSize)
            }
          }
          .frame(width: UIScreen.main.bounds.width, alignment: .center)
        }
      }
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground)
    .navigationTitle(model.user?.displayName ?? "Profile")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
  }

  private var profileHeader: some View {
    VStack(spacing: MIRATheme.Space.md) {
      RemoteAvatar(url: model.user?.profileImage, size: 92)
      VStack(spacing: 4) {
        Text(model.user?.displayName ?? "mira")
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
}

private struct ProfilePostTile: View {
  let post: MIRAPost
  let size: CGFloat

  var body: some View {
    ZStack {
      if let media = post.mediaURLs.first {
        RemoteMediaView(url: media, isVideo: media.isVideoURL, shouldPlay: false)
      } else {
        MIRATheme.Color.surfaceSoft
      }
    }
    .frame(width: size, height: size)
    .clipped()
    .contentShape(Rectangle())
  }
}

@MainActor
final class ChatNativeModel: ObservableObject {
  @Published var conversations: [MIRAConversation] = []
  @Published var isLoading = false
  let api: MIRAAPIClient
  private let conversationsCacheKey = "native.chat.conversations.v2"

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    if conversations.isEmpty, let cached: [MIRAConversation] = await MIRALocalJSONCache.load([MIRAConversation].self, key: conversationsCacheKey) {
      conversations = cached
    }
    isLoading = conversations.isEmpty
    defer { isLoading = false }
    let fresh: [MIRAConversation] = (try? await api.get("/conversations")) ?? conversations
    conversations = fresh
    await MIRALocalJSONCache.save(fresh, key: conversationsCacheKey)
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

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          chatHeader
          friendStoryPlaceholder

          if model.conversations.isEmpty && model.isLoading {
            chatListSkeleton
          } else if model.conversations.isEmpty {
            MIRAEmptyState(title: "No chats yet", message: "Friends and replies will appear here.", systemImage: "bubble.left.and.bubble.right")
          } else {
            LazyVStack(spacing: 0) {
              ForEach(model.conversations) { conversation in
                if let groupId = conversation.groupId {
                  NavigationLink(destination: ConversationNativeView(groupId: groupId, title: conversation.displayName, api: model.api, currentUserId: currentUserId)) {
                    ChatConversationRow(conversation: conversation)
                  }
                  .buttonStyle(.plain)
                } else if let peerId = conversation.otherUserId {
                  NavigationLink(destination: ConversationNativeView(peerId: peerId, title: conversation.displayName, api: model.api, currentUserId: currentUserId)) {
                    ChatConversationRow(conversation: conversation)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            .padding(.horizontal, MIRATheme.Space.md)
          }
        }
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
      .background(MIRATheme.Color.appBackground)
      .task { await model.load() }
      .sheet(isPresented: $showCreateGroup) {
        CreateGroupChatSheet(api: model.api, currentUserId: currentUserId) {
          showCreateGroup = false
          Task { await model.load() }
        }
        .presentationDetents([.medium, .large])
      }
    }
  }

  private var chatHeader: some View {
    HStack {
      Text("Chat")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      Button { showCreateGroup = true } label: {
        Image(systemName: "person.2.badge.plus")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 38, height: 38)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      MIRAHeaderCircleButton(systemImage: "magnifyingglass")
    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var friendStoryPlaceholder: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "person.2")
        .font(.system(size: 17, weight: .semibold))
      Text("Friend stories will appear here")
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .foregroundStyle(MIRATheme.Color.textMuted)
    .frame(maxWidth: .infinity, minHeight: 56)
    .background(MIRATheme.Color.surface)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(MIRATheme.Color.hairline, lineWidth: 1))
    .padding(.horizontal, MIRATheme.Space.md)
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
    HStack(spacing: MIRATheme.Space.md) {
      if conversation.isGroup {
        ZStack {
          Circle().fill(MIRATheme.Color.surfaceSoft)
          Image(systemName: "person.2.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
        .frame(width: 56, height: 56)
      } else {
        MIRAFollowAvatar(url: conversation.otherProfileImage, size: 56)
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(conversation.displayName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Text(rowPreview)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: MIRATheme.Space.sm) {
        Text(chatTime(conversation.lastMessageTime ?? conversation.updatedAt))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Image(systemName: "video")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .frame(width: 30, height: 30)
          .background(MIRATheme.Color.surface)
          .clipShape(Circle())
          .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
      }
    }
    .padding(.vertical, MIRATheme.Space.md)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5).padding(.leading, 72)
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
  let onCreated: () -> Void

  init(api: MIRAAPIClient, currentUserId: String, onCreated: @escaping () -> Void) {
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
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(model.isCreating ? "Creating" : "Create") {
            Task {
              if await model.create() {
                dismiss()
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
    .task { await model.load() }
  }
}
