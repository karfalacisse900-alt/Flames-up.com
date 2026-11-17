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
  private var applications: [String: CaptroTeaApplicationModel] = [:]
  struct Listing {
    let items: [CaptroTeaConversation]
    let cursor: String?
    let receivedAt: Date
  }
  private var listing: Listing?
  let listViewport = CaptroFeedViewport()
  init(api: MIRAAPIClient) { self.api = api }
  func cachedListing() -> Listing? {
    synchronizeScope()
    guard let listing, Date().timeIntervalSince(listing.receivedAt) < 600 else { return nil }
    return listing
  }
  func saveListing(_ items: [CaptroTeaConversation], cursor: String?, receivedAt: Date) {
    synchronizeScope()
    listing = Listing(items: items, cursor: cursor, receivedAt: receivedAt)
  }
  private func synchronizeScope() {
    if scope != api.presentationScope {
      if !scope.isEmpty { invalidate() }
      scope = api.presentationScope
    }
  }
  func model(for post: CaptroTeaConversation) -> CaptroTeaConversationModel {
    synchronizeScope()
    if let model = models[post.id] { return model }
    let model = CaptroTeaConversationModel(post: post, api: api)
    models[post.id] = model; order.append(post.id)
    if order.count > 24 { models[order.removeFirst()] = nil }
    return model
  }
  func invalidate() {
    for model in applications.values { model.clear() }
    applications.removeAll()
    for model in models.values { model.clear() }
    models.removeAll(); order.removeAll()
    listing = nil; listViewport.setActive(false)
    NotificationCenter.default.post(name: .captroTeaAccessChanged, object: nil)
  }
  func application(for note: CaptroTeaConversation) -> CaptroTeaApplicationModel {
    synchronizeScope()
    if let model = applications[note.id] { model.refresh(note); return model }
    let model = CaptroTeaApplicationModel(note: note, api: api)
    if applications.count >= 24, let key = applications.keys.first { applications.removeValue(forKey: key)?.clear() }
    applications[note.id] = model
    return model
  }
}

