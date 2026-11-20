import Foundation

/// One in-memory list per account, owned by Captro's existing Tea store.
/// Freshness controls requests, not whether previously loaded content can render.
@MainActor final class CaptroTeaNotesListModel: ObservableObject {
  @Published private(set) var items: [CaptroTeaConversation]
  @Published private(set) var nextCursor: String?
  @Published private(set) var loading = false
  @Published private(set) var loaded: Bool
  @Published private(set) var error: String?
  @Published private(set) var revision = 0
  private(set) var receivedAt: Date?
  private unowned let api: MIRAAPIClient
  private var scope: String
  private var flight: Task<Void, Never>?
  private var flightID: UUID?
  private var failedReset = true
  static let freshness: TimeInterval = 120

  init(api: MIRAAPIClient, cached: CaptroTeaConversationStore.Listing?) {
    self.api = api; scope = api.presentationScope
    items = cached?.items ?? []; nextCursor = cached?.cursor
    receivedAt = cached?.receivedAt; loaded = cached != nil
  }
  func clear() {
    flight?.cancel(); flight = nil; flightID = nil; revision += 1
    items = []; nextCursor = nil; receivedAt = nil; loaded = false; loading = false; error = nil
    scope = api.presentationScope
  }
  func update(_ post: CaptroTeaConversation, insert: Bool = false) {
    guard scope == api.presentationScope else { return }
    if let index = items.firstIndex(where: { $0.id == post.id }) { items[index] = post }
    else if insert { items.insert(post, at: 0) }
    save()
  }
  private func save() {
    guard scope == api.presentationScope, let receivedAt else { return }
    api.teaConversations.saveListing(items, cursor: nextCursor, receivedAt: receivedAt)
  }
  func retry() async { await load(reset: failedReset || nextCursor == nil, force: true) }
  func load(reset: Bool, force: Bool = false) async {
    if scope != api.presentationScope { clear() }
    if let flight { await flight.value; return }
    guard reset || nextCursor != nil else { return }
    if reset, !force, let receivedAt, Date().timeIntervalSince(receivedAt) < Self.freshness { return }
    let token = UUID(), owner = scope, expectedRevision = revision
    let started = Date(), count = items.count, tail = items.last?.id
    flightID = token
    let task = Task { [weak self] in
      guard let self else { return }
      loading = true; error = nil
      defer { if flightID == token { loading = false } }
      do {
        let path = "/tea/conversations" + (!reset && nextCursor != nil ? "?cursor=" + nextCursor! : "")
        var page: CaptroTeaConversationPage<CaptroTeaConversation> = try await api.getFresh(path)
        var refreshed = page.items, cursors = Set<String>()
        // Revalidate the loaded range before replacing anything, including a
        // page beyond that range when a removed tail no longer exists.
        while reset, let cursor = page.nextCursor,
          refreshed.count < count || (tail != nil && !refreshed.contains { $0.id == tail } && cursors.count < (count + 19) / 20) {
          guard flightID == token, owner == api.presentationScope, revision == expectedRevision else { return }
          try Task.checkCancellation()
          guard Date().timeIntervalSince(started) < 30 else { throw URLError(.timedOut) }
          guard cursors.insert(cursor).inserted, cursors.count <= 64 else { throw MIRAAPIError.decodingFailed }
          page = try await api.getFresh("/tea/conversations?cursor=" + cursor)
          refreshed += page.items
        }
        guard flightID == token, owner == api.presentationScope, revision == expectedRevision, !Task.isCancelled else { return }
        var seen = Set(reset ? [] : items.map(\.id))
        let existing = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unique = refreshed.filter { seen.insert($0.id).inserted }.map { incoming in
          if let current = existing[incoming.id], current.version > incoming.version { return current }
          return incoming
        }
        if reset { api.teaConversations.listViewport.preserveForContentRefresh(survivingIDs: Set(unique.map(\.id))) }
        items = reset ? unique : items + unique
        nextCursor = page.nextCursor; receivedAt = Date(); loaded = true
        for post in unique { api.teaConversations.signal(for: post).hydrate(post.interest, readStartedAt: started) }
        save()
      } catch {
        guard flightID == token, owner == api.presentationScope, revision == expectedRevision,
              !Task.isCancelled, !CaptroRefreshFailure.isCancellation(error) else { return }
        failedReset = reset
        if case MIRAAPIError.server(400, "TEA_DISCUSSION_INVALID", _) = error { nextCursor = nil; receivedAt = nil }
        if case MIRAAPIError.server(let status, _, _) = error, [401,403,410].contains(status) {
          items = []; nextCursor = nil; receivedAt = Date(); loaded = false
          save()
        }
        self.error = CaptroRefreshFailure.message(error, content: "Notes", cached: !items.isEmpty)
      }
    }
    flight = task; await task.value
    if flightID == token { flight = nil; flightID = nil }
  }
}

