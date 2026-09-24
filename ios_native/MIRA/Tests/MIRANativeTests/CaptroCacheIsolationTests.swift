import XCTest
@testable import MIRANative

final class CaptroCacheIsolationTests: XCTestCase {
  func testSnapshotsAreIsolatedByAccount() async {
    let key = "cache-isolation-\(UUID().uuidString)"
    let firstId = UUID().uuidString
    let secondId = UUID().uuidString
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }

    MIRALocalJSONCache.setAccountScope(userId: firstId)
    await MIRALocalJSONCache.save([1, 2, 3], key: key)
    let firstRead = await MIRALocalJSONCache.load([Int].self, key: key)
    XCTAssertEqual(firstRead, [1, 2, 3])

    MIRALocalJSONCache.setAccountScope(userId: secondId)
    let otherRead = await MIRALocalJSONCache.load([Int].self, key: key)
    XCTAssertNil(otherRead)
    await MIRALocalJSONCache.save([9], key: key)

    MIRALocalJSONCache.setAccountScope(userId: firstId)
    let restoredFirstRead = await MIRALocalJSONCache.load([Int].self, key: key)
    XCTAssertEqual(restoredFirstRead, [1, 2, 3])
    await MIRALocalJSONCache.remove(key: key)

    MIRALocalJSONCache.setAccountScope(userId: secondId)
    await MIRALocalJSONCache.remove(key: key)
  }

  func testClearingPostDraftDoesNotDeleteAnotherVoiceRecording() async throws {
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let directory = try XCTUnwrap(postDraftMediaDirectory())
    let voice = directory.appendingPathComponent("captro-voice-\(UUID().uuidString).m4a")
    let photo = directory.appendingPathComponent("captro-post-draft-\(UUID().uuidString).jpg")
    try Data([1, 2, 3]).write(to: voice, options: .atomic)
    try Data([4, 5, 6]).write(to: photo, options: .atomic)
    defer { try? FileManager.default.removeItem(at: voice) }

    await MIRAAppCacheStore.shared.clearPostDraft()

    XCTAssertTrue(FileManager.default.fileExists(atPath: voice.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: photo.path))
  }

  func testRecentChatReconciliationRemovesDeletedRowsButKeepsPendingSend() async {
    let store = MIRAChatLocalStore.shared
    let old = MIRAMessage(id: "old", createdAt: "2026-09-24T10:00:00Z")
    let deleted = MIRAMessage(id: "deleted", createdAt: "2026-09-24T10:01:00Z")
    let kept = MIRAMessage(id: "kept", createdAt: "2026-09-24T10:02:00Z")
    let pending = MIRAMessage(id: "local-pending", createdAt: "2026-09-24T10:03:00Z", status: "sending")

    let current = await store.reconcileRecent([old, deleted, kept, pending], with: [old, kept])
    XCTAssertEqual(Set(current.map(\.id)), Set(["old", "kept", "local-pending"]))

    let empty = await store.reconcileRecent([old, deleted, pending], with: [])
    XCTAssertEqual(empty.map(\.id), ["local-pending"])
  }

  func testGroupChatCacheKeyIncludesSignedInUser() async {
    let store = MIRAChatLocalStore.shared
    let groupId = UUID().uuidString
    let firstUser = UUID().uuidString
    let secondUser = UUID().uuidString
    let kind = ConversationNativeKind.group(groupId: groupId)
    MIRALocalJSONCache.setAccountScope(userId: firstUser)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    await store.saveThread(
      kind: kind, currentUserId: firstUser,
      messages: [MIRAMessage(id: "private", content: "Private club message")],
      lastSyncedAt: nil, lastServerSequence: nil, hasOlderRemote: false
    )
    let wrongUser = await store.loadThread(kind: kind, currentUserId: secondUser)
    XCTAssertNil(wrongUser)
    await store.removeThread(kind: kind, currentUserId: firstUser)
  }
}
