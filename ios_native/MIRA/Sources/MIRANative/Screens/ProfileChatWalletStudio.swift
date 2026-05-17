import SwiftUI

@MainActor
final class ProfileNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var posts: [MIRAPost] = []
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    user = try? await api.get("/auth/me")
    if let user {
      posts = (try? await api.get("/users/\(user.id)/posts")) ?? []
    }
  }
}

public struct ProfileNativeView: View {
  @StateObject private var model: ProfileNativeModel
  private let authSession: MIRAAuthSession?

  public init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil) {
    self.authSession = authSession
    _model = StateObject(wrappedValue: ProfileNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          profileHeader
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(model.posts) { post in
              if let media = post.mediaURLs.first {
                RemoteMediaView(url: media, isVideo: media.isVideoURL)
                  .aspectRatio(1, contentMode: .fill)
              } else {
                MIRATheme.Color.surfaceSoft.aspectRatio(1, contentMode: .fill)
              }
            }
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
          NavigationLink(destination: SettingsNativeView(authSession: authSession)) {
            Image(systemName: "gearshape")
          }
        }
      }
      .task { await model.load() }
      .refreshable { await model.load() }
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
final class ChatNativeModel: ObservableObject {
  @Published var conversations: [MIRAConversation] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = conversations.isEmpty
    defer { isLoading = false }
    conversations = (try? await api.get("/conversations")) ?? []
  }
}

public struct ChatNativeView: View {
  @StateObject private var model: ChatNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: ChatNativeModel(api: api))
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          Text("Chat")
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, MIRATheme.Space.md)

          if model.conversations.isEmpty && !model.isLoading {
            MIRAEmptyState(title: "No chats yet", message: "Friends and replies will appear here.", systemImage: "bubble.left.and.bubble.right")
          } else {
            ForEach(model.conversations) { conversation in
              if let peerId = conversation.otherUserId {
                NavigationLink(destination: ConversationNativeView(peerId: peerId, title: conversation.displayName, api: model.api)) {
                  HStack(spacing: MIRATheme.Space.sm) {
                    MIRAFollowAvatar(url: conversation.otherProfileImage, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                      Text(conversation.displayName)
                        .font(.system(size: 16, weight: .semibold))
                      Text(conversation.lastMessage ?? "Start chat")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(MIRATheme.Color.textSecondary)
                        .lineLimit(1)
                    }
                    Spacer()
                    if (conversation.unreadCount ?? 0) > 0 {
                      Text("\(conversation.unreadCount ?? 0)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(MIRATheme.Color.forest)
                        .clipShape(Circle())
                    }
                  }
                  .padding(MIRATheme.Space.md)
                  .miraCardSurface(cornerRadius: MIRATheme.Radius.medium)
                  .padding(.horizontal, MIRATheme.Space.md)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .padding(.vertical, MIRATheme.Space.md)
      }
      .background(MIRATheme.Color.appBackground)
      .task { await model.load() }
    }
  }
}

@MainActor
final class WalletNativeModel: ObservableObject {
  @Published var wallet: MIRAWallet?
  private let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    wallet = try? await api.get("/wallet")
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

public struct StudioNativeView: View {
  public init() {}

  public var body: some View {
    VStack(spacing: MIRATheme.Space.xl) {
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(MIRATheme.Color.forest)
      Text("Native Studio")
        .font(.system(size: 22, weight: .semibold))
      Text("This is the SwiftUI starting point for the camera, post composer, notes composer, places, preview, and media tools.")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .multilineTextAlignment(.center)
      MIRAPrimaryButton("Open camera", systemImage: "camera") {}
    }
    .padding(MIRATheme.Space.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("Studio")
  }
}
