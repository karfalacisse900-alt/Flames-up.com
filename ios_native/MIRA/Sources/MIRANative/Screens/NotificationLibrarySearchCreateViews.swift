import SwiftUI

@MainActor
final class NotificationNativeModel: ObservableObject {
  @Published var notifications: [MIRANotification] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = notifications.isEmpty
    defer { isLoading = false }
    do {
      notifications = try await api.get("/notifications?limit=60")
      let _: EmptyResponse = try await api.post("/notifications/mark-read", body: EmptyBody())
      errorMessage = nil
    } catch {
      errorMessage = "Notifications could not load."
    }
  }
}

public struct NotificationNativeView: View {
  @StateObject private var model: NotificationNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: NotificationNativeModel(api: api))
  }

  public var body: some View {
    ScrollView {
      LazyVStack(spacing: MIRATheme.Space.sm) {
        if model.isLoading && model.notifications.isEmpty {
          ForEach(0..<6, id: \.self) { _ in notificationSkeleton }
        } else if model.notifications.isEmpty {
          MIRAEmptyState(title: "No notifications yet", message: "Likes, replies, follows, gifts, and posts will appear here.", systemImage: "bell")
        } else {
          ForEach(model.notifications) { item in
            notificationRow(item)
          }
        }
      }
      .padding(MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("Notifications")
    .task { await model.load() }
    .refreshable { await model.load() }
  }

  private func notificationRow(_ item: MIRANotification) -> some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: icon(for: item.type))
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title ?? "New activity")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(item.body ?? "Something new happened on MIRA.")
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }
      Spacer()
      if item.isRead?.value == false {
        Circle().fill(MIRATheme.Color.accent).frame(width: 8, height: 8)
      }
    }
    .padding(MIRATheme.Space.md)
    .miraCardSurface()
  }

  private var notificationSkeleton: some View {
    HStack(spacing: MIRATheme.Space.md) {
      Circle().fill(MIRATheme.Color.surfaceSoft).frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 180, height: 14)
        RoundedRectangle(cornerRadius: 6).fill(MIRATheme.Color.surfaceSoft).frame(width: 250, height: 12)
      }
    }
    .padding(MIRATheme.Space.md)
    .miraCardSurface()
    .redacted(reason: .placeholder)
  }

  private func icon(for type: String?) -> String {
    switch type {
    case "like": return "heart.fill"
    case "comment", "comment_reply": return "bubble.left.fill"
    case "follow": return "person.badge.plus"
    case "message": return "message.fill"
    case "coin_gift": return "gift.fill"
    case "new_post": return "sparkles"
    default: return "bell.fill"
    }
  }
}

@MainActor
final class LibraryNativeModel: ObservableObject {
  enum Tab: String, CaseIterable {
    case saved = "Saved"
    case liked = "Liked"
    case collections = "Collections"
  }

  @Published var tab: Tab = .saved
  @Published var savedPosts: [MIRAPost] = []
  @Published var likedPosts: [MIRAPost] = []
  @Published var collections: [MIRALibraryCollection] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      switch tab {
      case .saved:
        savedPosts = try await api.get("/library/saved")
      case .liked:
        likedPosts = try await api.get("/library/liked")
      case .collections:
        collections = try await api.get("/library/collections")
      }
    } catch {}
  }
}

public struct LibraryNativeView: View {
  @StateObject private var model: LibraryNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: LibraryNativeModel(api: api))
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: MIRATheme.Space.lg) {
        Picker("Library", selection: $model.tab) {
          ForEach(LibraryNativeModel.Tab.allCases, id: \.self) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, MIRATheme.Space.md)

        if model.tab == .collections {
          collectionList
        } else {
          postGrid(posts: model.tab == .saved ? model.savedPosts : model.likedPosts)
        }
      }
      .padding(.top, MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("My Library")
    .task { await model.load() }
    .onChange(of: model.tab) { _ in Task { await model.load() } }
    .refreshable { await model.load() }
  }

  private func postGrid(posts: [MIRAPost]) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
      ForEach(posts) { post in
        if let media = post.mediaURLs.first {
          RemoteMediaView(url: media, isVideo: media.isVideoURL)
            .aspectRatio(1, contentMode: .fill)
        } else {
          ZStack {
            MIRATheme.Color.surfaceSoft
            Text(post.titleText)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .padding(8)
          }
          .aspectRatio(1, contentMode: .fill)
        }
      }
    }
  }

  private var collectionList: some View {
    LazyVStack(spacing: MIRATheme.Space.sm) {
      if model.collections.isEmpty {
        MIRAEmptyState(title: "No collections yet", message: "Saved posts can be organized here.", systemImage: "folder")
      } else {
        ForEach(model.collections) { collection in
          HStack {
            Image(systemName: "folder.fill")
              .foregroundStyle(MIRATheme.Color.forest)
              .frame(width: 44, height: 44)
              .background(MIRATheme.Color.forestSoft)
              .clipShape(Circle())
            Text(collection.collection ?? collection.name ?? "Collection")
              .font(.system(size: 17, weight: .semibold))
            Spacer()
            Text("\(collection.count ?? 0)")
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
          .padding(MIRATheme.Space.md)
          .miraCardSurface()
          .padding(.horizontal, MIRATheme.Space.md)
        }
      }
    }
  }
}

