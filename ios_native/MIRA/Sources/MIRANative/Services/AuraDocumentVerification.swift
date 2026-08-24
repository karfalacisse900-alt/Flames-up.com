import Foundation

public struct AuraVerifiedMerchant: Decodable, Equatable, Sendable {
  public let name: String?
  public let address: String?
  public let phone: String?
  public let storeNumber: String?
}

public struct AuraDocumentFraudSignals: Decodable, Equatable, Sendable {
  public let decision: String?
  public let score: String?
  public let digitalTampering: Bool?
  public let aiGenerated: Bool?
  public let screenshot: Bool?
  public let invalidQr: Bool?
  public let vendorLayoutMismatch: Bool?
  public let notADocument: Bool?
}

public struct AuraVerifiedLineItem: Decodable, Equatable, Identifiable, Sendable {
  public let description: String?
  public let sku: String?
  public let quantity: String?
  public let unitPrice: String?
  public let total: String?

  public var id: String {
    [description, sku, quantity, unitPrice, total].compactMap { $0 }.joined(separator: "|")
  }
}

public struct AuraDocumentPrivacy: Decodable, Equatable, Sendable {
  public let storedByAura: Bool
  public let providerAutoDeleteRequested: Bool
}

public struct AuraDocumentVerificationResult: Decodable, Equatable, Sendable {
  public let provider: String
  public let providerDocumentId: String?
  public let submittedType: String
  public let providerDocumentType: String?
  public let isDocument: Bool?
  public let verificationLevel: Int
  public let verificationLabel: String
  public let documentVerified: Bool
  public let transactionCorroborated: Bool
  public let merchantSigned: Bool
  public let proofIssued: Bool
  public let blockchainSubmitted: Bool
  public let independentPurchaseConfirmed: Bool
  public let merchant: AuraVerifiedMerchant
  public let date: String?
  public let time: String?
  public let currency: String?
  public let subtotal: String?
  public let tax: String?
  public let discount: String?
  public let total: String?
  public let invoiceNumber: String?
  public let dueDate: String?
  public let receiptNumber: String?
  public let duplicate: Bool?
  public let fraud: AuraDocumentFraudSignals
  public let lineItems: [AuraVerifiedLineItem]
  public let rawResponseSha256: String
  public let privacy: AuraDocumentPrivacy
}

extension MIRAAPIClient {
  func verifyAuraDocument(_ document: AuraLocalDocument) async throws -> AuraDocumentVerificationResult {
    let upload = try document.verificationUpload()
    return try await uploadMultipart(
      "/aura/documents/verify?type=\(document.kind.rawValue)",
      fileName: upload.filename,
      mimeType: upload.mediaType,
      data: upload.data
    )
  }
}