/// Private, account-scoped form drafts use the existing Tea store. An uncertain
/// write keeps its exact request identity and payload until reconciled.
@MainActor final class CaptroTeaApplicationModel: ObservableObject {
  @Published var note: CaptroTeaConversation
  @Published var fullName = ""
  @Published var availability = ""
  @Published var height = ""
  @Published var portfolio = ""
  @Published var busy = false
  @Published var confirmed = false
  @Published var error: String?
  @Published private(set) var pending: CaptroTeaApplicationPayload?
  private unowned let api: MIRAAPIClient
  private let scope: String
  private var invalidated = false
  private var requestID = UUID().uuidString
  init(note: CaptroTeaConversation, api: MIRAAPIClient) {
    self.note = note; self.api = api; scope = api.presentationScope; confirmed = note.applicationSubmitted == true
  }
  var validScope: Bool { !invalidated && api.presentationScope == scope }
  var validFields: Bool {
    !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fullName.count <= 100 &&
    !availability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && availability.count <= 1000 && height.count <= 40 &&
    (portfolio.isEmpty || CaptroTeaLink(portfolio) != nil)
  }
  func refresh(_ note: CaptroTeaConversation) {
    guard validScope, note.id == self.note.id else { return }
    self.note = note; confirmed = confirmed || note.applicationSubmitted == true
  }
  func clear() {
    invalidated = true; fullName = ""; availability = ""; height = ""; portfolio = ""; pending = nil
    confirmed = false; error = nil
  }
  func submit() async {
    guard validScope, !busy, !confirmed, pending != nil || validFields else { return }
    busy = true; error = nil; defer { busy = false }
    let payload = pending ?? CaptroTeaApplicationPayload(requestID: requestID, version: note.version,
      fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines), availability: availability.trimmingCharacters(in: .whitespacesAndNewlines),
      height: note.primaryAction?.heightRequested == true && !height.isEmpty ? height : nil, portfolio: portfolio.isEmpty ? nil : portfolio)
    pending = payload
    do {
      let receipt: CaptroTeaApplicationReceipt = try await api.post("/tea/conversations/" + note.id + "/applications", body: payload)
      guard validScope else { return }
      guard receipt.confirmed else { throw MIRAAPIError.decodingFailed }
      confirmed = true; pending = nil; fullName = ""; availability = ""; height = ""; portfolio = ""
      note.applicationSubmitted = true
      api.teaConversations.model(for: note).updated(note)
    } catch {
      guard validScope else { return }
      if case MIRAAPIError.server(let status, _, let message) = error, [400,401,403,404,409].contains(status) {
        pending = nil; self.error = message ?? "This application could not be submitted. Close and reopen the form to check its current status."
      } else { self.error = "Submission wasn’t confirmed. Retry checks the same application. Your draft is still here." }
    }
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
  @Published var threads: [String: [CaptroTeaReply]] = [:]
  @Published var threadCursors: [String: String] = [:]
  @Published var threadErrors: [String: String] = [:]
  @Published var loadingThreads: Set<String> = []
  @Published var authorProfile: MIRAUser?
  @Published var authorError: String?
  @Published var followingAuthor = false
  @Published private(set) var replyPending = false
  @Published private(set) var replySubmissionFailed = false
  @Published var nextCursor: String?
  private unowned let api: MIRAAPIClient
  private let scope: String
  let id: String
  let viewport = CaptroFeedViewport()
  private var loadedAt: Date?
  private var replyLoadedAt: Date?
  private var authorLoadedAt: Date?
  private var loadingAuthor = false
  private var threadLoadedAt: [String: Date] = [:]
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
    viewport.select("tea:" + post.id); viewport.updateOrder(["caption", "general"])
  }
  var valid: Bool { !invalidated && scope == api.presentationScope }
  func clear() {
    invalidated = true; revision += 1; accessRevision += 1
    viewport.setActive(false)
    flight?.cancel(); flight = nil; flightID = nil; post = nil; replies = []; draft = ""; loadedAt = nil; replyLoadedAt = nil
    pendingReply = nil; replyPending = false; requestID = UUID().uuidString; nextCursor = nil
    replyTarget = nil; pendingTarget = nil; expandedTargets = []; authorProfile = nil
    threads = [:]; threadCursors = [:]; threadErrors = [:]; loadingThreads = []
    authorLoadedAt = nil; threadLoadedAt = [:]
    error = "Refresh this post to check access."
  }
  func load(force: Bool = false) async {
    guard scope == api.presentationScope else { clear(); return }
    invalidated = false
    if let flight { await flight.value; return }
    if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 30 {
      // Post freshness is not evidence that replies or author metadata loaded.
      await loadSupplementary(force: false)
      return
    }
    let expectedRevision = revision
    let task = Task { [weak self] in
      guard let self else { return }
      loading = true; error = nil
      defer { loading = false }
      let interval = MIRAApplePerformanceLogger.beginInterval("tea_detail_read")
      defer { interval.end(status: valid ? "finished" : "discarded") }
      async let supplementary: Void = loadSupplementary(force: force)
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
      await supplementary
    }
    let token = UUID()
    flightID = token; flight = task; await task.value
    if flightID == token { flight = nil; flightID = nil }
  }
  private func loadSupplementary(force: Bool) async {
    if valid, post != nil {
      async let replies: Void = loadReplies(reset: true, force: force)
      async let author: Void = loadAuthor(force: force)
      _ = await (replies, author)
      for count in post?.replyTargets ?? [] where expandedTargets.contains(count.target.id) {
        if force || threadLoadedAt[count.target.id].map({ Date().timeIntervalSince($0) >= 30 }) != false {
          await loadThread(count.target, reset: true)
        }
      }
    }
  }
  func loadReplies(reset: Bool, force: Bool = false) async {
    guard valid, post != nil, !loadingReplies, reset || nextCursor != nil else { return }
    if reset, !force, let replyLoadedAt, Date().timeIntervalSince(replyLoadedAt) < 30 { return }
    loadingReplies = true
    if !replySubmissionFailed { replyError = nil }
    let expectedAccess = accessRevision
    defer { loadingReplies = false }
    do {
      var path = "/tea/conversations/\(id)/replies?target=general"
      if !reset, let nextCursor { path += "&cursor=" + nextCursor }
      var page: CaptroTeaConversationPage<CaptroTeaReply> = try await api.getFresh(path)
      var refreshed = page.items
      // Revalidate already displayed pages as one replacement. A first-page
      // refresh must not discard the history the reader has scrolled into.
      var cursors = Set<String>()
      while reset, refreshed.count < replies.count, let cursor = page.nextCursor,
            cursors.insert(cursor).inserted {
        guard cursors.count <= 16 else { throw MIRAAPIError.decodingFailed }
        guard valid, accessRevision == expectedAccess, !Task.isCancelled else { return }
        page = try await api.getFresh("/tea/conversations/\(id)/replies?target=general&cursor=" + cursor)
        refreshed += page.items
      }
      guard valid, accessRevision == expectedAccess, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : replies.map(\.id))
      let unique = refreshed.filter { seen.insert($0.id).inserted }
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
      let wasKnown = replies.contains { $0.id == reply.id } || threads.values.contains { $0.contains { $0.id == reply.id } }
      // When older replies are paged, do not insert out of chronological order.
      if let target = reply.target {
        if threads[target.id] != nil, threadCursors[target.id] == nil, !wasKnown { threads[target.id, default: []].append(reply) }
      } else if nextCursor == nil, !wasKnown { replies.append(reply) }
      draft = ""; pendingReply = nil; replyPending = false; replyLoadedAt = nil
      if let target = pendingTarget { expandedTargets.insert(target.id); await loadThread(target, reset: true) }
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
  func loadThread(_ target: CaptroTeaReplyTarget, reset: Bool = false) async {
    guard valid, !loadingThreads.contains(target.id) else { return }
    if !reset, threads[target.id] != nil, threadCursors[target.id] == nil { return }
    let expected = accessRevision
    loadingThreads.insert(target.id); threadErrors[target.id] = nil
    defer { loadingThreads.remove(target.id) }
    do {
      var path = "/tea/conversations/\(id)/replies?target=" + target.id
      if !reset, let cursor = threadCursors[target.id] { path += "&cursor=" + cursor }
      var page: CaptroTeaConversationPage<CaptroTeaReply> = try await api.getFresh(path)
      var refreshed = page.items
      var cursors = Set<String>()
      while reset, refreshed.count < (threads[target.id]?.count ?? 0), let cursor = page.nextCursor,
            cursors.insert(cursor).inserted {
        guard cursors.count <= 16 else { throw MIRAAPIError.decodingFailed }
        guard valid, expected == accessRevision, !Task.isCancelled else { return }
        page = try await api.getFresh("/tea/conversations/\(id)/replies?target=" + target.id + "&cursor=" + cursor)
        refreshed += page.items
      }
      guard valid, expected == accessRevision, !Task.isCancelled else { return }
      var seen = Set(reset ? [] : (threads[target.id] ?? []).map(\.id))
      threads[target.id] = (reset ? [] : threads[target.id] ?? []) + refreshed.filter { $0.target?.id == target.id && seen.insert($0.id).inserted }
      threadCursors[target.id] = page.nextCursor
      threadLoadedAt[target.id] = Date()
    } catch {
      guard valid, expected == accessRevision else { return }
      if Self.denied(error) { clear() }
      else { threadErrors[target.id] = "Couldn’t load these replies. Try again." }
    }
  }
  func loadAuthor(force: Bool = false) async {
    guard valid, !loadingAuthor, let author = post?.author.id else { return }
    if !force, let authorLoadedAt, Date().timeIntervalSince(authorLoadedAt) < 60 { return }
    loadingAuthor = true
    defer { loadingAuthor = false }
    do {
      let user: MIRAUser = try await api.getFresh("/users/" + author)
      guard valid, post?.author.id == user.id else { return }
      authorProfile = user; authorError = nil; authorLoadedAt = Date()
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
      await loadAuthor(force: true)
      await load(force: true)
    } catch { if valid { await loadAuthor(force: true); authorError = "Couldn’t confirm the follow change. Refresh and try again." } }
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
