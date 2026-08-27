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

  func testFeedbackAuthorizationIsWalletLocalAndCommitmentBound() throws {
    let created = try AuraWalletSession.create(network: .devnet)
    let identity = try created.session.identity()
    let base = AuraFeedbackAuthorizationRequest(
      chainIdHashHex: AuraExpectedDevnet.chainIdHash,
      proofIdHex: String(repeating: "31", count: 32),
      feedbackCommitmentHex: String(repeating: "41", count: 32)
    )
    let first = try created.session.authorizeFeedback(base)
    let repeated = try created.session.authorizeFeedback(base)
    let changed = try created.session.authorizeFeedback(
      AuraFeedbackAuthorizationRequest(
        chainIdHashHex: AuraExpectedDevnet.chainIdHash,
        proofIdHex: String(repeating: "31", count: 32),
        feedbackCommitmentHex: String(repeating: "42", count: 32)
      )
    )

    XCTAssertEqual(first.ownerPublicKeyHex, identity.publicKeyHex)
    XCTAssertEqual(first, repeated)
    XCTAssertEqual(first.ownerPublicKeyHex.count, 64)
    XCTAssertEqual(first.ownerSignatureHex.count, 128)
    XCTAssertNotEqual(first.ownerSignatureHex, changed.ownerSignatureHex)
  }
}
