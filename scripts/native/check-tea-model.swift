// Host-only adapters for network, UIKit viewport and follow integrations.
// The production Tea model and its Codable types are compiled unchanged.
// These fixtures do NOT test rendering, authentication or backend permissions.
@_exported import Combine
import Foundation

@MainActor final class CaptroFeedViewport {
  func select(_ value: String) {}
  func updateOrder(_ values: [String]) {}
  func setActive(_ value: Bool) {}
}
enum MIRAAPIError: Error { case server(Int, String?, String?), badStatus(Int), decodingFailed }
struct MIRAUser: Decodable {
  let id: String
  var viewerHasBlocked: Bool? = nil, viewerBlockedBy: Bool? = nil, followPending: Bool? = nil
  var viewerFollowing = false
}
struct FollowBody: Encodable { let following: Bool }
struct FollowResponse: Decodable { let following: Bool?; let followersCount: Int? }
struct MIRAUserFollowUpdate { let userId: String; let following: Bool; var followersCount: Int? = nil }
enum MIRAUserFollowSync { static func publish(_ value: MIRAUserFollowUpdate) {} }
struct CaptroProfileLink { static func parse(_ url: URL) -> Self? { nil } }
enum MIRAApplePerformanceLogger {
  struct Interval { func end(status: String?) {} }
  static func beginInterval(_ name: String) -> Interval { Interval() }
}
@MainActor final class MIRAAPIClient {
  var presentationScope = "fixture-a"
  var reads: [String: Int] = [:]
  var failReplies = true
  var deny = false
  var sentIDs: [String] = []
  var failSend = true
  let seed = CaptroTeaConversation(id: "post", title: "A real seed title", body: "Caption from the list.", links: [],
    author: CaptroTeaAuthor(id: "author", name: "Author", username: "author"), createdAt: "2026-11-15T12:00:00Z", version: 1, isAuthor: false, following: false)
  lazy var teaConversations = CaptroTeaConversationStore(api: self)
  func getFresh<T: Decodable>(_ path: String) async throws -> T {
    reads[path, default: 0] += 1
    await Task.yield()
    if deny { throw MIRAAPIError.badStatus(403) }
    let data: Data
    if path.contains("/replies") {
      if failReplies { failReplies = false; throw URLError(.notConnectedToInternet) }
      data = Data(#"{"items":[{"id":"reply","body":"Existing reply","author":{"id":"reader","name":"Reader","username":"reader"},"createdAt":"2026-11-15T12:00:01Z"}]}"#.utf8)
    } else if path.hasPrefix("/users/") {
      data = Data(#"{"id":"author","viewerFollowing":false}"#.utf8)
    } else { data = try JSONEncoder().encode(seed) }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
    let id = json["requestID"] as? String ?? ""
    sentIDs.append(id)
    if failSend { failSend = false; throw URLError(.timedOut) }
    let response: [String: Any] = ["id": id, "body": json["body"] ?? "", "createdAt": "2026-11-15T12:00:02Z",
      "author": ["id":"viewer", "name":"Viewer", "username":"viewer"]]
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: response))
  }
  func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T { try await getFresh(path) }
}

@main struct TeaModelChecks {
  @MainActor static func main() async throws {
    var count = 0
    func check(_ name: String, _ condition: Bool) {
      guard condition else { print("FAIL: \(name)"); exit(1) }
      count += 1; print("PASS: \(name)")
    }
    let api = MIRAAPIClient()
    let model = api.teaConversations.model(for: api.seed)
    model.draft = "Keep the unfinished reply"
    check("Seed title and caption are immediately available", model.post?.title == api.seed.title && model.post?.body == api.seed.body)
    async let a: Void = model.load()
    async let b: Void = model.load()
    _ = await (a, b)
    check("Concurrent detail loads coalesce", api.reads["/tea/conversations/post"] == 1)
    check("Reply failure keeps the post and draft", model.replyError != nil && model.post != nil && model.draft == "Keep the unfinished reply")
    await model.load()
    check("Fresh post retries missing replies on reopen", model.replyError == nil && model.replies.first?.body == "Existing reply")
    let reads = api.reads
    await model.load()
    check("Fresh repeat open does not repeat API reads", api.reads == reads)
    check("Reopen reuses draft and model", api.teaConversations.model(for: api.seed) === model && model.draft == "Keep the unfinished reply")
    await model.sendReply()
    check("Uncertain send retains its pending content", model.replyPending && model.replySubmissionFailed && !model.draft.isEmpty)
    await model.sendReply()
    check("Retry uses one operation ID and credits one reply", api.sentIDs.count == 2 && api.sentIDs[0] == api.sentIDs[1] && !api.sentIDs[0].isEmpty && model.replies.filter { $0.id == api.sentIDs[0] }.count == 1)
    model.draft = "Private draft"
    api.presentationScope = "fixture-b"
    let other = api.teaConversations.model(for: api.seed)
    check("Account switch clears prior content and draft", other !== model && !model.valid && model.post == nil && model.draft.isEmpty)
    api.deny = true
    await other.load(force: true)
    check("Confirmed denial clears presentation", other.post == nil && other.replies.isEmpty && !other.valid)
    print("\(count) actual Tea model checks passed with host adapters; no app/device UI executed.")
  }
}
