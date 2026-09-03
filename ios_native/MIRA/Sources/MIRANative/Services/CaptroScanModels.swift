import CryptoKit
import Foundation
import PDFKit
import UIKit

enum CaptroLocalDocumentError: Error, LocalizedError {
  case inaccessible
  case empty
  case tooLarge
  case unsupported
  case corrupt

  var errorDescription: String? {
    switch self {
    case .inaccessible: return "Captro could not securely read that file."
    case .empty: return "The selected document is empty."
    case .tooLarge: return "Documents must be 12 MiB or smaller."
    case .unsupported: return "Choose a JPG, PNG, HEIC/HEIF, or PDF document."
    case .corrupt: return "The selected document could not be decoded safely."
    }
  }
}

enum CaptroLocalDocumentSource: String {
  case camera = "Document Scanner"
  case fileImport = "Files Import"
  case photoLibrary = "Photo Library"

  var apiValue: String {
    switch self {
    case .camera: return "camera"
    case .fileImport: return "files"
    case .photoLibrary: return "photo_library"
    }
  }
}

enum CaptroDetectedDocumentType: String, Codable, Hashable {
  case receipt
  case invoice
  case unsupported

  var title: String {
    switch self {
    case .receipt: return "Receipt detected"
    case .invoice: return "Invoice detected"
    case .unsupported: return "Couldn't recognize document"
    }
  }
}

/// Sensitive document bytes stay in memory until Captro begins the private receipt review.
struct CaptroLocalDocument: Identifiable {
  static let maximumBytes = 12 * 1024 * 1024

  let id = UUID()
  let source: CaptroLocalDocumentSource
  let filename: String
  let mediaType: String
  let pages: [Data]
  let byteCount: Int
  let sha256Hex: String

  var firstPageImage: UIImage? {
    if mediaType == "application/pdf",
       let data = pages.first,
       let page = PDFDocument(data: data)?.page(at: 0) {
      return page.thumbnail(of: CGSize(width: 1_100, height: 1_500), for: .mediaBox)
    }
    guard let first = pages.first else { return nil }
    return UIImage(data: first)
  }

  func verificationUpload() throws -> (filename: String, mediaType: String, data: Data) {
    if pages.count == 1, let page = pages.first {
      return (filename, mediaType, page)
    }
    let pdf = PDFDocument()
    for (index, data) in pages.enumerated() {
      guard let image = UIImage(data: data), let page = PDFPage(image: image) else {
        throw CaptroLocalDocumentError.corrupt
      }
      pdf.insert(page, at: index)
    }
    guard let data = pdf.dataRepresentation(), !data.isEmpty else {
      throw CaptroLocalDocumentError.corrupt
    }
    guard data.count <= Self.maximumBytes else { throw CaptroLocalDocumentError.tooLarge }
    return ("Captro Scan.pdf", "application/pdf", data)
  }

  static func scanned(pages: [Data]) throws -> Self {
    try make(
      source: .camera,
      filename: "Captro Scan.jpg",
      mediaType: "image/jpeg",
      pages: pages
    )
  }

