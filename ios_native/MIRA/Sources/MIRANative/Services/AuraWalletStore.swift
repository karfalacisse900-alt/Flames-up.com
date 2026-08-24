import Combine
import Foundation

public enum AuraWalletLockState: Equatable {
  case unavailable
  case noWallet
  case locked
  case unlocked
}

/// Owns the one live Rust wallet handle used by Aura Mobile and its encrypted on-disk envelope.
/// Passwords are passed directly to Rust for Argon2id derivation and are never stored here.
@MainActor
public final class AuraWalletStore: ObservableObject {
  @Published public private(set) var state: AuraWalletLockState
  @Published public private(set) var identity: AuraWalletIdentity?
  @Published public private(set) var errorMessage: String?

  private let walletURL: URL?
  private var session: AuraWalletSession?

  public convenience init() {
    self.init(walletURL: Self.defaultWalletURL())
  }

  init(walletURL: URL?) {
    self.walletURL = walletURL
    if let walletURL {
      state = FileManager.default.fileExists(atPath: walletURL.path) ? .locked : .noWallet
    } else {
      state = .unavailable
    }
    MIRAApplePerformanceLogger.event("wallet_bridge_store_initialized", detail: Self.diagnosticState(state))
  }

  private static func diagnosticState(_ state: AuraWalletLockState) -> String {
    switch state {
    case .unavailable: return "unavailable"
    case .noWallet: return "no_wallet"
    case .locked: return "locked"
    case .unlocked: return "unlocked"
    }
  }

  public func create(password: String, network: AuraWalletNetwork = .devnet) throws -> String {
    let walletURL = try writableWalletURL()
    guard !FileManager.default.fileExists(atPath: walletURL.path) else {
      throw AuraWalletNativeError.nativeFailure(
        "A wallet already exists on this device. Unlock it instead of replacing it."
      )
    }
    try validateNewPassword(password)

    let creation = try AuraWalletSession.create(network: network)
    _ = try creation.session.saveEncrypted(to: walletURL, password: password)
    applyCompleteFileProtection(to: walletURL)
    session = creation.session
    identity = try creation.session.identity()
    errorMessage = nil
    state = .unlocked
    return creation.recoveryPhrase
  }

  public func restore(
    recoveryPhrase: String,
    password: String,
    network: AuraWalletNetwork = .devnet
  ) throws {
    let walletURL = try writableWalletURL()
    guard !FileManager.default.fileExists(atPath: walletURL.path) else {
      throw AuraWalletNativeError.nativeFailure(
        "A wallet already exists on this device. Unlock it instead of replacing it."
      )
    }
    try validateNewPassword(password)

    let restored = try AuraWalletSession.restore(
      recoveryPhrase: recoveryPhrase,
      network: network
    )
    _ = try restored.saveEncrypted(to: walletURL, password: password)
    applyCompleteFileProtection(to: walletURL)
    session = restored
    identity = try restored.identity()
    errorMessage = nil
    state = .unlocked
  }

  public func unlock(password: String) throws {
    let walletURL = try writableWalletURL()
    guard FileManager.default.fileExists(atPath: walletURL.path) else {
      state = .noWallet
      throw AuraWalletNativeError.nativeFailure("No encrypted Aura wallet exists on this device.")
    }
    let unlocked = try AuraWalletSession.loadEncrypted(from: walletURL, password: password)
    session = unlocked
    identity = try unlocked.identity()
    errorMessage = nil
    state = .unlocked
  }

  public func lock() {
    session?.lock()
    session = nil
    identity = nil
    errorMessage = nil
    state = walletURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
      ? .locked
      : .noWallet
  }

  public func report(_ error: Error) {
    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  public func clearError() {
    errorMessage = nil
  }

  public func signTransfer(_ request: AuraUnsignedTransferRequest) throws -> AuraSignedTransfer {
    guard let session, let identity else { throw AuraWalletNativeError.releasedSession }
    let identityNetwork: AuraWalletNetwork? = switch identity.network {
    case "mainnet": .mainnet
    case "testnet": .testnet
    case "devnet": .devnet
    default: nil
    }
    guard identity.address == request.senderAddress,
          identityNetwork?.rawValue == request.network else {
      throw AuraWalletGatewayError.walletIdentityMismatch
    }
    let unsigned = try AuraWalletNative.buildUnsignedTransfer(request)
    return try session.sign(unsignedBodyHex: unsigned.unsignedBodyHex)
  }

  private func writableWalletURL() throws -> URL {
    guard let walletURL else {
      throw AuraWalletNativeError.nativeFailure(
        "Aura could not access this device's Application Support directory."
      )
    }
    return walletURL
  }

  private func validateNewPassword(_ password: String) throws {
    guard password.utf8.count >= 12 else {
      throw AuraWalletNativeError.nativeFailure(
        "Use a wallet password of at least 12 characters. It cannot be recovered by Aura."
      )
    }
  }

  private func applyCompleteFileProtection(to url: URL) {
    // The Rust envelope already encrypts the key with Argon2id + XChaCha20-Poly1305. iOS Data
    // Protection is an additional device-lock boundary and may not be available in a simulator.
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
  }

  private static func defaultWalletURL() -> URL? {
    guard let support = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else {
      return nil
    }
    return support
      .appendingPathComponent("Aura", isDirectory: true)
      .appendingPathComponent("wallet-v1.aura", isDirectory: false)
  }
}
