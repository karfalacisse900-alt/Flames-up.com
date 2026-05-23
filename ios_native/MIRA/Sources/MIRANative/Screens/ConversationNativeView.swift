import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ConversationNativeKind: Hashable {
  case direct(peerId: String)
  case group(groupId: String)
}

struct MIRAVoiceDraft: Identifiable, Hashable {
  let url: URL
  let duration: TimeInterval

  var id: String {
    url.absoluteString
  }
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
  static let voice = Color.black
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
  @Published var pendingVoiceDraft: MIRAVoiceDraft?
  @Published var isLoading = false
  @Published var isSending = false
  @Published var isUploading = false
  @Published var isRecording = false
  @Published var errorMessage: String?

  let kind: ConversationNativeKind
  let api: MIRAAPIClient
  let currentUserId: String
  private let uploadService: MIRAMediaUploadService
  private let recorder = MIRAVoiceRecorder()

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
    isLoading = messages.isEmpty
    defer { isLoading = false }
    do {
      switch kind {
      case let .direct(peerId):
        let rows: [MIRAMessage] = try await api.get("/messages/\(peerId)")
        messages = rows
        presence = try? await api.get("/messages/presence/\(peerId)")
      case let .group(groupId):
        let response: MIRAGroupMessagesResponse = try await api.get("/group-chats/\(groupId)/messages")
        messages = response.messages
      }
      errorMessage = nil
    } catch {
      errorMessage = "Could not load this chat."
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
    if await send(content: clean, mediaUrl: nil, mediaType: nil) {
      draft = ""
      updateTyping(false)
    }
  }

  func sendPickedMedia(data: Data, contentTypes: [UTType]) async {
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    do {
      let (kind, fileName, mimeType) = pickedMediaKind(from: contentTypes, fallbackData: data)
      let url = try await uploadService.upload(MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType))
      await send(content: "", mediaUrl: url, mediaType: kind == .video ? "video" : "image")
    } catch {
      errorMessage = "Could not send this media."
    }
  }

  func sendFile(url: URL) async {
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access { url.stopAccessingSecurityScopedResource() }
    }
    do {
      let data = try Data(contentsOf: url)
      let type = UTType(filenameExtension: url.pathExtension)
      let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
      let uploaded = try await uploadService.uploadFile(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
      await send(content: url.lastPathComponent, mediaUrl: uploaded, mediaType: "file")
    } catch {
      errorMessage = "Could not send this file."
    }
  }

  func sendGIF(_ gif: MIRAGifItem) async {
    guard let url = gif.mediaUrl ?? gif.previewUrl, !url.isEmpty else { return }
    await send(content: gif.title ?? "", mediaUrl: url, mediaType: "image")
  }

  func startVoiceRecording() async {
    guard !isRecording, pendingVoiceDraft == nil else { return }
    do {
      try await recorder.start()
      isRecording = true
      errorMessage = nil
    } catch {
      errorMessage = "Microphone permission is needed for voice messages."
    }
  }

  func stopVoiceRecording() {
    guard isRecording else { return }
    isRecording = false
    guard let draft = recorder.stop() else {
      errorMessage = "No voice was recorded."
      return
    }
    guard draft.duration >= 0.4 else {
      try? FileManager.default.removeItem(at: draft.url)
      errorMessage = "Hold a little longer to record a voice message."
      return
    }
    pendingVoiceDraft = draft
    errorMessage = nil
  }

  func cancelVoiceRecording() {
    if isRecording {
      isRecording = false
      if let draft = recorder.stop() {
        try? FileManager.default.removeItem(at: draft.url)
      }
    }
    discardVoiceDraft()
  }

  func discardVoiceDraft() {
    if let draft = pendingVoiceDraft {
      try? FileManager.default.removeItem(at: draft.url)
    }
    pendingVoiceDraft = nil
  }

  func sendVoiceDraft() async {
    guard let draft = pendingVoiceDraft, !isUploading, !isSending else { return }
    isUploading = true
    defer { isUploading = false }
    do {
      let data = try Data(contentsOf: draft.url)
      let remote = try await uploadService.uploadAudio(data: data, fileName: draft.url.lastPathComponent)
      if await send(content: "Voice message", mediaUrl: remote, mediaType: "voice") {
        pendingVoiceDraft = nil
        try? FileManager.default.removeItem(at: draft.url)
        errorMessage = nil
      } else {
        errorMessage = "Could not send the voice message."
      }
    } catch {
      errorMessage = "Could not send the voice message."
    }
  }

  func updateTyping(_ typing: Bool) {
    guard case let .direct(peerId) = kind else { return }
    Task {
      let _: EmptyResponse? = try? await api.post("/messages/typing", body: TypingBody(peerId: peerId, isTyping: typing))
    }
  }

  @discardableResult
  private func send(content: String, mediaUrl: String?, mediaType: String?) async -> Bool {
    guard !isSending else { return false }
    isSending = true
    defer { isSending = false }
    do {
      switch kind {
      case let .direct(peerId):
        let sent: MIRAMessage = try await api.post(
          "/messages",
          body: SendMessageBody(receiverId: peerId, content: content, mediaUrl: mediaUrl, mediaType: mediaType)
        )
        messages.append(sent)
      case let .group(groupId):
        let sent: MIRAMessage = try await api.post(
          "/group-chats/\(groupId)/messages",
          body: GroupMessageBody(content: content, mediaUrl: mediaUrl, mediaType: mediaType)
        )
        messages.append(sent)
      }
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not send this message."
      return false
    }
  }
}

