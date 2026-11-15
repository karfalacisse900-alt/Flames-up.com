import Foundation

@MainActor final class CaptroTeaClubStore {
  private unowned let api: MIRAAPIClient
  private var scope = ""
  private var models: [String: CaptroTeaClubModel] = [:]
  private var order: [String] = []
  init(api: MIRAAPIClient) { self.api = api }
  func model(_ id: String) -> CaptroTeaClubModel {
    if scope != api.presentationScope { invalidate(); scope = api.presentationScope }
    if let model = models[id], model.valid { return model }
    let model = CaptroTeaClubModel(id: id, api: api)
    models[id] = model; order.append(id)
    if order.count > 12 { models.removeValue(forKey: order.removeFirst())?.clear() }
    return model
  }
  func invalidate() { models.values.forEach { $0.clear() }; models = [:]; order = [] }
}

@MainActor final class CaptroTeaClubModel: ObservableObject {
  struct Messages {
    var items: [CaptroClubMessage] = []
    var cursor: String?
    var date: Date?
  }
  let id: String
  private unowned let api: MIRAAPIClient
  private let scope: String
  @Published var club: CaptroTeaClub?
  @Published var denied = false
  @Published var error: String?
  @Published var actionError: String?
  @Published var loading = false
  @Published var busy = false
  @Published var room: String?
  @Published var tab = "Chat"
  @Published var pages: [String: Messages] = [:]
  @Published var drafts: [String: String] = [:]
  @Published var quotes: [String: CaptroClubQuote] = [:]
  @Published var links: [CaptroClubLink] = []
  @Published var linkCursor: String?
  @Published var linksLoaded = false
  @Published var linksError: String?
  @Published var loadingLinks = false
  @Published var pending: [String: CaptroClubAction] = [:]
  @Published var focusedHistory: Set<String> = []
  var scrollIDs: [String: String] = [:]
  private var loadedAt: Date?
  private var flight: Task<Void, Never>?
  private var messageFlights: [String: UUID] = [:]
  private var readCandidate: [String: CaptroClubMessage] = [:]
  private var readTasks: [String: Task<Void, Never>] = [:]
  private var readThrough: [String: String] = [:]
  private var revision = 0
  private var invalidated = false
  init(id: String, api: MIRAAPIClient) { self.id = id; self.api = api; scope = api.presentationScope }
  var key: String { room ?? "general" }
  var messages: [CaptroClubMessage] { pages[key]?.items ?? [] }
  var readOnly: Bool { club?.rooms.first { $0.id == room }?.announcements == true && club?.canManage != true }
  var valid: Bool { !invalidated && scope == api.presentationScope }
  var base: String { "/tea/clubs/" + id }
  func clear() {
    invalidated = true; revision += 1; flight?.cancel(); flight = nil
    club = nil; pages = [:]; drafts = [:]; quotes = [:]; links = []; pending = [:]; scrollIDs = [:]; focusedHistory = []; messageFlights = [:]
    loadedAt = nil; linksLoaded = false; denied = true
    readTasks.values.forEach { $0.cancel() }; readTasks = [:]; readCandidate = [:]; readThrough = [:]
  }
  func load(force: Bool = false) async {
    guard valid else { return }
    if let flight { await flight.value; return }
    if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 15 { return }
    let expected = revision
    let task = Task { [weak self] in
      guard let self else { return }; loading = true
      defer { loading = false }
      do {
        let result: CaptroTeaClub = try await api.getFresh(base)
        guard valid, expected == revision, !Task.isCancelled, result.id == id else { return }
        club = result; denied = false; error = nil; loadedAt = Date()
      } catch { handle(error, expected: expected) }
    }
    flight = task; await task.value; flight = nil
  }
  func loadMessages(older: Bool = false, force: Bool = false, through: String? = nil, latest: Bool = false) async {
    let selected = room, roomKey = key, expected = revision
    guard valid, club != nil else { return }
    if through == nil, !latest, messageFlights[roomKey] != nil { return }
    if through == nil, !older, !latest, focusedHistory.contains(roomKey) { return }
    let previous = pages[roomKey]
    if older && previous?.cursor == nil { return }
    if through == nil, !latest, !older, !force, let date = previous?.date, Date().timeIntervalSince(date) < 5 { return }
    let token = UUID(); messageFlights[roomKey] = token
    defer { if messageFlights[roomKey] == token { messageFlights[roomKey] = nil } }
    do {
      var parts = URLComponents(); parts.path = base + "/messages"
      var query: [URLQueryItem] = []
      if let selected { query.append(.init(name: "room", value: selected)) }
      if let through { query.append(.init(name: "through", value: through)) }
      if older, let cursor = previous?.cursor { query.append(.init(name: "cursor", value: cursor)) }
      parts.queryItems = query.isEmpty ? nil : query
      let page: CaptroTeaConversationPage<CaptroClubMessage> = try await api.getFresh(parts.string!)
      guard valid, expected == revision, messageFlights[roomKey] == token, !Task.isCancelled else { return }
      let prior = pages[roomKey]?.items ?? []
      var combined: [CaptroClubMessage]
      if through != nil || latest { combined = page.items }
      else if older { combined = page.items + prior }
      else if page.nextCursor != nil, let first = page.items.first {
        combined = prior.filter { ($0.createdAt, $0.id) < (first.createdAt, first.id) } + page.items
      } else { combined = page.items }
      var seen = Set<String>(); combined = combined.filter { seen.insert($0.id).inserted }
      pages[roomKey] = Messages(items: combined, cursor: older || through != nil || latest ? page.nextCursor : (prior.count > 50 ? previous?.cursor : page.nextCursor), date: Date())
      if through != nil { focusedHistory.insert(roomKey) }
      if latest { focusedHistory.remove(roomKey) }
      error = nil
    } catch { if messageFlights[roomKey] == token { handle(error, expected: expected) } }
  }
  func markRead(_ message: CaptroClubMessage) async {
    guard valid, tab == "Chat", message.room == room else { return }
    let roomKey = key
    guard message.createdAt > (readThrough[roomKey] ?? "") else { return }
    if message.createdAt >= (readCandidate[roomKey]?.createdAt ?? "") { readCandidate[roomKey] = message }
    guard readTasks[roomKey] == nil else { return }
    readTasks[roomKey] = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
      guard let self, valid, let candidate = readCandidate.removeValue(forKey: roomKey) else { return }
      defer { readTasks[roomKey] = nil }
      do {
        let _: EmptyResponse = try await api.post(base + "/read", body: CaptroClubAction(room: candidate.room, message: candidate.id))
        if valid { readThrough[roomKey] = candidate.createdAt }
      } catch { if Self.accessDenied(error) { clear() } }
    }
  }
  func loadLinks(more: Bool = false, force: Bool = false) async {
    guard valid, !loadingLinks, !more || linkCursor != nil else { return }
    if !more, linksLoaded, !force { return }
    loadingLinks = true; linksError = nil; let expected = revision
    defer { loadingLinks = false }
    do {
      let page: CaptroTeaConversationPage<CaptroClubLink> = try await api.getFresh(base + "/links" + (more ? "?cursor=" + (linkCursor ?? "") : ""))
      guard valid, revision == expected else { return }
      var seen = Set(more ? links.map(\.id) : [])
      links = (more ? links : []) + page.items.filter { seen.insert($0.id).inserted }
      linkCursor = page.nextCursor; linksLoaded = true
    } catch { if Self.accessDenied(error) { clear() } else { linksError = "Couldn’t load saved links. Try again." } }
  }
  func send() async {
    let roomKey = key, selected = room
    let body = drafts[roomKey, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    guard valid, !busy, !readOnly, !body.isEmpty, body.count <= 2000 else { return }
    let action = pending[roomKey] ?? CaptroClubAction(id: UUID().uuidString, body: body, room: selected, quote: quotes[roomKey]?.id)
    pending[roomKey] = action; busy = true; actionError = nil; let expected = revision
    defer { busy = false }
    do {
      let message: CaptroClubMessage = try await api.post(base + "/send", body: action)
      guard valid, revision == expected else { return }
      if pages[roomKey] == nil { pages[roomKey] = Messages() }
      if pages[roomKey]?.items.contains(where: { $0.id == message.id }) != true { pages[roomKey]?.items.append(message) }
      drafts[roomKey] = ""; quotes[roomKey] = nil; pending[roomKey] = nil
      if focusedHistory.contains(roomKey), key == roomKey { await loadMessages(latest: true) }
    } catch {
      if Self.accessDenied(error) { clear() }
      else {
        if case MIRAAPIError.server(let status, _, _) = error, [400,409].contains(status) { pending[roomKey] = nil }
        actionError = "Message wasn’t confirmed. Retry checks the same message; your draft is saved."
      }
    }
  }
  func perform(_ action: String, _ data: CaptroClubAction) async throws {
    guard valid else { throw MIRAAPIError.badStatus(403) }
    let expected = revision
    do {
      let _: EmptyResponse = try await api.post(base + "/" + action, body: data)
      guard valid, revision == expected else { throw CancellationError() }
      loadedAt = nil
      await load(force: true)
      if ["saveLink", "editLink", "removeLink"].contains(action) { await loadLinks(force: true) }
    } catch { if Self.accessDenied(error) { clear() }; throw error }
  }
  func message(_ reference: CaptroClubQuote) async throws -> CaptroClubMessage {
    let result: CaptroClubMessage = try await api.getFresh(base + "/messages/" + reference.id)
    guard valid else { throw CancellationError() }
    return result
  }
  private func handle(_ error: Error, expected: Int) {
    guard valid, revision == expected, !Task.isCancelled else { return }
    if Self.accessDenied(error) { clear() }
    else { self.error = "Couldn’t refresh this club. Try again." }
  }
  private static func accessDenied(_ error: Error) -> Bool {
    switch error {
    case MIRAAPIError.server(let status, _, _), MIRAAPIError.badStatus(let status): return [401,403,404,410].contains(status)
    default: return false
    }
  }
}
