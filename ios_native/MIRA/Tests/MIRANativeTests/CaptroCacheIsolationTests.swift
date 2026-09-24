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
