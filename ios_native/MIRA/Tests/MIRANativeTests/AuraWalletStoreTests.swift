import XCTest
@testable import MIRANative

@MainActor
final class AuraWalletStoreTests: XCTestCase {
  func testCreateLockAndPasswordOnlyUnlock() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let walletURL = directory.appendingPathComponent("wallet.aura")
    let store = AuraWalletStore(walletURL: walletURL)

    XCTAssertEqual(store.state, .noWallet)
    let recoveryPhrase = try store.create(password: "a-long-test-password")
    XCTAssertEqual(recoveryPhrase.split(separator: " ").count, 24)
    let identity = try XCTUnwrap(store.identity)
    XCTAssertEqual(store.state, .unlocked)

    store.lock()
    XCTAssertEqual(store.state, .locked)
    XCTAssertNil(store.identity)

    try store.unlock(password: "a-long-test-password")
    XCTAssertEqual(store.identity, identity)
    XCTAssertEqual(store.state, .unlocked)
  }

  func testStoreRefusesToOverwriteAnExistingWallet() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AuraWalletStore(walletURL: directory.appendingPathComponent("wallet.aura"))

    _ = try store.create(password: "a-long-test-password")
    store.lock()
    XCTAssertThrowsError(try store.create(password: "another-long-password"))
  }
}
