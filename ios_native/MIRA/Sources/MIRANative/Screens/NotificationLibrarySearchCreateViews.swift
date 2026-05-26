import AVFoundation
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
    .miraScreenEnter(.push)
    .navigationTitle("Notifications")
    .task { await model.load() }
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
    .miraScreenEnter(.push)
    .navigationTitle("My Library")
    .toolbar(.hidden, for: .tabBar)
    .task { await model.load() }
    .onChange(of: model.tab) { _ in Task { await model.load() } }
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
    .miraScreenEnter(.push)
    .navigationTitle("Search")
    .searchable(text: $model.query, prompt: "Search users")
    .task(id: model.query) {
      try? await Task.sleep(nanoseconds: 250_000_000)
      await model.search()
    }
  }
}

private struct MIRAEditorPresentation: Identifiable {
  let id = UUID()
  let media: MIRAPickedMedia
  var replacementIndex: Int?
  var returnsToCamera = false
}

private enum PostDetailSheet: Identifiable, Equatable {
  case location
  case people
  case tags

  var id: String {
    switch self {
    case .location: return "location"
    case .people: return "people"
    case .tags: return "tags"
    }
  }
}

private struct MIRAMapboxPlace: Decodable, Identifiable, Hashable {
  let placeId: String?
  let mapboxId: String?
  let name: String?
  let formattedAddress: String?
  let address: String?
  let vicinity: String?
  let lat: Double?
  let lng: Double?

  var id: String {
    placeId ?? mapboxId ?? [displayName, addressText].compactMap { $0 }.joined(separator: "-")
  }

  var displayName: String {
    let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? "Place" : clean
  }

  var addressText: String? {
    for value in [formattedAddress, address, vicinity] {
      let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !clean.isEmpty { return clean }
    }
    return nil
  }
}

public struct CreatePostNativeView: View {
  let api: MIRAAPIClient
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var bodyText = ""
  @State private var mediaItems: [MIRAPickedMedia] = []
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var showPreview = false
  @State private var isEditingPostDetails = false
  @State private var isPosting = false
  @State private var isLoadingMedia = false
  @State private var errorMessage: String?
  @State private var editingMedia: MIRAEditorPresentation?
  @State private var editedCameraMedia: MIRAPickedMedia?
  @State private var activePostDetailSheet: PostDetailSheet?
  @State private var selectedPlace: MIRAMapboxPlace?
  @State private var taggedUsers: [MIRAUser] = []
  @State private var hashtags: [String] = []