public struct ConversationNativeView: View {
  @StateObject private var model: ConversationNativeModel
  @State private var pickerItem: PhotosPickerItem?
  @State private var showFileImporter = false
  @State private var showGIFPicker = false
  @State private var showAttachmentTray = false
  @Environment(\.dismiss) private var dismiss
  private let title: String

  public init(peerId: String, title: String, api: MIRAAPIClient, currentUserId: String = "") {
    self.title = title
    _model = StateObject(wrappedValue: ConversationNativeModel(kind: .direct(peerId: peerId), api: api, currentUserId: currentUserId))
  }

  public init(groupId: String, title: String, api: MIRAAPIClient, currentUserId: String = "") {
    self.title = title
    _model = StateObject(wrappedValue: ConversationNativeModel(kind: .group(groupId: groupId), api: api, currentUserId: currentUserId))
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
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: model.messages.count) { _ in
          if let last = model.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
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
    .miraBottomSheet(isPresented: $showGIFPicker, preferredHeightFraction: 0.72) { dismissGIFPicker in
      ChatGIFPickerSheet(api: model.api, onClose: dismissGIFPicker) { gif in
        dismissGIFPicker()
        Task { await model.sendGIF(gif) }
      }
    }
    .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
      guard case let .success(urls) = result, let url = urls.first else { return }
      Task { await model.sendFile(url: url) }
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

      if model.peerId != nil {
        Button {
          startCall(mode: .video)
        } label: {
          Image(systemName: "video.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.black)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel("Video Call")
      }

      Menu {
        if model.peerId != nil {
          Button {
            startCall(mode: .video)
          } label: {
            Label("Video Call", systemImage: "video.fill")
          }
        } else {
          Text("Group chat")
        }
      } label: {
        Image(systemName: "ellipsis.vertical")
          .font(.system(size: 19, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: 36, height: 40)
          .contentShape(Rectangle())
      }
      .buttonStyle(.miraPress)
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

  private func startCall(mode: MIRAAgoraCallMode) {
    guard let peerId = model.peerId, !peerId.isEmpty else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    guard mode == .video else { return }
    Task {
      await MIRAAppCallCoordinator.shared.startVideoCall(
        peerId: peerId,
        peerName: title,
        peerAvatar: peerAvatarURL
      )
    }
  }

  private var peerAvatarURL: String? {
    model.messages.first { !isOutgoing($0) }?.profileImage
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
          timestamp: nil
        )
      }
      .frame(maxWidth: bubbleMaxWidth, alignment: outgoing ? .trailing : .leading)
      if !outgoing { Spacer(minLength: 68) }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
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

      if model.isRecording {
        VoiceRecordingComposerBar(
          onCancel: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.cancelVoiceRecording()
          },
          onStop: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.stopVoiceRecording()
          }
        )
        .padding(.horizontal, MIRATheme.Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      if let voiceDraft = model.pendingVoiceDraft {
        VoiceDraftComposerPreview(
          draft: voiceDraft,
          isSending: model.isUploading || model.isSending,
          onDelete: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.discardVoiceDraft()
          },
          onSend: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await model.sendVoiceDraft() }
          }
        )
        .padding(.horizontal, MIRATheme.Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      if showAttachmentTray {
        attachmentTray
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      HStack(spacing: 10) {
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
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
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: showAttachmentTray)
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: model.isRecording)
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: model.pendingVoiceDraft)
  }

