import SwiftUI
@_spi(CustomerSessionBetaAccess) import StripePaymentSheet
import StripePayments

@MainActor
private final class CaptroPaymentsModel: ObservableObject {
  let api: MIRAAPIClient
  @Published var methods: [CaptroSavedPaymentMethod] = []
  @Published var payoutAccount: CaptroPayoutAccount?
  @Published var customerSheet: CustomerSheet?
  @Published var hostedDestination: CaptroCheckoutDestination?
  @Published var isLoadingCards = false
  @Published var isLoadingPayout = false
  @Published var cardError: String?
  @Published var payoutError: String?

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func load() async {
    await refreshPaymentMethods()
    await refreshPayoutAccount()
    if customerSheet == nil { await prepareCustomerSheet() }
  }

  func refreshPaymentMethods() async {
    isLoadingCards = true
    defer { isLoadingCards = false }
    do {
      let response = try await api.loadPaymentMethods()
      methods = response.methods
      cardError = nil
    } catch {
      cardError = apiMessage(error, fallback: "Could not load your payment cards.")
    }
  }

  func refreshPayoutAccount() async {
    isLoadingPayout = true
    defer { isLoadingPayout = false }
    do {
      payoutAccount = try await api.loadPayoutAccount().account
      payoutError = nil
    } catch {
      payoutError = apiMessage(error, fallback: "Could not load your payout method.")
    }
  }

  func prepareCustomerSheet() async {
    do {
      let initialSession = try await api.createPaymentMethodSession()
      guard ["test", "live"].contains(initialSession.mode),
            initialSession.publishableKey.hasPrefix("pk_\(initialSession.mode)_"),
            initialSession.customerId.hasPrefix("cus_"),
            initialSession.customerSessionClientSecret.hasPrefix("cuss_") else {
        throw CaptroPaymentsError.invalidConfiguration
      }
      let stripeClient = STPAPIClient(publishableKey: initialSession.publishableKey)
      var configuration = CustomerSheet.Configuration()
      configuration.apiClient = stripeClient
      configuration.merchantDisplayName = initialSession.merchantDisplayName
      configuration.headerTextForSelectionScreen = "Payment cards"
      configuration.returnURL = initialSession.returnURL
      configuration.billingDetailsCollectionConfiguration.name = .always
      configuration.billingDetailsCollectionConfiguration.address = .automatic
      configuration.removeSavedPaymentMethodMessage = "Remove this card from your Captro payment methods?"

      let intentConfiguration = CustomerSheet.IntentConfiguration(paymentMethodTypes: ["card"]) { [api] in
        let setup = try await api.createPaymentMethodSetup(requestId: UUID().uuidString)
        guard ["test", "live"].contains(setup.mode),
              setup.setupIntentClientSecret.hasPrefix("seti_") else {
          throw CaptroPaymentsError.invalidConfiguration
        }
        return setup.setupIntentClientSecret
      }
      customerSheet = CustomerSheet(
        configuration: configuration,
        intentConfiguration: intentConfiguration,
        customerSessionClientSecretProvider: { [api] in
          let session = try await api.createPaymentMethodSession()
          guard session.customerId.hasPrefix("cus_"),
                session.customerSessionClientSecret.hasPrefix("cuss_") else {
            throw CaptroPaymentsError.invalidConfiguration
          }
          return CustomerSessionClientSecret(
            customerId: session.customerId,
            clientSecret: session.customerSessionClientSecret
          )
        }
      )
      cardError = nil
    } catch {
      customerSheet = nil
      cardError = apiMessage(error, fallback: "Could not open secure card setup.")
    }
  }

  func handleCustomerSheet(_ result: CustomerSheet.CustomerSheetResult) {
    switch result {
    case .selected, .canceled:
      Task { await refreshPaymentMethods() }
    case .error(let error):
      cardError = error.localizedDescription
    }
  }

  func payoutLink(manage: Bool) async -> CaptroHostedAccountLinkResponse? {
    guard !isLoadingPayout else { return nil }
    isLoadingPayout = true
    defer { isLoadingPayout = false }
    do {
      let link = manage
        ? try await api.createPayoutManagementLink()
        : try await api.createPayoutOnboardingLink()
      payoutError = nil
      return link
    } catch {
      payoutError = payoutAPIMessage(error, fallback: "Could not open secure payout card setup. Please try again.")
      return nil
    }
  }

  var savedDebitCards: [CaptroSavedPaymentMethod] {
    methods.filter { $0.funding.lowercased() == "debit" }
  }

