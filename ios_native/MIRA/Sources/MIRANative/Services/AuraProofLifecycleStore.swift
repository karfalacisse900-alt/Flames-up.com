import Combine
import Foundation

public struct AuraGatewayProofStatus: Decodable, Equatable, Sendable {
  public let proofId: String
  public let transactionId: String?
  public let receiptNullifier: String?
  public let owner: String?
  public let state: String
  public let blockId: String?
  public let blockHeight: String?
  public let confirmations: String?
  public let requiredConfirmations: String?
}

public struct AuraFeedbackEligibility: Decodable, Equatable, Sendable {
  public let proofId: String
  public let owner: String
  public let eligible: Bool
  public let reason: String
  public let confirmations: String
}

public struct AuraFeedbackRewardResult: Decodable, Equatable, Sendable {
  public let proofId: String
  public let owner: String
  public let feedbackCommitment: String
  public let feedbackAccepted: Bool
  public let rewardState: String
  public let rewardAtoms: String
  public let rewardTransactionId: String
  public let relayedPeers: String
  public let alreadyRecorded: Bool
}

public struct AuraGatewayTransactionStatus: Decodable, Equatable, Sendable {
  public let intentId: String
  public let state: String
  public let confirmations: String
  public let blockHeight: String?
  public let blockId: String?
}

private struct AuraFeedbackRequest: Encodable {
  let owner: String
  let feedbackCommitment: String
  let ownerPublicKey: String
  let ownerSignature: String
}

public struct AuraPrivateProofRecord: Codable, Equatable, Identifiable, Sendable {
  public let proofId: String
  public let proofTransactionId: String
  public let owner: String
  public let submittedAtSeconds: UInt64
  public var state: String
  public var blockId: String?
  public var blockHeight: String?
  public var confirmations: String
  public var requiredConfirmations: String
  public var feedbackCommitment: String?
  public var rewardTransactionId: String?
  public var rewardAtoms: String?
  public var rewardState: String?
  public var rewardBlockHeight: String?
  public var rewardConfirmations: String?

  public var id: String { proofId }
  public var isConfirmed: Bool { state == "confirmed" }
  public var feedbackUsed: Bool { feedbackCommitment != nil }
}

/// Stores only privacy-safe proof/transaction identifiers and canonical status metadata.
/// Raw receipts, OCR fields, and provider responses are never written by this store.
@MainActor
public final class AuraProofLifecycleStore: ObservableObject {
  @Published public private(set) var records: [AuraPrivateProofRecord]
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var errorMessage: String?

  private let api: MIRAAPIClient
  private let storeURL: URL?

  public init(api: MIRAAPIClient) {
    self.api = api
    storeURL = Self.defaultStoreURL()
    records = Self.load(from: storeURL)
  }

  public func record(
    submission: AuraPurchaseProofSubmission,
    owner: String,
    submittedAtSeconds: UInt64
  ) {
    guard records.first(where: { $0.proofId == submission.proofId }) == nil else { return }
    records.insert(
      AuraPrivateProofRecord(
        proofId: submission.proofId,
        proofTransactionId: submission.transactionId,
        owner: owner,
        submittedAtSeconds: submittedAtSeconds,
        state: "pending",
        blockId: nil,
        blockHeight: nil,
        confirmations: "0",
        requiredConfirmations: "2",
        feedbackCommitment: nil,
        rewardTransactionId: nil,
        rewardAtoms: nil,
        rewardState: nil,
        rewardBlockHeight: nil,
        rewardConfirmations: nil
      ),
      at: 0
    )
    persist()
  }

  public func refreshAll() async {
    guard !records.isEmpty else { return }
    isRefreshing = true
    errorMessage = nil
    defer { isRefreshing = false }
    do {
      for index in records.indices {
        let proof: AuraGatewayProofStatus = try await api.get(
          "/aura/proof/\(records[index].proofId)?required_confirmations=2"
        )
        guard proof.proofId == records[index].proofId else {
          throw AuraWalletGatewayError.chainIdentityMismatch
        }
        records[index].state = proof.state
        records[index].blockId = proof.blockId
        records[index].blockHeight = proof.blockHeight
        records[index].confirmations = proof.confirmations ?? "0"
        records[index].requiredConfirmations = proof.requiredConfirmations ?? "2"

        if let rewardTransactionId = records[index].rewardTransactionId {
          let reward: AuraGatewayTransactionStatus = try await api.get(
            "/aura/transaction/\(rewardTransactionId)"
          )
          guard reward.intentId == rewardTransactionId else {
            throw AuraWalletGatewayError.chainIdentityMismatch
          }
          records[index].rewardState = reward.state
          records[index].rewardBlockHeight = reward.blockHeight
          records[index].rewardConfirmations = reward.confirmations
        }
      }
      persist()
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  public func eligibility(for record: AuraPrivateProofRecord) async throws -> AuraFeedbackEligibility {
    try await api.get(
      "/aura/proof/\(record.proofId)/feedback-eligibility?owner=\(record.owner)"
    )
  }

  public func submitFeedback(
    proofId: String,
    owner: String,
    feedbackCommitment: String,
    authorization: AuraFeedbackAuthorization
  ) async throws -> AuraFeedbackRewardResult {
    let result: AuraFeedbackRewardResult = try await api.post(
      "/aura/proof/\(proofId)/feedback",
      body: AuraFeedbackRequest(
        owner: owner,
        feedbackCommitment: feedbackCommitment,
        ownerPublicKey: authorization.ownerPublicKeyHex,
        ownerSignature: authorization.ownerSignatureHex
      )
    )
    guard result.proofId == proofId,
          result.owner == owner,
          result.feedbackCommitment == feedbackCommitment,
          result.feedbackAccepted else {
      throw AuraWalletGatewayError.chainIdentityMismatch
    }
    guard let index = records.firstIndex(where: { $0.proofId == proofId }) else {
      throw AuraWalletGatewayError.invalidNetworkValue
    }
    records[index].feedbackCommitment = result.feedbackCommitment
    records[index].rewardTransactionId = result.rewardTransactionId
    records[index].rewardAtoms = result.rewardAtoms
    records[index].rewardState = result.rewardState
    persist()
    return result
  }

  public func clearError() {
    errorMessage = nil
  }

  private func persist() {
    guard let storeURL, let data = try? JSONEncoder().encode(records) else { return }
    do {
      try FileManager.default.createDirectory(
        at: storeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.complete]
      )
      try data.write(to: storeURL, options: [.atomic, .completeFileProtection])
    } catch {
      errorMessage = "Aura could not save private proof status on this device."
    }
  }

  private static func load(from storeURL: URL?) -> [AuraPrivateProofRecord] {
    guard let storeURL,
          let data = try? Data(contentsOf: storeURL),
          let decoded = try? JSONDecoder().decode([AuraPrivateProofRecord].self, from: data) else {
      return []
    }
    return decoded
  }

  private static func defaultStoreURL() -> URL? {
    guard let support = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else { return nil }
    return support
      .appendingPathComponent("Aura", isDirectory: true)
      .appendingPathComponent("proof-index-v1.json", isDirectory: false)
  }
}
