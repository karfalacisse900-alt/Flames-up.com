import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ConversationNativeKind: Hashable {
  case direct(peerId: String)
  case group(groupId: String)
}

private enum ChatRoomPalette {
  static let background = MIRATheme.Color.surfaceSoft
  static let backgroundWash = MIRATheme.Color.surfaceSoft
  static let composer = MIRATheme.Color.surface
  static let input = MIRATheme.Color.surfaceRaised
  static let incomingBubble = MIRATheme.Color.surface
  static let outgoingBubble = MIRATheme.Color.forest
  static let outgoingSoft = MIRATheme.Color.forest.opacity(0.82)
  static let accent = MIRATheme.Color.forest
  static let hairline = MIRATheme.Color.hairline
  static let incomingStroke = Color.clear
  static let outgoingStroke = Color.clear
  static let incomingTimestamp = MIRATheme.Color.textSecondary
  static let outgoingTimestamp = MIRATheme.Color.onPrimary.opacity(0.8)
  static let messageShadow = Color.black.opacity(0.030)
}

@MainActor
final class ConversationNativeModel: ObservableObject {
  @Published var messages: [MIRAMessage] = []
  @Published var groupInfo: MIRAGroupInfo?
  @Published var presence: MIRAPresence?
  @Published var draft = ""
  @Published var isLoading = false
  @Published var isSyncing = false
  @Published var isLoadingOlder = false
  @Published var hasOlderMessages = false
  @Published var isSending = false
  @Published var isUploading = false
  @Published var errorMessage: String?

  let kind: ConversationNativeKind
  let api: MIRAAPIClient
  let currentUserId: String
  private let uploadService: MIRAMediaUploadService
  private let localStore = MIRAChatLocalStore.shared
  private var didBeginInitialLoad = false
  private var lastSyncedAt: String?
  private var lastServerSequence: Int?
  private var consecutiveSyncFailures = 0
  private var isRealtimeConnected = false
  private var lastRecentReconcile = Date.distantPast

  init(kind: ConversationNativeKind, api: MIRAAPIClient, currentUserId: String = "") {
    self.kind = kind
    self.api = api
    self.currentUserId = currentUserId
    self.uploadService = MIRAMediaUploadService(api: api)
  }

  var isGroup: Bool {
    if case .group = kind { return true }
    return false
  }

  var peerId: String? {
    if case let .direct(peerId) = kind { return peerId }
    return nil
  }

  func load() async {
    if didBeginInitialLoad {
      await syncNewMessages()
      return
    }
    didBeginInitialLoad = true
    await hydrateLocalMessages()
    if !messages.isEmpty {
      await refreshRecentMessages()
    }
    await syncNewMessages()
    if case let .direct(peerId) = kind {
      presence = try? await api.get("/messages/presence/\(peerId)")
    }
  }

  private func hydrateLocalMessages() async {
    guard messages.isEmpty else { return }
    if let snapshot = await localStore.loadThread(kind: kind, currentUserId: currentUserId, limit: 50) {
      messages = snapshot.messages
      lastSyncedAt = snapshot.lastSyncedAt ?? latestMessageCursor()
      lastServerSequence = snapshot.lastServerSequence
      hasOlderMessages = snapshot.hasOlderRemote
      prefetchMessageMedia(snapshot.messages)
      MIRAPerformanceTimeline.markOnce("chat_room_first_content", detail: "cache")
    }
  }

  private func syncNewMessages() async {
    guard !isSyncing else { return }
    isSyncing = true
    isLoading = messages.isEmpty
    defer {
      isLoading = false
      isSyncing = false
    }
    do {
      let rows: [MIRAMessage]
      let cursor = lastSyncedAt ?? latestMessageCursor()
      switch kind {
      case let .direct(peerId):
        rows = try await api.get(messagesPath("/messages/\(peerId)", after: cursor, limit: 50))
      case let .group(groupId):
        let response: MIRAGroupMessagesResponse = try await api.get(messagesPath("/group-chats/\(groupId)/messages", after: cursor, limit: 50))
        groupInfo = response.group
        rows = response.messages
      }
      if !rows.isEmpty || messages.isEmpty {
        messages = await localStore.merge(messages, with: rows)
        lastSyncedAt = latestMessageCursor() ?? lastSyncedAt
        lastServerSequence = messages.compactMap(\.serverSequence).max() ?? lastServerSequence
        if messages.count >= 50 { hasOlderMessages = true }
        prefetchMessageMedia(messages)
        await persistThread()
      }
      consecutiveSyncFailures = 0
      errorMessage = nil
    } catch {
      consecutiveSyncFailures = min(4, consecutiveSyncFailures + 1)
      if await clearIfAccessRevoked(error) { return }
      if messages.isEmpty {
        errorMessage = "Could not load this chat."
      }
    }
  }

