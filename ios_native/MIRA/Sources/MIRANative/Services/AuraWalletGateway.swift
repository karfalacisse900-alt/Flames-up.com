import Combine
import Foundation

public struct AuraGatewayNetwork: Decodable, Equatable, Sendable {
  public let protocolVersion: String
  public let network: String
  public let chainId: String
  public let chainIdHash: String
  public let genesisHash: String
  public let targetBlockIntervalSeconds: String
  public let consensus: String
  public let mainnetAvailable: Bool
}

public struct AuraGatewayChainStatus: Decodable, Equatable, Sendable {
  public let chainId: String
  public let chainIdHash: String
  public let genesisHash: String
  public let canonicalHeight: String
  public let tipHash: String
  public let cumulativeWorkHex: String
  public let connectedPeers: String
  public let mempoolTransactions: String
  public let syncStatus: String
}

public struct AuraGatewayBalance: Decodable, Equatable, Sendable {
  public let address: String
  public let availableAtoms: String
  public let lockedAtoms: String
}

public struct AuraGatewayNonce: Decodable, Equatable, Sendable {
  public let address: String
  public let currentNonce: String
  public let nextNonce: String?
}

public struct AuraGatewayFees: Decodable, Equatable, Sendable {
  public let minimumFeeAtoms: String
  public let policy: String
  public let estimated: Bool
}

public struct AuraGatewayTransaction: Decodable, Equatable, Identifiable, Sendable {
  public let transactionId: String
  public let witnessId: String
  public let state: String
  public let direction: String
  public let sender: String?
  public let recipient: String
  public let amountAtoms: String
  public let feeAtoms: String
  public let nonce: String?
  public let blockId: String?
  public let blockHeight: String?
  public let timestampSeconds: String?
  public let confirmations: String

  public var id: String { transactionId }
}

public struct AuraGatewayHistory: Decodable, Equatable, Sendable {
  public let address: String
  public let complete: Bool
  public let oldestScannedHeight: String
  public let transactions: [AuraGatewayTransaction]
}

public struct AuraGatewayBroadcastResult: Decodable, Equatable, Sendable {
  public let intentId: String
  public let relayedPeers: String
  public let evictedIntentIds: [String]
}

private struct AuraGatewayBroadcastBody: Encodable {
  let transactionHex: String
  let expectedChainIdHash: String
  let expectedGenesisHash: String
}

public enum AuraWalletGatewayError: Error, Equatable, LocalizedError {
  case chainIdentityMismatch
  case networkUnavailable
  case invalidNetworkValue
  case invalidAmount
  case insufficientFunds
  case nonceUnavailable
  case walletIdentityMismatch

  public var errorDescription: String? {
    switch self {
    case .chainIdentityMismatch:
      return "The Aura gateway identifies a different chain. No transaction was signed."
    case .networkUnavailable:
      return "Aura Mobile could not obtain validated Devnet state from the gateway."
    case .invalidNetworkValue:
      return "The Aura gateway returned an invalid exact integer value."
    case .invalidAmount:
      return "Enter a positive AUR amount with no more than 8 decimal places."
    case .insufficientFunds:
      return "The available balance is not enough for this amount and the network fee."
    case .nonceUnavailable:
      return "The next transaction nonce is unavailable. Refresh the wallet and try again."
    case .walletIdentityMismatch:
      return "The unlocked wallet does not match the address being used for this transaction."
    }
  }
}

enum AuraAmountCodec {
  static let atomsPerAUR: UInt64 = 100_000_000

  static func atoms(fromAUR text: String) throws -> UInt64 {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !value.hasPrefix("-"), !value.hasPrefix("+") else {
      throw AuraWalletGatewayError.invalidAmount
    }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          !parts[0].isEmpty,
          parts[0].allSatisfy(\.isNumber),
          let whole = UInt64(parts[0]) else {
      throw AuraWalletGatewayError.invalidAmount
    }
    let fractionText = parts.count == 2 ? String(parts[1]) : ""
    guard fractionText.count <= 8, fractionText.allSatisfy(\.isNumber) else {
      throw AuraWalletGatewayError.invalidAmount
    }
    let paddedFraction = fractionText.padding(
      toLength: 8,
      withPad: "0",
      startingAt: 0
    )
    let wholeResult = whole.multipliedReportingOverflow(by: atomsPerAUR)
    guard let fraction = UInt64(paddedFraction), !wholeResult.overflow else {
      throw AuraWalletGatewayError.invalidAmount
    }
    let (atoms, overflow) = wholeResult.partialValue.addingReportingOverflow(fraction)
    guard !overflow, atoms > 0 else { throw AuraWalletGatewayError.invalidAmount }
    return atoms
  }

  static func aur(fromAtoms text: String) -> String? {
    guard let atoms = UInt64(text) else { return nil }
    let whole = atoms / atomsPerAUR
    let fraction = atoms % atomsPerAUR
    guard fraction != 0 else { return String(whole) }
    var fractionText = String(format: "%08llu", fraction)
    while fractionText.last == "0" { fractionText.removeLast() }
    return "\(whole).\(fractionText)"
  }
}

@MainActor
public final class AuraWalletGatewayStore: ObservableObject {
  @Published public private(set) var network: AuraGatewayNetwork?
  @Published public private(set) var chainStatus: AuraGatewayChainStatus?
  @Published public private(set) var balance: AuraGatewayBalance?
  @Published public private(set) var nonce: AuraGatewayNonce?
  @Published public private(set) var fees: AuraGatewayFees?
  @Published public private(set) var history: AuraGatewayHistory?
  @Published public private(set) var isLoading = false
  @Published public private(set) var errorMessage: String?
  @Published public private(set) var lastSubmittedIntentId: String?

