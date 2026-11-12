import SwiftUI
import StripePaymentSheet
import StripePayments

struct CaptroBusinessBagView: View {
  let api: MIRAAPIClient
  let business: CaptroBusiness
  @Binding var bag: CaptroBusinessBag
  let isGuest: Bool
  let backToBusiness: () -> Void
  @State private var quote: CaptroBusinessQuote?
  @State private var quoteKey: String?
  @State private var error: String?
  @State private var loadingQuote = false
  @State private var editing: CaptroBusinessBag.Line?
  @State private var clearConfirmation = false
  @State private var checkout = false
  @State private var checkoutQuote: CaptroBusinessQuote?
  @State private var checkoutInput: CaptroBusinessCheckoutInput?
  @State private var retry = 0

  private struct QuoteInput: Encodable { let lines: [CaptroBusinessBag.Input] }

  var body: some View {
    ScrollView {
      VStack(spacing: 13) {
        if bag.lines.isEmpty { ContentUnavailableView("Your bag is empty", systemImage: "bag") }
        ForEach(bag.lines) { line in
          HStack(spacing: 10) {
            CaptroBusinessPhoto(url: line.product.imageUrl, fill: false).frame(width: 54, height: 61)
            VStack(alignment: .leading, spacing: 3) {
              Text(line.product.name).font(.subheadline.bold())
              Text(captroBusinessPrice(line.product.price(line.selection))).font(.subheadline)
              let names = line.product.groups.flatMap(\.options).filter { line.selection.contains($0.id) }.map(\.name)
              if !names.isEmpty { Text(names.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
              if line.product.isCustom {
                Button("Edit options") { editing = line }.font(.caption).frame(minHeight: 44)
              }
            }
            Spacer(minLength: 0)
            CaptroBusinessStepper(quantity: line.quantity) {
              bag.set(product: line.product, selection: line.selection, quantity: $0, editing: line.id)
            }
          }
          Divider()
        }
        if !bag.lines.isEmpty {
          if quoteKey == bag.requestId, let quote {
            CaptroBusinessTotals(quote: quote)
            Button("Checkout") {
              checkoutQuote = quote
              checkoutInput = .init(lines: bag.inputs, requestId: bag.requestId, total: quote.total)
              checkout = true
            }.buttonStyle(CaptroBusinessPrimary())
          } else {
            HStack {
              Text("Estimated subtotal")
              Spacer()
              Text(captroBusinessPrice(bag.subtotal))
            }
            if isGuest { Text("Sign in to check out.").foregroundStyle(.secondary) }
            if loadingQuote { ProgressView("Checking prices") }
            if let error {
              Text(error).foregroundStyle(.secondary)
              Button("Refresh total") { retry += 1 }
            }
          }
        }
      }.padding(16)
    }
    .navigationTitle("Your Bag")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !bag.lines.isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button { clearConfirmation = true } label: { Label("Clear bag", systemImage: "trash") }
        }
      }
    }
    .confirmationDialog("Clear your bag?", isPresented: $clearConfirmation, titleVisibility: .visible) {
      Button("Clear bag", role: .destructive) { bag = CaptroBusinessBag() }
    }
    .sheet(item: $editing) { line in
      NavigationStack {
        CaptroBusinessCustomize(product: line.product, initial: line.selection, quantity: line.quantity) { choices, count in
          bag.set(product: line.product, selection: choices, quantity: count, editing: line.id)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
      }
    }
    .navigationDestination(isPresented: $checkout) {
      if let checkoutQuote, let checkoutInput {
        CaptroBusinessPay(api: api, business: business, quote: checkoutQuote, input: checkoutInput,
                          backToBusiness: backToBusiness) { request in
          if bag.requestId == request { bag = CaptroBusinessBag() }
        }
      }
    }
    .task(id: "\(bag.requestId):\(retry)") { await refreshQuote() }
  }

  @MainActor private func refreshQuote() async {
    quote = nil
    quoteKey = nil
    error = nil
    loadingQuote = false
    guard !bag.lines.isEmpty && !isGuest else { return }
    let key = bag.requestId
    let inputs = bag.inputs
    loadingQuote = true
    defer { if bag.requestId == key && !Task.isCancelled { loadingQuote = false } }
    do {
      try await Task.sleep(for: .milliseconds(250))
      let result: CaptroBusinessQuote = try await api.post("/businesses/\(business.id)/quote", body: QuoteInput(lines: inputs))
      try Task.checkCancellation()
      guard bag.requestId == key else { return }
      quote = result
      quoteKey = key
    } catch is CancellationError {
    } catch { if bag.requestId == key { self.error = error.localizedDescription } }
  }
}

private struct CaptroBusinessTotals: View {
  let quote: CaptroBusinessQuote
  var body: some View {
    VStack(spacing: 9) {
      amount("Subtotal", quote.subtotal)
      amount("Tax", quote.tax)
      if quote.fee > 0 { amount("Fees", quote.fee) }
      Divider()
      amount("Total", quote.total).font(.headline)
    }.accessibilityElement(children: .contain)
  }
  private func amount(_ title: String, _ amount: Int) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(captroBusinessPrice(amount)).monospacedDigit()
    }
  }
}

