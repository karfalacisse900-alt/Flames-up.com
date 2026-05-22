import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ConversationNativeKind: Hashable {
  case direct(peerId: String)
  case group(groupId: String)
}

@MainActor
final class ConversationNativeModel: ObservableObject {
  @Published var messages: [MIRAMessage] = []
  @Published var presence: MIRAPresence?
  @Published var draft = ""
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
    await send(content: clean, mediaUrl: nil, mediaType: nil)
    draft = ""
    updateTyping(false)
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

  func toggleVoiceRecording() async {
    if isRecording {
      isRecording = false
      guard let url = recorder.stop() else { return }
      do {
        let data = try Data(contentsOf: url)
        let remote = try await uploadService.uploadAudio(data: data, fileName: url.lastPathComponent)
        await send(content: "", mediaUrl: remote, mediaType: "voice")
      } catch {
        errorMessage = "Could not send the voice message."
      }
      try? FileManager.default.removeItem(at: url)
    } else {
      do {
        try await recorder.start()
        isRecording = true
      } catch {
        errorMessage = "Microphone permission is needed for voice messages."
      }
    }
  }

  func updateTyping(_ typing: Bool) {
    guard case let .direct(peerId) = kind else { return }
    Task {
      let _: EmptyResponse? = try? await api.post("/messages/typing", body: TypingBody(peerId: peerId, isTyping: typing))
    }
  }

  private func send(content: String, mediaUrl: String?, mediaType: String?) async {
    guard !isSending else { return }
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
    } catch {
      errorMessage = "Could not send this message."
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
      MIRATheme.Color.appBackground.ignoresSafeArea()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: MIRATheme.Space.md) {
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
          .padding(.top, MIRATheme.Space.md)
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
    .background(MIRATheme.Color.appBackground)
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
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.forestSoft)
        .clipShape(Circle())
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
    min(UIScreen.main.bounds.width * 0.74, 304)
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
          .background(MIRATheme.Color.surface)
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
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showAttachmentTray.toggle()
          }
        } label: {
          Image(systemName: showAttachmentTray ? "xmark" : "plus")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
            .frame(width: 38, height: 38)
            .background(MIRATheme.Color.forestSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        TextField("Send message...", text: $model.draft, axis: .vertical)
          .lineLimit(1...5)
          .font(.system(size: 15))
          .padding(.horizontal, MIRATheme.Space.md)
          .padding(.vertical, 11)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .stroke(MIRATheme.Color.hairline, lineWidth: 1)
          }
          .onChange(of: model.draft) { value in
            model.updateTyping(!value.isEmpty)
          }

        composerPrimaryButton
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.vertical, 10)
    }
    .background(MIRATheme.Color.surface)
    .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: -4)
    .overlay(alignment: .top) {
      Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5)
    }
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: showAttachmentTray)
  }

  private var attachmentTray: some View {
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
        Task { await model.toggleVoiceRecording() }
      } label: {
        trayButton(model.isRecording ? "stop.fill" : "mic.fill", model.isRecording ? "Stop" : "Voice", tint: model.isRecording ? .red : MIRATheme.Color.textMuted)
      }
      .buttonStyle(.plain)

    }
    .padding(.horizontal, MIRATheme.Space.md)
  }

  private var composerPrimaryButton: some View {
    let hasDraft = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      Task {
        if hasDraft {
          await model.sendText()
        } else {
          await model.toggleVoiceRecording()
        }
      }
    } label: {
      Image(systemName: hasDraft ? "arrow.up" : (model.isRecording ? "stop.fill" : "mic.fill"))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .background(model.isRecording ? Color.red : MIRATheme.Color.forest)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(hasDraft && model.isSending)
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
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
      if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
        Text(content)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(outgoing ? .trailing : .leading)
          .frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
      }
    }
    .padding(.horizontal, hasLargeMedia ? 6 : MIRATheme.Space.md)
    .padding(.vertical, hasLargeMedia ? 6 : MIRATheme.Space.sm)
    .frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
    .background(outgoing ? MIRATheme.Color.forest : MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      if !outgoing {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .stroke(MIRATheme.Color.hairline, lineWidth: 1)
      }
    }
  }

  private var hasLargeMedia: Bool {
    guard let mediaType = message.mediaType?.lowercased() else { return false }
    return mediaType == "image" || mediaType == "video"
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

private struct VoicePlaybackPill: View {
  let url: String
  let outgoing: Bool
  @State private var player: AVPlayer?
  @State private var isPlaying = false

  var body: some View {
    Button {
      toggle()
    } label: {
      HStack(spacing: MIRATheme.Space.sm) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        Image(systemName: "waveform")
        Text("Voice message")
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
    }
    .buttonStyle(.plain)
  }

  private func toggle() {
    guard let remoteURL = URL(string: url) else { return }
    if player == nil {
      player = AVPlayer(url: remoteURL)
    }
    if isPlaying {
      player?.pause()
      isPlaying = false
    } else {
      player?.play()
      isPlaying = true
    }
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

private final class MIRAVoiceRecorder: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?

  func start() async throws {
    let granted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { allowed in
        continuation.resume(returning: allowed)
      }
    }
    guard granted else { throw MIRARecorderError.permissionDenied }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
    recorder?.record()
  }

  func stop() -> URL? {
    let url = recorder?.url
    recorder?.stop()
    recorder = nil
    return url
  }
}

private enum MIRARecorderError: Error {
  case permissionDenied
}
