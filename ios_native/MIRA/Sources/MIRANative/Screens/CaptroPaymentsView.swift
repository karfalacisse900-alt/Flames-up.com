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

enum CaptroPaymentSettingsPage {
  case overview, cards, payout
  var title: String {
    switch self { case .overview: return "Payments & payouts"; case .cards: return "Payment methods"; case .payout: return "Payout account" }
  }
}

struct CaptroPaymentsView: View {
  @StateObject private var model: CaptroPaymentsModel
  @StateObject private var payoutOnboarding = CaptroPayoutOnboardingCoordinator()
  @State private var showingCustomerSheet = false
  private let page: CaptroPaymentSettingsPage

  init(api: MIRAAPIClient) {
    _model = StateObject(wrappedValue: CaptroPaymentsModel(api: api))
    page = .overview
  }
  init(api: MIRAAPIClient, model: CaptroPaymentsModel, page: CaptroPaymentSettingsPage = .overview) {
    _model = StateObject(wrappedValue: model)
    self.page = page
  }

  var body: some View {
    SettingsDetailScaffold(title: page.title) {
      switch page {
      case .overview:
        SettingsCard(title: "Buying") {
          SettingsNavigationRow(title: "Payment methods", subtitle: "Cards saved for purchases", systemImage: "creditcard",
            destination: CaptroPaymentsView(api: model.api, model: model, page: .cards))
        }
        SettingsCard(title: "Selling") {
          if let account = model.payoutAccount, account.status != "not_started" {
            SettingsNavigationRow(title: "Your earnings", subtitle: "", systemImage: "dollarsign",
              destination: CaptroEarningsView(api: model.api, model: model.earningsModel))
            SettingsNavigationRow(title: "Payout account", subtitle: "", systemImage: "building.columns",
              destination: CaptroPaymentsView(api: model.api, model: model, page: .payout))
          } else if model.isLoadingPayout {
            ProgressView("Checking seller setup…")
          } else if let error = model.payoutError {
            Text(error).foregroundStyle(.red).font(.subheadline)
            Button("Try again") { Task { await model.refreshPayoutAccount() } }
          } else {
            SettingsNavigationRow(title: "Set up earnings", subtitle: "For creators who want to sell", systemImage: "building.columns",
              destination: CaptroPaymentsView(api: model.api, model: model, page: .payout))
          }
        }
      case .cards: paymentCardsSection
      case .payout: payoutSection
      }
    }
    .task { await refresh() }
    .refreshable { await refresh(force: true) }
  }

  private func refresh(force: Bool = false) async {
    switch page {
    case .overview: await model.refreshPayoutAccount()
    case .cards: await model.refreshPaymentMethods()
    case .payout: await model.refreshPayoutAccount()
    }
  }

  private var paymentCardsSection: some View {
    Group {
      Section {
        if model.isLoadingCards && model.methods.isEmpty { ProgressView("Loading payment methods…") }
        else if model.methods.isEmpty && model.cardError == nil {
          Text("No saved cards").foregroundStyle(.secondary)
        }
        ForEach(model.methods) { method in
          Label {
            VStack(alignment: .leading, spacing: 3) {
              Text("\(method.brand) •••• \(method.last4)")
              Text("Expires \(String(format: "%02d", method.expirationMonth))/\(String(method.expirationYear).suffix(2))")
                .font(.footnote).foregroundStyle(.secondary)
            }
          } icon: { Image(systemName: "creditcard").foregroundStyle(MIRATheme.Color.textPrimary) }
            .frame(minHeight: 44)
        }
        if let customerSheet = model.customerSheet {
          cardManagementButton.customerSheet(isPresented: $showingCustomerSheet, customerSheet: customerSheet, onCompletion: model.handleCustomerSheet)
        } else { cardManagementButton }
      } header: { Text("Saved cards") } footer: {
        Text("Saving a card is optional. Choose your payment method at checkout. Card details are securely managed by Stripe.")
      }
      if let error = model.cardError {
        Section { Text(error).font(.subheadline).foregroundStyle(.red)
          Button("Reload payment methods") { Task { await model.refreshPaymentMethods() } }
        }
      }
    }
  }

  private var cardManagementButton: some View {
    Button { openCardSetup() } label: {
      HStack {
        Label(model.methods.isEmpty ? "Add payment method" : "Manage payment methods", systemImage: "plus")
        Spacer()
        if model.isPreparingCardSetup { ProgressView() }
      }.frame(minHeight: 44)
    }.disabled(model.isPreparingCardSetup)
  }

  private var payoutSection: some View {
    Group {
      Section {
        if let account = model.payoutAccount {
          if let card = account.payoutCard {
            Label {
              VStack(alignment: .leading, spacing: 3) {
                Text("\(card.brand) Debit •••• \(card.last4)")
                Text(account.ready ? "Ready" : "Setup needs attention").font(.footnote).foregroundStyle(.secondary)
              }
            } icon: { Image(systemName: "building.columns") }.frame(minHeight: 44)
          } else { Text(account.payoutCardStatusTitle) }
          Text(account.payoutCardGuidance).font(.subheadline).foregroundStyle(.secondary)
          Button { openPayoutSetup() } label: {
            HStack { Text(account.ready ? "Manage payout method" : "Continue setup"); Spacer(); if model.isLoadingPayout { ProgressView() } }
              .frame(minHeight: 44)
          }.disabled(model.isLoadingPayout)
          SettingsNavigationRow(title: "Earnings & verification", subtitle: "", systemImage: "checkmark.shield",
            destination: CaptroEarningsView(api: model.api, model: model.earningsModel))
        } else if model.isLoadingPayout { ProgressView("Loading payout account…") }
      } header: { Text("Seller payouts") } footer: {
        Text("Complete the required identity and payout details to receive earnings. A card saved for purchases is not a payout destination.")
      }
      if let error = model.payoutError {
        Section { Text(error).foregroundStyle(.red).font(.subheadline)
          Button("Try again") { Task { await model.refreshPayoutAccount() } }
        }
      }
    }
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
