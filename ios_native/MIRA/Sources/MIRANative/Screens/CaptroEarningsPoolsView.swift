import SwiftUI

struct CaptroEarningsPoolsSection: View {
  let api: MIRAAPIClient
  @ObservedObject var model: CaptroEarningsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("EARNINGS BY CATEGORY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if let response = model.pools {
        if response.mode == "test" { Label("Test payments — not real funds", systemImage: "testtube.2").font(.caption) }
        ForEach(response.pools) { pool in
          NavigationLink {
            CaptroEarningsPoolView(api: api, pool: pool, earnings: model)
          } label: {
            HStack(alignment: .center) {
              Text(pool.title).font(.body.weight(.semibold))
              Spacer(minLength: 12)
              VStack(alignment: .trailing, spacing: 3) {
                Text(pool.money(pool.available)).font(.body.monospacedDigit())
                Text("Available · \(pool.money(pool.pending)) pending").font(.caption).foregroundStyle(.secondary)
              }
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("earnings.pool.\(pool.category).\(pool.currency)")
          if pool.id != response.pools.last?.id { Divider() }
        }
        Text("Categories describe your earnings, not separate wallets. Withdrawals use your existing payout account across categories in the same currency.")
          .font(.caption).foregroundStyle(.secondary)
      } else if model.isLoadingPools {
        ProgressView("Loading categories…")
      }
      if let error = model.poolsError {
        Text(error).font(.callout).foregroundStyle(.secondary)
        Button("Retry categories") { Task { await model.loadPools(forceRefresh: true) } }
          .frame(minHeight: 44).disabled(model.isLoadingPools)
      }
    }
    .padding(16)
  }
}

@MainActor
final class CaptroEarningsPoolPageModel: ObservableObject {
  @Published var transactions: [CaptroPoolTransaction] = []
  @Published var payouts: [CaptroPoolPayout] = []
  @Published var error: String?
  @Published var loading = false
  @Published var loaded = false
  @Published var nextOffset: Int?
  private var generation = UUID()

  func cancel() { generation = UUID(); loading = false }

  func load(api: MIRAAPIClient, pool: CaptroEarningsPool, section: String, reset: Bool) async {
    if reset {
      generation = UUID()
      transactions = []; payouts = []; nextOffset = nil; loaded = false
    } else if loading || nextOffset == nil { return }
    let request = generation
    let offset = reset ? 0 : nextOffset ?? 0
    loading = true; error = nil
    defer { if generation == request { loading = false } }
    do {
      if section == "transactions" {
        let page: CaptroEarningsPoolPage<CaptroPoolTransaction> = try await api.loadCreatorPoolPage(pool, section: section, offset: offset)
        guard generation == request, !Task.isCancelled else { return }
        guard page.category == pool.category, page.currency == pool.currency, page.section == section else { throw URLError(.badServerResponse) }
        let known = Set(transactions.map(\.id))
        transactions += page.items.filter { !known.contains($0.id) }
        nextOffset = page.nextOffset
      } else {
        let page: CaptroEarningsPoolPage<CaptroPoolPayout> = try await api.loadCreatorPoolPage(pool, section: section, offset: offset)
        guard generation == request, !Task.isCancelled else { return }
        guard page.category == pool.category, page.currency == pool.currency, page.section == section else { throw URLError(.badServerResponse) }
        let known = Set(payouts.map(\.id))
        payouts += page.items.filter { !known.contains($0.id) }
        nextOffset = page.nextOffset
      }
      loaded = true
    } catch {
      guard generation == request, !Task.isCancelled else { return }
      self.error = "Could not load \(section). Your recorded earnings have not changed."
    }
  }
}