  func pollMessagesWhileActive() async {
    let realtimeTask = Task { [weak self] in
      guard let self else { return }
      await MIRAChatRealtime.observe(
        kind: kind, userId: currentUserId, api: api,
        onChange: { [weak self] in await self?.syncNewMessages() },
        onConnectionChange: { [weak self] connected in self?.isRealtimeConnected = connected }
      )
    }
    defer {
      realtimeTask.cancel()
      isRealtimeConnected = false
    }
    while !Task.isCancelled {
      await syncNewMessages()
      if Date().timeIntervalSince(lastRecentReconcile) >= 45 {
        await refreshRecentMessages()
      }
      // A healthy socket still gets occasional reconciliation for removals,
      // changed permissions, and events missed while the app was suspended.
      let delay = isRealtimeConnected ? 45 : min(60, 5 * (1 << consecutiveSyncFailures))
      do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }
      catch { break }
    }
  }

  private func refreshRecentMessages() async {
    guard !isSyncing else { return }
    isSyncing = true
    lastRecentReconcile = Date()
    defer { isSyncing = false }
    do {
      let rows: [MIRAMessage]
      switch kind {
      case let .direct(peerId):
        rows = try await api.get(messagesPath("/messages/\(peerId)", limit: 50))
      case let .group(groupId):
        let response: MIRAGroupMessagesResponse = try await api.get(messagesPath("/group-chats/\(groupId)/messages", limit: 50))
        groupInfo = response.group
        rows = response.messages
      }
      messages = await localStore.reconcileRecent(messages, with: rows)
      lastSyncedAt = latestMessageCursor()
      lastServerSequence = messages.compactMap(\.serverSequence).max()
      hasOlderMessages = rows.count >= 50 || messages.filter { !$0.id.hasPrefix("local-") }.count > rows.count
      prefetchMessageMedia(rows)
      await persistThread()
    } catch {
      if await clearIfAccessRevoked(error) { return }
      // Keep the cached chat visible; foreground sync will retry next open/poll.
    }
  }

  private func clearIfAccessRevoked(_ error: Error) async -> Bool {
    let status: Int
    switch error {
    case MIRAAPIError.server(let code, _, _): status = code
    case MIRAAPIError.badStatus(let code): status = code
    default: return false
    }
    guard status == 403 || status == 404 else { return false }
    messages = []
    groupInfo = nil
    lastSyncedAt = nil
    lastServerSequence = nil
    hasOlderMessages = false
    await localStore.removeThread(kind: kind, currentUserId: currentUserId)
    errorMessage = "This conversation is no longer available."
    return true
  }

  func loadOlderMessagesIfNeeded() async {
    guard hasOlderMessages, !isLoadingOlder, let before = messages.first?.createdAt else { return }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      let rows: [MIRAMessage]
      switch kind {
      case let .direct(peerId):
        rows = try await api.get(messagesPath("/messages/\(peerId)", before: before, limit: 50))
      case let .group(groupId):
        let response: MIRAGroupMessagesResponse = try await api.get(messagesPath("/group-chats/\(groupId)/messages", before: before, limit: 50))
        groupInfo = response.group
        rows = response.messages
      }
      guard !rows.isEmpty else {
        hasOlderMessages = false
        await persistThread()
        return
      }
      messages = await localStore.merge(rows, with: messages)
      hasOlderMessages = rows.count >= 50
      prefetchMessageMedia(rows)
      await persistThread()
    } catch {
      errorMessage = messages.isEmpty ? "Could not load earlier messages." : nil
    }
  }

  func pollPresence() async {
    guard case let .direct(peerId) = kind else { return }
    while !Task.isCancelled {
      presence = try? await api.get("/messages/presence/\(peerId)")
      try? await Task.sleep(nanoseconds: 8_000_000_000)
    }
  }

  func sendSharedPost(_ post: MIRAPost) async {
    _ = await send(content: MIRAProductionBackend.siteURL("post/\(post.id)").absoluteString, mediaUrl: nil, mediaType: nil)
  }

  func sendText() async {
    let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !isSending else { return }
    draft = ""
    updateTyping(false)
    if !(await send(content: clean, mediaUrl: nil, mediaType: nil)) {
      draft = clean
    }
  }

  func sendPickedMedia(data: Data, contentTypes: [UTType]) async {
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    let (kind, fileName, mimeType) = pickedMediaKind(from: contentTypes, fallbackData: data)
    let localURL = await localStore.storeOutgoingMedia(data: data, fileName: fileName)
    let localId = appendLocalOutgoingMessage(
      content: "",
      mediaUrl: localURL?.absoluteString,
      mediaType: kind == .video ? "video" : "image",
      uploadStatus: "uploading"
    )
    do {
      let url = try await uploadService.upload(MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType))
      await send(content: "", mediaUrl: url, mediaType: kind == .video ? "video" : "image", replacingLocalId: localId)
    } catch {
      updateLocalMessage(localId, status: "failed", uploadStatus: "failed")
      errorMessage = "Could not send this media."
    }
  }

  func updateTyping(_ typing: Bool) {
    guard case let .direct(peerId) = kind else { return }
    Task {
      let _: EmptyResponse? = try? await api.post("/messages/typing", body: TypingBody(peerId: peerId, isTyping: typing))
    }
  }

  func deleteForMe(_ message: MIRAMessage) {
    messages.removeAll { $0.id == message.id }
    Task { await persistThread() }
  }

  func removeMessages(byUserId userId: String) {
    messages.removeAll { $0.senderId == userId || $0.receiverId == userId }
    Task { await persistThread() }
  }

  func blockUser(_ userId: String) async {
    guard !userId.isEmpty, userId != currentUserId else { return }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(userId)/block", body: EmptyBody())
      removeMessages(byUserId: userId)
      errorMessage = nil
    } catch {
      errorMessage = "Could not block this user. Try again in a moment."
    }
  }

  func blockPeer() async -> Bool {
    guard let peerId, !peerId.isEmpty else { return false }
    do {
      let _: EmptyResponse? = try await api.post("/users/\(peerId)/block", body: EmptyBody())
      messages = []
      await persistThread()
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not block this user. Try again in a moment."
      return false
    }
  }

  @discardableResult
  private func send(content: String, mediaUrl: String?, mediaType: String?, replacingLocalId: String? = nil) async -> Bool {
    guard !isSending else { return false }
    isSending = true
    let localId = replacingLocalId ?? appendLocalOutgoingMessage(content: content, mediaUrl: mediaUrl, mediaType: mediaType, uploadStatus: mediaUrl == nil ? nil : "uploaded")
    defer { isSending = false }
    do {
      let sent: MIRAMessage
      switch kind {
      case let .direct(peerId):
        sent = try await api.post(
          "/messages",
          body: SendMessageBody(receiverId: peerId, content: content, mediaUrl: mediaUrl, mediaType: mediaType)
        )
      case let .group(groupId):
        sent = try await api.post(
          "/group-chats/\(groupId)/messages",
          body: GroupMessageBody(content: content, mediaUrl: mediaUrl, mediaType: mediaType)
        )
      }
      replaceLocalMessage(localId, with: sent.updating(status: "sent", uploadStatus: "uploaded"))
      errorMessage = nil
      return true
    } catch {
      updateLocalMessage(localId, status: "failed", uploadStatus: mediaUrl == nil ? nil : "failed")
      errorMessage = "Could not send this message."
      return false
    }
  }

  func retry(_ message: MIRAMessage) async {
    guard message.status?.lowercased() == "failed" else { return }
    messages.removeAll { $0.id == message.id }
    await persistThread()
    let mediaUrl = message.mediaUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let mediaUrl,
       let url = URL(string: mediaUrl),
       url.isFileURL,
       let data = await loadLocalRetryData(from: url) {
      let type = message.mediaType?.lowercased() == "video" ? UTType.movie : UTType.image
      await sendPickedMedia(data: data, contentTypes: [type])
      return
    }
    _ = await send(
      content: message.content ?? "",
      mediaUrl: (mediaUrl?.isEmpty == false && URL(string: mediaUrl ?? "")?.isFileURL != true) ? mediaUrl : nil,
      mediaType: message.mediaType
    )
  }

  private func prefetchMessageMedia(_ rows: [MIRAMessage]) {
    guard shouldAutoDownloadChatImagePreviews else { return }
    let avatarURLs = rows.suffix(40)
      .compactMap { $0.profileImage?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let imageURLs = rows.suffix(30).flatMap { message -> [String] in
      let mediaType = message.mediaType?.lowercased()
      guard mediaType == "image" || mediaType == "video" else { return [] }
      return [message.thumbnailUrl, message.posterUrl, message.mediaType?.lowercased() == "image" ? message.mediaUrl : nil]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.isVideoURL }
    }
    let urls = avatarURLs + imageURLs
    guard !urls.isEmpty else { return }
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 760, limit: 18)
    }
  }

  private func appendLocalOutgoingMessage(content: String, mediaUrl: String?, mediaType: String?, uploadStatus: String?) -> String {
    let id = "local-\(UUID().uuidString)"
    let timestamp = ISO8601DateFormatter.miraConversation.string(from: Date())
    let message = MIRAMessage(
      id: id,
      groupId: groupId,
      senderId: currentUserId,
      receiverId: peerId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      createdAt: timestamp,
      updatedAt: timestamp,
      status: "sending",
      localCreatedAt: timestamp,
      uploadStatus: uploadStatus
    )
    messages.append(message)
    Task { await persistThread() }
    return id
  }

  private func replaceLocalMessage(_ localId: String, with sent: MIRAMessage) {
    if let index = messages.firstIndex(where: { $0.id == localId }) {
      let localCreatedAt = messages[index].localCreatedAt ?? messages[index].createdAt
      messages[index] = sent.updating(localCreatedAt: localCreatedAt)
    } else {
      messages.append(sent)
    }
    messages = messages.sortedForConversation()
    lastSyncedAt = latestMessageCursor() ?? lastSyncedAt
    lastServerSequence = messages.compactMap(\.serverSequence).max() ?? lastServerSequence
    Task { await persistThread() }
  }

  private func updateLocalMessage(_ localId: String, status: String, uploadStatus: String?) {
    guard let index = messages.firstIndex(where: { $0.id == localId }) else { return }
    messages[index] = messages[index].updating(status: status, uploadStatus: uploadStatus)
    Task { await persistThread() }
  }

  private func persistThread() async {
    await localStore.saveThread(
      kind: kind,
      currentUserId: currentUserId,
      messages: messages,
      lastSyncedAt: lastSyncedAt ?? latestMessageCursor(),
      lastServerSequence: lastServerSequence,
      hasOlderRemote: hasOlderMessages
    )
  }

  private func messagesPath(_ base: String, after: String? = nil, before: String? = nil, limit: Int) -> String {
    var components = URLComponents()
    var items = [URLQueryItem(name: "limit", value: "\(limit)")]
    if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
    if let before, !before.isEmpty { items.append(URLQueryItem(name: "before", value: before)) }
    components.queryItems = items
    return "\(base)?\(components.percentEncodedQuery ?? "limit=\(limit)")"
  }

  private func latestMessageCursor() -> String? {
    messages
      .filter { !$0.id.hasPrefix("local-") && ($0.status ?? "sent") != "failed" }
      .compactMap(\.createdAt)
      .max { lhs, rhs in conversationDateValue(lhs) < conversationDateValue(rhs) }
  }

  private var groupId: String? {
    if case let .group(groupId) = kind { return groupId }
    return nil
  }

  private var shouldAutoDownloadChatImagePreviews: Bool {
    let key = "mira.chat.autodownload.images.wifi"
    if UserDefaults.standard.object(forKey: key) == nil { return true }
    return UserDefaults.standard.bool(forKey: key)
  }

  private nonisolated func loadLocalRetryData(from url: URL) async -> Data? {
    await Task.detached(priority: .utility) {
      try? Data(contentsOf: url)
    }.value
  }
}