  static func imported(url: URL) throws -> Self {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }

    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values?.isRegularFile != false else { throw CaptroLocalDocumentError.inaccessible }
    guard let size = values?.fileSize, size > 0 else { throw CaptroLocalDocumentError.empty }
    guard size <= maximumBytes else { throw CaptroLocalDocumentError.tooLarge }

    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw CaptroLocalDocumentError.inaccessible
    }
    let mediaType = try detectAndValidate(data)
    return try make(
      source: .fileImport,
      filename: url.lastPathComponent,
      mediaType: mediaType,
      pages: [data]
    )
  }

  static func photoImported(data: Data) throws -> Self {
    guard !data.isEmpty else { throw CaptroLocalDocumentError.empty }
    guard data.count <= maximumBytes else { throw CaptroLocalDocumentError.tooLarge }
    let mediaType = try detectAndValidate(data)
    guard mediaType != "application/pdf" else { throw CaptroLocalDocumentError.unsupported }
    return try make(
      source: .photoLibrary,
      filename: "Captro Photo.\(fileExtension(for: mediaType))",
      mediaType: mediaType,
      pages: [data]
    )
  }

  static func privateDownload(data: Data) throws -> Self {
    guard !data.isEmpty else { throw CaptroLocalDocumentError.empty }
    guard data.count <= maximumBytes else { throw CaptroLocalDocumentError.tooLarge }
    let mediaType = try detectAndValidate(data)
    return try make(source: .fileImport, filename: "Original document", mediaType: mediaType, pages: [data])
  }

  private static func make(
    source: CaptroLocalDocumentSource,
    filename: String,
    mediaType: String,
    pages: [Data]
  ) throws -> Self {
    guard !pages.isEmpty, pages.allSatisfy({ !$0.isEmpty }) else {
      throw CaptroLocalDocumentError.empty
    }
    let byteCount = try pages.reduce(0) { partial, page in
      let total = partial.addingReportingOverflow(page.count)
      guard !total.overflow else { throw CaptroLocalDocumentError.tooLarge }
      return total.partialValue
    }
    guard byteCount <= maximumBytes else { throw CaptroLocalDocumentError.tooLarge }
    if mediaType != "application/pdf", !pages.allSatisfy({ UIImage(data: $0) != nil }) {
      throw CaptroLocalDocumentError.corrupt
    }
    return Self(
      source: source,
      filename: filename,
      mediaType: mediaType,
      pages: pages,
      byteCount: byteCount,
      sha256Hex: hash(pages: pages)
    )
  }

  private static func detectAndValidate(_ data: Data) throws -> String {
    if data.starts(with: Data("%PDF-".utf8)) {
      guard PDFDocument(data: data) != nil else { throw CaptroLocalDocumentError.corrupt }
      return "application/pdf"
    }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
      guard UIImage(data: data) != nil else { throw CaptroLocalDocumentError.corrupt }
      return "image/jpeg"
    }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      guard UIImage(data: data) != nil else { throw CaptroLocalDocumentError.corrupt }
      return "image/png"
    }
    if data.count >= 12,
       data[4..<8].elementsEqual(Data("ftyp".utf8)),
       ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(String(decoding: data[8..<12], as: UTF8.self)) {
      guard UIImage(data: data) != nil else { throw CaptroLocalDocumentError.corrupt }
      return "image/heic"
    }
    throw CaptroLocalDocumentError.unsupported
  }

  private static func fileExtension(for mediaType: String) -> String {
    switch mediaType {
    case "image/png": return "png"
    case "image/heic": return "heic"
    default: return "jpg"
    }
  }

  private static func hash(pages: [Data]) -> String {
    var hasher = SHA256()
    hasher.update(data: Data("CAPTRO_SCAN_DOCUMENT_V1".utf8))
    for page in pages {
      var length = UInt64(page.count).bigEndian
      withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
      hasher.update(data: page)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

struct CaptroScanCreditBalance: Decodable {
  let balanceCents: Int
  let verificationPriceCents: Int
}

struct CaptroScanCreditRedemption: Decodable {
  let credited: Bool
  let duplicate: Bool
  let balanceCents: Int
  let verificationPriceCents: Int
}

struct CaptroScanAddress: Decodable, Hashable {
  let original: String?
  let street: String?
  let city: String?
  let state: String?
  let postalCode: String?
  let country: String?
}

struct CaptroScanBusiness: Decodable, Hashable {
  let name: String?
  let address: CaptroScanAddress?
  let phone: String?
  let storeNumber: String?
}

struct CaptroScanCustomer: Decodable, Hashable {
  let name: String?
  let address: String?
}

struct CaptroScanLineItem: Decodable, Hashable, Identifiable {
  let description: String?
  let sku: String?
  let quantity: String?
  let unitPrice: String?
  let discount: String?
  let total: String?

  var id: String {
    [description, sku, quantity, unitPrice, total].compactMap { $0 }.joined(separator: "|")
  }
}

struct CaptroScanPayment: Decodable, Hashable {
  let method: String?
  let lastFour: String?
}

struct CaptroScanBarcode: Decodable, Hashable, Identifiable {
  let data: String?
  let type: String?
  var id: String { "\(type ?? "code"):\(data ?? "unknown")" }
}

struct CaptroScanCheck: Decodable, Hashable, Identifiable {
  let key: String
  let status: String
  let detail: String
  var id: String { key }
}

struct CaptroScanVerificationResult: Decodable, Identifiable {
  let verificationId: String
  let documentType: String
  let status: String
  let verdict: String?
  let business: CaptroScanBusiness?
  let customer: CaptroScanCustomer?
  let documentNumber: String?
  let transactionReference: String?
  let issueDate: String?
  let dueDate: String?
  let time: String?
  let items: [CaptroScanLineItem]
  let subtotal: String?
  let tax: String?
  let discount: String?
  let fees: String?
  let total: String?
  let currency: String?
  let payment: CaptroScanPayment?
  let paymentTerms: String?
  let barcodes: [CaptroScanBarcode]
  let checks: [CaptroScanCheck]
  let duplicateOf: String?
  let priceChargedCents: Int
  let billingState: String
  let proofId: String?
  let createdAt: String
  let completedAt: String?

  var id: String { verificationId }
  var isComplete: Bool { status == "verified" || status == "couldnt_verify" }
  var isVerified: Bool { status == "verified" }
}

struct CaptroScanProof: Decodable {
  let proofId: String
  let verificationId: String
  let documentType: String
  let summary: CaptroScanProofSummary
  let createdAt: String
}

struct CaptroScanProofSummary: Decodable {
  let businessName: String?
  let city: String?
  let state: String?
  let documentNumber: String?
  let issueDate: String?
  let total: String?
  let currency: String?
}

enum CaptroPurchaseCategory: String, Decodable, Hashable {
  case restaurantFood = "restaurant_food"
  case productRetail = "product_retail"
  case grocery
  case serviceBusiness = "service_business"
  case general

  var title: String {
    switch self {
    case .restaurantFood: return "Food purchase"
    case .productRetail: return "Retail purchase"
    case .grocery: return "Grocery purchase"
    case .serviceBusiness: return "Service purchase"
    case .general: return "Purchase"
    }
  }
}

struct CaptroReceiptReview: Decodable, Identifiable {
  let receiptId: String
  let documentType: String
  let status: String
  let merchantName: String?
  let category: CaptroPurchaseCategory
  let business: CaptroScanBusiness?
  let documentNumber: String?
  let transactionReference: String?
  let customer: CaptroScanCustomer?
  let dueDate: String?
  let paymentTerms: String?
  let fees: String?
  let discount: String?
  let checks: [CaptroScanCheck]?
  let verificationId: String?
  let providerDocumentId: String?
  let purchaseDate: String?
  let purchaseTime: String?
  let items: [CaptroScanLineItem]
  let subtotal: String?
  let tax: String?
  let total: String?
  let currency: String?
  let verdict: String?
  let rewardEligible: Bool
  let duplicate: Bool
  let rewardCents: Int
  let createdAt: String

  var id: String { receiptId }
}

struct CaptroReceiptRewardResult: Decodable {
  let rewarded: Bool
  let duplicate: Bool
  let rewardId: String
  let amountCents: Int
  let availableBalanceCents: Int
  let lifetimeEarnedCents: Int
  let currency: String
}

struct CaptroReceiptRewardBalance: Decodable, Equatable {
  let availableBalanceCents: Int
  let lifetimeEarnedCents: Int
  let lifetimeWithdrawnCents: Int
  let pendingRewardCents: Int
  let pendingWithdrawalCents: Int
  let currency: String
  let withdrawalEnabled: Bool
}

struct CaptroReceiptSubmission: Decodable, Identifiable, Hashable {
  let receiptId: String
  let documentType: String
  let status: String
  let verdict: String?
  let merchantName: String?
  let purchaseDate: String?
  let total: String?
  let currency: String?
  let earnedCents: Int
  let duplicate: Bool
  let createdAt: String

  var id: String { receiptId }
}

struct CaptroReceiptSubmissionHistory: Decodable {
  let submissions: [CaptroReceiptSubmission]
}

struct CaptroPrivateDocumentLink: Decodable {
  let signedUrl: URL
  let expiresIn: Int
}

private struct CaptroReceiptFeedbackBody: Encodable {
  let idempotencyKey: String
  let ratings: [String: Int]
  let note: String?
}

private struct CaptroStoreTransactionBody: Encodable {
  let transactionId: String
}

extension MIRAAPIClient {
  func reviewCaptroReceipt(
    _ document: CaptroLocalDocument,
    idempotencyKey: String
  ) async throws -> CaptroReceiptReview {
    let upload = try document.verificationUpload()
    return try await uploadMultipart(
      "/scan/receipts/review",
      fileName: upload.filename,
      mimeType: upload.mediaType,
      data: upload.data,
      fields: [
        "idempotencyKey": idempotencyKey,
        "source": document.source.apiValue,
      ]
    )
  }

  func captroReceiptReview(id: String) async throws -> CaptroReceiptReview {
    try await get("/scan/receipts/\(id)")
  }

  func captroReceiptSubmissionHistory() async throws -> [CaptroReceiptSubmission] {
    let response: CaptroReceiptSubmissionHistory = try await get("/scan/receipts/history")
    return response.submissions
  }

  func captroReceiptOriginalLink(id: String) async throws -> CaptroPrivateDocumentLink {
    try await get("/scan/receipts/\(id)/original")
  }

  func submitCaptroReceiptFeedback(
    receiptId: String,
    ratings: [String: Int],
    note: String?,
    idempotencyKey: String
  ) async throws -> CaptroReceiptRewardResult {
    let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await post(
      "/scan/receipts/\(receiptId)/feedback",
      body: CaptroReceiptFeedbackBody(
        idempotencyKey: idempotencyKey,
        ratings: ratings,
        note: normalizedNote?.isEmpty == false ? normalizedNote : nil
      )
    )
  }

  func captroReceiptRewardBalance() async throws -> CaptroReceiptRewardBalance {
    try await get("/scan/rewards/balance")
  }

  func captroScanBalance() async throws -> CaptroScanCreditBalance {
    try await get("/scan/credits")
  }

  func redeemCaptroScanCredits(transactionID: String) async throws -> CaptroScanCreditRedemption {
    try await post("/scan/credits/redeem", body: CaptroStoreTransactionBody(transactionId: transactionID))
  }

  func verifyCaptroDocument(
    _ document: CaptroLocalDocument,
    detectedType: CaptroDetectedDocumentType,
    idempotencyKey: String
  ) async throws -> CaptroScanVerificationResult {
    guard detectedType != .unsupported else { throw CaptroLocalDocumentError.unsupported }
    let upload = try document.verificationUpload()
    return try await uploadMultipart(
      "/scan/verify",
      fileName: upload.filename,
      mimeType: upload.mediaType,
      data: upload.data,
      fields: [
        "idempotencyKey": idempotencyKey,
        "detectedType": detectedType.rawValue,
      ]
    )
  }

  func captroScanVerification(id: String) async throws -> CaptroScanVerificationResult {
    try await get("/scan/verifications/\(id)")
  }

  func captroScanProof(id: String) async throws -> CaptroScanProof {
    try await get("/scan/proofs/\(id)")
  }
}