  public init(api: MIRAAPIClient, onClose: (() -> Void)? = nil) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    Group {
      if isEditingPostDetails {
        finalPostPage
      } else {
        mediaFirstPage
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .miraScreenEnter(.modal)
    .navigationBarBackButtonHidden(true)
    .onChange(of: pickerItems) { _, newItems in
      Task { await loadPickerItems(newItems) }
    }
    .miraBottomSheet(isPresented: $showPreview, preferredHeightFraction: 0.72) { _ in
      ComposerPreviewSheet(title: title, bodyText: bodyText, mediaItems: mediaItems)
    }
    .miraBottomSheet(isPresented: postDetailSheetPresentedBinding, preferredHeightFraction: postDetailSheetHeightFraction) { closeSheet in
      switch activePostDetailSheet {
      case .location:
        PostLocationPickerSheet(api: api, selectedPlace: $selectedPlace, onClose: closeSheet)
      case .people:
        PostPeopleTagSheet(api: api, selectedUsers: $taggedUsers, onClose: closeSheet)
      case .tags:
        PostHashtagSheet(hashtags: $hashtags, onClose: closeSheet)
      case nil:
        Color.clear
      }
    }
    .miraFullScreenOverlay(item: $editingMedia, background: .black) { item, closeEditor in
      MIRANativeMediaEditorView(media: item.media, mode: .post, onClose: closeEditor) { edited in
        if item.returnsToCamera {
          editedCameraMedia = edited
        } else if let index = item.replacementIndex, mediaItems.indices.contains(index) {
          mediaItems[index] = edited
        } else {
          mediaItems.append(edited)
          withAnimation(.snappy(duration: 0.2)) {
            isEditingPostDetails = true
          }
        }
      }
      .ignoresSafeArea()
    }
  }

  private var postDetailSheetPresentedBinding: Binding<Bool> {
    Binding(
      get: { activePostDetailSheet != nil },
      set: { isPresented in
        if !isPresented {
          activePostDetailSheet = nil
        }
      }
    )
  }

  private var postDetailSheetHeightFraction: CGFloat {
    activePostDetailSheet == .tags ? 0.50 : 0.76
  }

  private var mediaFirstPage: some View {
    ZStack {
      MIRAStoryLiveCameraView(
        editedMedia: editedCameraMedia,
        dismissesOnCapture: false,
        dismissesOnCancel: false,
        onCapture: { media in
          addCapturedMediaAndContinue(media)
        },
        onCancel: {
          close()
        },
        onEdit: { media, _ in
          editingMedia = MIRAEditorPresentation(media: media, returnsToCamera: true)
        }
      )
      .ignoresSafeArea()

      if isLoadingMedia {
        ProgressView()
          .tint(.white)
          .scaleEffect(1.12)
      }
    }
    .background(Color.black.ignoresSafeArea())
  }

  private var finalPostPage: some View {
    GeometryReader { proxy in
      VStack(spacing: 0) {
        postDetailsTopBar

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 0) {
            postDetailsMediaStrip
              .padding(.top, 24)

            postDetailsTextFields
              .padding(.top, 34)

            Spacer(minLength: max(120, proxy.size.height * 0.22))

            postDetailsQuickActions
              .padding(.top, 24)

            Rectangle()
              .fill(MIRATheme.Color.hairline.opacity(0.75))
              .frame(height: 0.7)
              .padding(.top, 20)

            postOptionRow(
              icon: "mappin.circle",
              title: selectedPlace?.displayName ?? "Add Location",
              subtitle: selectedPlace?.addressText ?? "Search places or add an address",
              action: { activePostDetailSheet = .location }
            )
          }
          .padding(.horizontal, 16)
          .padding(.bottom, max(proxy.safeAreaInsets.bottom + 28, 52))
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
    }
  }

  private var postDetailsTopBar: some View {
    HStack {
      Button {
        returnToCapture()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 34, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 54, height: 54)
      }
      .buttonStyle(.plain)

      Spacer()

      HStack(spacing: 10) {
        Button { showPreview = true } label: {
          HStack(spacing: 6) {
            Text("Preview")
              .font(.system(size: 17, weight: .semibold))
            Image(systemName: "eye")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.horizontal, 15)
          .frame(height: 46)
          .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
          Task { await submit() }
        } label: {
          HStack(spacing: 7) {
            if isPosting {
              ProgressView()
                .tint(.white)
                .scaleEffect(0.72)
            }
            Text(isPosting ? "Posting" : "Post")
              .font(.system(size: 17, weight: .semibold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 19)
          .frame(height: 46)
          .background(canPost && !isPosting ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.45))
          .clipShape(Capsule())
          .shadow(color: MIRATheme.Color.forest.opacity(canPost ? 0.18 : 0), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isPosting || !canPost)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .frame(height: 98)
  }

  private var postDetailsMediaStrip: some View {
    HStack(spacing: 14) {
      if let first = mediaItems.first {
        postComposerMedia(first, width: 104, height: 108, cornerRadius: 14)
          .overlay(alignment: .bottomLeading) {
            Text("Cover")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .frame(height: 31)
              .background(.black.opacity(0.52))
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
              .padding(8)
          }
          .onTapGesture {
            if first.kind == .image {
              editingMedia = MIRAEditorPresentation(media: first, replacementIndex: 0)
            }
          }
      }

      PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(MIRATheme.Color.surfaceSoft.opacity(0.6))
          .frame(width: 104, height: 108)
          .overlay {
            Image(systemName: "plus")
              .font(.system(size: 36, weight: .light))
              .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.82))
          }
      }
    }
  }

  private var postDetailsTextFields: some View {
    VStack(alignment: .leading, spacing: 18) {
      TextField("Add a catchy headline", text: $title)
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .submitLabel(.next)

      Rectangle()
        .fill(MIRATheme.Color.hairline.opacity(0.78))
        .frame(height: 0.7)

      TextField("Write caption with details to get more views.", text: $bodyText, axis: .vertical)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(4...8)

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.red.opacity(0.9))
      }
    }
  }

  private var postDetailsQuickActions: some View {
    HStack(spacing: 10) {
      postDetailsChip(selectedPlace?.displayName ?? "Places", systemImage: "mappin.circle") {
        activePostDetailSheet = .location
      }
      postDetailsChip(taggedUsers.isEmpty ? "@" : "@ \(taggedUsers.count)", systemImage: nil) {
        activePostDetailSheet = .people
      }
      postDetailsChip(hashtags.isEmpty ? "#" : "# \(hashtags.count)", systemImage: nil) {
        activePostDetailSheet = .tags
      }
    }
  }

  private func postDetailsChip(_ title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 19, weight: .regular))
        }
        Text(title)
          .font(.system(size: title.count == 1 ? 23 : 17, weight: .semibold))
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, title.count == 1 ? 18 : 20)
      .frame(height: 52)
      .background(MIRATheme.Color.surfaceSoft.opacity(0.58))
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func postOptionRow(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 18) {
        Image(systemName: icon)
          .font(.system(size: icon == "ellipsis" ? 25 : 28, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 34)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 14, weight: .regular))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 27, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.82))
      }
      .frame(minHeight: 72)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(MIRATheme.Color.hairline.opacity(0.72))
        .frame(height: 0.7)
    }
  }

  @ViewBuilder
  private func postComposerMedia(_ media: MIRAPickedMedia, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
    LocalMediaThumb(media: media, width: width, height: height, cornerRadius: cornerRadius)
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
      var mediaDimensions: [MIRAMediaDimension] = []
      for item in mediaItems {
        uploaded.append(try await uploader.upload(item))
        mediaTypes.append(item.kind.rawValue)
        mediaDimensions.append(await item.mediaDimension())
      }
      let cleanedTags = hashtags
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
        .filter { !$0.isEmpty }
      let tagLine = cleanedTags.isEmpty ? "" : cleanedTags.map { "#\($0)" }.joined(separator: " ")
      let postContent = [bodyText.trimmingCharacters(in: .whitespacesAndNewlines), tagLine]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      let taggedPayload = taggedUsers.map {
        MIRATaggedUserPayload(id: $0.id, username: $0.username, fullName: $0.fullName, profileImage: $0.profileImage)
      }
      let body = CreatePostBody(
        title: title,
        content: postContent,
        image: uploaded.first,
        images: uploaded,
        mediaTypes: mediaTypes,
        mediaDimensions: mediaDimensions,
        editorOverlays: editorUploadMetadata(),
        location: selectedPlace?.addressText ?? selectedPlace?.displayName,
        postType: selectedPlace == nil ? "general" : "place",
        placeId: selectedPlace?.placeId ?? selectedPlace?.mapboxId,
        placeName: selectedPlace?.displayName,
        placeLat: selectedPlace?.lat,
        placeLng: selectedPlace?.lng,
        taggedUsers: taggedPayload.isEmpty ? nil : taggedPayload,
        visibility: "public",
        clientRequestId: UUID().uuidString
      )
      let _: MIRAPost = try await api.post("/posts", body: body)
      close()
    } catch {
      errorMessage = "Post could not be created."
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func loadPickerItems(_ items: [PhotosPickerItem]) async {
    isLoadingMedia = true
    defer {
      isLoadingMedia = false
      pickerItems = []
    }
    var loaded: [MIRAPickedMedia] = []
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
      let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
      loaded.append(MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType))
    }
    mediaItems.append(contentsOf: loaded)
    if !loaded.isEmpty {
      withAnimation(.snappy(duration: 0.2)) {
        isEditingPostDetails = true
      }
    }
  }

  private func addCapturedMediaAndContinue(_ media: MIRAPickedMedia) {
    editedCameraMedia = nil
    mediaItems.append(media)
    withAnimation(.snappy(duration: 0.2)) {
      isEditingPostDetails = true
    }
  }

  private func returnToCapture() {
    editedCameraMedia = nil
    withAnimation(.snappy(duration: 0.2)) {
      isEditingPostDetails = false
    }
  }

  private func editorUploadMetadata() -> [MIRAEditorUploadMetadata]? {
    let metadata = mediaItems.enumerated().compactMap { index, item -> MIRAEditorUploadMetadata? in
      guard let editorMetadata = item.editorMetadata else { return nil }
      return MIRAEditorUploadMetadata(mediaIndex: index, metadata: editorMetadata)
    }
    return metadata.isEmpty ? nil : metadata
  }
}