public struct ConversationNativeView: View {
  @StateObject private var model: ConversationNativeModel
  @State private var pickerItem: PhotosPickerItem?
  @State private var showAttachmentTray = false
  @State private var showGroupMembers = false
  @State private var showSharePostPicker = false
  @State private var showPinnedMessage = false
  @State private var showActivityDetails = false
  @State private var showProfileOptions = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportMessage: MIRAMessage?
  @State private var isReportSheetPresented = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let title: String
  private let initialAvatarURL: String?

  public init(peerId: String, title: String, api: MIRAAPIClient, currentUserId: String = "", initialAvatarURL: String? = nil) {
    self.title = title
    self.initialAvatarURL = initialAvatarURL
    _model = StateObject(wrappedValue: ConversationNativeModel(kind: .direct(peerId: peerId), api: api, currentUserId: currentUserId))
  }

  public init(groupId: String, title: String, api: MIRAAPIClient, currentUserId: String = "", initialAvatarURL: String? = nil) {
    self.title = title
    self.initialAvatarURL = initialAvatarURL
    _model = StateObject(wrappedValue: ConversationNativeModel(kind: .group(groupId: groupId), api: api, currentUserId: currentUserId))
  }

  init(title: String, model: ConversationNativeModel, initialAvatarURL: String? = nil) {
    self.title = title
    self.initialAvatarURL = initialAvatarURL
    _model = StateObject(wrappedValue: model)
  }

