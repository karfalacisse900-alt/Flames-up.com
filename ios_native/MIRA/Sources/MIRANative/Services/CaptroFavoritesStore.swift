import Foundation
import SwiftUI

struct CaptroFavoriteState: Codable, Equatable {
  var postId: String
  var saved: Bool
  var revision: Int
  var collectionIds: [String]
}
struct CaptroFavoriteCollection: Decodable, Identifiable {
  let id: String
  let name: String
  let count: Int
  var previews: [MIRAPost]?
}
struct CaptroFavoriteEntry: Decodable, Identifiable {
  let id: String
  let post: MIRAPost?
}
struct CaptroFavoritePage: Decodable {
  let collections: [CaptroFavoriteCollection]
  let entries: [CaptroFavoriteEntry]
  let hasMore: Bool
  let nextOffset: Int
}
private struct FavoriteResponse: Decodable {
  let state: CaptroFavoriteState?
  let collections: [CaptroFavoriteCollection]
}
private struct FavoriteWrite: Encodable {
  let saved: Bool
  let collectionIds: [String]
  let expectedRevision: Int
  let requestId: String
}

/// One account-scoped owner, shared by Home, Details and Me. No media or scroll state.
@MainActor final class CaptroFavoritesStore: ObservableObject {
  @Published private(set) var states: [String: CaptroFavoriteState] = [:]
  @Published private(set) var collections: [CaptroFavoriteCollection] = []
  @Published private(set) var busy: Set<String> = []
  @Published private(set) var accountID = ""
  @Published private(set) var notice: String?
  @Published private(set) var noticeAction: String?
  @Published private(set) var changeVersion = 0
  private unowned let api: MIRAAPIClient
  private var epoch = UUID()
  private var postVersions: [String: Int] = [:]
  private var reads: [String: UUID] = [:]
  private var collectionVersion = 0
  private var noticeTask: Task<Void, Never>?
  private var action: (() async -> Void)?
  init(api: MIRAAPIClient) { self.api = api }