  private let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var isConnected: Bool {
    network != nil && chainStatus != nil && balance != nil && nonce != nil && fees != nil
  }

  public var availableAUR: String? {
    balance.flatMap { AuraAmountCodec.aur(fromAtoms: $0.availableAtoms) }
  }

  public func clear() {
    network = nil
    chainStatus = nil
    balance = nil
    nonce = nil
    fees = nil
    history = nil
    errorMessage = nil
    lastSubmittedIntentId = nil
    isLoading = false
  }

  public func refresh(identity: AuraWalletIdentity) async {
    isLoading = true
    errorMessage = nil
    do {
      let remoteNetwork: AuraGatewayNetwork = try await api.get("/aura/network")
      guard remoteNetwork.network == identity.network,
            remoteNetwork.network == "devnet",
            !remoteNetwork.chainIdHash.isEmpty,
            !remoteNetwork.genesisHash.isEmpty else {
        throw AuraWalletGatewayError.chainIdentityMismatch
      }

      async let statusRequest: AuraGatewayChainStatus = api.get("/aura/chain/status")
      async let balanceRequest: AuraGatewayBalance = api.get(
        "/aura/address/\(identity.address)/balance"
      )
      async let nonceRequest: AuraGatewayNonce = api.get(
        "/aura/address/\(identity.address)/nonce"
      )
      async let feesRequest: AuraGatewayFees = api.get("/aura/fees")
      async let historyRequest: AuraGatewayHistory = api.get(
        "/aura/address/\(identity.address)/transactions?limit=50"
      )

      let (remoteStatus, remoteBalance, remoteNonce, remoteFees, remoteHistory) = try await (
        statusRequest,
        balanceRequest,
        nonceRequest,
        feesRequest,
        historyRequest
      )
      guard remoteStatus.chainIdHash == remoteNetwork.chainIdHash,
            remoteStatus.genesisHash == remoteNetwork.genesisHash,
            remoteBalance.address == identity.address,
            remoteNonce.address == identity.address,
            remoteHistory.address == identity.address else {
        throw AuraWalletGatewayError.chainIdentityMismatch
      }
      guard UInt64(remoteStatus.canonicalHeight) != nil,
            UInt64(remoteStatus.connectedPeers) != nil,
            UInt64(remoteBalance.availableAtoms) != nil,
            UInt64(remoteBalance.lockedAtoms) != nil,
            UInt64(remoteFees.minimumFeeAtoms) != nil else {
        throw AuraWalletGatewayError.invalidNetworkValue
      }

      network = remoteNetwork
      chainStatus = remoteStatus
      balance = remoteBalance
      nonce = remoteNonce
      fees = remoteFees
      history = remoteHistory
    } catch {
      network = nil
      chainStatus = nil
      balance = nil
      nonce = nil
      fees = nil
      history = nil
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    isLoading = false
  }

  public func send(
    from wallet: AuraWalletStore,
    identity: AuraWalletIdentity,
    recipient: String,
    amountAUR: String
  ) async throws -> AuraGatewayBroadcastResult {
    guard let network, let chainStatus, let balance, let nonce, let fees else {
      throw AuraWalletGatewayError.networkUnavailable
    }
    guard identity.address == balance.address, identity.network == network.network else {
      throw AuraWalletGatewayError.walletIdentityMismatch
    }
    guard AuraWalletNative.validate(address: recipient) else {
      throw AuraWalletNativeError.nativeFailure("The recipient Aura address is invalid.")
    }
    let amount = try AuraAmountCodec.atoms(fromAUR: amountAUR)
    guard let available = UInt64(balance.availableAtoms),
          let fee = UInt64(fees.minimumFeeAtoms) else {
      throw AuraWalletGatewayError.invalidNetworkValue
    }
    let (total, overflow) = amount.addingReportingOverflow(fee)
    guard !overflow, total <= available else { throw AuraWalletGatewayError.insufficientFunds }
    guard let nextNonceText = nonce.nextNonce,
          let nextNonce = UInt64(nextNonceText),
          let height = UInt64(chainStatus.canonicalHeight) else {
      throw AuraWalletGatewayError.nonceUnavailable
    }
    let validUntil = height.addingReportingOverflow(100)
    guard !validUntil.overflow else { throw AuraWalletGatewayError.invalidNetworkValue }
    let request = AuraUnsignedTransferRequest(
      network: .devnet,
      chainIdHashHex: network.chainIdHash,
      senderAddress: identity.address,
      recipientAddress: recipient,
      amountAtoms: amount,
      feeAtoms: fee,
      nonce: nextNonce,
      validUntilHeight: validUntil.partialValue
    )
    let signed = try wallet.signTransfer(request)
    let now = Date().timeIntervalSince1970
    guard now >= 0, now <= Double(UInt64.max) else {
      throw AuraWalletGatewayError.invalidNetworkValue
    }
    let result: AuraGatewayBroadcastResult = try await api.postAuraTransaction(
      "/aura/transactions/broadcast",
      body: AuraGatewayBroadcastBody(
        transactionHex: signed.signedTransferHex,
        expectedChainIdHash: network.chainIdHash,
        expectedGenesisHash: network.genesisHash
      ),
      idempotencyKey: UUID().uuidString,
      timestampSeconds: UInt64(now)
    )
    guard result.intentId == signed.intentIdHex else {
      throw AuraWalletGatewayError.chainIdentityMismatch
    }
    lastSubmittedIntentId = result.intentId
    await refresh(identity: identity)
    return result
  }
}