  private var attachmentTray: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
          trayButton("photo.on.rectangle", "Media")
        }
        .disabled(model.isUploading)

        Button { showGIFPicker = true } label: {
          trayButton("gift", "GIF")
        }
        .buttonStyle(.plain)

        Button { showFileImporter = true } label: {
          trayButton("paperclip", "File")
        }
        .buttonStyle(.plain)

        Button {
          toggleVoiceRecording()
        } label: {
          trayButton(
            model.isRecording ? "stop.fill" : "mic.fill",
            model.isRecording ? "Stop" : "Voice",
            tint: model.isRecording ? ChatRoomPalette.voice : Color.black.opacity(0.62)
          )
        }
        .buttonStyle(.plain)

        if model.peerId != nil {
          Button {
            startCall(mode: .video)
          } label: {
            trayButton("video.fill", "Video", tint: ChatRoomPalette.accent)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
    }
  }

  private var composerPrimaryButton: some View {
    let hasDraft = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasVoiceDraft = model.pendingVoiceDraft != nil
    return Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      Task {
        if hasDraft {
          await model.sendText()
        } else if hasVoiceDraft {
          await model.sendVoiceDraft()
        } else if model.isRecording {
          model.stopVoiceRecording()
        } else {
          await model.startVoiceRecording()
        }
      }
    } label: {
      Image(systemName: hasDraft || hasVoiceDraft ? "arrow.up" : (model.isRecording ? "stop.fill" : "mic.fill"))
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(model.isRecording ? ChatRoomPalette.voice : ChatRoomPalette.accent)
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
    .disabled((hasDraft && model.isSending) || (hasVoiceDraft && (model.isUploading || model.isSending)))
  }

  private func toggleVoiceRecording() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if model.isRecording {
      model.stopVoiceRecording()
    } else {
      Task { await model.startVoiceRecording() }
    }
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

private struct VoiceRecordingComposerBar: View {
  let onCancel: () -> Void
  let onStop: () -> Void
  @State private var pulse = false

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Circle()
        .fill(ChatRoomPalette.voice)
        .frame(width: 10, height: 10)
        .scaleEffect(pulse ? 1.28 : 0.86)
        .opacity(pulse ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: pulse)

      Image(systemName: "waveform")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(ChatRoomPalette.voice)

      Text("Recording voice")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .lineLimit(1)

      Spacer()

      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .frame(width: 34, height: 34)
          .background(ChatRoomPalette.input)
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)

      Button(action: onStop) {
        Image(systemName: "stop.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 34)
          .background(ChatRoomPalette.voice)
          .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(ChatRoomPalette.hairline, lineWidth: 1)
    }
    .onAppear { pulse = true }
  }
}

private struct VoiceDraftComposerPreview: View {
  let draft: MIRAVoiceDraft
  let isSending: Bool
  let onDelete: () -> Void
  let onSend: () -> Void
  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var endObserver: NSObjectProtocol?

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Button {
        togglePlayback()
      } label: {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(ChatRoomPalette.accent)
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)

      Image(systemName: "waveform")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(ChatRoomPalette.voice)

      VStack(alignment: .leading, spacing: 2) {
        Text("Voice message")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(voiceDurationLabel(draft.duration))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      Spacer()

      Button(action: onDelete) {
        Image(systemName: "trash")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .frame(width: 36, height: 36)
          .background(ChatRoomPalette.input)
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)
      .disabled(isSending)

      Button(action: onSend) {
        Group {
          if isSending {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: "arrow.up")
              .font(.system(size: 14, weight: .bold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 40, height: 36)
        .background(ChatRoomPalette.accent)
        .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
      .disabled(isSending)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 10)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(ChatRoomPalette.hairline, lineWidth: 1)
    }
    .onDisappear {
      cleanup()
    }
  }

  private func togglePlayback() {
    if player == nil {
      let item = AVPlayerItem(url: draft.url)
      player = AVPlayer(playerItem: item)
      player?.volume = 1
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { _ in
        isPlaying = false
        player?.seek(to: .zero)
      }
    }
    if isPlaying {
      player?.pause()
      isPlaying = false
    } else {
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
      } catch {
        return
      }
      player?.seek(to: .zero)
      player?.play()
      isPlaying = true
    }
  }