private struct PostLocationPickerSheet: View {
  let api: MIRAAPIClient
  @Binding var selectedPlace: MIRAMapboxPlace?
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var places: [MIRAMapboxPlace] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: MIRATheme.Space.md) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(MIRATheme.Color.textMuted)
            TextField("Search place or address", text: $query)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .submitLabel(.search)
              .focused($isSearchFocused)
              .onSubmit {
                Task { await searchPlaces(for: cleanQuery) }
              }
            if !cleanQuery.isEmpty {
              Button {
                query = ""
                places = []
                isLoading = false
                errorMessage = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.75))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .frame(height: 48)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Capsule())

          if let selectedPlace {
            selectedPlacePill(selectedPlace)
          }
        }
        .padding(MIRATheme.Space.md)

        ScrollView {
          LazyVStack(spacing: 10) {
            searchStatusView

            if cleanQuery.count >= 2 {
              Button {
                selectManualPlace()
              } label: {
                placeRowTitle(
                  systemImage: "plus.circle.fill",
                  name: "Use \"\(cleanQuery)\"",
                  subtitle: "Custom place or address"
                )
              }
              .buttonStyle(.miraPress)
            }

            ForEach(places) { place in
              Button {
                selectedPlace = place
                close()
              } label: {
                placeRowTitle(systemImage: "mappin.circle.fill", name: place.displayName, subtitle: place.addressText)
              }
              .buttonStyle(.miraPress)
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.bottom, 28)
        }
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Add Location")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if selectedPlace != nil {
            Button("Remove") {
              selectedPlace = nil
              close()
            }
            .foregroundStyle(.red)
          }
        }
      }
      .onAppear {
        isSearchFocused = true
      }
      .task(id: cleanQuery) {
        let snapshot = cleanQuery
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        await searchPlaces(for: snapshot)
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func selectedPlacePill(_ place: MIRAMapboxPlace) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "mappin.circle.fill")
        .foregroundStyle(MIRATheme.Color.forest)
      VStack(alignment: .leading, spacing: 2) {
        Text(place.displayName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        if let address = place.addressText {
          Text(address)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.forestSoft)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var searchStatusView: some View {
    if isLoading {
      HStack(spacing: MIRATheme.Space.sm) {
        ProgressView()
          .tint(MIRATheme.Color.forest)
        Text("Finding places...")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 62)
      .background(MIRATheme.Color.surfaceSoft.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    } else if let errorMessage {
      placePickerMessage(errorMessage, systemImage: "exclamationmark.triangle")
    } else if cleanQuery.isEmpty {
      placePickerMessage("Search for a restaurant, venue, city, or type any address.", systemImage: "magnifyingglass.circle")
    } else if cleanQuery.count < 2 {
      placePickerMessage("Keep typing to search places.", systemImage: "text.cursor")
    } else if places.isEmpty {
      placePickerMessage("No matching places yet. You can still use your typed location.", systemImage: "mappin.circle")
    }
  }

  private func placePickerMessage(_ text: String, systemImage: String) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  private func placeRowTitle(systemImage: String, name: String, subtitle: String?) -> some View {
    HStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
      }
      Spacer(minLength: MIRATheme.Space.sm)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.65))
    }
    .padding(MIRATheme.Space.md)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.hairline, lineWidth: 1)
    }
  }

  private var cleanQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var manualPlaceId: String {
    let slug = cleanQuery
      .lowercased()
      .filter { $0.isLetter || $0.isNumber }
      .prefix(42)
    return "manual-\(slug.isEmpty ? "place" : String(slug))"
  }

  private func selectManualPlace() {
    selectedPlace = MIRAMapboxPlace(
      placeId: manualPlaceId,
      mapboxId: nil,
      name: cleanQuery,
      formattedAddress: cleanQuery,
      address: cleanQuery,
      vicinity: nil,
      lat: nil,
      lng: nil
    )
    close()
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func searchPlaces(for clean: String) async {
    guard clean.count >= 2 else {
      places = []
      errorMessage = nil
      isLoading = false
      return
    }
    isLoading = true
    do {
      let encoded = clean.addingPercentEncoding(withAllowedCharacters: urlQueryComponentAllowed) ?? clean
      let loaded: [MIRAMapboxPlace] = try await api.get("/mapbox-places/nearby?keyword=\(encoded)&type=place")
      guard !Task.isCancelled, clean == cleanQuery else { return }
      places = loaded
      errorMessage = nil
      isLoading = false
    } catch {
      guard !Task.isCancelled, clean == cleanQuery else { return }
      places = []
      errorMessage = "Mapbox places could not load. You can still use your typed address."
      isLoading = false
    }
  }

  private var urlQueryComponentAllowed: CharacterSet {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=?+")
    return allowed
  }
}

