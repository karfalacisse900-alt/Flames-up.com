import PhotosUI
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
  @State private var mediaItems: [MIRAPickedMedia] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var showCamera = false
  @State private var showPreview = false
  @State private var isPosting = false
  @State private var isLoadingMedia = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
        composerHeader("Create post")
        mediaPreview
        composerTextFields
        composerToolbar
        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red.opacity(0.85))
        }
        MIRAPrimaryButton(isPosting ? "Posting..." : "Post", systemImage: "paperplane.fill") {
          Task { await submit() }
        }
        .disabled(isPosting || !canPost)
      }
      .padding(MIRATheme.Space.md)
    }
    .background(MIRATheme.Color.appBackground)
    .toolbar(.hidden, for: .navigationBar)
    .onChange(of: pickerItems) { _, newItems in
      Task { await loadPickerItems(newItems) }
    }
    .sheet(isPresented: $showCamera) {
      MIRACameraCaptureView(allowsVideo: true) { media in
        mediaItems.append(media)
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $showPreview) {
      ComposerPreviewSheet(title: title, bodyText: bodyText, mediaItems: mediaItems)
    }
  }

  private var composerTextFields: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      TextField("Add a catchy headline", text: $title)
        .font(.system(size: 24, weight: .semibold))
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
      TextField("Write caption with details to get more views.", text: $bodyText, axis: .vertical)
        .font(.system(size: 17, weight: .regular))
        .lineLimit(5...10)
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
  }

  private var mediaPreview: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MIRATheme.Space.sm) {
        ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, item in
          LocalMediaThumb(media: item)
            .overlay(alignment: .topTrailing) {
              Button {
                mediaItems.remove(at: index)
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(.white)
                  .frame(width: 22, height: 22)
                  .background(.black.opacity(0.55))
                  .clipShape(Circle())
              }
              .padding(6)
            }
        }
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
          addTile
        }
      }
      .padding(.vertical, MIRATheme.Space.xs)
    }
  }

  private var composerToolbar: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
        composerTool("Gallery", systemImage: "photo.on.rectangle")
      }
      Button { showCamera = true } label: {
        composerTool("Camera", systemImage: "camera")
      }
      Button { showPreview = true } label: {
        composerTool("Preview", systemImage: "eye")
      }
      Spacer()
      if isLoadingMedia { ProgressView() }
    }
    .buttonStyle(.plain)
  }

  private var addTile: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(MIRATheme.Color.surfaceSoft)
      .frame(width: 96, height: 96)
      .overlay {
        Image(systemName: "plus")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
  }

  private var canPost: Bool {
    !mediaItems.isEmpty ||
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func submit() async {
    isPosting = true
    defer { isPosting = false }
    do {
      let uploader = MIRAMediaUploadService(api: api)
      var uploaded: [String] = []
      var mediaTypes: [String] = []
      for item in mediaItems {
        uploaded.append(try await uploader.upload(item))
        mediaTypes.append(item.kind.rawValue)
      }
      let body = CreatePostBody(
        title: title,
        content: bodyText,
        image: uploaded.first,
        images: uploaded,
        mediaTypes: mediaTypes,
        visibility: "public",
        clientRequestId: UUID().uuidString
      )
      let _: MIRAPost = try await api.post("/posts", body: body)
      dismiss()
    } catch {
      errorMessage = "Post could not be created."
    }
  }

  @MainActor
  private func loadPickerItems(_ items: [PhotosPickerItem]) async {
    isLoadingMedia = true
    defer {
      isLoadingMedia = false
      pickerItems = []
    }
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
      let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
      mediaItems.append(MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType))
    }
  }
}

