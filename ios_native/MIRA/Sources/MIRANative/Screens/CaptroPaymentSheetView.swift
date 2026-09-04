import SwiftUI
import StripePaymentSheet
import StripePayments

struct CaptroPaymentSheetView: View {
  let api: MIRAAPIClient
  let configuration: CaptroPaymentConfiguration
  let purchase: CaptroCommercePurchase
  @Environment(\.dismiss) private var dismiss
  @State private var sheet: PaymentSheet?
  @State private var showingPayment = false
  @State private var confirming = false
  @State private var paid = false
  @State private var message: String?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text(purchase.itemTitle).font(.title2.bold())
        Text(purchase.priceLabel).font(.subheadline).foregroundStyle(.secondary)
        if configuration.mode == "test" {
          Text("Test payment").font(.caption.bold()).foregroundStyle(CaptroDetailStyle.accent)
        }
        Divider()
        amountRow("Item", purchase.itemAmount ?? purchase.unitAmount * purchase.quantity)
        amountRow("Service fee", purchase.serviceFeeAmount ?? 0)
        amountRow("Tax", purchase.taxAmount ?? 0)
        Divider()
        amountRow("Total", purchase.totalAmount).fontWeight(.bold)
        if let message { Text(message).font(.subheadline).accessibilityIdentifier("payment.status") }
        if paid {
          Label("Purchase Complete", systemImage: "checkmark.circle.fill")
          Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        } else if confirming {
          ProgressView("Confirming payment...")
        } else if let sheet {
          Button { showingPayment = true } label: {
            Label("Continue to Payment", systemImage: "lock.fill")
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .paymentSheet(isPresented: $showingPayment, paymentSheet: sheet, onCompletion: handlePayment)
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      .background(Color.white)
      .foregroundStyle(.black)
      .tint(CaptroDetailStyle.accent)
      .navigationTitle("Payment")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
      .task { prepare() }
    }
  }

  private func amountRow(_ title: String, _ value: Int) -> some View {
    HStack { Text(title); Spacer(); Text(CaptroMoney.format(minorUnits: value, currency: purchase.currency)) }
  }

  private func prepare() {
    guard sheet == nil,
          ["test", "live"].contains(configuration.mode),
          configuration.publishableKey.hasPrefix("pk_\(configuration.mode)_"),
          configuration.purchaseId == purchase.id else { return }
    var settings = PaymentSheet.Configuration()
    settings.apiClient = STPAPIClient(publishableKey: configuration.publishableKey)
    settings.merchantDisplayName = configuration.merchantDisplayName
    settings.returnURL = configuration.returnURL
    settings.allowsDelayedPaymentMethods = false
    // Enabled only in builds provisioned with this real Apple merchant identifier.
    if let merchant = configuration.applePayMerchantId,
       Bundle.main.object(forInfoDictionaryKey: "CaptroApplePayMerchantIdentifier") as? String == merchant {
      settings.applePay = .init(merchantId: merchant, merchantCountryCode: configuration.merchantCountryCode)
    }
    sheet = PaymentSheet(paymentIntentClientSecret: configuration.paymentIntentClientSecret, configuration: settings)
  }

  private func handlePayment(_ result: PaymentSheetResult) {
    switch result {
    case .completed:
      confirming = true
      Task {
        defer { confirming = false }
        // PaymentSheet completion is not an entitlement. Only our signed webhook grants it.
        for delay in [1, 2, 3, 5, 8] {
          try? await Task.sleep(for: .seconds(delay))
          guard !Task.isCancelled else { return }
          if let response: CaptroCommerceActionResponse = try? await api.get("/payments/purchases/\(purchase.id)") {
            if response.purchase.status == "confirmed" {
              paid = true
              message = nil
              return
            }
          }
        }
        sheet = nil
        message = "Payment is being confirmed. Your purchase will appear in My Stuff when confirmation arrives."
      }
    case .canceled:
      message = nil
    case .failed:
      message = "Payment could not be completed. Please try again."
    }
  }
}