  public var body: some View {
    VStack(spacing: 0) {
      if model.isGroup {
        clubContextHeader
      } else {
        chatHeader
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 12) {
            if model.isLoading && model.messages.isEmpty {
              chatSkeleton
            } else if model.messages.isEmpty {
              MIRAEmptyState(title: "Start the chat", message: "Send a message when you are ready.", systemImage: "message")
            } else {
              if model.hasOlderMessages {
                loadEarlierControl
              }
              ForEach(model.messages) { message in
                messageBubble(message)
                  .id(message.id)
              }
            }
          }
          .padding(.horizontal, 14)
          .padding(.top, 14)
          .padding(.bottom, 16)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .miraScrollFeel(.chat)
        .onChange(of: model.messages.map(\.id)) { oldIDs, newIDs in
          guard let last = newIDs.last else { return }
          if oldIDs.isEmpty {
            DispatchQueue.main.async {
              var transaction = Transaction()
              transaction.disablesAnimations = true
              withTransaction(transaction) {
                proxy.scrollTo(last, anchor: .bottom)
              }
            }
            return
          }
          let shouldStayPinnedToBottom = oldIDs.isEmpty || oldIDs.last != last
          guard shouldStayPinnedToBottom else { return }
          DispatchQueue.main.async {
            withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
              proxy.scrollTo(last, anchor: .bottom)
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      composerContainer
    }
    .background(model.isGroup ? MIRATheme.Color.surface : ChatRoomPalette.background)
    .miraScreenEnter(.push)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .task { await model.load() }
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      await model.pollMessagesWhileActive()
    }
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      await model.pollPresence()
    }
    .miraActionModal(isPresented: $showProfileOptions) { dismissOptions in
      ChatProfileOptionsSheet(
        isGroup: model.isGroup,
        onReport: {
          dismissOptions()
          DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.actionModalClose) {
            presentProfileReport()
          }
        },
        onBlock: {
          dismissOptions()
          Task { _ = await model.blockPeer() }
        }
      )
    }
    .miraBottomSheet(
      isPresented: $isReportSheetPresented,
      preferredHeightFraction: 0.78,
      maxHeight: 700,
      onDismissed: {
        reportTarget = nil
        reportMessage = nil
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
    .sheet(isPresented: $showSharePostPicker) {
      ClubPostShareSheet(api: model.api, userId: model.currentUserId) { post in
        showSharePostPicker = false
        Task { await model.sendSharedPost(post) }
      }
    }
    .sheet(isPresented: $showGroupMembers) {
      ClubMembersSheet(members: model.groupInfo?.members ?? [], api: model.api)
    }
    .alert("Pinned message", isPresented: $showPinnedMessage) {
      Button("Done", role: .cancel) {}
    } message: {
      Text(model.groupInfo?.pinnedMessage ?? "")
    }
    .sheet(isPresented: $showActivityDetails) {
      if let activity = model.groupInfo?.activity {
        NavigationStack {
          VStack(alignment: .leading, spacing: 12) {
            Text(activity.title).font(.title2.bold())
            if let subtitle = activity.subtitle { Text(subtitle) }
            if let detail = activity.detail { Text(detail).foregroundStyle(.secondary) }
            Spacer()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(24)
          .navigationTitle("Club activity")
          .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
      }
    }
    .onChange(of: pickerItem) { item in
      guard let item else { return }
      Task {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await model.sendPickedMedia(data: data, contentTypes: item.supportedContentTypes)
      }
    }
  }

  private var clubContextHeader: some View {
    VStack(spacing: 0) {
      ClubChatHeader(title: title, info: model.groupInfo, onBack: {
        CaptroHaptics.light()
        dismiss()
      }, onMore: {
        CaptroHaptics.light()
        showProfileOptions = true
      })
      if let info = model.groupInfo, !(info.members ?? []).isEmpty {
        ClubMemberAvatarRow(info: info) { showGroupMembers = true }
      }
      if let activity = model.groupInfo?.activity {
        ActiveClubActivityCard(activity: activity) { showActivityDetails = true }
          .padding(.vertical, 8)
      }
      if let pinned = model.groupInfo?.pinnedMessage, !pinned.isEmpty {
        ClubPinnedMessageRow(message: pinned) { showPinnedMessage = true }
      }
      Rectangle()
        .fill(MIRATheme.Color.hairline)
        .frame(height: 0.5)
    }
    .background(MIRATheme.Color.surface)
  }

  private var chatHeader: some View {
    HStack(spacing: 10) {
      Button {
        CaptroHaptics.light()
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel("Back")

      RemoteAvatar(url: peerAvatarURL, size: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(statusText)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        CaptroHaptics.light()
        DispatchQueue.main.async {
          withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
            showProfileOptions = true
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 19, weight: .heavy))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
          .background(Color.black, in: Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1))
          .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
          .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
      .accessibilityLabel("Chat options")
      .zIndex(2)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(ChatRoomPalette.composer)
    .overlay(alignment: .bottom) {
      Rectangle().fill(ChatRoomPalette.hairline).frame(height: 0.5)
    }
  }

  private var statusText: String {
    if model.isGroup { return "group chat" }
    if model.presence?.isTyping == true { return "typing..." }
    if model.presence?.isOnline == true { return "online" }
    return "chat"
  }

  private func presentProfileReport() {
    guard let peerId = model.peerId, !peerId.isEmpty else { return }
    CaptroHaptics.medium()
    reportMessage = nil
    reportTarget = MIRAReportTarget(
      targetType: "profile",
      targetId: peerId,
      ownerUserId: peerId,
      title: "Report profile",
      subtitle: title
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  private func presentReport(for message: MIRAMessage) {
    CaptroHaptics.medium()
    reportMessage = message
    reportTarget = MIRAReportTarget(
      targetType: "message",
      targetId: message.id,
      ownerUserId: message.senderId,
      title: "Report message",
      subtitle: message.content?.isEmpty == false ? message.content : "Media message"
    )
    DispatchQueue.main.async {
      withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
        isReportSheetPresented = true
      }
    }
  }

  private func handleReportResult(_ result: MIRAReportResult) {
    if result.blocked, let peerId = model.peerId {
      model.removeMessages(byUserId: peerId)
    } else if result.hidden, let reportMessage {
      model.deleteForMe(reportMessage)
    }
  }

  private var peerAvatarURL: String? {
    let messageAvatar = model.messages
      .first { !isOutgoing($0) }?
      .profileImage?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let messageAvatar, !messageAvatar.isEmpty {
      return messageAvatar
    }
    let initial = initialAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return initial.isEmpty ? nil : initial
  }

  private var chatSkeleton: some View {
    VStack(spacing: MIRATheme.Space.md) {
      ForEach(0..<5, id: \.self) { index in
        HStack {
          if index.isMultiple(of: 2) { Spacer(minLength: 72) }
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(MIRATheme.Color.surfaceSoft)
            .frame(width: CGFloat(index.isMultiple(of: 2) ? 190 : 245), height: 42)
          if !index.isMultiple(of: 2) { Spacer(minLength: 72) }
        }
      }
    }
    .redacted(reason: .placeholder)
    .padding(.top, MIRATheme.Space.xl)
  }

  @ViewBuilder
  private func messageBubble(_ message: MIRAMessage) -> some View {
    if model.isGroup {
      clubMessageBubble(message)
    } else {
      directMessageBubble(message)
    }
  }

  private func clubMessageBubble(_ message: MIRAMessage) -> some View {
    let outgoing = isOutgoing(message)
    let sender = model.groupInfo?.members?.first { $0.id == message.senderId }
    return HStack(alignment: .bottom, spacing: 10) {
      if outgoing { Spacer(minLength: 46) }
      if !outgoing {
        NavigationLink(destination: UserProfileNativeView(userId: message.senderId ?? "", api: model.api)) {
          RemoteAvatar(url: message.profileImage ?? sender?.profileImage, size: 32)
        }
        .buttonStyle(.plain)
        .disabled(message.senderId == nil)
      }
      VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
        HStack(spacing: 6) {
          Text(outgoing ? "You" : (message.fullName ?? message.username ?? sender?.displayName ?? "Member"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          if let role = sender?.role, role == "owner" || role == "admin" {
            Text(role == "owner" ? "HOST" : "MOD")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
          Text(clubMessageTime(message.createdAt))
            .font(.system(size: 11))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        if let link = clubMessageLinkURL(message.content) {
          ClubChatLinkMessage(url: link, api: model.api)
        } else {
          MessageBubbleContent(
            message: message,
            outgoing: outgoing,
            maxWidth: bubbleMaxWidth,
            timestamp: nil,
            editorial: true
          )
        }
        if message.status == "failed" {
          Text("Failed to send · long press to retry")
            .font(.system(size: 11))
            .foregroundStyle(.red)
        }
      }
      .frame(maxWidth: bubbleMaxWidth, alignment: outgoing ? .trailing : .leading)
      if !outgoing { Spacer(minLength: 46) }
    }
    .contextMenu {
      if let content = message.content, !content.isEmpty {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = content }
      }
      if outgoing && message.status?.lowercased() == "failed" {
        Button("Retry", systemImage: "arrow.clockwise") { Task { await model.retry(message) } }
      }
      if !outgoing {
        Button("Report", systemImage: "flag") { presentReport(for: message) }
        if let senderId = message.senderId {
          Button(role: .destructive) {
            Task { await model.blockUser(senderId) }
          } label: {
            Label("Block user", systemImage: "hand.raised")
          }
        }
      }
      Button("Hide for me", systemImage: "eye.slash") { model.deleteForMe(message) }
    }
  }

  private func clubMessageLinkURL(_ content: String?) -> URL? {
    guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.contains(where: \.isWhitespace),
          let url = URL(string: content),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http",
          url.host != nil else { return nil }
    return url
  }

  private func clubMessageTime(_ value: String?) -> String {
    guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "" }
    return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
  }

  private func directMessageBubble(_ message: MIRAMessage) -> some View {
    let outgoing = isOutgoing(message)
    return HStack(alignment: .bottom, spacing: 0) {
      if outgoing { Spacer(minLength: 68) }
      VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
        MessageBubbleContent(
          message: message,
          outgoing: outgoing,
          maxWidth: bubbleMaxWidth,
          timestamp: statusText(for: message, outgoing: outgoing),
          editorial: false
        )
      }
      .frame(maxWidth: bubbleMaxWidth, alignment: outgoing ? .trailing : .leading)
      if !outgoing { Spacer(minLength: 68) }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .contextMenu {
      if outgoing, message.status?.lowercased() == "failed" {
        Button { Task { await model.retry(message) } } label: {
          Label("Retry", systemImage: "arrow.clockwise")
        }
      }
      if !outgoing {
        Button(role: .destructive) { presentReport(for: message) } label: {
          Label("Report message", systemImage: "flag")
        }
        Button(role: .destructive) { Task { _ = await model.blockPeer() } } label: {
          Label("Block user", systemImage: "hand.raised")
        }
      }
      Button(role: .destructive) { model.deleteForMe(message) } label: {
        Label("Delete for me", systemImage: "trash")
      }
    }
  }
  private var bubbleMaxWidth: CGFloat {
    min(UIScreen.main.bounds.width * 0.72, 296)
  }

  private func conversationMessageAge(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return "" }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 7 { return "\(days)d" }
    return "\(max(1, days / 7))w"
  }

  private func isOutgoing(_ message: MIRAMessage) -> Bool {
    if !model.currentUserId.isEmpty {
      return message.senderId == model.currentUserId
    }
    if let peerId = model.peerId {
      return message.senderId != peerId
    }
    return false
  }

  private var loadEarlierControl: some View {
    Button {
      Task { await model.loadOlderMessagesIfNeeded() }
    } label: {
      HStack(spacing: 8) {
        if model.isLoadingOlder {
          ProgressView()
            .scaleEffect(0.75)
        }
        Text(model.isLoadingOlder ? "Loading earlier messages..." : "Load earlier messages")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(MIRATheme.Color.textSecondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(model.isLoadingOlder)
    .onAppear {
      guard model.messages.count >= 35 else { return }
      Task { await model.loadOlderMessagesIfNeeded() }
    }
  }

  private func statusText(for message: MIRAMessage, outgoing: Bool) -> String? {
    guard outgoing else { return nil }
    switch message.status?.lowercased() {
    case "sending":
      return message.uploadStatus == "uploading" ? "uploading" : "sending"
    case "failed":
      return "failed - tap to retry"
    case "delivered":
      return "delivered"
    case "read":
      return "read"
    default:
      return nil
    }
  }

  private var composerContainer: some View {
    VStack(spacing: 0) {
      if let error = model.errorMessage {
        Text(error)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.xs)
          .padding(.bottom, MIRATheme.Space.xs)
          .background(ChatRoomPalette.composer)
      }
      composer
    }
  }

  private var composer: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      if model.isUploading {
        ProgressView("Sending...")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MIRATheme.Space.md)
      }

      if showAttachmentTray {
        attachmentTray
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      HStack(spacing: 10) {
        Button {
          CaptroHaptics.light()
          withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
            showAttachmentTray.toggle()
          }
        } label: {
          Image(systemName: showAttachmentTray ? "xmark" : "plus")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
            .background(ChatRoomPalette.input)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel(showAttachmentTray ? "Close attachments" : "Add attachment")

        TextField(model.isGroup ? "Message the club..." : "Message", text: $model.draft, axis: .vertical)
          .lineLimit(1...5)
          .font(.body)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.vertical, 8)
          .onChange(of: model.draft) { value in
            model.updateTyping(!value.isEmpty)
          }

        composerPrimaryButton
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
    }
    .background(ChatRoomPalette.composer)
    .shadow(color: model.isGroup ? .clear : .black.opacity(0.035), radius: model.isGroup ? 0 : 12, x: 0, y: model.isGroup ? 0 : -3)
    .overlay(alignment: .top) {
      Rectangle().fill(ChatRoomPalette.hairline).frame(height: 0.5)
    }
    .animation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion), value: showAttachmentTray)
  }

  private var attachmentTray: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
          trayButton("photo.on.rectangle", "Media")
        }
        .disabled(model.isUploading)
        if model.isGroup {
          Button {
            showAttachmentTray = false
            showSharePostPicker = true
          } label: {
            trayButton("square.on.square", "Captro post")
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private var composerPrimaryButton: some View {
    let hasDraft = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return Button {
      CaptroHaptics.light()
      Task {
        if hasDraft {
          await model.sendText()
        }
      }
    } label: {
      Image(systemName: "arrow.up")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(MIRATheme.Color.onPrimary)
        .frame(width: 44, height: 44)
        .background(hasDraft ? (model.isGroup ? MIRATheme.Color.textPrimary : ChatRoomPalette.accent) : MIRATheme.Color.textMuted.opacity(0.3))
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
    .disabled(!hasDraft || model.isSending)
    .accessibilityLabel(model.isSending ? "Sending message" : "Send message")
  }

  private func trayButton(_ systemImage: String, _ title: String, tint: Color = MIRATheme.Color.textMuted) -> some View {
    VStack(spacing: 4) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
      Text(title)
        .font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(tint)
    .frame(width: 58, height: 50)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(ChatRoomPalette.hairline, lineWidth: 1)
    }
  }

}

private struct ChatProfileOptionsSheet: View {
  let isGroup: Bool
  let onReport: () -> Void
  let onBlock: () -> Void

  var body: some View {
    MIRAActionModalCard {
      if !isGroup {
        MIRAActionModalButton(
          title: "Block",
          systemImage: "nosign",
          isDestructive: true,
          staggerIndex: 0,
          action: onBlock
        )

        MIRAActionModalButton(
          title: "Report",
          systemImage: "exclamationmark.triangle",
          staggerIndex: 1,
          action: onReport
        )
      } else {
        MIRAActionModalPillLabel(
          title: "Group chat",
          systemImage: "person.3.fill"
        )
          .opacity(0.72)
      }
    }
  }
}

private struct ChatProfileOptionRow: View {
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
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .padding(.horizontal, MIRATheme.Space.lg)
    .frame(minHeight: 58)
    .contentShape(Rectangle())
  }
}

private struct MessageBubbleContent: View {
  let message: MIRAMessage
  let outgoing: Bool
  let maxWidth: CGFloat
  let timestamp: String?
  let editorial: Bool
  @State private var isVideoPlaying = false

  var body: some View {
    VStack(alignment: outgoing ? .trailing : .leading, spacing: hasLargeMedia ? 6 : 5) {
      if let mediaUrl = message.mediaUrl, !mediaUrl.isEmpty {
        mediaContent(url: mediaUrl)
      }
      if shouldShowTextContent, let content = normalizedText {
        bubbleText(content)
      }
      if let timestamp, !timestamp.isEmpty {
        Text(timestamp)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(outgoing ? ChatRoomPalette.outgoingTimestamp : ChatRoomPalette.incomingTimestamp)
          .lineLimit(1)
          .padding(.top, hasLargeMedia ? 0 : 1)
      }
    }
    .padding(.leading, bubbleLeadingPadding)
    .padding(.trailing, bubbleTrailingPadding)
    .padding(.vertical, bubbleVerticalPadding)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: bubbleFrameMaxWidth, alignment: outgoing ? .trailing : .leading)
    .background {
      RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous)
        .fill(bubbleFill)
    }
    .overlay {
      RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous)
        .stroke(outgoing ? ChatRoomPalette.outgoingStroke : ChatRoomPalette.incomingStroke, lineWidth: 1)
    }
    .shadow(color: editorial ? .clear : ChatRoomPalette.messageShadow, radius: editorial ? 0 : 8, x: 0, y: editorial ? 0 : 4)
  }