private struct CaptroBusinessPay: View {
  let api: MIRAAPIClient
  let business: CaptroBusiness
  let quote: CaptroBusinessQuote
  let input: CaptroBusinessCheckoutInput
  let backToBusiness: () -> Void
  let didPay: (String) -> Void
  @State private var order: CaptroBusinessOrder?
  @State private var readySheet: PaymentSheet?
  @State private var showsSheet = false
  @State private var working = false
  @State private var note: String?
  @State private var viewOrder = false
  @State private var confirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: confirmation ? .center : .leading, spacing: 16) {
        if confirmation, let order {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 66)).foregroundStyle(.green)
            .padding(.top, 44).accessibilityHidden(true)
          Text("Order Placed!").font(.title2.bold())
          Text(order.businessName).font(.headline)
          Text("Order #\(order.number) · \(order.statusLabel)").foregroundStyle(.secondary)
          Button("View Order") { viewOrder = true }.buttonStyle(CaptroBusinessPrimary())
          Button("Back to Business") {
            backToBusiness()
          }.frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
        } else {
          Text("Pickup at \(business.name)").font(.headline)
          Text(business.pickupAddress).foregroundStyle(.secondary)
          CaptroBusinessTotals(quote: quote)
          if let readySheet {
            Button("Choose payment method") { showsSheet = true }.buttonStyle(CaptroBusinessPrimary())
              .paymentSheet(isPresented: $showsSheet, paymentSheet: readySheet, onCompletion: paymentCompleted)
              .disabled(working)
          } else if !working {
            Button(order == nil ? "Confirm pickup and continue" : "Resume checkout") {
              Task { await begin() }
            }.buttonStyle(CaptroBusinessPrimary())
          }
          if working { ProgressView("Checking payment") }
          if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
          if order != nil && !working {
            Button("Check order status") { Task { await verify() } }.frame(minHeight: 44)
          }
        }
      }.frame(maxWidth: .infinity, alignment: confirmation ? .center : .leading).padding(16)
    }
    .navigationTitle(confirmation ? "" : "Checkout")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $viewOrder) {
      if let order { CaptroBusinessOrderDetail(api: api, order: order, vendor: false) }
    }
  }

  @MainActor private func begin() async {
    guard !working else { return }
    working = true
    note = nil
    defer { working = false }
    do {
      let response: CaptroBusinessCheckout = try await api.post("/businesses/\(business.id)/checkout", body: input)
      update(response.order)
      guard !confirmation, let payment = response.payment else { return }
      guard payment.publishableKey.hasPrefix("pk_test_"), payment.clientSecret.hasPrefix("pi_"),
            payment.clientSecret.contains("_secret_") else {
        note = "Payment setup could not be verified."
        return
      }
      var config = PaymentSheet.Configuration()
      config.apiClient = STPAPIClient(publishableKey: payment.publishableKey)
      config.merchantDisplayName = business.name
      config.returnURL = "captro://stripe-redirect"
      config.allowsDelayedPaymentMethods = false
      readySheet = PaymentSheet(paymentIntentClientSecret: payment.clientSecret, configuration: config)
      note = "Stripe test checkout"
    } catch { note = error.localizedDescription }
  }

  private func paymentCompleted(_ result: PaymentSheetResult) {
    switch result {
    case .completed:
      readySheet = nil
      Task { await verify() }
    case .canceled:
      readySheet = nil
      note = "Checkout canceled. Your bag is still here."
    case .failed:
      readySheet = nil
      note = "Payment could not be completed. Check your order or resume checkout."
    }
  }

  @MainActor private func verify() async {
    guard let order, !working else { return }
    working = true
    defer { working = false }
    do {
      for attempt in 0..<4 {
        let latest: CaptroBusinessOrder = try await api.post("/business-orders/\(order.id)/verify", body: CaptroBusinessEmpty())
        update(latest)
        guard latest.status == "awaiting_payment" else { return }
        if attempt < 3 { try await Task.sleep(for: .seconds(1)) }
      }
      note = "Payment is awaiting confirmation. Check Your Orders for updates."
    } catch { note = error.localizedDescription }
  }

  private func update(_ latest: CaptroBusinessOrder) {
    order = latest
    confirmation = latest.hasConfirmedOrder
    if confirmation { didPay(input.requestId) }
    if latest.status != "awaiting_payment" { note = latest.statusLabel }
  }
}

struct CaptroBusinessOrders: View {
  let api: MIRAAPIClient
  @State private var orders: [CaptroBusinessOrder] = []
  @State private var error: String?
  @State private var loading = true
  @State private var more = false