struct CaptroTeaInsights: Decodable {
  let uniqueOpens: Int
  let interested: Int
  let replies: Int
}
struct CaptroTeaInterestPayload: Codable {
  let interest: String?
  enum CodingKeys: String, CodingKey { case interest }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(interest, forKey: .interest) // Explicit null means undo.
  }
}

/// Feed and detail observe the same private selection; no public score exists.
@MainActor final class CaptroTeaNoteSignal: ObservableObject {
  @Published private(set) var interest: String?
  @Published private(set) var busy = false
  @Published private(set) var error: String?
  @Published private(set) var insights: CaptroTeaInsights?
  @Published private(set) var insightsError: String?
  @Published private(set) var loadingInsights = false
  private unowned let api: MIRAAPIClient
  let id: String
  private let scope: String
  private var invalidated = false
  private var mutationStarted = Date.distantPast
  private var pending: CaptroTeaInterestPayload?
  private var didOpen = false
  private var opening = false
  private var insightsAt: Date?
  init(post: CaptroTeaConversation, api: MIRAAPIClient) {
    id = post.id; interest = post.interest; self.api = api; scope = api.presentationScope
  }
  var valid: Bool { !invalidated && scope == api.presentationScope }
  func clear() { invalidated = true; interest = nil; insights = nil; pending = nil; error = nil; insightsError = nil }
  func hydrate(_ value: String?, readStartedAt: Date) {
    guard valid, !busy, pending == nil, readStartedAt >= mutationStarted else { return }
    interest = value
  }
  func choose(_ value: String) async {
    guard valid, !busy, ["interested", "pass"].contains(value) else { return }
    // A retry reconciles its original absolute value before accepting another
    // intent. Repeating a request cannot toggle it a second time on the server.
    let payload = pending ?? CaptroTeaInterestPayload(interest: interest == value ? nil : value)
    pending = payload; busy = true; error = nil; mutationStarted = Date()
    defer { busy = false }
    do {
      let response: CaptroTeaInterestPayload = try await api.put("/tea/conversations/" + id + "/interest", body: payload)
      guard valid else { return }
      interest = response.interest; pending = nil; mutationStarted = Date(); insightsAt = nil
      if insights != nil { await loadInsights(force: true) }
    } catch {
      guard valid else { return }
      if case MIRAAPIError.server(let status, _, _) = error, [400,401,403,404].contains(status) { pending = nil }
      self.error = "Couldn’t save your choice. Tap again to retry."
    }
  }
  func opened(isAuthor: Bool, authenticated: Bool) async {
    guard valid, authenticated else { return }
    if isAuthor { await loadInsights(); return }
    guard !didOpen, !opening else { return }
    opening = true; defer { opening = false }
    struct Receipt: Decodable { let confirmed: Bool }
    do {
      let result: Receipt = try await api.post("/tea/conversations/" + id + "/open", body: [String: String]())
      if valid { didOpen = result.confirmed }
    } catch { /* Retry only on another actual detail opening. Never from a row. */ }
  }
  func loadInsights(force: Bool = false) async {
    guard valid, !loadingInsights else { return }
    if !force, let insightsAt, Date().timeIntervalSince(insightsAt) < 60 { return }
    loadingInsights = true; insightsError = nil; defer { loadingInsights = false }
    do {
      let value: CaptroTeaInsights = try await api.getFresh("/tea/conversations/" + id + "/insights")
      guard valid else { return }; insights = value; insightsAt = Date()
    } catch {
      guard valid else { return }
      if case MIRAAPIError.server(let status, _, _) = error, [401,403,404].contains(status) { insights = nil }
      insightsError = "Couldn’t load private Insights."
    }
  }
}
