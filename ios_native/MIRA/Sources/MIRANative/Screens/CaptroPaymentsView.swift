import SwiftUI
@_spi(CustomerSessionBetaAccess) import StripePaymentSheet
import StripePayments

@MainActor
final class CaptroPaymentsModel: ObservableObject {
  let api: MIRAAPIClient
  let earningsModel: CaptroEarningsModel
  @Published var methods: [CaptroSavedPaymentMethod] = []
  @Published var payoutAccount: CaptroPayoutAccount?
  @Published var customerSheet: CustomerSheet?
  @Published var isLoadingCards = false
  @Published var isLoadingPayout = false
  @Published var isPreparingCardSetup = false
  @Published var cardError: String?
  @Published var payoutError: String?
  private var currentUserId = ""
  private var lastRefreshAttemptAt: Date?

  init(api: MIRAAPIClient) {
    self.api = api
    self.earningsModel = CaptroEarningsModel(api: api)
  }

  func configure(currentUserId: String) {
    guard self.currentUserId != currentUserId else { return }
    self.currentUserId = currentUserId
    earningsModel.configure(currentUserId: currentUserId)
    methods = []
    payoutAccount = nil
    customerSheet = nil
    cardError = nil
    payoutError = nil
    isLoadingCards = false
    isLoadingPayout = false
    isPreparingCardSetup = false
    lastRefreshAttemptAt = nil
  }

  func load(forceRefresh: Bool = false) async {
    if !forceRefresh, let lastRefreshAttemptAt,
       Date().timeIntervalSince(lastRefreshAttemptAt) < 30 { return }
    lastRefreshAttemptAt = Date()
    // Neither section waits for the other, and secure card setup only starts
    // after an explicit tap on its action.
    async let cards: Void = refreshPaymentMethods()
    async let payout: Void = refreshPayoutAccount()
    _ = await (cards, payout)
  }

  func refreshPaymentMethods() async {
    guard !isLoadingCards else { return }
    isLoadingCards = true
    let accountID = currentUserId
    defer { if accountID == currentUserId { isLoadingCards = false } }
    do {
      let response = try await api.loadPaymentMethods()
      guard accountID == currentUserId else { return }
      methods = response.methods
      cardError = nil
      MIRAPerformanceTimeline.mark("payment_cards_confirmed")
    } catch {
      guard accountID == currentUserId else { return }
      cardError = apiMessage(error, fallback: "Could not load your payment cards.")
    }
  }

  func refreshPayoutAccount() async {
    guard !isLoadingPayout else { return }
    isLoadingPayout = true
    let accountID = currentUserId
    defer { if accountID == currentUserId { isLoadingPayout = false } }
    do {
      let freshAccount = try await api.loadPayoutAccount().account
      guard accountID == currentUserId else { return }
      payoutAccount = freshAccount
      payoutError = nil
      MIRAPerformanceTimeline.mark("payout_method_confirmed")
    } catch {
      guard accountID == currentUserId else { return }
      payoutError = apiMessage(error, fallback: "Could not load your payout method.")
    }
  }

