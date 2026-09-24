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
}