private struct PostPeopleTagSheet: View {
  let api: MIRAAPIClient
  @Binding var selectedUsers: [MIRAUser]
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var users: [MIRAUser] = []
  @State private var isLoading = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(MIRATheme.Color.textMuted)
          TextField("Search people", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .frame(height: 48)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .padding(MIRATheme.Space.md)

        List {
          if !selectedUsers.isEmpty {
            Section("Tagged") {
              ForEach(selectedUsers) { user in
                personRow(user, selected: true)
                  .listRowBackground(MIRATheme.Color.surface)
              }
            }
          }

          Section(query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? "Results" : "Search") {
            if isLoading {
              ProgressView()
                .frame(maxWidth: .infinity, minHeight: 58)
                .listRowBackground(MIRATheme.Color.surface)
            } else {
              ForEach(users) { user in
                personRow(user, selected: selectedUsers.contains(where: { $0.id == user.id }))
                  .listRowBackground(MIRATheme.Color.surface)
              }
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Tag People")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { close() }
            .fontWeight(.semibold)
        }
      }
      .task(id: query) {
        try? await Task.sleep(nanoseconds: 250_000_000)
        await searchUsers()
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func personRow(_ user: MIRAUser, selected: Bool) -> some View {
    Button {
      toggle(user)
    } label: {
      HStack(spacing: MIRATheme.Space.md) {
        RemoteAvatar(url: user.profileImage, size: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(user.displayName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          if let fullName = user.fullName, fullName != user.displayName {
            Text(fullName)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(selected ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .padding(.vertical, 5)
    }
    .buttonStyle(.plain)
  }

  private func toggle(_ user: MIRAUser) {
    if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
      selectedUsers.remove(at: index)
    } else if selectedUsers.count < 10 {
      selectedUsers.append(user)
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  @MainActor
  private func searchUsers() async {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else {
      users = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    users = (try? await api.get("/users/search/\(clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean)")) ?? []
  }
}

private struct PostHashtagSheet: View {
  @Binding var hashtags: [String]
  let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var draft = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
        HStack(spacing: MIRATheme.Space.sm) {
          TextField("Add tag", text: $draft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, MIRATheme.Space.md)
            .frame(height: 48)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Capsule())

          Button("Add") {
            addTag()
          }
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 74, height: 48)
          .background(canAddTag ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.45))
          .clipShape(Capsule())
          .disabled(!canAddTag)
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)

        if hashtags.isEmpty {
          MIRAEmptyState(title: "No tags yet", message: "Add a few tags to help people understand the post.", systemImage: "number")
            .padding(.top, MIRATheme.Space.xl)
        } else {
          LazyVStack(spacing: MIRATheme.Space.sm) {
            ForEach(hashtags, id: \.self) { tag in
              HStack {
                Text("#\(tag)")
                  .font(.system(size: 17, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                Spacer()
                Button {
                  hashtags.removeAll { $0 == tag }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(MIRATheme.Color.textMuted)
                }
                .buttonStyle(.plain)
              }
              .padding(MIRATheme.Space.md)
              .background(MIRATheme.Color.surfaceSoft.opacity(0.7))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
          }
          .padding(.horizontal, MIRATheme.Space.md)
        }

        Spacer()
      }
      .background(MIRATheme.Color.surface.ignoresSafeArea())
      .navigationTitle("Tags")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { close() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { close() }
            .fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private var canAddTag: Bool {
    normalizedDraft.count >= 1 && !hashtags.contains(normalizedDraft)
  }

  private var normalizedDraft: String {
    let raw = draft
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      .lowercased()
    let allowed = raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return String(allowed.prefix(30))
  }

  private func addTag() {
    let clean = normalizedDraft
    guard !clean.isEmpty, !hashtags.contains(clean), hashtags.count < 12 else { return }
    hashtags.append(clean)
    draft = ""
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
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
    .miraScreenEnter(.modal)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      await loadCurrentUser()
      restoreDraft()
    }
    .onChange(of: pickerItem) { _, newItem in
      Task { await loadPickerItem(newItem) }
    }
  }

  private var noteComposerHeader: some View {
    HStack {
      Button("Cancel") { dismiss() }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 56)

      Spacer()

      Button("Save") {
        saveDraft()
      }
        .font(.system(size: 16, weight: .semibold))
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
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)

        ZStack(alignment: .topLeading) {
          if noteText.isEmpty {
            Text("What's new?")
              .font(.system(size: 19, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.72))
              .padding(.top, 7)
              .allowsHitTesting(false)
          }

          TextEditor(text: $noteText)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 130)
            .padding(.leading, -5)
        }

        HStack(spacing: MIRATheme.Space.xl) {
          PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo")
              .font(.system(size: 24, weight: .regular))
              .frame(width: 42, height: 42)
          }

          Button {
            openGIFPicker()
          } label: {
            Text("GIF")
              .font(.system(size: 16, weight: .heavy))
              .frame(width: 56, height: 40)
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
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)

      Text("Reply options")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.78)

      Spacer()

      Button {} label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(width: 46, height: 46)
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
            .font(.system(size: 16, weight: .semibold))
        }
      }
      .foregroundStyle(.white)
      .frame(width: 98, height: 50)
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
        Text(isSearchingGIFs ? "Loading GIFs..." : "Tap search or type a word to find GIFs.")
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
  private func openGIFPicker() {
    let shouldLoadInitialResults = gifResults.isEmpty
    withAnimation(.snappy(duration: 0.18)) {
      showGIFField = true
    }
    guard shouldLoadInitialResults else { return }
    if gifQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      gifQuery = "reaction"
    }
    Task { await searchGIFs() }
  }

  @MainActor
  private func searchGIFs() async {
    let clean = gifQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else {
      gifResults = []
      return
    }
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
  private let onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showCamera = false
  @State private var didOpenInitialCamera = false
  @State private var isPosting = false
  @State private var errorMessage: String?
  @State private var editingMedia: MIRAEditorPresentation?

  public init(api: MIRAAPIClient, onClose: (() -> Void)? = nil) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack {
        HStack {
          Button { close() } label: {
            Image(systemName: "xmark")
              .font(.system(size: 24, weight: .regular))
              .foregroundStyle(.white)
              .frame(width: 48, height: 48)
          }

          Spacer()
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.sm)

        Spacer()

        VStack(spacing: MIRATheme.Space.md) {
          if isPosting {
            ProgressView()
              .tint(.white)
            Text("Posting story...")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.82))
          } else if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.86))
              .multilineTextAlignment(.center)

            Button { showCamera = true } label: {
              Label("Try again", systemImage: "camera")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 46)
                .background(.white)
                .clipShape(Capsule())
            }
          } else {
            ProgressView()
              .tint(.white)
            Text("Opening camera...")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.72))
          }
        }

        Spacer()
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .miraScreenEnter(.modal)
    .task {
      guard !didOpenInitialCamera else { return }
      didOpenInitialCamera = true
      showCamera = true
    }
    .miraFullScreenOverlay(isPresented: $showCamera, background: .black) { closeCamera in
      MIRAStoryLiveCameraView(
        dismissesOnCapture: false,
        dismissesOnCancel: false,
        onCapture: { media in
          closeCamera()
          presentStoryEditor(for: media)
        },
        onCancel: {
          closeCamera()
          DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : MIRATransitionTiming.fullScreenClose)) {
            close()
          }
        }
      )
      .ignoresSafeArea()
    }
    .miraFullScreenOverlay(item: $editingMedia, background: .black) { item, closeEditor in
      MIRANativeMediaEditorView(media: item.media, mode: .story, onClose: closeEditor) { edited in
        Task { await submit(media: edited) }
      }
      .ignoresSafeArea()
    }
  }

  private func submit(media: MIRAPickedMedia) async {
    isPosting = true
    defer { isPosting = false }
    do {
      let uploaded = try await MIRAMediaUploadService(api: api).upload(media)
      let _: MIRAStatusPreview = try await api.post(
        "/statuses",
        body: CreateStatusBody(
          content: "",
          image: uploaded,
          backgroundColor: "#1B4332",
          textColor: "#FFFFFF",
          visibility: "public",
          editorMetadata: media.editorMetadata
        )
      )
      close()
    } catch {
      errorMessage = "Story could not be posted."
    }
  }

  private func presentStoryEditor(for media: MIRAPickedMedia) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      editingMedia = MIRAEditorPresentation(media: media)
    }
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
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

