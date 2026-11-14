import Foundation

/// Presentation state owned by the existing API client. Nothing is stored in a
/// global or disk cache, and the auth/session generation is checked after awaits.
@MainActor final class CaptroTeaConversationStore {
  private let api: MIRAAPIClient
  private var scope = ""
  private var models: [String: CaptroTeaConversationModel] = [:]
  private var order: [String] = []
  init(api: MIRAAPIClient) { self.api = api }
  func model(for post: CaptroTeaConversation) -> CaptroTeaConversationModel {
    if scope != api.presentationScope { invalidate(); scope = api.presentationScope }
    if let model = models[post.id] { return model }
    let model = CaptroTeaConversationModel(post: post, api: api)
    models[post.id] = model; order.append(post.id)
    if order.count > 24 { models[order.removeFirst()] = nil }
    return model
  }
  func invalidate() {
    for model in models.values { model.clear() }
    models.removeAll(); order.removeAll()
  }
}

@MainActor final class CaptroTeaConversationModel: ObservableObject {
  @Published var post: CaptroTeaConversation?
  @Published var replies: [CaptroTeaReply] = []
  @Published var error: String?
  @Published var loading = false
  @Published var replyError: String?
  @Published var loadingReplies = false
  @Published var busy = false
  @Published var draft = ""
  @Published var nextCursor: String?
  private let api: MIRAAPIClient
  private let scope: String
  let id: String
  private var loadedAt: Date?
  private var replyLoadedAt: Date?
  private var requestID = UUID().uuidString
  private var pendingReply: String?
  private var flight: Task<Void, Never>?

  init(post: CaptroTeaConversation, api: MIRAAPIClient) {
    self.post = post; self.id = post.id; self.api = api; scope = api.presentationScope
  }
  var valid: Bool { scope == api.presentationScope }
  func clear() {
    flight?.cancel(); flight = nil; post = nil; replies = []; draft = ""; loadedAt = nil; replyLoadedAt = nil
  }
  func load(force: Bool = false) async {
    guard valid else { clear(); return }
    if let flight { await flight.value; return }
    if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 30 { return }
    let task = Task { [weak self] in
      guard let self else { return }
      loading = true; error = nil
      defer { loading = false }
      do {
        let result: CaptroTeaConversation = try await api.getFresh("/tea/conversations/" + id)
        guard valid, !Task.isCancelled else { return }
        guard result.id == id else { throw MIRAAPIError.decodingFailed }
        post = result; loadedAt = Date()
      } catch {
        guard valid, !Task.isCancelled else { return }
        if Self.denied(error) { post = nil; replies = []; draft = ""; self.error = "This post is no longer available." }
        else { self.error = "Couldn’t refresh this post. Try again." }
      }
    }
    flight = task; await task.value; flight = nil
    if post != nil { await loadReplies(reset: true, force: force) }
  }
  func loadReplies(reset: Bool, force: Bool = false) async {
    guard valid, post != nil, !loadingReplies, reset || nextCursor != nil else { return }
    if reset, !force, let replyLoadedAt, Date().timeIntervalSince(replyLoadedAt) < 30 { return }
    loadingReplies = true; replyError = nil
    defer { loadingReplies = false }
    do {
      var path = "/tea/conversations/\(id)/replies"
      if !reset, let nextCursor { path += "?cursor=" + nextCursor }
      let page: CaptroTeaConversationPage<CaptroTeaReply> = try await api.getFresh(path)
      guard valid, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : replies.map(\.id))
      let unique = page.items.filter { seen.insert($0.id).inserted }
      replies = reset ? unique : replies + unique
      nextCursor = page.nextCursor; replyLoadedAt = Date()
    } catch {
      guard valid, !Task.isCancelled else { return }
      if Self.denied(error) { post = nil; replies = []; self.error = "This post is no longer available." }
      else { replyError = "Couldn’t load replies. Try again." }
    }
  }
  func follow() async {
    guard valid, !busy, let post else { return }
    busy = true; error = nil; defer { busy = false }
    struct Body: Encodable { let following: Bool }
    do {
      let updated: CaptroTeaConversation = try await api.put("/tea/conversations/\(id)/follow", body: Body(following: !post.following))
      guard valid, updated.id == id else { return }
      self.post = updated; loadedAt = Date()
    } catch { if valid { self.error = "Couldn’t update Follow. Try again."; loadedAt = nil } }
  }
  func sendReply() async {
    let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard valid, !busy, post != nil, !body.isEmpty, body.count <= 4000 else { return }
    if pendingReply != body { requestID = UUID().uuidString; pendingReply = body }
    busy = true; replyError = nil; defer { busy = false }
    struct Body: Encodable { let requestID, body: String }
    do {
      let reply: CaptroTeaReply = try await api.post("/tea/conversations/\(id)/replies", body: Body(requestID: requestID, body: body))
      guard valid else { return }
      // When older replies are paged, do not insert out of chronological order.
      if nextCursor == nil, !replies.contains(where: { $0.id == reply.id }) { replies.append(reply) }
      draft = ""; pendingReply = nil; replyLoadedAt = nil
    } catch { if valid { replyError = "Reply wasn’t confirmed. Retry to check or send it." } }
  }
  func updated(_ result: CaptroTeaConversation) {
    guard valid, result.id == id else { return }
    post = result; loadedAt = Date()
  }
  private static func denied(_ error: Error) -> Bool {
    switch error {
    case MIRAAPIError.server(let status, _, _), MIRAAPIError.badStatus(let status): return [401,403,404,410].contains(status)
    default: return false
    }
  }
}
