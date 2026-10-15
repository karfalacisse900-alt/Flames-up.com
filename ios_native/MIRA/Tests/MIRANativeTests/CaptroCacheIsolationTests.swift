import XCTest
import UIKit
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

  func testRetiredVoiceDraftRemainsDecodedAndArchivedWithoutRecordingDeletion() async throws {
    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    let directory = try XCTUnwrap(postDraftMediaDirectory())
    let voiceURL = directory.appendingPathComponent("captro-voice-\(UUID().uuidString).m4a")
    try Data([1, 2, 3]).write(to: voiceURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: voiceURL) }
    let snapshot = MIRAVoiceDraftSnapshot(localFilePath: voiceURL.path, duration: 1,
      levels: [0.1], disclosureVersion: "legacy", disclosureAcceptedAt: Date())
    var draft = try JSONDecoder().decode(MIRAPostDraftSnapshot.self, from: Data(#"{"title":"","bodyText":"Keep writing","hashtags":[],"uploadStatus":"draft","showBroadLocation":false,"isEditingPostDetails":false,"media":[],"savedAt":"2026-10-13T00:00:00Z"}"#.utf8))
    draft.voiceDraft = snapshot
    await MIRAAppCacheStore.shared.savePostDraft(draft)
    await MIRAAppCacheStore.shared.clearPostDraft()
    let archived = await MIRALocalJSONCache.load(MIRAVoiceDraftSnapshot.self, key: "native.retired_voice_draft.v1")
    XCTAssertEqual(archived, snapshot)
    XCTAssertTrue(FileManager.default.fileExists(atPath: voiceURL.path))
    await MIRALocalJSONCache.remove(key: "native.retired_voice_draft.v1")
  }

  func testDraftCleanupSuspendedAfterReadCannotDeleteNextAccountsDraftOrMedia() async throws {
    let store = MIRAAppCacheStore()
    let accountA = "draft-cleanup-a-\(UUID().uuidString)"
    let accountB = "draft-cleanup-b-\(UUID().uuidString)"
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    MIRALocalJSONCache.setAccountScope(userId: accountA)
    let scopeA = MIRALocalJSONCache.currentScopeIdentifier
    let directoryA = try XCTUnwrap(postDraftMediaDirectory())
    let voice = directoryA.appendingPathComponent("captro-voice-\(UUID().uuidString).m4a")
    try Data([1, 2, 3]).write(to: voice, options: .atomic)
    defer { try? FileManager.default.removeItem(at: voice) }
    var draftA = try cleanupDraft("Account A writing")
    draftA.voiceDraft = MIRAVoiceDraftSnapshot(localFilePath: voice.path, duration: 1,
      levels: [0.1], disclosureVersion: "legacy", disclosureAcceptedAt: Date())
    await store.savePostDraft(draftA)
    let photoA = directoryA.appendingPathComponent("captro-post-draft-\(UUID().uuidString).jpg")
    try Data([4, 5, 6]).write(to: photoA, options: .atomic)
    defer { try? FileManager.default.removeItem(at: photoA) }

    let reachedRead = expectation(description: "A cleanup has read A draft")
    let gate = DraftCleanupGate()
    await store.setAfterDraftCleanupReadForTesting {
      reachedRead.fulfill()
      await gate.wait()
    }
    let cleanup = Task { await store.clearPostDraft(expectedScope: scopeA) }
    await fulfillment(of: [reachedRead], timeout: 3)

    MIRALocalJSONCache.setAccountScope(userId: accountB)
    let draftB = try cleanupDraft("Account B writing")
    await store.savePostDraft(draftB)
    let directoryB = try XCTUnwrap(postDraftMediaDirectory())
    let photoB = directoryB.appendingPathComponent("captro-post-draft-\(UUID().uuidString).jpg")
    try Data([7, 8, 9]).write(to: photoB, options: .atomic)
    defer { try? FileManager.default.removeItem(at: photoB) }
    await gate.open()
    await cleanup.value
    await store.setAfterDraftCleanupReadForTesting(nil)

    let retainedB = await store.loadPostDraft()
    let wronglyArchivedVoice = await MIRALocalJSONCache.load(MIRAVoiceDraftSnapshot.self,
      key: "native.retired_voice_draft.v1")
    XCTAssertEqual(retainedB, draftB)
    XCTAssertNil(wronglyArchivedVoice, "A's retired voice metadata must not be copied into B's account")
    XCTAssertTrue(FileManager.default.fileExists(atPath: photoB.path))
    MIRALocalJSONCache.setAccountScope(userId: accountA)
    let retainedA = await store.loadPostDraft()
    XCTAssertEqual(retainedA, draftA, "Obsolete cleanup is cancelled at the account boundary")
    XCTAssertTrue(FileManager.default.fileExists(atPath: photoA.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: voice.path))
    await store.clearPostDraft()
    await MIRALocalJSONCache.remove(key: "native.retired_voice_draft.v1")
    MIRALocalJSONCache.setAccountScope(userId: accountB)
    await store.clearPostDraft()
  }

  func testQueuedDraftCleanupAndScopedCacheOperationsRejectEndedAccount() async throws {
    let store = MIRAAppCacheStore()
    let accountA = "draft-queued-a-\(UUID().uuidString)"
    let accountB = "draft-queued-b-\(UUID().uuidString)"
    let key = "scoped-cleanup-\(UUID().uuidString)"
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }
    MIRALocalJSONCache.setAccountScope(userId: accountA)
    let scopeA = MIRALocalJSONCache.currentScopeIdentifier
    MIRALocalJSONCache.setAccountScope(userId: accountB)
    let draftB = try cleanupDraft("Keep B draft")
    await store.savePostDraft(draftB)
    await MIRALocalJSONCache.save([2], key: key)
    await store.clearPostDraft(expectedScope: scopeA)
    let wrongRead = await MIRALocalJSONCache.load([Int].self, key: key, expectedScopeIdentifier: scopeA)
    await MIRALocalJSONCache.remove(key: key, expectedScopeIdentifier: scopeA)
    let retainedCache = await MIRALocalJSONCache.load([Int].self, key: key)
    let retainedDraft = await store.loadPostDraft()
    XCTAssertNil(wrongRead)
    XCTAssertEqual(retainedCache, [2])
    XCTAssertEqual(retainedDraft, draftB)
    await store.clearPostDraft()
    await MIRALocalJSONCache.remove(key: key)
  }

  private func cleanupDraft(_ body: String) throws -> MIRAPostDraftSnapshot {
    let value: [String: Any] = ["title": "", "bodyText": body, "hashtags": [],
      "uploadStatus": "draft", "showBroadLocation": false, "isEditingPostDetails": false,
      "media": [], "savedAt": "2026-10-14T00:00:00Z"]
    return try JSONDecoder().decode(MIRAPostDraftSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
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

  func testReturningToChatReusesRoomModelButAccountSwitchDoesNot() async {
    await MainActor.run {
      let api = MIRAAPIClient(sessionProvider: StaticSessionProvider(token: "test"))
      let inbox = ChatNativeModel(api: api)
      let conversation = MIRAConversation(
        id: "room", type: "direct", otherUserId: "peer", otherUsername: "peer",
        otherFullName: nil, otherProfileImage: nil, otherLastSeenAt: nil,
        otherIsOnline: nil, otherIsTyping: nil, lastMessage: nil,
        lastMessageTime: nil, updatedAt: nil, unreadCount: nil,
        groupId: nil, groupName: nil, memberCount: nil
      )

      inbox.configure(currentUserId: "account-a")
      let first = inbox.roomModel(for: conversation)
      XCTAssertNotNil(first)
      XCTAssertTrue(first === inbox.roomModel(for: conversation))

      inbox.configure(currentUserId: "account-b")
      let second = inbox.roomModel(for: conversation)
      XCTAssertNotNil(second)
      XCTAssertFalse(first === second)
      XCTAssertEqual(second?.currentUserId, "account-b")
    }
  }

  func testPaymentDisplayStateIsClearedOnAccountSwitch() async throws {
    let method = try JSONDecoder().decode(
      CaptroSavedPaymentMethod.self,
      from: Data(#"{"id":"pm_test","brand":"visa","last4":"1234","expirationMonth":12,"expirationYear":2028,"funding":"debit"}"#.utf8)
    )
    await MainActor.run {
      let model = CaptroPaymentsModel(api: MIRAAPIClient(sessionProvider: StaticSessionProvider(token: "test")))
      model.configure(currentUserId: "account-a")
      model.methods = [method]
      model.cardError = "Old account error"
      model.earningsModel.errorMessage = "Old balance error"

      model.configure(currentUserId: "account-b")
      XCTAssertTrue(model.methods.isEmpty)
      XCTAssertNil(model.cardError)
      XCTAssertNil(model.earningsModel.errorMessage)
      XCTAssertNil(model.earningsModel.response)
    }
  }

  func testDecodedMediaDiskCacheDoesNotCrossAccounts() async throws {
    let url = try XCTUnwrap(URL(string: "https://captro.app/cache-isolation-\(UUID().uuidString).png"))
    let data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    let firstAccount = UUID().uuidString
    defer { MIRALocalJSONCache.setAccountScope(userId: nil) }

    MIRALocalJSONCache.setAccountScope(userId: firstAccount)
    await MIRAImageDiskCache.store(data: data, for: url)
    let ownImage = await MIRAImageDiskCache.image(for: url)
    XCTAssertNotNil(ownImage)

    MIRALocalJSONCache.setAccountScope(userId: UUID().uuidString)
    let otherAccountImage = await MIRAImageDiskCache.image(for: url)
    XCTAssertNil(otherAccountImage)
  }
}

private actor DraftCleanupGate {
  private var isOpen = false
  private var waiter: CheckedContinuation<Void, Never>?
  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func open() {
    isOpen = true
    waiter?.resume()
    waiter = nil
  }
}