private final class LocalVideoPlayerUIView: UIView {
  override static var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspectFill
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private struct LocalAVPlayerLayerView: UIViewRepresentable {
  let player: AVPlayer?

  func makeUIView(context: Context) -> LocalVideoPlayerUIView {
    LocalVideoPlayerUIView()
  }

  func updateUIView(_ uiView: LocalVideoPlayerUIView, context: Context) {
    uiView.playerLayer.player = player
  }
}

private struct LocalVideoPreview: View {
  let media: MIRAPickedMedia
  @Binding var isPlaying: Bool
  @State private var player: AVPlayer?
  @State private var tempURL: URL?
  @State private var failed = false

  private var signature: String {
    "\(media.fileName)-\(media.data.count)"
  }

  var body: some View {
    ZStack {
      if let player {
        LocalAVPlayerLayerView(player: player)
      } else {
        Color.black.opacity(0.9)
        if failed {
          Image(systemName: "video.slash")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
        } else {
          ProgressView()
            .tint(.white)
        }
      }
    }
    .task(id: signature) {
      await preparePlayer()
    }
    .onChange(of: isPlaying) { _, playing in
      updatePlayback(playing)
    }
    .onDisappear {
      cleanup()
    }
  }

  private func preparePlayer() async {
    cleanup()
    failed = false
    let data = media.data
    let ext = URL(fileURLWithPath: media.fileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: media.fileName).pathExtension
    let preparedURL = await Task.detached(priority: .utility) { () -> URL? in
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-preview-\(UUID().uuidString).\(ext)")
      do {
        try data.write(to: url, options: .atomic)
        return url
      } catch {
        return nil
      }
    }.value

    guard let preparedURL else {
      failed = true
      return
    }

    tempURL = preparedURL
    let item = AVPlayerItem(url: preparedURL)
    let nextPlayer = AVPlayer(playerItem: item)
    nextPlayer.isMuted = true
    nextPlayer.actionAtItemEnd = .pause
    player = nextPlayer
    updatePlayback(isPlaying)
  }

