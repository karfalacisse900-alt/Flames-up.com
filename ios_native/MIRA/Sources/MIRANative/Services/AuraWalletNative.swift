import Foundation
import MIRACoreCpp

public enum AuraWalletNetwork: UInt8, Codable, CaseIterable, Sendable {
  case mainnet = 0
  case testnet = 1
  case devnet = 2
}

public struct AuraWalletIdentity: Decodable, Equatable, Sendable {
  public let network: String
  public let address: String
  public let publicKeyHex: String
}

public struct AuraWalletSaveReport: Decodable, Equatable, Sendable {
  public let bytesWritten: Int
  public let permissionStatus: String
}

public struct AuraUnsignedTransfer: Decodable, Equatable, Sendable {
  public let unsignedBodyHex: String
  public let signingHashHex: String
}

public struct AuraSignedTransfer: Decodable, Equatable, Sendable {
  public let signedTransferHex: String
  public let witnessIdHex: String
  public let intentIdHex: String
}

public struct AuraUnsignedTransferRequest: Encodable, Equatable, Sendable {
  public let network: UInt8
  public let chainIdHashHex: String
  public let senderAddress: String
  public let recipientAddress: String
  public let amountAtoms: String
  public let feeAtoms: String
  public let nonce: String
  public let validUntilHeight: String

  public init(
    network: AuraWalletNetwork,
    chainIdHashHex: String,
    senderAddress: String,
    recipientAddress: String,
    amountAtoms: UInt64,
    feeAtoms: UInt64,
    nonce: UInt64,
    validUntilHeight: UInt64
  ) {
    self.network = network.rawValue
    self.chainIdHashHex = chainIdHashHex
    self.senderAddress = senderAddress
    self.recipientAddress = recipientAddress
    self.amountAtoms = String(amountAtoms)
    self.feeAtoms = String(feeAtoms)
    self.nonce = String(nonce)
    self.validUntilHeight = String(validUntilHeight)
  }
}

public struct AuraWalletCreation {
  public let session: AuraWalletSession
  public let recoveryPhrase: String
}

public enum AuraWalletNativeError: Error, Equatable, LocalizedError {
  case nativeFailure(String)
  case invalidResponse
  case encodingFailure
  case releasedSession

  public var errorDescription: String? {
    switch self {
    case .nativeFailure(let message): return message
    case .invalidResponse: return "Aura wallet returned an invalid response."
    case .encodingFailure: return "Aura wallet request could not be encoded."
    case .releasedSession: return "The Aura wallet is locked."
    }
  }
}

private struct AuraNativeEnvelope<Value: Decodable>: Decodable {
  let ok: Bool
  let error: String?
  let data: Value?
}

/// Memory-safe Swift ownership wrapper for Aura's Rust wallet handle.
///
/// Private keys never enter Swift. The only key material Swift receives is the explicit,
/// one-time recovery phrase returned during wallet creation or entered by the user during
/// restoration. Signed transactions and public identity data are safe outputs from Rust.
@MainActor
public final class AuraWalletSession {
  private var handle: UnsafeMutableRawPointer?

  private init(handle: UnsafeMutableRawPointer) {
    self.handle = handle
  }

  deinit {
    if let handle {
      mira_wallet_free(handle)
    }
  }

  public static func create(network: AuraWalletNetwork) throws -> AuraWalletCreation {
    var phrasePointer: UnsafeMutablePointer<CChar>?
    guard let handle = mira_wallet_create(network.rawValue, &phrasePointer) else {
      let message = consumeString(phrasePointer) ?? "Aura wallet creation failed."
      throw AuraWalletNativeError.nativeFailure(message)
    }
    guard let phrase = consumeString(phrasePointer), !phrase.isEmpty else {
      mira_wallet_free(handle)
      throw AuraWalletNativeError.invalidResponse
    }
    return AuraWalletCreation(
      session: AuraWalletSession(handle: handle),
      recoveryPhrase: phrase
    )
  }

  public static func restore(
    recoveryPhrase: String,
    network: AuraWalletNetwork
  ) throws -> AuraWalletSession {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let handle = recoveryPhrase.withCString { phrasePointer in
      mira_wallet_restore_from_mnemonic(phrasePointer, network.rawValue, &errorPointer)
    }
    guard let handle else {
      let message = consumeString(errorPointer) ?? "Aura wallet restoration failed."
      throw AuraWalletNativeError.nativeFailure(message)
    }
    if let errorPointer {
      mira_free_string(errorPointer)
    }
    return AuraWalletSession(handle: handle)
  }