public struct CreateNoteNativeView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var currentUser: MIRAUser?
  @State private var noteText = ""
  @State private var mediaItem: MIRAPickedMedia?
  @State private var pickerItem: PhotosPickerItem?
  @State private var gifURL = ""
  @State private var gifQuery = ""
  @State private var gifResults: [MIRAGifItem] = []
  @State private var showGIFField = false
  @State private var showCamera = false
  @State private var isPosting = false
  @State private var isLoadingMedia = false
  @State private var isSearchingGIFs = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    VStack(spacing: 0) {
      noteComposerHeader
      Divider().overlay(MIRATheme.Color.hairline)

      ScrollView {
        noteEditorContent
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.lg)
          .padding(.bottom, 140)
      }

      noteBottomBar
    }
    .background(MIRATheme.Color.surface)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      await loadCurrentUser()
      restoreDraft()
    }
    .onChange(of: pickerItem) { _, newItem in
      Task { await loadPickerItem(newItem) }
    }
    .sheet(isPresented: $showCamera) {
      MIRACameraCaptureView(allowsVideo: false) { media in
        mediaItem = media
      }
      .ignoresSafeArea()
    }
  }

  private var noteComposerHeader: some View {
    HStack {
      Button("Cancel") { dismiss() }
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 56)

      Spacer()

      Button("Save") {
        saveDraft()
      }
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(canSaveDraft ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      .frame(width: 92, height: 46)
      .background(canSaveDraft ? MIRATheme.Color.forestSoft : MIRATheme.Color.surfaceSoft.opacity(0.72))
      .clipShape(Capsule())
      .disabled(!canSaveDraft)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.xs)
    .padding(.bottom, MIRATheme.Space.sm)
    .background(MIRATheme.Color.surface)
  }

  private var noteEditorContent: some View {
    HStack(alignment: .top, spacing: MIRATheme.Space.md) {
      VStack(spacing: 0) {
        RemoteAvatar(url: currentUser?.profileImage, size: 48)
        Rectangle()
          .fill(MIRATheme.Color.surfaceSoft)
          .frame(width: 5)
          .frame(minHeight: 460)
          .clipShape(Capsule())
          .padding(.top, MIRATheme.Space.sm)
        Text((currentUser?.displayName.first.map(String.init) ?? "M").uppercased())
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.45))
          .frame(width: 34, height: 34)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.35))
          .clipShape(Circle())
          .padding(.top, MIRATheme.Space.sm)
      }

      VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
        Text(currentUser?.displayName ?? "karfala900")
          .font(.system(size: 27, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)

        ZStack(alignment: .topLeading) {
          if noteText.isEmpty {
            Text("What's new?")
              .font(.system(size: 27, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.72))
              .padding(.top, 7)
              .allowsHitTesting(false)
          }

          TextEditor(text: $noteText)
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 130)
            .padding(.leading, -5)
        }

        HStack(spacing: MIRATheme.Space.xl) {
          PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo")
              .font(.system(size: 29, weight: .regular))
              .frame(width: 42, height: 42)
          }

          Button {
            withAnimation(.snappy(duration: 0.18)) { showGIFField.toggle() }
          } label: {
            Text("GIF")
              .font(.system(size: 19, weight: .heavy))
              .frame(width: 62, height: 42)
              .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(lineWidth: 2.4))
          }

          if isLoadingMedia {
            ProgressView()
              .tint(MIRATheme.Color.textMuted)
          }
        }
        .foregroundStyle(MIRATheme.Color.textMuted)
        .buttonStyle(.plain)
        .padding(.top, MIRATheme.Space.sm)

        if showGIFField {
          gifSearchPanel
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        noteMediaPreview
          .padding(.top, MIRATheme.Space.sm)

        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.top, MIRATheme.Space.xs)
        }
      }
    }
  }

  private var noteBottomBar: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "slider.horizontal.3")
        .font(.system(size: 23, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)

      Text("Reply options")
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.78)

      Spacer()

      Button {} label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(width: 54, height: 54)
          .background(MIRATheme.Color.surface)
          .overlay(Circle().stroke(MIRATheme.Color.hairline, lineWidth: 1))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button {
        Task { await submit() }
      } label: {
        if isPosting {
          ProgressView().tint(.white)
        } else {
          Text("Post")
            .font(.system(size: 23, weight: .semibold))
        }
      }
      .foregroundStyle(.white)
      .frame(width: 116, height: 58)
      .background(canPostNote ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.55))
      .clipShape(Capsule())
      .disabled(isPosting || !canPostNote)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.top, MIRATheme.Space.sm)
    .padding(.bottom, MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
  }

  private var gifSearchPanel: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      HStack(spacing: MIRATheme.Space.sm) {
        TextField("Search GIFs", text: $gifQuery)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 15, weight: .medium))
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 44)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.80))
          .clipShape(Capsule())
          .onSubmit { Task { await searchGIFs() } }

        Button {
          Task { await searchGIFs() }
        } label: {
          if isSearchingGIFs {
            ProgressView().tint(MIRATheme.Color.forest)
          } else {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 17, weight: .semibold))
          }
        }
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
        .buttonStyle(.plain)
      }

      if !gifResults.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MIRATheme.Space.sm) {
            ForEach(gifResults) { gif in
              Button {
                gifURL = gif.mediaUrl ?? gif.previewUrl ?? ""
              } label: {
                RemoteMediaView(url: gif.previewUrl ?? gif.mediaUrl ?? "", isVideo: false)
                  .frame(width: 92, height: 92)
                  .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous)
                      .stroke((gif.mediaUrl == gifURL || gif.previewUrl == gifURL) ? MIRATheme.Color.forest : .clear, lineWidth: 2)
                  )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
      } else {
        Text("Search Giphy and tap one to add it.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
  }

  private func submit() async {
    isPosting = true
    defer { isPosting = false }
    do {
      let uploadedURL: String?
      if let mediaItem {
        uploadedURL = try await MIRAMediaUploadService(api: api).upload(mediaItem)
      } else {
        let cleanGIF = gifURL.trimmingCharacters(in: .whitespacesAndNewlines)
        uploadedURL = cleanGIF.isEmpty ? nil : cleanGIF
      }
      let _: MIRANote = try await api.post("/notes", body: CreateNoteBody(body: noteText, mediaUrl: uploadedURL, color: "#FFFFFF"))
      dismiss()
    } catch {
      errorMessage = "Note could not be created."
    }
  }

  private var canPostNote: Bool {
    noteText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ||
      mediaItem != nil ||
      !gifURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canSaveDraft: Bool {
    canPostNote
  }

  private var noteMediaPreview: some View {
    Group {
      if let mediaItem {
        LocalMediaThumb(media: mediaItem, width: UIScreen.main.bounds.width - 94, height: 260)
      } else if !gifURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        RemoteMediaView(url: gifURL, isVideo: false)
          .frame(maxWidth: .infinity)
          .frame(height: 260)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
      }
    }
  }

  @MainActor
  private func loadCurrentUser() async {
    guard currentUser == nil else { return }
    currentUser = try? await api.get("/auth/me")
  }

  private func saveDraft() {
    UserDefaults.standard.set(noteText, forKey: "mira.noteDraft.text")
    UserDefaults.standard.set(gifURL, forKey: "mira.noteDraft.gifURL")
  }

  private func restoreDraft() {
    guard noteText.isEmpty && gifURL.isEmpty && mediaItem == nil else { return }
    noteText = UserDefaults.standard.string(forKey: "mira.noteDraft.text") ?? ""
    gifURL = UserDefaults.standard.string(forKey: "mira.noteDraft.gifURL") ?? ""
    showGIFField = !gifURL.isEmpty
  }

  @MainActor
  private func searchGIFs() async {
    let clean = gifQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else { return }
    isSearchingGIFs = true
    defer { isSearchingGIFs = false }
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: clean),
      URLQueryItem(name: "limit", value: "18"),
    ]
    let query = components.percentEncodedQuery ?? "q=\(clean)"
    do {
      let response: MIRAGifSearchResponse = try await api.get("/gifs/search?\(query)")
      gifResults = response.gifs
      errorMessage = nil
    } catch {
      errorMessage = "GIF search is not available yet."
    }
  }

  @MainActor
  private func loadPickerItem(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isLoadingMedia = true
    defer {
      isLoadingMedia = false
      pickerItem = nil
    }
    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
    let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
    mediaItem = MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType)
  }
}