  private func updatePlayback(_ playing: Bool) {
    guard let player else { return }
    if playing {
      player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
      player.play()
    } else {
      player.pause()
    }
  }

  private func cleanup() {
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    if let tempURL {
      try? FileManager.default.removeItem(at: tempURL)
    }
    tempURL = nil
  }
}

private struct LocalMediaThumb: View {
  let media: MIRAPickedMedia
  var width: CGFloat = 96
  var height: CGFloat = 96
  var cornerRadius: CGFloat = 18
  @State private var isVideoPlaying = false

  var body: some View {
    ZStack {
      if media.kind == .image, let image = UIImage(data: media.data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        LocalVideoPreview(media: media, isPlaying: $isVideoPlaying)
        if !isVideoPlaying {
          Circle()
            .fill(.black.opacity(0.44))
            .frame(width: min(58, min(width, height) * 0.54), height: min(58, min(width, height) * 0.54))
          Image(systemName: "play.fill")
            .font(.system(size: min(28, min(width, height) * 0.24), weight: .bold))
            .foregroundStyle(.white)
            .offset(x: 2)
        }
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture {
      guard media.kind == .video else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      withAnimation(.easeInOut(duration: 0.14)) {
        isVideoPlaying.toggle()
      }
    }
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
            let width = UIScreen.main.bounds.width - 32
            let height = min(width * (first.kind == .video ? 16.0 / 9.0 : 1.25), UIScreen.main.bounds.height * 0.74)
            LocalMediaThumb(media: first, width: width, height: height)
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