  public static func loadEncrypted(from url: URL, password: String) throws -> AuraWalletSession {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let handle = url.path.withCString { pathPointer in
      password.withCString { passwordPointer in
        mira_wallet_load(pathPointer, passwordPointer, &errorPointer)
      }
    }
    guard let handle else {
      let message = consumeString(errorPointer) ?? "Aura wallet unlock failed."
      throw AuraWalletNativeError.nativeFailure(message)
    }
    if let errorPointer {
      mira_free_string(errorPointer)
    }
    return AuraWalletSession(handle: handle)
  }

  public func identity() throws -> AuraWalletIdentity {
    try withHandle { handle in
      try Self.decode(mira_wallet_identity_json(handle), as: AuraWalletIdentity.self)
    }
  }

  public func saveEncrypted(to url: URL, password: String) throws -> AuraWalletSaveReport {
    try withHandle { handle in
      let response = url.path.withCString { pathPointer in
        password.withCString { passwordPointer in
          mira_wallet_save_json(handle, pathPointer, passwordPointer)
        }
      }
      return try Self.decode(response, as: AuraWalletSaveReport.self)
    }
  }

  public func sign(unsignedBodyHex: String) throws -> AuraSignedTransfer {
    try withHandle { handle in
      let response = unsignedBodyHex.withCString { bodyPointer in
        mira_wallet_sign_transfer_v2_json(handle, bodyPointer)
      }
      return try Self.decode(response, as: AuraSignedTransfer.self)
    }
  }

  public func lock() {
    if let handle {
      mira_wallet_free(handle)
      self.handle = nil
    }
  }

  private func withHandle<Value>(
    _ operation: (UnsafeMutableRawPointer) throws -> Value
  ) throws -> Value {
    guard let handle else {
      throw AuraWalletNativeError.releasedSession
    }
    return try operation(handle)
  }

  private static func decode<Value: Decodable>(
    _ pointer: UnsafeMutablePointer<CChar>?,
    as type: Value.Type
  ) throws -> Value {
    guard let json = consumeString(pointer), let data = json.data(using: .utf8) else {
      throw AuraWalletNativeError.invalidResponse
    }
    guard let envelope = try? JSONDecoder().decode(AuraNativeEnvelope<Value>.self, from: data) else {
      throw AuraWalletNativeError.invalidResponse
    }
    guard envelope.ok, let value = envelope.data else {
      throw AuraWalletNativeError.nativeFailure(envelope.error ?? "Aura wallet operation failed.")
    }
    return value
  }

  private static func consumeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    let value = String(cString: pointer)
    mira_free_string(pointer)
    return value
  }
}

public enum AuraWalletNative {
  public static func validate(address: String) -> Bool {
    address.withCString { mira_aura_validate_address($0) == 1 }
  }

  public static func buildUnsignedTransfer(
    _ request: AuraUnsignedTransferRequest
  ) throws -> AuraUnsignedTransfer {
    guard let data = try? JSONEncoder().encode(request),
          let json = String(data: data, encoding: .utf8) else {
      throw AuraWalletNativeError.encodingFailure
    }
    let response = json.withCString { mira_aura_build_unsigned_transfer_v2_json($0) }
    return try decode(response, as: AuraUnsignedTransfer.self)
  }

  private static func decode<Value: Decodable>(
    _ pointer: UnsafeMutablePointer<CChar>?,
    as type: Value.Type
  ) throws -> Value {
    guard let pointer else { throw AuraWalletNativeError.invalidResponse }
    let json = String(cString: pointer)
    mira_free_string(pointer)
    guard let data = json.data(using: .utf8),
          let envelope = try? JSONDecoder().decode(AuraNativeEnvelope<Value>.self, from: data) else {
      throw AuraWalletNativeError.invalidResponse
    }
    guard envelope.ok, let value = envelope.data else {
      throw AuraWalletNativeError.nativeFailure(envelope.error ?? "Aura wallet operation failed.")
    }
    return value
  }
}