@MainActor
final class SearchUsersNativeModel: ObservableObject {
  @Published var query = ""
  @Published var users: [MIRAUser] = []
  @Published var isLoading = false
  let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      users = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    users = (try? await api.get("/users/search/\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed)")) ?? []
  }
}

public struct SearchUsersNativeView: View {
  @StateObject private var model: SearchUsersNativeModel

  public init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: SearchUsersNativeModel(api: api))
  }

  public var body: some View {
    List {
      ForEach(model.users) { user in
        HStack(spacing: MIRATheme.Space.md) {
          RemoteAvatar(url: user.profileImage, size: 44)
          VStack(alignment: .leading) {
            Text(user.displayName).font(.system(size: 16, weight: .semibold))
            if let bio = user.bio, !bio.isEmpty {
              Text(bio).font(.system(size: 13)).foregroundStyle(MIRATheme.Color.textMuted).lineLimit(1)
            }
          }
        }
        .listRowBackground(MIRATheme.Color.surface)
      }
    }
    .scrollContentBackground(.hidden)
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("Search")
    .searchable(text: $model.query, prompt: "Search users")
    .task(id: model.query) {
      try? await Task.sleep(nanoseconds: 250_000_000)
      await model.search()
    }
  }
}

public struct CreatePostNativeView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var bodyText = ""
  @State private var mediaURL = ""
  @State private var isPosting = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    Form {
      Section("Post") {
        TextField("Headline", text: $title)
        TextField("Caption", text: $bodyText, axis: .vertical)
          .lineLimit(5...9)
        TextField("Image or video URL", text: $mediaURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
      }

      if let errorMessage {
        Text(errorMessage).foregroundStyle(.red)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack {
          Spacer()
          if isPosting { ProgressView() } else { Text("Post").fontWeight(.semibold) }
          Spacer()
        }
      }
      .disabled(isPosting || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaURL.isEmpty))
    }
    .navigationTitle("Create post")
  }

  private func submit() async {
    isPosting = true
    defer { isPosting = false }
    do {
      let cleanMedia = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let body = CreatePostBody(
        title: title,
        content: bodyText,
        image: cleanMedia.isEmpty ? nil : cleanMedia,
        images: cleanMedia.isEmpty ? [] : [cleanMedia],
        mediaTypes: cleanMedia.isVideoURL ? ["video"] : (cleanMedia.isEmpty ? [] : ["image"]),
        visibility: "public",
        clientRequestId: UUID().uuidString
      )
      let _: MIRAPost = try await api.post("/posts", body: body)
      dismiss()
    } catch {
      errorMessage = "Post could not be created."
    }
  }
}

public struct CreateNoteNativeView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var noteText = ""
  @State private var mediaURL = ""
  @State private var isPosting = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    Form {
      Section {
        TextField("What's new?", text: $noteText, axis: .vertical)
          .lineLimit(6...12)
        TextField("Photo or GIF URL", text: $mediaURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
      }

      if let media = mediaPreviewURL {
        RemoteMediaView(url: media, isVideo: media.isVideoURL)
          .frame(height: 260)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
      }

      if let errorMessage {
        Text(errorMessage).foregroundStyle(.red)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack {
          Spacer()
          if isPosting { ProgressView() } else { Text("Post note").fontWeight(.semibold) }
          Spacer()
        }
      }
      .disabled(isPosting || (noteText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 && mediaURL.isEmpty))
    }
    .navigationTitle("New note")
  }

  private var mediaPreviewURL: String? {
    let clean = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }

  private func submit() async {
    isPosting = true
    defer { isPosting = false }
    do {
      let _: MIRANote = try await api.post("/notes", body: CreateNoteBody(body: noteText, mediaUrl: mediaPreviewURL, color: "#FFFFFF"))
      dismiss()
    } catch {
      errorMessage = "Note could not be created."
    }
  }
}

public struct SettingsNativeView: View {
  public init() {}

  public var body: some View {
    List {
      Section("Account") {
        Label("Privacy", systemImage: "lock")
        Label("Notifications", systemImage: "bell")
        Label("Security", systemImage: "shield")
      }
      Section("Support") {
        Label("Help", systemImage: "questionmark.circle")
        Label("Terms", systemImage: "doc.text")
        Label("Privacy Policy", systemImage: "hand.raised")
      }
    }
    .scrollContentBackground(.hidden)
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("Settings")
  }
}
