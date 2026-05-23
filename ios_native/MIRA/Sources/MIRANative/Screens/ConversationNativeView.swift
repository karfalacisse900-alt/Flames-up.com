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
  static let background = Color(red: 0.946, green: 0.957, blue: 0.954)
  static let backgroundWash = Color(red: 0.910, green: 0.942, blue: 0.936)
  static let composer = Color.white
  static let input = Color(red: 0.965, green: 0.972, blue: 0.970)
  static let incomingBubble = Color.white
  static let outgoingBubble = Color(red: 0.035, green: 0.250, blue: 0.285)
  static let outgoingSoft = Color(red: 0.105, green: 0.380, blue: 0.410)
  static let accent = Color(red: 0.040, green: 0.220, blue: 0.260)
  static let voice = Color(red: 0.840, green: 0.220, blue: 0.330)
  static let hairline = Color.black.opacity(0.070)
  static let messageShadow = Color.black.opacity(0.055)
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
  @State private var activeCall: MIRAAgoraCallPresentation?
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
    ZStack {
      LinearGradient(
        colors: [ChatRoomPalette.background, ChatRoomPalette.backgroundWash],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
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
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.top, MIRATheme.Space.lg)
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
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 2) {
          Text(title)
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          Text(statusText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        if model.peerId != nil {
          callToolbarButton(systemImage: "phone.fill", mode: .voice)
          callToolbarButton(systemImage: "video.fill", mode: .video)
        }
      }
    }
    .task { await model.load() }
    .task { await model.pollPresence() }
    .fullScreenCover(item: $activeCall) { presentation in
      MIRAAgoraCallView(presentation: presentation, api: model.api)
    }
    .sheet(isPresented: $showGIFPicker) {
      ChatGIFPickerSheet(api: model.api) { gif in
        showGIFPicker = false
        Task { await model.sendGIF(gif) }
      }
      .presentationDetents([.medium, .large])
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

  private var statusText: String {
    if model.isGroup { return "group chat" }
    if model.presence?.isTyping == true { return "typing..." }
    if model.presence?.isOnline == true { return "online" }
    return "chat"
  }

  private func callToolbarButton(systemImage: String, mode: MIRAAgoraCallMode) -> some View {
    Button {
      startCall(mode: mode)
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(ChatRoomPalette.accent)
        .frame(width: 34, height: 34)
        .background(Color.white)
        .clipShape(Circle())
        .overlay(Circle().stroke(ChatRoomPalette.hairline, lineWidth: 1))
    }
    .buttonStyle(.miraPress)
  }

  private func startCall(mode: MIRAAgoraCallMode) {
    guard let peerId = model.peerId, !peerId.isEmpty else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    activeCall = MIRAAgoraCallPresentation.direct(
      currentUserId: model.currentUserId,
      peerId: peerId,
      peerName: title,
      peerAvatar: peerAvatarURL,
      mode: mode
    )
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
    return HStack(alignment: .bottom, spacing: MIRATheme.Space.sm) {
      if outgoing { Spacer(minLength: 54) }
      if !outgoing {
        RemoteAvatar(url: message.profileImage, size: 30)
      }
      VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
        if model.isGroup && !outgoing {
          Text(message.fullName ?? message.username ?? "MIRA")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }
        MessageBubbleContent(message: message, outgoing: outgoing, maxWidth: bubbleMaxWidth)
        if let createdAt = message.createdAt {
          Text(conversationMessageAge(createdAt))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.78))
            .padding(.horizontal, 4)
        }
      }
      .frame(maxWidth: bubbleMaxWidth, alignment: outgoing ? .trailing : .leading)
      if !outgoing { Spacer(minLength: 54) }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private var bubbleMaxWidth: CGFloat {
    min(UIScreen.main.bounds.width * 0.78, 324)
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
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ChatRoomPalette.accent)
            .frame(width: 38, height: 38)
            .background(ChatRoomPalette.input)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        TextField("Send message...", text: $model.draft, axis: .vertical)
          .lineLimit(1...5)
          .font(.system(size: 15))
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.vertical, 11)
          .background(ChatRoomPalette.input)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .stroke(ChatRoomPalette.hairline, lineWidth: 1)
          }
          .onChange(of: model.draft) { value in
            model.updateTyping(!value.isEmpty)
          }

        composerPrimaryButton
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 10)
    }
    .background(ChatRoomPalette.composer)
    .shadow(color: .black.opacity(0.07), radius: 22, x: 0, y: -6)
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
            tint: model.isRecording ? ChatRoomPalette.voice : MIRATheme.Color.textMuted
          )
        }
        .buttonStyle(.plain)

        if model.peerId != nil {
          Button {
            startCall(mode: .voice)
          } label: {
            trayButton("phone.fill", "Call", tint: ChatRoomPalette.accent)
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
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
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
    .background(ChatRoomPalette.input)
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

  var body: some View {
    VStack(alignment: outgoing ? .trailing : .leading, spacing: MIRATheme.Space.xs) {
      if let mediaUrl = message.mediaUrl, !mediaUrl.isEmpty {
        mediaContent(url: mediaUrl)
      }
      if shouldShowTextContent, let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
        Text(content)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(outgoing ? .trailing : .leading)
          .frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
      }
    }
    .padding(.leading, bubbleLeadingPadding)
    .padding(.trailing, bubbleTrailingPadding)
    .padding(.vertical, hasLargeMedia ? 6 : 10)
    .frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
    .background {
      ChatBubbleShape(outgoing: outgoing, radius: hasLargeMedia ? 18 : 22)
        .fill(outgoing ? ChatRoomPalette.outgoingBubble : ChatRoomPalette.incomingBubble)
    }
    .overlay {
      ChatBubbleShape(outgoing: outgoing, radius: hasLargeMedia ? 18 : 22)
        .stroke(outgoing ? Color.white.opacity(0.10) : ChatRoomPalette.hairline, lineWidth: 1)
    }
    .shadow(color: ChatRoomPalette.messageShadow, radius: outgoing ? 12 : 10, x: 0, y: 5)
  }

  private var hasLargeMedia: Bool {
    guard let mediaType = message.mediaType?.lowercased() else { return false }
    return mediaType == "image" || mediaType == "video"
  }

  private var bubbleLeadingPadding: CGFloat {
    hasLargeMedia ? 6 : (outgoing ? MIRATheme.Space.md : MIRATheme.Space.md + 6)
  }

  private var bubbleTrailingPadding: CGFloat {
    hasLargeMedia ? 6 : (outgoing ? MIRATheme.Space.md + 6 : MIRATheme.Space.md)
  }

  private var shouldShowTextContent: Bool {
    let mediaType = message.mediaType?.lowercased()
    return mediaType != "voice" && mediaType != "audio"
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
        Text(message.content?.isEmpty == false ? message.content! : "File")
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
      .frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
    } else {
      RemoteMediaView(url: url, isVideo: type == "video" || url.isVideoURL, shouldPlay: false)
        .frame(width: mediaWidth, height: type == "video" || url.isVideoURL ? mediaWidth * 1.22 : mediaWidth * 0.86)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }
}

