import CoreImage.CIFilterBuiltins
import SafariServices
import SwiftUI
import UIKit

struct CaptroCheckoutDestination: Identifiable, Equatable {
  let url: URL
  var id: String { url.absoluteString }
}

struct CaptroCommerceDetailSection: View {
  @ObservedObject var model: PostDetailModel
  @State private var selectedPriceID = ""
  @State private var quantity = 1
  @State private var fulfillmentMethod = ""
  @State private var bookingStart = Date().addingTimeInterval(60 * 60 * 24)
  @State private var isShowingPass = false

  private var commerce: CaptroCommerceDetails? { model.commerce ?? model.post.detail?.commerce }
  private var selectedPrice: CaptroCommercePrice? {
    commerce?.prices.first(where: { $0.id == selectedPriceID }) ?? commerce?.lowestPrice ?? commerce?.prices.first
  }
  private var isCreator: Bool {
    guard let current = model.currentUserId, let creator = model.post.userId else { return false }
    return current == creator
  }

  var body: some View {
    if let commerce {
      VStack(alignment: .leading, spacing: 18) {
        heading(commerce)
        typeSpecificFacts(commerce)
        purchaseControls(commerce)
        if !commerce.refundPolicy.isEmpty {
          factBlock("REFUND / CANCELLATION", commerce.refundPolicy)
        }
        if !commerce.description.isEmpty && commerce.description != model.post.detailCaption {
          factBlock("ABOUT", commerce.description)
        }
        CaptroDetailCreatorRow(post: model.post, api: model.api, context: creatorContext(commerce), showsTime: false)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .background(Color.white)
      .sheet(isPresented: $isShowingPass) {
        if let pass = model.commercePass {
          CaptroCommercePassView(post: model.post, commerce: commerce, pass: pass)
        }
      }
      .onAppear {
        if selectedPriceID.isEmpty { selectedPriceID = commerce.lowestPrice?.id ?? commerce.prices.first?.id ?? "" }
        if fulfillmentMethod.isEmpty { fulfillmentMethod = commerce.publicData?.fulfillmentMethods?.first ?? "" }
      }
      .onChange(of: commerce.id) { _, _ in
        selectedPriceID = commerce.lowestPrice?.id ?? commerce.prices.first?.id ?? ""
      }
    }
  }

  private func heading(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(contentLabel(commerce))
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(CaptroDetailStyle.accent)
      Text(commerce.title)
        .font(.system(size: 26, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      if let location = commerce.displayLocation {
        Text(location)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(CaptroDetailStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func typeSpecificFacts(_ commerce: CaptroCommerceDetails) -> some View {
    switch commerce.contentType {
    case "event", "party", "ticket", "access_pass", "meetup":
      eventFacts(commerce)
    case "club", "group":
      membershipFacts(commerce)
    case "deal":
      dealFacts(commerce)
    case "offer":
      offerFacts(commerce)
    case "booking", "reservation":
      bookingFacts(commerce)
    default:
      EmptyView()
    }
  }

  private func eventFacts(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      if let schedule = commerce.scheduleLabel { iconFact("calendar", schedule) }
      if let address = commerce.address { iconFact("mappin.and.ellipse", address) }
      if let age = commerce.publicData?.ageRequirement { iconFact("person.text.rectangle", age) }
      HStack(spacing: 16) {
        if let capacity = commerce.capacity {
          Text("\(commerce.joinedCount) / \(capacity) joined")
        } else {
          Text("\(commerce.joinedCount) joined")
        }
        if let remaining = commerce.remaining { Text(remaining == 0 ? "Sold out" : "\(remaining) left") }
      }
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(CaptroDetailStyle.secondary)
      if let event = model.post.detail?.event,
         event.attendeesCount != nil || !(event.attendees ?? []).isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("People going").font(.system(size: 13, weight: .semibold))
          CaptroEventAttendees(event: event, api: model.api)
        }
      }
      if let map = model.post.detailMapURL {
        Link(destination: map) {
          Label("View location", systemImage: "arrow.up.right")
            .font(.system(size: 13, weight: .semibold))
            .frame(minHeight: 40)
        }
      }
    }
  }

  private func membershipFacts(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      HStack(spacing: 16) {
        Label("\(commerce.joinedCount) members", systemImage: "person.2")
        if commerce.audience != "anyone" { Label(commerce.audience.capitalized, systemImage: "lock") }
      }
      .font(.system(size: 13, weight: .semibold))
      if let benefits = commerce.publicData?.benefits, !benefits.isEmpty {
        listBlock("BENEFITS", values: benefits)
      }
      if let rules = commerce.publicData?.rules, !rules.isEmpty {
        listBlock("RULES", values: rules)
      }
    }
  }

  private func dealFacts(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      if let original = commerce.publicData?.originalPrice {
        HStack(spacing: 8) {
          Text("Original")
          Text(original).strikethrough()
        }
        .font(.system(size: 14))
        .foregroundStyle(CaptroDetailStyle.secondary)
      }
      if let expires = formattedDate(commerce.expiresAt) { iconFact("clock", "Valid until \(expires)") }
      if let remaining = commerce.remaining { iconFact("number", "\(remaining) remaining") }
      if let rules = commerce.publicData?.redemptionRules { factBlock("REDEMPTION RULES", rules) }
    }
  }

  private func offerFacts(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      if let methods = commerce.publicData?.fulfillmentMethods, !methods.isEmpty {
        factBlock("FULFILLMENT", methods.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: " · "))
      }
      if let expires = formattedDate(commerce.expiresAt) { iconFact("clock", "Available until \(expires)") }
      if let remaining = commerce.remaining { iconFact("shippingbox", "\(remaining) available") }
    }
  }

  private func bookingFacts(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      if let availability = commerce.publicData?.availability { factBlock("AVAILABILITY", availability) }
      if let minutes = commerce.publicData?.durationMinutes { iconFact("clock", "\(minutes) minutes") }
      if let location = commerce.address ?? commerce.locationName { iconFact("mappin.and.ellipse", location) }
      DatePicker("Choose a time", selection: $bookingStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
        .font(.system(size: 14, weight: .medium))
    }
  }

  private func purchaseControls(_ commerce: CaptroCommerceDetails) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      thinDivider
      if commerce.prices.count > 1 {
        Picker("Ticket type", selection: $selectedPriceID) {
          ForEach(commerce.prices) { price in
            Text("\(price.label) · \(price.unitAmount == 0 ? "Free" : price.money)").tag(price.id)
          }
        }
        .pickerStyle(.menu)
      } else if let price = selectedPrice {
        HStack {
          Text(price.label).font(.system(size: 14, weight: .semibold))
          Spacer()
          Text(price.unitAmount == 0 ? "Free" : price.money).font(.system(size: 18, weight: .bold))
        }
      }

      if commerce.contentType == "offer", let methods = commerce.publicData?.fulfillmentMethods, methods.count > 1 {
        Picker("Pickup or delivery", selection: $fulfillmentMethod) {
          ForEach(methods, id: \.self) { Text($0.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
      }

      if ["offer", "deal", "event", "party", "ticket", "access_pass"].contains(commerce.contentType) {
        Stepper("Quantity · \(quantity)", value: $quantity, in: 1...maxQuantity)
          .font(.system(size: 14, weight: .medium))
      }

      if selectedPrice?.unitAmount ?? 0 > 0 {
        orderSummary(commerce)
      }

      if commerce.isActiveForViewer,
         ["membership", "group_access"].contains(commerce.fulfillmentType),
         let destinationId = commerce.viewerDestinationId {
        NavigationLink {
          ConversationNativeView(
            groupId: destinationId,
            title: commerce.title,
            api: model.api,
            currentUserId: model.currentUserId ?? ""
          )
          .miraHideTabBarOnAppear()
        } label: {
          commerceActionLabel(title: commerce.contentType == "club" ? "OPEN CLUB" : "OPEN GROUP", disabled: false)
        }
        .buttonStyle(.plain)
      } else {
        Button { performAction(commerce) } label: {
          commerceActionLabel(title: actionTitle(commerce), disabled: actionDisabled(commerce))
        }
        .buttonStyle(.plain)
        .disabled(actionDisabled(commerce) || model.isUpdatingCommerce)
      }

      if isCreator {
        Text("Manage buyers, approvals, passes, and totals in Me.")
          .font(.system(size: 12))
          .foregroundStyle(CaptroDetailStyle.secondary)
      } else if commerce.approvalRequired && !commerce.needsApproval && !commerce.isActiveForViewer {
        Text("The creator must approve this request before access is issued.")
          .font(.system(size: 12))
          .foregroundStyle(CaptroDetailStyle.secondary)
      }
      if let error = model.commerceError {
        Text(error)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.red.opacity(0.86))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var maxQuantity: Int {
    let remaining = selectedPrice?.remaining ?? commerce?.remaining ?? 20
    return max(1, min(20, remaining))
  }

  private func orderSummary(_ commerce: CaptroCommerceDetails) -> some View {
    let amounts = displayedAmounts(commerce)
    return VStack(alignment: .leading, spacing: 9) {
      Text(isCreator ? "CREATOR EARNINGS" : "ORDER SUMMARY")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(CaptroDetailStyle.secondary)
      if isCreator {
        amountRow("Sale", amount: amounts.item, currency: amounts.currency)
        amountRow("You earn", amount: amounts.item, currency: amounts.currency, emphasized: true)
      } else {
        amountRow("\(selectedPrice?.label ?? commerce.title)\(quantity > 1 ? " × \(quantity)" : "")", amount: amounts.item, currency: amounts.currency)
        amountRow("Tax", amount: amounts.tax, currency: amounts.currency)
        amountRow("Service fee", amount: amounts.fee, currency: amounts.currency)
        Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
        amountRow("TOTAL", amount: amounts.total, currency: amounts.currency, emphasized: true)
      }
    }
    .padding(.vertical, 4)
  }

  private func amountRow(_ title: String, amount: Int, currency: String, emphasized: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
      Spacer(minLength: 12)
      Text(CaptroMoney.format(minorUnits: amount, currency: currency))
    }
    .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .bold : .regular))
  }

  private func displayedAmounts(_ commerce: CaptroCommerceDetails) -> (item: Int, fee: Int, tax: Int, total: Int, currency: String) {
    guard let price = selectedPrice else { return (0, 0, 0, 0, "USD") }
    let item = max(0, price.unitAmount * quantity)
    guard item > 0 else { return (0, 0, 0, 0, price.currency) }
    let basisPoints = max(0, commerce.serviceFeeBasisPoints ?? 0)
    let fixed = max(0, commerce.serviceFeeFixedAmount ?? 0)
    let minimum = max(0, commerce.serviceFeeMinimumAmount ?? 0)
    let percentage = (item * basisPoints + 9_999) / 10_000
    let fee = max(minimum, percentage + fixed)
    let tax = max(0, (price.taxAmount ?? 0) * quantity)
    return (item, fee, tax, item + fee + tax, price.currency)
  }

  private func commerceActionLabel(title: String, disabled: Bool) -> some View {
    HStack(spacing: 8) {
      if model.isUpdatingCommerce { ProgressView().tint(.white) }
      if commerce?.isActiveForViewer == true,
         let fulfillmentType = commerce?.fulfillmentType,
         ["ticket", "redemption"].contains(fulfillmentType) {
        Image(systemName: "qrcode")
      }
      Text(title).font(.system(size: 14, weight: .semibold))
    }
    .frame(maxWidth: .infinity, minHeight: 48)
    .foregroundStyle(disabled ? CaptroDetailStyle.secondary : Color.white)
    .background(disabled ? Color.black.opacity(0.06) : CaptroDetailStyle.accent)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func actionDisabled(_ commerce: CaptroCommerceDetails) -> Bool {
    if isCreator || commerce.status != "active" && commerce.status != "sold_out" { return true }
    if commerce.needsApproval { return true }
    if commerce.isActiveForViewer {
      return !["ticket", "redemption"].contains(commerce.fulfillmentType) && !commerce.passRequired
    }
    if commerce.remaining == 0 || selectedPrice?.remaining == 0 { return true }
    return selectedPrice == nil
  }

  private func actionTitle(_ commerce: CaptroCommerceDetails) -> String {
    if isCreator { return "CREATOR MANAGEMENT" }
    if commerce.remaining == 0 || selectedPrice?.remaining == 0 { return "SOLD OUT" }
    if commerce.isActiveForViewer {
      if ["ticket", "redemption"].contains(commerce.fulfillmentType) || commerce.passRequired { return "VIEW PASS" }
      return commerce.primaryActionTitle
    }
    if commerce.needsApproval { return "REQUEST PENDING" }
    if commerce.requiresPaymentContinuation { return "CONTINUE CHECKOUT" }
    let base = commerce.primaryActionTitle.components(separatedBy: " — ").first ?? commerce.primaryActionTitle
    guard let price = selectedPrice, price.unitAmount > 0 else { return base }
    return "\(base) — \(CaptroMoney.format(minorUnits: price.unitAmount * quantity, currency: price.currency))"
  }

  private func performAction(_ commerce: CaptroCommerceDetails) {
    if commerce.isActiveForViewer && (["ticket", "redemption"].contains(commerce.fulfillmentType) || commerce.passRequired) {
      Task {
        await model.loadCommercePass()
        if model.commercePass != nil { isShowingPass = true }
      }
      return
    }
    guard let price = selectedPrice else { return }
    var selection = CaptroCommerceSelection()
    if !fulfillmentMethod.isEmpty { selection.fulfillmentMethod = fulfillmentMethod }
    if commerce.fulfillmentType == "reservation" {
      let formatter = ISO8601DateFormatter()
      selection.startsAt = formatter.string(from: bookingStart)
      if let duration = commerce.publicData?.durationMinutes {
        selection.endsAt = formatter.string(from: bookingStart.addingTimeInterval(Double(duration * 60)))
      }
    }
    Task { await model.performCommerceAction(priceId: price.id, quantity: quantity, selection: selection) }
  }

  private func contentLabel(_ commerce: CaptroCommerceDetails) -> String {
    switch commerce.contentType {
    case "local_offer", "offer": return "OFFER"
    case "access_pass", "ticket": return "TICKET / ACCESS PASS"
    case "booking", "reservation": return "BOOKING"
    default: return commerce.contentType.uppercased()
    }
  }

  private func creatorContext(_ commerce: CaptroCommerceDetails) -> String {
    ["event", "party", "ticket", "access_pass", "meetup"].contains(commerce.contentType) ? "Hosted by" : "Created by"
  }

  private func iconFact(_ icon: String, _ value: String) -> some View {
    Label(value, systemImage: icon)
      .font(.system(size: 14))
      .foregroundStyle(CaptroDetailStyle.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func factBlock(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
      Text(value).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func listBlock(_ title: String, values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
      ForEach(values, id: \.self) { value in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).padding(.top, 3)
          Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var thinDivider: some View {
    Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
  }

  private func formattedDate(_ value: String?) -> String? {
    guard let value else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
}

struct CaptroCommercePassView: View {
  @Environment(\.dismiss) private var dismiss
  let post: MIRAPost
  let commerce: CaptroCommerceDetails
  let pass: CaptroCommercePass

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          Text(pass.kind == "redemption" ? "REDEMPTION PASS" : "ACCESS PASS")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(CaptroDetailStyle.accent)
          Text(commerce.title)
            .font(.system(size: 25, weight: .bold))
            .multilineTextAlignment(.center)
          if let image = CaptroCommerceQRCode.image(for: pass.token) {
            Image(uiImage: image)
              .interpolation(.none)
              .resizable()
              .scaledToFit()
              .frame(width: 210, height: 210)
              .padding(12)
              .background(Color.white)
              .accessibilityLabel("Scannable access code")
          }
          if let tier = pass.tier { Text(tier.uppercased()).font(.system(size: 13, weight: .bold)) }
          if let schedule = commerce.scheduleLabel { Label(schedule, systemImage: "calendar").font(.system(size: 14)) }
          if let location = commerce.displayLocation { Label(location, systemImage: "mappin.and.ellipse").font(.system(size: 14)) }
          VStack(spacing: 5) {
            Text("ISSUED BY").font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
            Text(post.detailCreatorHandle).font(.system(size: 15, weight: .semibold))
          }
          VStack(spacing: 5) {
            Text("PASS ID").font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
            Text(pass.code).font(.system(size: 15, weight: .semibold)).monospaced()
          }
          Text(pass.status == "active" ? "ACTIVE" : pass.status.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(pass.status == "active" ? MIRATheme.Color.forest : CaptroDetailStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
      }
      .background(Color.white)
      .foregroundStyle(CaptroDetailStyle.ink)
      .privacySensitive()
      .navigationTitle("Pass")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }

}

struct CaptroCheckoutBrowser: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let controller = SFSafariViewController(url: url)
    controller.preferredControlTintColor = UIColor(MIRATheme.Color.forest)
    return controller
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