  var body: some View {
    List {
      if loading && orders.isEmpty { ProgressView() }
      if let error {
        Text(error)
        Button("Retry") { Task { await load() } }
      }
      if !loading && error == nil && orders.isEmpty { Text("You have no orders yet.").foregroundStyle(.secondary) }
      ForEach(orders) { order in
        NavigationLink { CaptroBusinessOrderDetail(api: api, order: order, vendor: false) } label: {
          VStack(alignment: .leading) {
            Text(order.businessName).font(.headline)
            Text("#\(order.number) · \(order.statusLabel)").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
      if more { Button("Load older orders") { Task { await load(next: true) } }.disabled(loading) }
    }
    .navigationTitle("Your Orders")
    .task { await load() }
    .refreshable { await load() }
  }

  @MainActor private func load(next: Bool = false) async {
    loading = true
    defer { loading = false }
    error = nil
    do {
      let page: [CaptroBusinessOrder] = try await api.get("/business-orders?offset=\(next ? orders.count : 0)")
      orders = next ? orders + page.filter { row in !orders.contains { $0.id == row.id } } : page
      more = page.count == 50
    } catch { self.error = error.localizedDescription }
  }
}

struct CaptroBusinessOrderDetail: View {
  let api: MIRAAPIClient
  let vendor: Bool
  @State private var order: CaptroBusinessOrder
  @State private var error: String?
  @State private var working = false
  @State private var refundAction: String?

  init(api: MIRAAPIClient, order: CaptroBusinessOrder, vendor: Bool) {
    self.api = api
    self.vendor = vendor
    _order = State(initialValue: order)
  }

  var body: some View {
    List {
      Section(order.businessName) {
        Text("Order #\(order.number)").font(.headline)
        Text(order.statusLabel).accessibilityIdentifier("business.order.status")
        if let error { Text(error).foregroundStyle(.secondary) }
      }
      Section("Pickup") {
        Button(order.pickupAddress) { captroBusinessDirections(order.businessName, order.latitude, order.longitude) }
        if let date = captroBusinessDate(order.locationUpdatedAt) {
          Text("Location updated \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
        }
        if let token = order.pickupToken,
           let qr = CaptroCommerceQRCode.image(for: "captro-pickup:\(order.id):\(token)") {
          Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 172, height: 172)
            .padding(12).background(.white).accessibilityLabel("Pickup QR code")
          Text("Show this code to the business when you pick up your order.").font(.footnote)
        }
      }
      Section("Items") {
        ForEach(Array(order.lines.enumerated()), id: \.offset) { _, line in
          VStack(alignment: .leading) {
            Text("\(line.quantity) × \(line.name)")
            if !line.options.isEmpty { Text(line.options.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary) }
          }
        }
        CaptroBusinessTotals(quote: .init(subtotal: order.subtotal, tax: order.tax, fee: order.fee, total: order.total))
        if let fee = order.processingFee { Text("Stripe processing: \(captroBusinessPrice(fee))").font(.footnote) }
        if order.refundedAmount > 0 { Text("Refunded: \(captroBusinessPrice(order.refundedAmount))") }
      }
      Section {
        if vendor {
          if order.status == "received" {
            action("Accept order", "accept")
            refundButton("Reject and refund", "reject")
          }
          if order.status == "accepted" { action("Start preparing", "prepare") }
          if order.status == "preparing" { action("Mark ready", "ready") }
          if order.status == "ready" { Text("Scan the customer’s pickup QR from your order queue.").font(.footnote) }
          if order.status == "refund_pending" { refundButton("Retry refund", "reject") }
        } else {
          Button("Refresh order status") { Task { await refresh() } }.disabled(working)
          if order.status == "received" { refundButton("Cancel and refund", "cancel") }
          if order.status == "refund_pending" { refundButton("Retry refund", "cancel") }
        }
      }
    }
    .navigationTitle("Order #\(order.number)")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await refresh() }
    .task { await refresh() }
    .confirmationDialog("Refund this order?", isPresented: Binding(
      get: { refundAction != nil }, set: { if !$0 { refundAction = nil } }
    ), titleVisibility: .visible) {
      Button("Request refund", role: .destructive) {
        if let request = refundAction { Task { await change(request) } }
        refundAction = nil
      }
    }
  }

  private func refundButton(_ title: String, _ code: String) -> some View {
    Button(title, role: .destructive) { refundAction = code }.disabled(working)
  }

  private func action(_ title: String, _ code: String) -> some View {
    Button(title) { Task { await change(code) } }.disabled(working)
  }

  @MainActor private func change(_ action: String) async {
    guard !working else { return }
    working = true
    error = nil
    defer { working = false }
    do { order = try await api.post("/business-orders/\(order.id)/action", body: CaptroBusinessAction(action: action)) }
    catch { self.error = error.localizedDescription }
  }

  @MainActor private func refresh() async {
    guard !working else { return }
    working = true
    error = nil
    defer { working = false }
    do {
      if vendor {
        order = try await api.get("/business-owner/\(order.businessId)/orders/\(order.id)")
      } else if order.status == "awaiting_payment" {
        order = try await api.post("/business-orders/\(order.id)/verify", body: CaptroBusinessEmpty())
      } else { order = try await api.get("/business-orders/\(order.id)") }
    } catch { self.error = error.localizedDescription }
  }
}
