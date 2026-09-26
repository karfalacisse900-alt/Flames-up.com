import SwiftUI
@_spi(CustomerSessionBetaAccess) import StripePaymentSheet
import StripePayments
import os

struct CaptroPaymentSheetView: View {
  let api: MIRAAPIClient
  let configuration: CaptroPaymentConfiguration
  let purchase: CaptroCommercePurchase
  @Environment(\.dismiss) private var dismiss
  @State private var sheet: PaymentSheet?
  @State private var refreshedConfiguration: CaptroPaymentConfiguration?
  @State private var needsFreshSession = false
  @State private var preparingPayment = false
  private var activeConfiguration: CaptroPaymentConfiguration { refreshedConfiguration ?? configuration }
  private let paymentLog = Logger(subsystem: "com.captro.app", category: "buyer-checkout")
  @State private var showingPayment = false
  @State private var confirming = false
  @State private var paid = false
  @State private var message: String?

  var body: some View {
    NavigationStack {
      ScrollView {
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
          Button { Task { await openPayment() } } label: {
            Label("Continue to Payment", systemImage: "lock.fill")
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .disabled(preparingPayment || showingPayment)
          .overlay(alignment: .trailing) { if preparingPayment { ProgressView() } }
          .paymentSheet(isPresented: $showingPayment, paymentSheet: sheet, onCompletion: handlePayment)
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      }
      .background(MIRATheme.Color.surface)
      .foregroundStyle(MIRATheme.Color.textPrimary)
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
    let configuration = activeConfiguration
    guard
          ["test", "live"].contains(configuration.mode),
          configuration.publishableKey.hasPrefix("pk_\(configuration.mode)_"),
          configuration.purchaseId == purchase.id,
          configuration.paymentIntentClientSecret.hasPrefix("pi_"),
          configuration.paymentIntentClientSecret.contains("_secret_") else {
      message = "Secure checkout could not be verified. Close this screen and try again. Your card has not been charged."
      return
    }
    var settings = PaymentSheet.Configuration()
    settings.apiClient = STPAPIClient(publishableKey: configuration.publishableKey)
    settings.merchantDisplayName = configuration.merchantDisplayName
    settings.returnURL = configuration.returnURL
    settings.allowsDelayedPaymentMethods = false
    settings.savePaymentMethodOptInBehavior = .requiresOptIn
    // Buyers pay Captro as Stripe Customers. Keep the billing details on their
    // PaymentMethod so card checks include the cardholder name and postal address.
    settings.billingDetailsCollectionConfiguration.name = .always
    settings.billingDetailsCollectionConfiguration.address = .full
    if let customerId = configuration.customerId,
       let customerSessionClientSecret = configuration.customerSessionClientSecret,
       customerId.hasPrefix("cus_"), customerSessionClientSecret.hasPrefix("cuss_") {
      settings.customer = .init(
        id: customerId,
        customerSessionClientSecret: customerSessionClientSecret
      )
    }
    // Enabled only in builds provisioned with this real Apple merchant identifier.
    if let merchant = configuration.applePayMerchantId,
       Bundle.main.object(forInfoDictionaryKey: "CaptroApplePayMerchantIdentifier") as? String == merchant {
      settings.applePay = .init(merchantId: merchant, merchantCountryCode: configuration.merchantCountryCode)
    }
    sheet = PaymentSheet(paymentIntentClientSecret: configuration.paymentIntentClientSecret, configuration: settings)
  }

  @MainActor
  private func openPayment() async {
    guard !preparingPayment, !showingPayment, !confirming, !paid else { return }
    preparingPayment = true
    defer { preparingPayment = false }
    if needsFreshSession {
      do {
        // Resume the SAME order/intent; a retry must never create another charge.
        let response = try await api.continueCommerceCheckout(purchaseId: purchase.id)
        if response.purchase.status == "confirmed" { paid = true; message = nil; return }
        guard let fresh = response.paymentSheet else {
          message = "This checkout is no longer payable. Close it and check your purchases."
          return
        }
        refreshedConfiguration = fresh
        prepare()
      } catch {
        trace("session_refresh_failed", error: error)
        message = "We couldn't reconnect to checkout. Try again."
        return
      }
    }
    guard sheet != nil else { return }
    needsFreshSession = true
    trace("presented")
    showingPayment = true
  }

  private func trace(_ stage: String, error: Error? = nil) {
    // Release/TestFlight diagnostics: only structured identifiers and allowlisted
    // Stripe metadata. Never dump userInfo, credentials, URLs or card details.
    let config = activeConfiguration
    let intentID = String(config.paymentIntentClientSecret.components(separatedBy: "_secret_").first ?? "")
    var fields: [String: Any] = ["stage": stage, "orderId": purchase.id,
      "mode": config.mode, "paymentIntentId": intentID, "customerId": config.customerId ?? "none",
      "endpoint": "Stripe PaymentSheet", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
    if let error {
      fields["errorType"] = String(reflecting: type(of: error))
      var chain: [[String: Any]] = []
      var current: NSError? = error as NSError
      for _ in 0..<4 {
        guard let failure = current else { break }
        var entry: [String: Any] = ["domain": failure.domain, "code": failure.code]
        for (label, key) in ["stripeCode": "StripeErrorCodeKey", "stripeType": "StripeErrorTypeKey",
                             "declineCode": "DeclineCodeKey", "requestId": "StripeRequestIDKey"] {
          if let value = failure.userInfo["com.stripe.lib:" + key] as? String,
             value.range(of: "^[A-Za-z0-9_]{1,100}$", options: .regularExpression) != nil {
            entry[label] = value
          }
        }
        entry["httpStatus"] = failure.userInfo["com.stripe.lib:HTTPStatusCodeKey"] as? Int
        chain.append(entry)
        current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
      }
      fields["errors"] = chain
      // SDK-owned integration diagnostics explain configuration failures. Do not
      // serialize arbitrary provider error text which can contain personal data.
      if let sdk = error as? PaymentSheetError {
        switch sdk {
        case .integrationError(let description):
          fields["sdkError"] = description.replacingOccurrences(
            of: "(?:pi_|seti_|cuss_|ek_|sk_|rk_|pk_)[A-Za-z0-9_]+", with: "[redacted]", options: .regularExpression)
        case .invalidClientSecret: fields["sdkError"] = "invalidClientSecret"
        case .alreadyPresented: fields["sdkError"] = "alreadyPresented"
        case .paymentIntentInTerminalState(let status): fields["sdkError"] = "paymentIntentInTerminalState: \(status)"
        default: fields["sdkError"] = "PaymentSheetError code: \((error as NSError).code)"
        }
      }
    }
    if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
      paymentLog.error("\(line, privacy: .public)")
    }
  }

  private func paymentFailureMessage(_ error: Error) -> String {
    let failure = error as NSError
    let code = failure.userInfo["com.stripe.lib:StripeErrorCodeKey"] as? String
    switch code {
    case "card_declined": return "Your card was declined. Try another payment method."
    case "expired_card": return "This card has expired. Choose another payment method."
    case "resource_missing": return "This saved payment method is no longer available. Choose another payment method."
    default:
      if failure.domain == NSURLErrorDomain { return "We couldn't connect. Try again." }
      return "Payment couldn't be completed. Please choose another payment method."
    }
  }

  private func handlePayment(_ result: PaymentSheetResult) {
    switch result {
    case .completed:
      trace("completed_awaiting_server")
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
      trace("canceled")
      message = nil
    case .failed(let error):
      trace("failed", error: error)
      needsFreshSession = true
      message = paymentFailureMessage(error)
    }
  }
}