  func prepareCustomerSheet() async {
    guard !isPreparingCardSetup else { return }
    isPreparingCardSetup = true
    let accountID = currentUserId
    defer { if accountID == currentUserId { isPreparingCardSetup = false } }
    do {
      let initialSession = try await api.createPaymentMethodSession()
      guard accountID == currentUserId else { return }
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
      configuration.billingDetailsCollectionConfiguration.address = .full
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
      guard accountID == currentUserId else { return }
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

  private func apiMessage(_ error: Error, fallback: String) -> String {
    (error as? MIRAAPIError)?.errorDescription ?? fallback
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

  init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: CaptroPaymentsModel(api: api))
  }

  init(api: MIRAAPIClient, model: CaptroPaymentsModel) {
    _model = StateObject(wrappedValue: model)
  }

  private var savedDebitCards: [CaptroSavedPaymentMethod] {
    model.methods.filter { $0.funding.lowercased() == "debit" }
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
    .background(MIRATheme.Color.surface)
    .foregroundStyle(CaptroDetailStyle.ink)
    .navigationTitle("Payments")
    .navigationBarTitleDisplayMode(.inline)
    .miraHideTabBarOnAppear()
    .onAppear {
      MIRAPerformanceTimeline.mark("payments_screen_visible", detail: model.methods.isEmpty ? "empty" : "retained")
    }
    .task { await model.load() }
    .refreshable { await model.load(forceRefresh: true) }
  }

  private var paymentCardsSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading("PAYMENT CARDS")
      if model.isLoadingCards && !model.methods.isEmpty {
        ProgressView("Checking payment cards...")
          .font(.system(size: 12))
      }
      if model.isLoadingCards && model.methods.isEmpty {
        ProgressView("Loading cards...").frame(minHeight: 48)
      } else if model.methods.isEmpty {
        Text("No saved payment card")
          .font(.system(size: 15, weight: .semibold))
      } else {
        ForEach(model.methods) { method in
          HStack(spacing: 12) {
            Image(systemName: "creditcard")
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

      Text("You are a Captro customer when you pay—no Stripe account connection is needed for purchases.")
        .font(.system(size: 12))
        .foregroundStyle(CaptroDetailStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if !model.methods.isEmpty, model.payoutAccount?.ready != true {
        Text("Your payment card is ready for purchases. To receive sales earnings, add an eligible debit card in Seller Setup below.")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(CaptroDetailStyle.ink)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let customerSheet = model.customerSheet {
        Button {
          openCardSetup()
        } label: {
          Label(model.methods.isEmpty ? "Add Payment Card" : "Manage Payment Cards", systemImage: "creditcard")
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.onPrimary)
        .padding(.vertical, 6)
        .background(MIRATheme.Color.forest, in: RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
        .buttonStyle(.miraPress)
        .customerSheet(
          isPresented: $showingCustomerSheet,
          customerSheet: customerSheet,
          onCompletion: model.handleCustomerSheet
        )
      } else {
        Button {
          openCardSetup()
        } label: {
          Label(model.methods.isEmpty ? "Add Payment Card" : "Manage Payment Cards", systemImage: "creditcard")
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.onPrimary)
        .padding(.vertical, 6)
        .background(MIRATheme.Color.forest, in: RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
        .buttonStyle(.miraPress)
        .disabled(model.isPreparingCardSetup)
      }
      if model.isPreparingCardSetup {
        ProgressView("Opening secure card setup...")
          .font(.system(size: 12))
      }
      if let cardError = model.cardError {
        Text(cardError).font(.system(size: 12)).foregroundStyle(.red)
      }
    }
    .padding(16)
  }

  private var payoutSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading("SELLER SETUP")
      if model.isLoadingPayout && model.payoutAccount != nil {
        ProgressView("Checking payout method...")
          .font(.system(size: 12))
      }
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
        Text("Before your paid listings can accept purchases, complete the business and identity details Stripe requires, accept its terms, and add an eligible payout destination. Saving a payment card does not complete seller setup. Buying and free posts do not require seller setup. Credit cards cannot receive payouts.")
          .font(.system(size: 12))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if account.payoutCard == nil && !savedDebitCards.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("ADD A PAYOUT DEBIT CARD")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(CaptroDetailStyle.secondary)
            ForEach(savedDebitCards) { method in
              Button {
                openPayoutSetup()
              } label: {
                Label("Use \(method.brand) ···· \(method.last4) for payouts", systemImage: "creditcard")
                  .frame(maxWidth: .infinity, minHeight: 44)
              }
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(CaptroDetailStyle.ink)
              .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
              .buttonStyle(.plain)
              .disabled(model.isLoadingPayout)
            }
            Text("For security, enter this same debit card in the next screen. Captro never copies your saved card details.")
              .font(.system(size: 12))
              .foregroundStyle(CaptroDetailStyle.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Button(account.ready ? account.payoutCardActionTitle : "Continue Seller Setup") {
          openPayoutSetup()
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
      CaptroEarningsView(api: model.api, model: model.earningsModel)
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

  private func openPayoutSetup() {
    guard !model.isLoadingPayout else { return }
    model.isLoadingPayout = true
    model.payoutError = nil
    payoutOnboarding.start(api: model.api) { result in
      model.isLoadingPayout = false
      switch result {
      case .success(.complete):
        Task { await model.refreshPayoutAccount() }
      case .failure(let error):
        model.payoutError = error.localizedDescription
      }
    }
  }

  private func openCardSetup() {
    guard !model.isPreparingCardSetup else { return }
    Task {
      await model.prepareCustomerSheet()
      if model.customerSheet != nil { showingCustomerSheet = true }
    }
  }
}