  private var hasLargeMedia: Bool {
    guard let mediaType = message.mediaType?.lowercased() else { return false }
    return mediaType == "image" || mediaType == "video"
  }

  private var hasAnyMedia: Bool {
    guard let mediaUrl = message.mediaUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    return !mediaUrl.isEmpty
  }

  private var normalizedText: String? {
    if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
      return content
    }
    return nil
  }

  private var bubbleFill: Color {
    editorial ? (outgoing ? Color(red: 0.94, green: 0.95, blue: 0.94) : MIRATheme.Color.surfaceSoft) : (outgoing ? ChatRoomPalette.outgoingBubble : ChatRoomPalette.incomingBubble)
  }

  private var bubbleTextColor: Color {
    editorial ? MIRATheme.Color.textPrimary : (outgoing ? MIRATheme.Color.onPrimary : MIRATheme.Color.textPrimary)
  }

  private var bubbleRadius: CGFloat {
    editorial ? 12 : (hasLargeMedia ? 18 : 22)
  }

  private var bubbleVerticalPadding: CGFloat {
    return hasLargeMedia ? 6 : 12
  }

  private var textMaxWidth: CGFloat {
    max(96, maxWidth - bubbleLeadingPadding - bubbleTrailingPadding)
  }

  private var bubbleFrameMaxWidth: CGFloat? {
    if isCompactTextOnly { return nil }
    return maxWidth
  }

  private var bubbleLeadingPadding: CGFloat {
    if hasLargeMedia { return outgoing ? 10 : 14 }
    return 18
  }

  private var bubbleTrailingPadding: CGFloat {
    if hasLargeMedia { return outgoing ? 14 : 10 }
    return 18
  }

  private var shouldShowTextContent: Bool {
    true
  }

  private var isCompactTextOnly: Bool {
    guard !hasAnyMedia, let content = normalizedText else { return false }
    return shouldUseCompactTextLayout(content)
  }

  private func shouldUseCompactTextLayout(_ content: String) -> Bool {
    let longestWord = content.split(separator: " ").map(\.count).max() ?? content.count
    return content.count <= 36 && longestWord <= 18 && !content.contains("\n")
  }

  @ViewBuilder
  private func bubbleText(_ content: String) -> some View {
    if shouldUseCompactTextLayout(content) {
      Text(content)
        .font(.body)
        .foregroundStyle(bubbleTextColor)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: textMaxWidth, alignment: outgoing ? .trailing : .leading)
        .multilineTextAlignment(outgoing ? .trailing : .leading)
    } else {
      Text(content)
        .font(.body)
        .foregroundStyle(bubbleTextColor)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(outgoing ? .trailing : .leading)
        .frame(maxWidth: textMaxWidth, alignment: outgoing ? .trailing : .leading)
    }
  }

  @ViewBuilder
  private func mediaContent(url: String) -> some View {
    let type = message.mediaType?.lowercased() ?? ""
    let mediaWidth = min(maxWidth, 260)
    let isVideo = type == "video" || url.isVideoURL
    if type == "file" {
      fileCard
    } else if type == "voice" || type == "audio" {
      EmptyView()
    } else {
      ZStack {
        RemoteMediaView(
          url: url,
          isVideo: isVideo,
          placeholderURL: isVideo ? (message.posterUrl ?? message.thumbnailUrl) : (message.thumbnailUrl ?? message.posterUrl),
          shouldPlay: isVideo && isVideoPlaying,
          maxPixelSize: 900,
          showsVideoPlaceholderIcon: true,
          placeholderColor: ChatRoomPalette.backgroundWash
        )
        .allowsHitTesting(false)

        if isVideo && !isVideoPlaying {
          Image(systemName: "play.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.48), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .allowsHitTesting(false)
        }
      }
        .frame(width: mediaWidth, height: isVideo ? mediaWidth * 1.22 : mediaWidth * 0.86)
        .background(ChatRoomPalette.backgroundWash)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
          guard isVideo else { return }
          toggleVideoPlayback()
        }
        .accessibilityLabel(isVideo ? (isVideoPlaying ? "Pause video message" : "Play video message") : "Image message")
        .onChange(of: url) { _, _ in
          isVideoPlaying = false
        }
        .onDisappear {
          isVideoPlaying = false
        }
    }
  }

  private func toggleVideoPlayback() {
    CaptroHaptics.light()
    MIRAApplePerformanceLogger.event(isVideoPlaying ? "chat_video_pause" : "chat_video_prepare")
    withAnimation(CaptroMotion.smallMenuAnimation(reduceMotion: false)) {
      isVideoPlaying.toggle()
    }
  }

  private var fileCard: some View {
    HStack(spacing: 10) {
      Image(systemName: "doc.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(outgoing ? .white : .black)
        .frame(width: 34, height: 34)
        .background((outgoing ? MIRATheme.Color.onPrimary : MIRATheme.Color.textPrimary).opacity(0.12))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(message.fileName?.isEmpty == false ? message.fileName! : "File")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(outgoing ? .white : .black)
          .lineLimit(1)
        if let fileSize = message.fileSize, fileSize > 0 {
          Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(outgoing ? ChatRoomPalette.outgoingTimestamp : MIRATheme.Color.textSecondary)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

private extension Array where Element == MIRAMessage {
  func sortedForConversation() -> [MIRAMessage] {
    sorted { lhs, rhs in
      if let lhsSequence = lhs.serverSequence, let rhsSequence = rhs.serverSequence, lhsSequence != rhsSequence {
        return lhsSequence < rhsSequence
      }
      let left = conversationSortDate(lhs)
      let right = conversationSortDate(rhs)
      if left == right {
        return lhs.id < rhs.id
      }
      return left < right
    }
  }
}

private func conversationSortDate(_ message: MIRAMessage) -> Date {
  let status = message.status?.lowercased() ?? ""
  let shouldUseLocalDate = message.id.hasPrefix("local-") || status == "sending" || status == "failed"
  if shouldUseLocalDate, let localCreatedAt = message.localCreatedAt {
    return conversationDateValue(localCreatedAt)
  }
  if let createdAt = message.createdAt {
    return conversationDateValue(createdAt)
  }
  if let localCreatedAt = message.localCreatedAt {
    return conversationDateValue(localCreatedAt)
  }
  return .distantPast
}

private func conversationDateValue(_ value: String) -> Date {
  if let date = ISO8601DateFormatter.miraConversation.date(from: value) { return date }
  if let date = ISO8601DateFormatter.miraConversationPlain.date(from: value) { return date }
  return .distantPast
}

private extension ISO8601DateFormatter {
  static let miraConversation: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let miraConversationPlain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