  private func cleanup() {
    player?.pause()
    isPlaying = false
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    player = nil
  }
}

private struct MessageBubbleContent: View {
  let message: MIRAMessage
  let outgoing: Bool
  let maxWidth: CGFloat
  let timestamp: String?

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

  private var isVoiceMessage: Bool {
    let mediaType = message.mediaType?.lowercased()
    return mediaType == "voice" || mediaType == "audio"
  }

  private var normalizedText: String? {
    guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
      return nil
    }
    return content
  }

  private var bubbleFill: Color {
    outgoing || isVoiceMessage ? ChatRoomPalette.outgoingBubble : ChatRoomPalette.incomingBubble
  }

  private var bubbleTextColor: Color {
    outgoing || isVoiceMessage ? .white : .black
  }

  private var bubbleRadius: CGFloat {
    isVoiceMessage ? 25 : (hasLargeMedia ? 18 : 22)
  }

  private var bubbleVerticalPadding: CGFloat {
    if isVoiceMessage { return 6 }
    return hasLargeMedia ? 6 : 12
  }

  private var textMaxWidth: CGFloat {
    max(96, maxWidth - bubbleLeadingPadding - bubbleTrailingPadding)
  }

  private var bubbleFrameMaxWidth: CGFloat? {
    if isVoiceMessage || isCompactTextOnly { return nil }
    return maxWidth
  }

  private var bubbleLeadingPadding: CGFloat {
    if hasLargeMedia { return outgoing ? 10 : 14 }
    if isVoiceMessage { return 8 }
    return 18
  }

  private var bubbleTrailingPadding: CGFloat {
    if hasLargeMedia { return outgoing ? 14 : 10 }
    if isVoiceMessage { return 8 }
    return 18
  }

  private var shouldShowTextContent: Bool {
    let mediaType = message.mediaType?.lowercased()
    return mediaType != "voice" && mediaType != "audio"
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
    if type == "voice" || type == "audio" {
      VoicePlaybackPill(url: url, outgoing: outgoing)
    } else if type == "file" {
      HStack(spacing: MIRATheme.Space.sm) {
        Image(systemName: "doc.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(outgoing ? ChatRoomPalette.outgoingBubble : .white)
          .frame(width: 28, height: 28)
          .background(outgoing ? Color.white.opacity(0.92) : ChatRoomPalette.accent)
          .clipShape(Circle())
        Text(message.content?.isEmpty == false ? message.content! : "File")
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
      .frame(maxWidth: textMaxWidth, alignment: outgoing ? .trailing : .leading)
    } else {
      RemoteMediaView(url: url, isVideo: type == "video" || url.isVideoURL, shouldPlay: false)
        .frame(width: mediaWidth, height: type == "video" || url.isVideoURL ? mediaWidth * 1.22 : mediaWidth * 0.86)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }
}

private struct VoicePlaybackPill: View {
  let url: String
  let outgoing: Bool
  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var playbackError = false
  @State private var endObserver: NSObjectProtocol?

  var body: some View {
    Button {
      toggle()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: 36, height: 36)
          .background(Color.white)
          .clipShape(Circle())
        VoiceWaveformBars(color: .white.opacity(0.88))
          .frame(width: 86, height: 28)
        if playbackError {
          Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.88))
        }
      }
      .frame(width: playbackError ? 154 : 136, alignment: outgoing ? .trailing : .leading)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .onDisappear {
      cleanup()
    }
  }

  private func toggle() {
    guard let remoteURL = resolvedVoicePlaybackURL(url) else {
      playbackError = true
      return
    }
    playbackError = false
    if player == nil {
      let item = AVPlayerItem(url: remoteURL)
      player = AVPlayer(playerItem: item)
      player?.volume = 1
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { _ in
        isPlaying = false
        player?.seek(to: .zero)
      }
    }
    if isPlaying {
      stop()
    } else {
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
      } catch {
        playbackError = true
        return
      }
      player?.seek(to: .zero)
      player?.play()
      isPlaying = true
    }
  }

  private func stop() {
    player?.pause()
    isPlaying = false
  }

  private func cleanup() {
    stop()
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    player = nil
  }
}