struct CaptroEarningsPoolView: View {
  let api: MIRAAPIClient
  let pool: CaptroEarningsPool
  @ObservedObject var earnings: CaptroEarningsModel
  @StateObject private var page = CaptroEarningsPoolPageModel()
  @State private var section = "transactions"
  private var current: CaptroEarningsPool { earnings.pools?.pools.first { $0.id == pool.id } ?? pool }
  private var requestKey: String { earnings.currentUserId + ":" + pool.id + ":" + section }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        summary
        if pool.category == "creator_support" { supportStatus }
        Divider()
        Picker("History", selection: $section) {
          Text("Transactions").tag("transactions")
          Text("Payout history").tag("payouts")
        }.pickerStyle(.segmented)
        if section == "transactions" {
          ForEach(page.transactions) { item in
            NavigationLink {
              CaptroEarningDetailView(api: api, earningID: item.id)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.title ?? current.title).font(.body.weight(.medium))
                  Text(CaptroCommerceDate.long(item.createdAt)).font(.caption).foregroundStyle(.secondary)
                  Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(current.money(item.grossReceived)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption)
              }.frame(minHeight: 60)
            }.buttonStyle(.plain)
            Divider()
          }
        } else {
          Text("Amounts below are this category’s contribution to a combined payout, not an additional balance. Payout fees apply to the whole payout and are shown separately.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(page.payouts) { payout in
            VStack(alignment: .leading, spacing: 10) {
              Text(CaptroCommerceDate.long(payout.paidAt ?? payout.createdAt)).font(.subheadline.weight(.semibold))
              value("Status", payout.status.replacingOccurrences(of: "_", with: " ").capitalized)
              value("From \(current.title)", current.money(payout.attributedAmount))
              value("Whole payout", current.money(payout.payoutAmount))
              value("Payout fee charged to you", payout.payoutFee.map { current.money($0) } ?? "Not yet reported")
            }.padding(.vertical, 4)
            Divider()
          }
          NavigationLink("All payout history") { CaptroPayoutsView(model: earnings) }.frame(minHeight: 44)
        }
        if let error = page.error {
          Text(error).font(.callout).foregroundStyle(.secondary)
          Button("Retry") { Task { await load(reset: !page.loaded) } }.frame(minHeight: 44)
        } else if page.loaded && (section == "transactions" ? page.transactions.isEmpty : page.payouts.isEmpty) {
          Text(section == "transactions" ? "No confirmed transactions in this category yet." : "No payouts attributed to this category yet.")
            .font(.callout).foregroundStyle(.secondary).padding(.vertical)
        }
        if page.loading { ProgressView("Loading…") }
        else if page.nextOffset != nil && page.error == nil {
          Button("Load more") { Task { await load(reset: false) } }.frame(minHeight: 44)
        }
      }.padding(16)
    }
    .background(MIRATheme.Color.surface)
    .foregroundStyle(CaptroDetailStyle.ink)
    .navigationTitle(current.title)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: requestKey) { await load(reset: true) }
    .onDisappear { page.cancel() }
    .refreshable {
      async let summary: () = earnings.loadPools(forceRefresh: true)
      async let history: () = load(reset: true)
      async let readiness: () = earnings.loadSupportReadiness()
      _ = await (summary, history, readiness)
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 12) {
      value(current.category == "creator_support" ? "Total support received" : "Gross received", current.money(current.grossReceived))
      value("Processing fees", current.money(current.processingFees))
      value("Captro fee", current.category == "creator_support" ? "0% · \(current.money(current.captroFee))" : current.money(current.captroFee))
      if current.refunded != 0 { value("Refunded to supporters / buyers", current.money(current.refunded)) }
      value("Creator net after adjustments", current.money(current.creatorNet))
      Divider()
      value("Pending", current.money(current.pending))
      if current.held != 0 { value("On hold (included in Pending)", current.money(current.held)) }
      value("Available", current.money(current.available))
      value("Paid out", current.money(current.paidOut))
      Text("Only provider-confirmed payments appear here. Pending includes clearance, review holds and payouts in progress. Available earnings remain subject to the existing payout-account requirements.")
        .font(.caption).foregroundStyle(.secondary)
      if earnings.poolsError != nil {
        Text("Last confirmed summary. Pull to refresh.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var supportStatus: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Captro takes 0%. Payment-processing fees apply.").font(.callout.weight(.medium))
      if let readiness = earnings.supportReadiness {
        if readiness.status == "unavailable" {
          Text("Support readiness could not be checked. Pull to retry; your existing payout setup is unchanged.").font(.callout)
        }
        ForEach(readiness.blockers) { blocker in
          VStack(alignment: .leading, spacing: 3) {
            Text(blocker.sourceLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(blocker.message).font(.callout)
          }
        }
      } else {
        ProgressView("Checking Support availability…")
      }
      Text("Use the existing payout method in Earnings. No separate Support account or withdrawal is required.").font(.caption).foregroundStyle(.secondary)
    }
  }

  private func value(_ label: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(text).monospacedDigit().multilineTextAlignment(.trailing)
    }.font(.subheadline)
  }
  private func load(reset: Bool) async { await page.load(api: api, pool: pool, section: section, reset: reset) }
}