private struct ChatBubbleShape: Shape {
  let outgoing: Bool
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let tailWidth: CGFloat = 7
    let bubbleRect = outgoing
      ? CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - tailWidth), height: rect.height)
      : CGRect(x: rect.minX + tailWidth, y: rect.minY, width: max(0, rect.width - tailWidth), height: rect.height)
    var path = Path()
    path.addRoundedRect(
      in: bubbleRect,
      cornerSize: CGSize(width: radius, height: radius),
      style: .continuous
    )
    var tail = Path()

    if outgoing {
      let start = CGPoint(x: bubbleRect.maxX - 1, y: bubbleRect.maxY - 19)
      tail.move(to: start)
      tail.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.maxY - 9),
        control: CGPoint(x: rect.maxX - 1, y: rect.maxY - 16)
      )
      tail.addQuadCurve(
        to: CGPoint(x: bubbleRect.maxX - 8, y: bubbleRect.maxY - 5),
        control: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)
      )
      tail.addLine(to: start)
    } else {
      let start = CGPoint(x: bubbleRect.minX + 1, y: bubbleRect.maxY - 19)
      tail.move(to: start)
      tail.addQuadCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - 9),
        control: CGPoint(x: rect.minX + 1, y: rect.maxY - 16)
      )
      tail.addQuadCurve(
        to: CGPoint(x: bubbleRect.minX + 8, y: bubbleRect.maxY - 5),
        control: CGPoint(x: rect.minX + 1, y: rect.maxY - 1)
      )
      tail.addLine(to: start)
    }

    path.addPath(tail)
    return path
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
      HStack(spacing: MIRATheme.Space.sm) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(outgoing ? ChatRoomPalette.outgoingBubble : .white)
          .frame(width: 28, height: 28)
          .background(outgoing ? Color.white : ChatRoomPalette.accent)
          .clipShape(Circle())
        Image(systemName: "waveform")
          .font(.system(size: 18, weight: .semibold))
        Text(playbackError ? "Could not play" : "Voice message")
          .lineLimit(1)
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(playbackError ? ChatRoomPalette.voice : (outgoing ? .white : MIRATheme.Color.textPrimary))
      .padding(.trailing, 4)
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

private struct ChatGIFPickerSheet: View {
  let api: MIRAAPIClient
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
          Button("Done") { dismiss() }
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