private struct VoiceWaveformBars: View {
  let color: Color

  private let heights: [CGFloat] = [
    4, 5, 4, 7, 10, 15, 20, 24, 14, 26,
    22, 18, 25, 17, 12, 20, 14, 9
  ]

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(color)
          .frame(width: 3, height: height)
      }
    }
    .frame(maxHeight: .infinity)
    .accessibilityHidden(true)
  }
}

private struct ChatGIFPickerSheet: View {
  let api: MIRAAPIClient
  let onClose: (() -> Void)?
  let onSelect: (MIRAGifItem) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = "reaction"
  @State private var results: [MIRAGifItem] = []
  @State private var isLoading = false

  var body: some View {
    NavigationStack {
      VStack(spacing: MIRATheme.Space.md) {
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(MIRATheme.Color.textMuted)
          TextField("Search GIFs", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { Task { await search() } }
        }
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, 12)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Capsule())
        .padding(.horizontal, MIRATheme.Space.md)

        if isLoading {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MIRATheme.Space.sm) {
              ForEach(results) { gif in
                Button {
                  onSelect(gif)
                } label: {
                  RemoteMediaView(url: gif.previewUrl ?? gif.mediaUrl ?? "", isVideo: false)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
              }
            }
            .padding(MIRATheme.Space.md)
          }
        }
      }
      .navigationTitle("GIF")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { close() }
        }
      }
      .task { await search() }
      .onChange(of: query) { _ in
        Task {
          try? await Task.sleep(nanoseconds: 350_000_000)
          if !Task.isCancelled { await search() }
        }
      }
    }
  }

  @MainActor
  private func search() async {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 2 else { return }
    isLoading = results.isEmpty
    defer { isLoading = false }
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: clean),
      URLQueryItem(name: "limit", value: "24"),
    ]
    let encoded = components.percentEncodedQuery ?? "q=\(clean)"
    if let response: MIRAGifSearchResponse = try? await api.get("/gifs/search?\(encoded)") {
      results = response.gifs
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

private func voiceDurationLabel(_ duration: TimeInterval) -> String {
  let totalSeconds = max(0, Int(duration.rounded()))
  let minutes = totalSeconds / 60
  let seconds = totalSeconds % 60
  return "\(minutes):\(String(format: "%02d", seconds))"
}

private func resolvedVoicePlaybackURL(_ value: String) -> URL? {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  if trimmed.hasPrefix("//") {
    return URL(string: "https:\(trimmed)")
  }
  if let absolute = URL(string: trimmed), absolute.scheme != nil {
    return absolute
  }
  let cleanPath = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  guard !cleanPath.isEmpty else { return nil }
  if cleanPath.hasPrefix("api/") {
    return MIRAProductionBackend.apiURL(String(cleanPath.dropFirst(4)))
  }
  return MIRAProductionBackend.apiURL(cleanPath)
}

private final class MIRAVoiceRecorder: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var startedAt: Date?

  func start() async throws {
    let granted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { allowed in
        continuation.resume(returning: allowed)
      }
    }
    guard granted else { throw MIRARecorderError.permissionDenied }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try session.setActive(true)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mira-voice-\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder?.delegate = self
    recorder?.isMeteringEnabled = true
    recorder?.prepareToRecord()
    startedAt = Date()
    guard recorder?.record() == true else {
      recorder = nil
      startedAt = nil
      throw MIRARecorderError.failedToStart
    }
  }

  func stop() -> MIRAVoiceDraft? {
    guard let activeRecorder = recorder else { return nil }
    let url = activeRecorder.url
    let duration = max(activeRecorder.currentTime, startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    activeRecorder.stop()
    self.recorder = nil
    startedAt = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    return MIRAVoiceDraft(url: url, duration: duration)
  }
}

private enum MIRARecorderError: Error {
  case permissionDenied
  case failedToStart
}
