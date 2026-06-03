import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ConversationNativeKind: Hashable {
  case direct(peerId: String)
  case group(groupId: String)
}

private enum ChatRoomPalette {
  static let background = Color(red: 0.944, green: 0.944, blue: 0.944)
  static let backgroundWash = Color(red: 0.944, green: 0.944, blue: 0.944)
  static let composer = Color.white
  static let input = Color(red: 0.910, green: 0.910, blue: 0.910)
  static let incomingBubble = Color.white
  static let outgoingBubble = Color.black
  static let outgoingSoft = Color.black.opacity(0.82)
  static let accent = Color.black
  static let hairline = Color.black.opacity(0.075)
  static let incomingStroke = Color.clear
  static let outgoingStroke = Color.clear
  static let incomingTimestamp = Color(red: 0.520, green: 0.520, blue: 0.520)
  static let outgoingTimestamp = Color.white.opacity(0.72)
  static let messageShadow = Color.black.opacity(0.030)
}

@MainActor
final class ConversationNativeModel: ObservableObject {
  @Published var messages: [MIRAMessage] = []
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
      errorMessage = nil
    } catch {
      if messages.isEmpty {
        errorMessage = "Could not load this chat."
      }
    }
  }

  private func refreshRecentMessages() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      let rows: [MIRAMessage]
      switch kind {
      case let .direct(peerId):
        rows = try await api.get(messagesPath("/messages/\(peerId)", limit: 50))
      case let .group(groupId):
        let response: MIRAGroupMessagesResponse = try await api.get(messagesPath("/group-chats/\(groupId)/messages", limit: 50))
        rows = response.messages
      }
      guard !rows.isEmpty else { return }
      messages = await localStore.merge(messages, with: rows)
      lastSyncedAt = latestMessageCursor() ?? lastSyncedAt
      lastServerSequence = messages.compactMap(\.serverSequence).max() ?? lastServerSequence
      prefetchMessageMedia(rows)
      await persistThread()
    } catch {
      // Keep the cached chat visible; foreground sync will retry next open/poll.
    }
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
  @State private var showProfileOptions = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var reportMessage: MIRAMessage?
  @State private var isReportSheetPresented = false
  @Environment(\.dismiss) private var dismiss
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
      chatHeader
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
          .padding(.bottom, 120)
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
    .background(ChatRoomPalette.background)
    .miraScreenEnter(.push)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .task { await model.load() }
    .task { await model.pollPresence() }
    .miraBottomSheet(isPresented: $showProfileOptions, preferredHeightFraction: 0.30, maxHeight: 260) { dismissOptions in
      ChatProfileOptionsSheet(
        isGroup: model.isGroup,
        onReport: {
          dismissOptions()
          DispatchQueue.main.asyncAfter(deadline: .now() + MIRATransitionTiming.sheetClose) {
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
    .onChange(of: pickerItem) { item in
      guard let item else { return }
      Task {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await model.sendPickedMedia(data: data, contentTypes: item.supportedContentTypes)
      }
    }
  }

  private var chatHeader: some View {
    HStack(spacing: 10) {
      Button {
        CaptroHaptics.light()
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(.black)
          .frame(width: 30, height: 40)
      }
      .buttonStyle(.miraPress)

      RemoteAvatar(url: peerAvatarURL, size: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.black)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(statusText)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.58))
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

  private func messageBubble(_ message: MIRAMessage) -> some View {
    let outgoing = isOutgoing(message)
    return HStack(alignment: .bottom, spacing: 0) {
      if outgoing { Spacer(minLength: 68) }
      VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
        if model.isGroup && !outgoing {
          Text(message.fullName ?? message.username ?? "MIRA")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
        MessageBubbleContent(
          message: message,
          outgoing: outgoing,
          maxWidth: bubbleMaxWidth,
          timestamp: statusText(for: message, outgoing: outgoing)
        )
      }
      .frame(maxWidth: bubbleMaxWidth, alignment: outgoing ? .trailing : .leading)
      if !outgoing { Spacer(minLength: 68) }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .contextMenu {
      if outgoing, message.status?.lowercased() == "failed" {
        Button {
          Task { await model.retry(message) }
        } label: {
          Label("Retry", systemImage: "arrow.clockwise")
        }
      }
      if !outgoing {
        Button(role: .destructive) {
          presentReport(for: message)
        } label: {
          Label("Report message", systemImage: "flag")
        }
        Button(role: .destructive) {
          Task { _ = await model.blockPeer() }
        } label: {
          Label("Block user", systemImage: "hand.raised")
        }
      }
      Button(role: .destructive) {
        model.deleteForMe(message)
      } label: {
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
      .foregroundStyle(Color.black.opacity(0.58))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.045))
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
            .foregroundStyle(.black)
            .frame(width: 32, height: 32)
            .background(ChatRoomPalette.input)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)

        TextField("Message", text: $model.draft, axis: .vertical)
          .lineLimit(1...5)
          .font(.system(size: 15))
          .foregroundStyle(.black)
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
    .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: -3)
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
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(hasDraft ? ChatRoomPalette.accent : Color.black.opacity(0.18))
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
    .disabled(!hasDraft || model.isSending)
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
    .background(Color.white)
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
    VStack(alignment: .leading, spacing: 0) {
      Capsule()
        .fill(Color.black.opacity(0.20))
        .frame(width: 42, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 16)

      Text(isGroup ? "Chat options" : "Profile options")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.black)
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.bottom, 10)

      if !isGroup {
        Button(role: .destructive, action: onReport) {
          ChatProfileOptionRow(title: "Report profile", subtitle: "Send this profile to moderation.", systemImage: "flag", tint: .red)
        }
        .buttonStyle(.miraPress)

        Button(role: .destructive, action: onBlock) {
          ChatProfileOptionRow(title: "Block user", subtitle: "Stop messages and unwanted contact.", systemImage: "hand.raised.fill", tint: .red)
        }
        .buttonStyle(.miraPress)
      } else {
        ChatProfileOptionRow(title: "Group chat", subtitle: "Group moderation tools are coming soon.", systemImage: "person.3.fill", tint: .black.opacity(0.68))
          .opacity(0.72)
      }

      Spacer(minLength: 0)
    }
    .background(ChatRoomPalette.composer)
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
          .foregroundStyle(.black)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.56))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.32))
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
    .shadow(color: ChatRoomPalette.messageShadow, radius: 8, x: 0, y: 4)
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
    outgoing ? ChatRoomPalette.outgoingBubble : ChatRoomPalette.incomingBubble
  }

  private var bubbleTextColor: Color {
    outgoing ? .white : .black
  }

  private var bubbleRadius: CGFloat {
    hasLargeMedia ? 18 : 22
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
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(bubbleTextColor)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .multilineTextAlignment(outgoing ? .trailing : .leading)
    } else {
      Text(content)
        .font(.system(size: 15, weight: .regular))
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
        .background((outgoing ? Color.white : Color.black).opacity(0.12))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(message.fileName?.isEmpty == false ? message.fileName! : "File")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(outgoing ? .white : .black)
          .lineLimit(1)
        if let fileSize = message.fileSize, fileSize > 0 {
          Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(outgoing ? Color.white.opacity(0.72) : Color.black.opacity(0.55))
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
