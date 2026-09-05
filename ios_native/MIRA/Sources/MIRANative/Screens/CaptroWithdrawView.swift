import SwiftUI

struct CaptroWithdrawView: View {
  let api: MIRAAPIClient
  @Environment(\.dismiss) private var dismiss
  @State private var earnings: CaptroEarningsResponse?
  @State private var quote: CaptroPayoutQuote?
  @State private var payout: CaptroPayout?
  @State private var amount = ""
  @State private var requestId = UUID().uuidString
  @State private var working = false
  @State private var error: String?
  @State private var hostedDestination: CaptroCheckoutDestination?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let payout {
            Text(CaptroMoney.format(minorUnits: payout.amount, currency: payout.currency)).font(.largeTitle.bold())
            Text(payout.status == "paid" ? "Paid" : payout.status == "failed" ? "Payout failed" : payout.status == "cancelled" ? "Cancelled" : "Processing")
              .font(.headline)
            if let failure = payout.failureMessage { Text(failure).font(.subheadline) }
            if ["failed", "cancelled"].contains(payout.status) {
              Button { retry() } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                .disabled(working)
              Button { changeCard() } label: { Label("Change Card", systemImage: "creditcard") }
                .disabled(working)
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
          } else if let quote {
            Text("Confirm Payout").font(.title2.bold())
            row("Amount", money(quote.amount, quote.currency))
            row("Debit Card", "\(quote.card.brand) ···· \(quote.card.last4)")
            row("Payout fee", money(quote.fee, quote.currency))
            Divider()
            row("You receive", money(quote.netAmount, quote.currency)).fontWeight(.bold)
            Button { submit(quote) } label: {
              Label("Withdraw \(money(quote.amount, quote.currency))", systemImage: "creditcard")
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).disabled(working)
          } else if let earnings {
            Text("Available for instant payout").font(.subheadline).foregroundStyle(.secondary)
            Text(money(earnings.balance.instantAvailable ?? 0, earnings.balance.currency)).font(.largeTitle.bold())
            if let card = earnings.account.payoutCard {
              row("Send to", "\(card.brand) Debit ···· \(card.last4)")
            }
            TextField("Amount", text: $amount).keyboardType(.decimalPad)
              .font(.title2).padding(.vertical, 12)
              .accessibilityLabel("Withdrawal amount in dollars")
              .onChange(of: amount) { _, _ in requestId = UUID().uuidString }
            Divider()
            Button { getQuote() } label: {
              Label("Continue", systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(working || minorAmount == nil || earnings.account.ready != true)
          } else { ProgressView("Loading payout balance...") }
          if working { ProgressView() }
          if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
        }
        .padding(20)
      }
      .background(Color.white).foregroundStyle(.black).tint(CaptroDetailStyle.accent)
      .navigationTitle("Withdraw").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
      .task {
        do { earnings = try await api.loadCreatorEarnings() }
        catch { self.error = "Could not retrieve your payout balance." }
      }
      .sheet(item: $hostedDestination) { destination in
        CaptroCheckoutBrowser(url: destination.url).ignoresSafeArea()
      }
      .task(id: payout?.id) {
        guard let id = payout?.id else { return }
        for _ in 0..<10 {
          guard ["pending", "in_transit"].contains(payout?.status ?? "") else { return }
          do {
            try await Task.sleep(for: .seconds(3))
            let history = try await api.loadCreatorPayouts()
            if let refreshed = history.payouts.first(where: { $0.id == id }) { payout = refreshed }
          } catch { return }
        }
      }
    }
  }

  private var minorAmount: Int? {
    let text = amount.trimmingCharacters(in: .whitespaces)
    guard text.range(of: "^[0-9]{1,4}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
          let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    let result = NSDecimalNumber(decimal: value * 100).intValue
    return result > 0 ? result : nil
  }

  private func money(_ value: Int, _ currency: String) -> String { CaptroMoney.format(minorUnits: value, currency: currency) }
  private func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) { Text(label); Spacer(); Text(value).multilineTextAlignment(.trailing) }
  }

  private func getQuote() {
    guard let amount = minorAmount, !working else { return }
    working = true; error = nil
    Task {
      defer { working = false }
      do { quote = try await api.quotePayout(amount: amount, requestId: requestId) }
      catch { self.error = (error as? MIRAAPIError)?.errorDescription ?? "Could not prepare this payout." }
    }
  }

  private func submit(_ quote: CaptroPayoutQuote) {
    guard !working else { return }
    working = true; error = nil
    Task {
      defer { working = false }
      do { payout = try await api.withdraw(quoteId: quote.id).payout }
      catch { self.error = (error as? MIRAAPIError)?.errorDescription ?? "Payout not confirmed. Retry or check Payout History." }
    }
  }

  private func retry() {
    guard !working else { return }
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        earnings = try await api.loadCreatorEarnings()
        payout = nil; quote = nil; requestId = UUID().uuidString
      } catch { self.error = "Could not refresh your available payout balance." }
    }
  }

  private func changeCard() {
    guard !working else { return }
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        let link = try await api.createPayoutManagementLink()
        if let url = URL(string: link.url) { hostedDestination = CaptroCheckoutDestination(url: url) }
      } catch { self.error = "Could not open payout method management." }
    }
  }
}