  func configure(accountID: String) {
    guard self.accountID != accountID else { return }
    epoch = UUID(); self.accountID = accountID
    states = [:]; collections = []; busy = []; postVersions = [:]; reads = [:]; collectionVersion += 1; dismissNotice()
    changeVersion += 1
  }
  func isSaved(_ post: MIRAPost) -> Bool { states[post.id]?.saved ?? post.viewerSaved }
  func requireAccount() -> Bool {
    guard !accountID.isEmpty else { show("Sign in to use Favorites."); return false }
    return true
  }
  private func path(_ id: String) -> String {
    "/favorites/posts/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? id)
  }
  func loadState(postID: String) async throws -> CaptroFavoriteState {
    let generation = epoch
    let version = postVersions[postID, default: 0]
    let read = UUID(); reads[postID] = read
    guard requireAccount() else { throw CancellationError() }
    let response: FavoriteResponse = try await api.get(path(postID))
    guard generation == epoch, reads[postID] == read, version == postVersions[postID, default: 0],
          let state = response.state, state.postId == postID else { throw CancellationError() }
    if !busy.contains(postID) { states[postID] = state }
    return state
  }
  func page(collectionID: String? = nil, offset: Int = 0) async throws -> CaptroFavoritePage {
    let generation = epoch
    let version = collectionVersion
    guard requireAccount() else { throw CancellationError() }
    var query = "/favorites?offset=\(offset)"
    if let collectionID { query += "&collection_id=\(collectionID)" }
    let page: CaptroFavoritePage = try await api.get(query)
    guard generation == epoch, version == collectionVersion else { throw CancellationError() }
    collections = page.collections
    return page
  }
  func toggle(_ post: MIRAPost) async {
    guard requireAccount(), !busy.contains(post.id) else { return }
    let generation = epoch
    let shown = states[post.id] ?? CaptroFavoriteState(postId: post.id, saved: post.viewerSaved, revision: 0, collectionIds: [])
    let desired = !shown.saved
    postVersions[post.id, default: 0] += 1
    busy.insert(post.id)
    states[post.id] = CaptroFavoriteState(postId: post.id, saved: desired, revision: shown.revision, collectionIds: desired ? shown.collectionIds : [])
    CaptroHaptics.light()
    if desired { show("Saved to Favorites") }
    do {
      // Fetch memberships before unsaving, so Undo restores the complete server state.
      let previous = try await loadState(postID: post.id)
      guard generation == epoch else { return }
      // Hold the same lock across the read and write, including the async call
      // boundary. No rapid tap may start a second operation between them.
      _ = await write(previous: previous, saved: desired, ids: desired ? previous.collectionIds : [],
        requestID: UUID().uuidString, ownsBusy: true)
    } catch {
      guard generation == epoch else { return }
      states[post.id] = shown; busy.remove(post.id)
      show("Couldn’t update Favorites.", actionTitle: "Retry") { [weak self] in await self?.toggle(post) }
    }
  }
  func organize(previous: CaptroFavoriteState, collectionIDs: Set<String>) async -> Bool {
    guard collectionIDs.count <= 20 else { show("Choose up to 20 collections."); return false }
    return await write(previous: previous, saved: true, ids: Array(collectionIDs).sorted(), requestID: UUID().uuidString)
  }
  func remove(state: CaptroFavoriteState) async {
    _ = await write(previous: state, saved: false, ids: [], requestID: UUID().uuidString)
  }
  private func write(previous: CaptroFavoriteState, saved: Bool, ids: [String], requestID: String,
    ownsBusy: Bool = false) async -> Bool {
    guard requireAccount(), ownsBusy || !busy.contains(previous.postId) else { return false }
    let generation = epoch, postID = previous.postId
    postVersions[postID, default: 0] += 1
    collectionVersion += 1
    let collectionsAtStart = collectionVersion
    if !ownsBusy { busy.insert(postID) }
    states[postID] = CaptroFavoriteState(postId: postID, saved: saved, revision: previous.revision, collectionIds: ids)
    do {
      let result: FavoriteResponse = try await api.put(path(postID), body: FavoriteWrite(saved: saved,
        collectionIds: ids, expectedRevision: previous.revision, requestId: requestID))
      guard generation == epoch else { return false }
      guard let confirmed = result.state, confirmed.postId == postID else { throw MIRAAPIError.badStatus(502) }
      states[postID] = confirmed
      if collectionsAtStart == collectionVersion { collections = result.collections }
      busy.remove(postID); changeVersion += 1
      // Private save-only notification; never write a like/count from this response.
      MIRAPostEngagementSync.publish(.init(postId: postID, saved: confirmed.saved))
      if !saved && previous.saved {
        show("Removed from Favorites", actionTitle: "Undo") { [weak self] in
          _ = await self?.write(previous: confirmed, saved: true, ids: previous.collectionIds, requestID: UUID().uuidString)
        }
      } else { show("Saved to Favorites") }
      return true
    } catch {
      guard generation == epoch else { return false }
      states[postID] = previous; busy.remove(postID)
      if let apiError = error as? MIRAAPIError, case .server(status: 409, code: _, detail: _) = apiError {
        show("Favorites changed elsewhere. Reload before choosing again.", actionTitle: "Reload") { [weak self] in
          guard let self else { return }
          do {
            let fresh = try await self.loadState(postID: postID)
            MIRAPostEngagementSync.publish(.init(postId: postID, saved: fresh.saved))
            self.changeVersion += 1
          } catch { self.show("Couldn’t reload Favorites. Please try again.") }
        }
        return false
      }
      // Reuse the operation ID on retry: a lost response must not duplicate a write.
      show("Couldn’t update Favorites. Try again.", actionTitle: "Retry") { [weak self] in
        guard let self else { return }
        _ = await self.write(previous: previous, saved: saved, ids: ids, requestID: requestID)
      }
      return false
    }
  }
  func manageCollection(id: String? = nil, name: String? = nil) async throws {
    struct Name: Encodable { let name: String }
    let generation = epoch
    guard requireAccount() else { throw CancellationError() }
    collectionVersion += 1
    let version = collectionVersion
    let result: FavoriteResponse
    if let id, let name { result = try await api.put("/favorites/collections/\(id)", body: Name(name: name)) }
    else if let id { result = try await api.delete("/favorites/collections/\(id)") }
    else { result = try await api.post("/favorites/collections", body: Name(name: name ?? "")) }
    guard generation == epoch else { throw CancellationError() }
    if version == collectionVersion { collections = result.collections }
    if name == nil { states = [:] } // deleted memberships need fresh revisions before another edit
    changeVersion += 1
  }
  func runNoticeAction() async { let selected = action; dismissNotice(); await selected?() }
  func dismissNotice() { noticeTask?.cancel(); notice = nil; noticeAction = nil; action = nil }
  private func show(_ message: String, actionTitle: String? = nil, action: (() async -> Void)? = nil) {
    noticeTask?.cancel(); notice = message; noticeAction = actionTitle; self.action = action
    if actionTitle != "Retry" {
      noticeTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(actionTitle == nil ? 3 : 8))
        guard !Task.isCancelled else { return }; self?.dismissNotice()
      }
    }
  }
}