public struct CreateStoryNativeView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var mediaItem: MIRAPickedMedia?
  @State private var pickerItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var isPosting = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    ZStack {
      MIRATheme.Color.textPrimary.ignoresSafeArea()
      VStack(spacing: MIRATheme.Space.md) {
        HStack {
          Button { dismiss() } label: {
            Image(systemName: "xmark")
              .font(.system(size: 24, weight: .regular))
              .foregroundStyle(.white)
          }
          Spacer()
          Button { showCamera = true } label: {
            Image(systemName: "camera")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
        .padding(MIRATheme.Space.md)

        ZStack(alignment: .bottomLeading) {
          if let mediaItem {
            LocalMediaThumb(media: mediaItem, width: UIScreen.main.bounds.width - 28, height: UIScreen.main.bounds.height * 0.70)
          } else {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
              .fill(MIRATheme.Color.forest)
              .overlay {
                VStack(spacing: MIRATheme.Space.md) {
                  Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .light))
                  Text("Add a story")
                    .font(.system(size: 24, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
              }
          }

          TextField("Aa", text: $text, axis: .vertical)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
            .padding(MIRATheme.Space.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

        HStack(spacing: MIRATheme.Space.lg) {
          PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
            Image(systemName: "photo.on.rectangle")
          }
          Button { showCamera = true } label: {
            Image(systemName: "camera")
          }
          Spacer()
          Button {
            Task { await submit() }
          } label: {
            Text(isPosting ? "Posting..." : "Share story")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(height: 48)
              .padding(.horizontal, MIRATheme.Space.lg)
              .background(.white)
              .clipShape(Capsule())
          }
          .disabled(isPosting || (mediaItem == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, MIRATheme.Space.md)

        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.white)
            .font(.system(size: 13, weight: .semibold))
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onChange(of: pickerItem) { _, newItem in
      Task { await loadPickerItem(newItem) }
    }
    .sheet(isPresented: $showCamera) {
      MIRACameraCaptureView(allowsVideo: true) { media in
        mediaItem = media
      }
      .ignoresSafeArea()
    }
  }

  private func submit() async {
    isPosting = true
    defer { isPosting = false }
    do {
      let uploaded: String?
      if let mediaItem {
        uploaded = try await MIRAMediaUploadService(api: api).upload(mediaItem)
      } else {
        uploaded = nil
      }
      let _: MIRAStatusPreview = try await api.post(
        "/statuses",
        body: CreateStatusBody(content: text, image: uploaded, backgroundColor: "#1B4332", textColor: "#FFFFFF", visibility: "public")
      )
      dismiss()
    } catch {
      errorMessage = "Story could not be posted."
    }
  }

  @MainActor
  private func loadPickerItem(_ item: PhotosPickerItem?) async {
    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
    let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
    mediaItem = MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType)
    pickerItem = nil
  }
}

private func composerHeader(_ title: String) -> some View {
  HStack {
    Text(title)
      .font(.system(size: 24, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
    Spacer()
  }
}

private func composerTool(_ title: String, systemImage: String) -> some View {
  HStack(spacing: 8) {
    Image(systemName: systemImage)
    Text(title)
  }
  .font(.system(size: 14, weight: .semibold))
  .foregroundStyle(MIRATheme.Color.textPrimary)
  .padding(.horizontal, MIRATheme.Space.md)
  .frame(height: 42)
  .background(MIRATheme.Color.surfaceSoft)
  .clipShape(Capsule())
}

private struct LocalMediaThumb: View {
  let media: MIRAPickedMedia
  var width: CGFloat = 96
  var height: CGFloat = 96

  var body: some View {
    ZStack {
      if media.kind == .image, let image = UIImage(data: media.data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        MIRATheme.Color.surfaceSoft
        Image(systemName: "play.fill")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private struct ComposerPreviewSheet: View {
  let title: String
  let bodyText: String
  let mediaItems: [MIRAPickedMedia]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
          if let first = mediaItems.first {
            LocalMediaThumb(media: first, width: UIScreen.main.bounds.width - 32, height: 420)
          }
          if !title.isEmpty {
            Text(title)
              .font(.system(size: 24, weight: .semibold))
          }
          if !bodyText.isEmpty {
            Text(bodyText)
              .font(.system(size: 16, weight: .regular))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
        }
        .padding(MIRATheme.Space.md)
      }
      .background(MIRATheme.Color.appBackground)
      .navigationTitle("Preview")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
  }
}

public struct SettingsNativeView: View {
  private let authSession: MIRAAuthSession?

  public init(authSession: MIRAAuthSession? = nil) {
    self.authSession = authSession
  }

  public var body: some View {
    List {
      Section("Account") {
        Label("Privacy", systemImage: "lock")
        Label("Notifications", systemImage: "bell")
        Label("Security", systemImage: "shield")
        if let authSession {
          Button(role: .destructive) {
            authSession.logout()
          } label: {
            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
          }
        }
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
