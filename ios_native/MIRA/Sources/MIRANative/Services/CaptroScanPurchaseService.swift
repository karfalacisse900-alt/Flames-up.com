import Foundation
import StoreKit

enum CaptroScanPurchaseError: Error, LocalizedError {
  case productUnavailable
  case pending
  case unverified

  var errorDescription: String? {
    switch self {
    case .productUnavailable: return "Verification credits are not available from the App Store right now."
    case .pending: return "The App Store purchase is pending approval. No verification has started."
    case .unverified: return "The App Store could not verify this purchase."
    }
  }
}

@MainActor
final class CaptroScanPurchaseService: ObservableObject {
  static let creditProductID = "com.captro.scan.credits.10"

  @Published private(set) var product: Product?
  @Published private(set) var balanceCents = 0
  @Published private(set) var verificationPriceCents = 10
  @Published private(set) var isLoading = false

  private let api: MIRAAPIClient

  init(api: MIRAAPIClient) {
    self.api = api
  }

  var localizedPackPrice: String {
    product?.displayPrice ?? "$0.99"
  }

  var availableVerifications: Int {
    guard verificationPriceCents > 0 else { return 0 }
    return balanceCents / verificationPriceCents
  }

  func prepare() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      product = try await Product.products(for: [Self.creditProductID]).first
      try await redeemUnfinishedTransactions()
      try await refreshBalance()
    } catch {
      try? await refreshBalance()
    }
  }

  func refreshBalance() async throws {
    let response = try await api.captroScanBalance()
    balanceCents = response.balanceCents
    verificationPriceCents = response.verificationPriceCents
  }

  /// Returns false only when the customer cancels the App Store purchase sheet.
  func purchaseCreditPack() async throws -> Bool {
    if product == nil {
      product = try await Product.products(for: [Self.creditProductID]).first
    }
    guard let product else { throw CaptroScanPurchaseError.productUnavailable }
    let result = try await product.purchase()
    switch result {
    case .success(let verification):
      let transaction = try verified(verification)
      let redemption = try await api.redeemCaptroScanCredits(transactionID: String(transaction.id))
      balanceCents = redemption.balanceCents
      verificationPriceCents = redemption.verificationPriceCents
      await transaction.finish()
      return true
    case .pending:
      throw CaptroScanPurchaseError.pending
    case .userCancelled:
      return false
    @unknown default:
      return false
    }
  }

  private func redeemUnfinishedTransactions() async throws {
    for await result in Transaction.unfinished {
      let transaction = try verified(result)
      guard transaction.productID == Self.creditProductID else { continue }
      let redemption = try await api.redeemCaptroScanCredits(transactionID: String(transaction.id))
      balanceCents = redemption.balanceCents
      verificationPriceCents = redemption.verificationPriceCents
      await transaction.finish()
    }
  }

  private func verified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let value): return value
    case .unverified: throw CaptroScanPurchaseError.unverified
    }
  }
}