  private func apiMessage(_ error: Error, fallback: String) -> String {
    (error as? MIRAAPIError)?.errorDescription ?? fallback
  }

  private func payoutAPIMessage(_ error: Error, fallback: String) -> String {
    guard case let MIRAAPIError.server(_, code, _) = error else { return fallback }
    switch code {
    case "COMMERCE_PAYOUT_EMAIL_REQUIRED":
      return "Add a valid email address to your Captro profile before setting up payouts."
    case "CAPTRO_PAYOUT_ACCOUNT_CONFLICT":
      return "We could not verify your existing payout setup securely. Please contact Captro support."
    default:
      return fallback
    }
  }
}

private enum CaptroPaymentsError: LocalizedError {
  case invalidConfiguration

  var errorDescription: String? {
    "The secure payment configuration could not be verified."
  }
}

struct CaptroPaymentsView: View {
  @StateObject private var model: CaptroPaymentsModel
  @StateObject private var payoutOnboarding = CaptroPayoutOnboardingCoordinator()
  @State private var showingCustomerSheet = false
  @State private var payoutDebitCardPendingConfirmation: CaptroSavedPaymentMethod?

  init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: CaptroPaymentsModel(api: api))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        paymentCardsSection
        divider
        payoutSection
        divider
        earningsLink
      }
    }
    .background(Color.white)
    .foregroundStyle(CaptroDetailStyle.ink)
    .navigationTitle("Payments")
    .navigationBarTitleDisplayMode(.inline)
    .miraHideTabBarOnAppear()
    .task { await model.load() }
    .refreshable { await model.load() }
    .sheet(item: $model.hostedDestination, onDismiss: {
      Task { await model.refreshPayoutAccount() }
    }) { destination in
      CaptroCheckoutBrowser(url: destination.url).ignoresSafeArea()
    }
    .confirmationDialog(
      "Use this debit card for payouts?",
      isPresented: Binding(
        get: { payoutDebitCardPendingConfirmation != nil },
        set: { if !$0 { payoutDebitCardPendingConfirmation = nil } }
      ),
      titleVisibility: .visible,
      presenting: payoutDebitCardPendingConfirmation
    ) { card in
      Button("Continue with Stripe") {
        payoutDebitCardPendingConfirmation = nil
        openPayoutSetup(manage: false)
      }
      Button("Cancel", role: .cancel) {
        payoutDebitCardPendingConfirmation = nil
      }
    } message: { card in
      Text("Stripe will securely verify \(card.brand) ending in \(card.last4) for payouts. Captro never copies or stores card details.")
    }
  }

  private var paymentCardsSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading("PAYMENT CARDS")
      if model.isLoadingCards && model.methods.isEmpty {
        ProgressView("Loading cards...").frame(minHeight: 48)
      } else if model.methods.isEmpty {
        Text("No saved payment card")
          .font(.system(size: 15, weight: .semibold))
      } else {
        ForEach(model.methods) { method in
          HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(CaptroDetailStyle.accent)
              .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
              Text("\(method.brand) ···· \(method.last4)")
                .font(.system(size: 15, weight: .semibold))
              Text("Expires \(String(format: "%02d", method.expirationMonth))/\(String(method.expirationYear).suffix(2))")
                .font(.system(size: 12))
                .foregroundStyle(CaptroDetailStyle.secondary)
            }
            Spacer(minLength: 8)
            Text(method.funding.capitalized)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(CaptroDetailStyle.secondary)
          }
          .frame(minHeight: 50)
        }
      }

      Text("Debit and credit cards saved here are available when you pay in Captro.")
        .font(.system(size: 13))
        .foregroundStyle(CaptroDetailStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if !model.methods.isEmpty, model.payoutAccount?.ready != true {
        Text("Your payment card is ready for purchases. To receive sales earnings, choose an eligible debit card in Payout Card below.")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.ink)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let customerSheet = model.customerSheet {
        Button {
          showingCustomerSheet = true
        } label: {
          Label(model.methods.isEmpty ? "Add Payment Card" : "Manage Payment Cards", systemImage: "creditcard")
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .background(CaptroDetailStyle.accent)
        .buttonStyle(.plain)
        .customerSheet(
          isPresented: $showingCustomerSheet,
          customerSheet: customerSheet,
          onCompletion: model.handleCustomerSheet
        )
      } else {
        Button {
          Task { await model.prepareCustomerSheet() }
        } label: {
          Label("Try Card Setup Again", systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .background(CaptroDetailStyle.accent)
        .buttonStyle(.plain)
        .disabled(model.isLoadingCards)
      }
      if let cardError = model.cardError {
        Text(cardError).font(.system(size: 12)).foregroundStyle(.red)
      }
    }
    .padding(16)
  }

  private var payoutSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading("PAYOUT CARD")
      if let account = model.payoutAccount {
        if let card = account.payoutCard {
          HStack(spacing: 12) {
            Image(systemName: "rectangle.and.hand.point.up.left.filled")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(CaptroDetailStyle.accent)
              .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
              Text("\(card.brand) Debit ···· \(card.last4)")
                .font(.system(size: 15, weight: .semibold))
              Text(account.ready ? "Ready for earnings" : "Setup needs attention")
                .font(.system(size: 12))
                .foregroundStyle(CaptroDetailStyle.secondary)
            }
            Spacer(minLength: 8)
            if account.ready {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(CaptroDetailStyle.accent)
            }
          }
          .frame(minHeight: 50)
        } else {
          Text(account.payoutCardStatusTitle)
            .font(.system(size: 15, weight: .semibold))
        }
        Text(account.payoutCardGuidance)
          .font(.system(size: 13))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text("You do not need to create or connect a separate Stripe account. Captro manages the secure payout profile behind the scenes. Credit cards cannot receive payouts.")
          .font(.system(size: 12))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if account.payoutCard == nil, !model.savedDebitCards.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("USE A SAVED DEBIT CARD")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(CaptroDetailStyle.secondary)
            Text("Select a debit card you already use for purchases. Stripe will securely confirm it again before Captro can send payouts.")
              .font(.system(size: 12))
              .foregroundStyle(CaptroDetailStyle.secondary)
              .fixedSize(horizontal: false, vertical: true)
            ForEach(model.savedDebitCards) { card in
              Button {
                payoutDebitCardPendingConfirmation = card
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: "creditcard.fill")
                    .foregroundStyle(CaptroDetailStyle.accent)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Use \(card.brand) ending in \(card.last4) for Payouts")
                      .font(.system(size: 14, weight: .semibold))
                    Text("Securely confirm this debit card with Stripe")
                      .font(.system(size: 12))
                      .foregroundStyle(CaptroDetailStyle.secondary)
                  }
                  Spacer(minLength: 8)
                  Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CaptroDetailStyle.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.horizontal, 12)
                .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
              }
              .buttonStyle(.plain)
              .disabled(model.isLoadingPayout)
            }
          }
        }
        Button(account.payoutCardActionTitle) {
          openPayoutSetup(manage: account.ready)
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 46)
        .foregroundStyle(CaptroDetailStyle.ink)
        .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
        .buttonStyle(.plain)
        .disabled(model.isLoadingPayout)
      } else if model.isLoadingPayout {
        ProgressView("Loading payout method...").frame(minHeight: 48)
      } else {
        Button("Try Payout Card Setup Again") {
          Task { await model.refreshPayoutAccount() }
        }
        .font(.system(size: 14, weight: .semibold))
      }
      if let payoutError = model.payoutError {
        Text(payoutError).font(.system(size: 12)).foregroundStyle(.red)
      }
    }
    .padding(16)
  }

  private var earningsLink: some View {
    NavigationLink {
      CaptroEarningsView(api: model.api)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Earnings and Payouts").font(.system(size: 15, weight: .semibold))
          Text("Balance, sales, withdrawals, and payout history")
            .font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.secondary)
      }
      .frame(minHeight: 58)
      .padding(16)
    }
    .buttonStyle(.plain)
  }

  private func sectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(CaptroDetailStyle.secondary)
  }

  private var divider: some View {
    Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
  }

  private func openPayoutSetup(manage: Bool) {
    if !manage {
      guard !model.isLoadingPayout else { return }
      model.isLoadingPayout = true
      model.payoutError = nil
      payoutOnboarding.start(api: model.api) { result in
        model.isLoadingPayout = false
        switch result {
        case .success(.complete):
          Task { await model.refreshPayoutAccount() }
        case .success(.refresh):
          openPayoutSetup(manage: false)
        case .success(.cancelled):
          break
        case .failure(let error):
          model.payoutError = error.localizedDescription
        }
      }
      return
    }

    Task {
      guard let link = await model.payoutLink(manage: true),
            let url = URL(string: link.url) else { return }
      if link.flow == "management" {
        model.hostedDestination = CaptroCheckoutDestination(url: url)
      } else {
        openPayoutSetup(manage: false)
      }
    }
  }
}
