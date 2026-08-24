import XCTest
@testable import MIRANative

@MainActor
final class AuraWalletNativeTests: XCTestCase {
  func testCreateRestoreAndEncryptedUnlockPreservePublicIdentity() throws {
    let created = try AuraWalletSession.create(network: .devnet)
    let original = try created.session.identity()

    XCTAssertEqual(created.recoveryPhrase.split(separator: " ").count, 24)
    XCTAssertTrue(AuraWalletNative.validate(address: original.address))
    XCTAssertFalse(AuraWalletNative.validate(address: original.address + "x"))

    let restored = try AuraWalletSession.restore(
      recoveryPhrase: created.recoveryPhrase,
      network: .devnet
    )
    XCTAssertEqual(try restored.identity(), original)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let walletURL = directory.appendingPathComponent("wallet.aura")

    let report = try created.session.saveEncrypted(
      to: walletURL,
      password: "mobile-wallet-test-password"
    )
    XCTAssertGreaterThan(report.bytesWritten, 0)
    let unlocked = try AuraWalletSession.loadEncrypted(
      from: walletURL,
      password: "mobile-wallet-test-password"
    )
    XCTAssertEqual(try unlocked.identity(), original)
  }

  func testWrongPasswordDoesNotUnlockEncryptedWallet() throws {
    let created = try AuraWalletSession.create(network: .devnet)
    let walletURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: walletURL) }
    _ = try created.session.saveEncrypted(to: walletURL, password: "right-password")

    XCTAssertThrowsError(
      try AuraWalletSession.loadEncrypted(from: walletURL, password: "wrong-password")
    )
  }
}
