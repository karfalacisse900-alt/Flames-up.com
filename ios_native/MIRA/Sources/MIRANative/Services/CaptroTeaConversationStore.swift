import Foundation

extension Notification.Name {
  static let captroTeaConversationChanged = Notification.Name("captro.tea.conversation.changed")
  static let captroTeaAccessChanged = Notification.Name("captro.tea.access.changed")
}

/// Presentation state owned by the existing API client. Nothing is stored in a
/// global or disk cache, and the auth/session generation is checked after awaits.
@MainActor final class CaptroTeaConversationStore {
  private unowned let api: MIRAAPIClient
  private var scope = ""
  private var models: [String: CaptroTeaConversationModel] = [:]
  private var order: [String] = []
  init(api: MIRAAPIClient) { self.api = api }
  func model(for post: CaptroTeaConversation) -> CaptroTeaConversationModel {
    if scope != api.presentationScope {
      if !scope.isEmpty { invalidate() }
      scope = api.presentationScope
    }
    if let model = models[post.id] { return model }
    let model = CaptroTeaConversationModel(post: post, api: api)
    models[post.id] = model; order.append(post.id)
    if order.count > 24 { models[order.removeFirst()] = nil }
    return model
  }
  func invalidate() {
    for model in models.values { model.clear() }
    models.removeAll(); order.removeAll()
    NotificationCenter.default.post(name: .captroTeaAccessChanged, object: nil)
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
  @Published private(set) var replyPending = false
  @Published var nextCursor: String?
  private unowned let api: MIRAAPIClient
  private let scope: String
  let id: String
  private var loadedAt: Date?
  private var replyLoadedAt: Date?
  private var requestID = UUID().uuidString
  private var pendingReply: String?
  private var flight: Task<Void, Never>?
  private var invalidated = false
  private var revision = 0

  init(post: CaptroTeaConversation, api: MIRAAPIClient) {
    self.post = post; self.id = post.id; self.api = api; scope = api.presentationScope
  }
  var valid: Bool { !invalidated && scope == api.presentationScope }
  func clear() {
    invalidated = true; revision += 1
    flight?.cancel(); flight = nil; post = nil; replies = []; draft = ""; loadedAt = nil; replyLoadedAt = nil
    pendingReply = nil; replyPending = false; requestID = UUID().uuidString; nextCursor = nil
    error = "Refresh this post to check access."
  }
  func load(force: Bool = false) async {
    guard scope == api.presentationScope else { clear(); return }
    invalidated = false
    if let flight { await flight.value; return }
    if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 30 { return }
    let expectedRevision = revision
    let task = Task { [weak self] in
      guard let self else { return }
      loading = true; error = nil
      defer { loading = false }
      do {
        let result: CaptroTeaConversation = try await api.getFresh("/tea/conversations/" + id)
        guard valid, revision == expectedRevision, !Task.isCancelled else { return }
        guard result.id == id else { throw MIRAAPIError.decodingFailed }
        post = result; loadedAt = Date()
      } catch {
        guard valid, revision == expectedRevision, !Task.isCancelled else { return }
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
    let expectedRevision = revision
    defer { loadingReplies = false }
    do {
      var path = "/tea/conversations/\(id)/replies"
      if !reset, let nextCursor { path += "?cursor=" + nextCursor }
      let page: CaptroTeaConversationPage<CaptroTeaReply> = try await api.getFresh(path)
      guard valid, revision == expectedRevision, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : replies.map(\.id))
      let unique = page.items.filter { seen.insert($0.id).inserted }
      replies = reset ? unique : replies + unique
      nextCursor = page.nextCursor; replyLoadedAt = Date()
    } catch {
      guard valid, revision == expectedRevision, !Task.isCancelled else { return }
      if Self.denied(error) { post = nil; replies = []; self.error = "This post is no longer available." }
      else { replyError = "Couldn’t load replies. Try again." }
    }
  }
  func follow() async {
    guard valid, !busy, let post else { return }
    busy = true; error = nil; defer { busy = false }
    let expectedRevision = revision
    struct Body: Encodable { let following: Bool }
    do {
      let updated: CaptroTeaConversation = try await api.put("/tea/conversations/\(id)/follow", body: Body(following: !post.following))
      guard valid, revision == expectedRevision, updated.id == id else { return }
      self.updated(updated)
    } catch { if valid { self.error = "Couldn’t update Follow. Try again."; loadedAt = nil } }
  }
  func sendReply() async {
    let body = pendingReply ?? draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard valid, !busy, post != nil, !body.isEmpty, body.count <= 4000 else { return }
    if pendingReply != body { requestID = UUID().uuidString; pendingReply = body }
    replyPending = true
    let expectedRevision = revision
    busy = true; replyError = nil; defer { busy = false }
    struct Body: Encodable { let requestID, body: String }
    do {
      let reply: CaptroTeaReply = try await api.post("/tea/conversations/\(id)/replies", body: Body(requestID: requestID, body: body))
      guard valid, revision == expectedRevision else { return }
      // When older replies are paged, do not insert out of chronological order.
      if nextCursor == nil, !replies.contains(where: { $0.id == reply.id }) { replies.append(reply) }
      draft = ""; pendingReply = nil; replyPending = false; replyLoadedAt = nil
    } catch {
      guard valid else { return }
      if case MIRAAPIError.server(let status, _, let detail) = error, [400,403,404,409].contains(status) {
        pendingReply = nil; replyPending = false
        replyError = detail ?? "Couldn’t send this reply. Check the post and try again."
      } else { replyError = "Reply wasn’t confirmed. Retry to check or send the same reply." }
    }
  }
  func updated(_ result: CaptroTeaConversation) {
    guard valid, result.id == id else { return }
    revision += 1; post = result; loadedAt = Date()
    NotificationCenter.default.post(name: .captroTeaConversationChanged, object: result, userInfo: ["scope": scope])
  }
  private static func denied(_ error: Error) -> Bool {
    switch error {
    case MIRAAPIError.server(let status, _, _), MIRAAPIError.badStatus(let status): return [401,403,404,410].contains(status)
    default: return false
    }
  }
}
