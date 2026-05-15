import SwiftUI

@MainActor
final class ConversationNativeModel: ObservableObject {
  @Published var messages: [MIRAMessage] = []
  @Published var presence: MIRAPresence?
  @Published var draft = ""
  @Published var isLoading = false
  @Published var isSending = false

  let peerId: String
  let api: MIRAAPIClient

  init(peerId: String, api: MIRAAPIClient) {
    self.peerId = peerId
    self.api = api
  }

  func load() async {
    isLoading = messages.isEmpty
    defer { isLoading = false }
    if let rows: [MIRAMessage] = try? await api.get("/messages/\(peerId)") {
      messages = rows
    }
    presence = try? await api.get("/messages/presence/\(peerId)")
  }

  func send() async {
    let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !isSending else { return }
    isSending = true
    defer { isSending = false }
    do {
      let sent: MIRAMessage = try await api.post("/messages", body: SendMessageBody(receiverId: peerId, content: clean))
      messages.append(sent)
      draft = ""
      let _: EmptyResponse? = try? await api.post("/messages/typing", body: TypingBody(peerId: peerId, isTyping: false))
    } catch {}
  }

  func updateTyping(_ typing: Bool) {
    Task {
      let _: EmptyResponse? = try? await api.post("/messages/typing", body: TypingBody(peerId: peerId, isTyping: typing))
    }
  }
}

public struct ConversationNativeView: View {
  @StateObject private var model: ConversationNativeModel
  private let title: String

  public init(peerId: String, title: String, api: MIRAAPIClient) {
    self.title = title
    _model = StateObject(wrappedValue: ConversationNativeModel(peerId: peerId, api: api))
  }

  public var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: MIRATheme.Space.sm) {
            if model.isLoading && model.messages.isEmpty {
              ProgressView().padding(MIRATheme.Space.xxl)
            } else if model.messages.isEmpty {
              MIRAEmptyState(title: "Start the chat", message: "Send a message when you are ready.", systemImage: "message")
            } else {
              ForEach(model.messages) { message in
                messageBubble(message)
                  .id(message.id)
              }
            }
          }
          .padding(MIRATheme.Space.md)
        }
        .onChange(of: model.messages.count) { _ in
          if let last = model.messages.last?.id {
            withAnimation(.easeOut(duration: 0.18)) {
              proxy.scrollTo(last, anchor: .bottom)
            }
          }
        }
      }

      composer
    }
    .background(MIRATheme.Color.appBackground)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 2) {
          Text(title).font(.system(size: 17, weight: .semibold))
          Text(statusText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
    }
    .task { await model.load() }
  }

  private var statusText: String {
    if model.presence?.isTyping == true { return "typing..." }
    if model.presence?.isOnline == true { return "online" }
    return "chat"
  }

  private func messageBubble(_ message: MIRAMessage) -> some View {
    let outgoing = message.senderId != model.peerId
    return HStack {
      if outgoing { Spacer(minLength: 52) }
      Text(message.content ?? "")
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(outgoing ? .white : MIRATheme.Color.textPrimary)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, MIRATheme.Space.sm)
        .background(outgoing ? MIRATheme.Color.forest : MIRATheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      if !outgoing { Spacer(minLength: 52) }
    }
  }

  private var composer: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      TextField("Message", text: $model.draft, axis: .vertical)
        .lineLimit(1...5)
        .font(.system(size: 15))
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.vertical, 10)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: model.draft) { value in
          model.updateTyping(!value.isEmpty)
        }

      Button {
        Task { await model.send() }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(MIRATheme.Color.forest)
          .clipShape(Circle())
      }
      .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
      .opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
    }
    .padding(MIRATheme.Space.md)
    .background(.ultraThinMaterial)
  }
}
