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
  @Published var replyTarget: CaptroTeaReplyTarget?
  @Published var expandedTargets: Set<String> = []
  @Published var authorProfile: MIRAUser?
  @Published var authorError: String?
  @Published var followingAuthor = false
  @Published private(set) var replyPending = false
  @Published private(set) var replySubmissionFailed = false
  @Published var nextCursor: String?
  private unowned let api: MIRAAPIClient
  private let scope: String
  let id: String
  private var loadedAt: Date?
  private var replyLoadedAt: Date?
  private var requestID = UUID().uuidString
  private var pendingReply: String?
  private var pendingTarget: CaptroTeaReplyTarget?
  private var flight: Task<Void, Never>?
  private var flightID: UUID?
  private var invalidated = false
  private var revision = 0
  private var accessRevision = 0

  init(post: CaptroTeaConversation, api: MIRAAPIClient) {
    self.post = post; self.id = post.id; self.api = api; scope = api.presentationScope
  }
  var valid: Bool { !invalidated && scope == api.presentationScope }
  func clear() {
    invalidated = true; revision += 1; accessRevision += 1
    flight?.cancel(); flight = nil; flightID = nil; post = nil; replies = []; draft = ""; loadedAt = nil; replyLoadedAt = nil
    pendingReply = nil; replyPending = false; requestID = UUID().uuidString; nextCursor = nil
    replyTarget = nil; pendingTarget = nil; expandedTargets = []; authorProfile = nil
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
        if Self.denied(error) { clear(); self.error = "This post is no longer available." }
        else { self.error = "Couldn’t refresh this post. Try again." }
      }
    }
    let token = UUID()
    flightID = token; flight = task; await task.value
    if flightID == token { flight = nil; flightID = nil }
    if post != nil {
      async let replies: Void = loadReplies(reset: true, force: force)
      async let author: Void = loadAuthor()
      _ = await (replies, author)
    }
  }
  func loadReplies(reset: Bool, force: Bool = false) async {
    guard valid, post != nil, !loadingReplies, reset || nextCursor != nil else { return }
    if reset, !force, let replyLoadedAt, Date().timeIntervalSince(replyLoadedAt) < 30 { return }
    loadingReplies = true; replyError = nil; replySubmissionFailed = false
    let expectedAccess = accessRevision
    defer { loadingReplies = false }
    do {
      var path = "/tea/conversations/\(id)/replies"
      if !reset, let nextCursor { path += "?cursor=" + nextCursor }
      let page: CaptroTeaConversationPage<CaptroTeaReply> = try await api.getFresh(path)
      guard valid, accessRevision == expectedAccess, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : replies.map(\.id))
      let unique = page.items.filter { seen.insert($0.id).inserted }
      replies = reset ? unique : replies + unique
      nextCursor = page.nextCursor; replyLoadedAt = Date()
    } catch {
      guard valid, accessRevision == expectedAccess, !Task.isCancelled else { return }
      if Self.denied(error) { clear(); self.error = "This post is no longer available." }
      else if case MIRAAPIError.server(400, "TEA_DISCUSSION_INVALID", _) = error {
        nextCursor = nil; replyLoadedAt = nil; replyError = "Refresh replies to continue."
      }
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
    if pendingReply == nil { requestID = UUID().uuidString; pendingReply = body; pendingTarget = replyTarget }
    replyPending = true
    let expectedAccess = accessRevision
    busy = true; replyError = nil; replySubmissionFailed = false; defer { busy = false }
    struct Body: Encodable { let requestID, body: String; let target: CaptroTeaReplyTarget? }
    do {
      let reply: CaptroTeaReply = try await api.post("/tea/conversations/\(id)/replies", body: Body(requestID: requestID, body: body, target: pendingTarget))
      guard valid, accessRevision == expectedAccess else { return }
      let wasKnown = replies.contains { $0.id == reply.id }
      // When older replies are paged, do not insert out of chronological order.
      if nextCursor == nil, !replies.contains(where: { $0.id == reply.id }) { replies.append(reply) }
      draft = ""; pendingReply = nil; replyPending = false; replyLoadedAt = nil
      if let target = pendingTarget { expandedTargets.insert(target.id) }
      if !wasKnown {
        post?.replyCount = (post?.replyCount ?? max(0, replies.count - 1)) + 1
        if let target = reply.target {
          var counts = post?.replyTargets ?? []
          let old = counts.first { $0.target.id == target.id }?.count ?? 0
          counts.removeAll { $0.target.id == target.id }
          counts.append(CaptroTeaReplyCount(target: target, count: old + 1)); post?.replyTargets = counts
        }
      }
      replyTarget = nil; pendingTarget = nil; loadedAt = nil
    } catch {
      guard valid, accessRevision == expectedAccess else { return }
      replySubmissionFailed = true
      if case MIRAAPIError.server(let status, _, let detail) = error, [400,403,404,409].contains(status) {
        pendingReply = nil; pendingTarget = nil; replyPending = false
        replyError = detail ?? "Couldn’t send this reply. Check the post and try again."
      } else { replyError = "Reply wasn’t confirmed. Retry to check or send the same reply." }
    }
  }
  func selectTarget(_ target: CaptroTeaReplyTarget?) {
    guard !busy, !replyPending else { return }
    replyTarget = target
  }
  func loadAuthor() async {
    guard valid, let author = post?.author.id else { return }
    do {
      let user: MIRAUser = try await api.getFresh("/users/" + author)
      guard valid, post?.author.id == user.id else { return }
      authorProfile = user; authorError = nil
    } catch { if valid { authorError = "Couldn’t refresh this profile." } }
  }
  func followAuthor() async {
    guard valid, !followingAuthor, let author = post?.author.id, post?.isAuthor != true else { return }
    followingAuthor = true; defer { followingAuthor = false }
    if authorProfile == nil { await loadAuthor() }
    guard let user = authorProfile, user.viewerHasBlocked != true, user.viewerBlockedBy != true else { return }
    do {
      let result: FollowResponse = try await api.post("/users/" + author + "/follow", body: FollowBody(following: !(user.viewerFollowing || user.followPending == true)))
      guard valid else { return }
      MIRAUserFollowSync.publish(MIRAUserFollowUpdate(userId: author, following: result.following == true, followersCount: result.followersCount))
      await loadAuthor()
      await load(force: true)
    } catch { if valid { await loadAuthor(); authorError = "Couldn’t confirm the follow change. Refresh and try again." } }
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
