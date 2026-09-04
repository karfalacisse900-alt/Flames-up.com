import SwiftUI
import UIKit

struct CaptroCommerceEditorFields: View {
  let kind: CaptroStampKind
  @Binding var draft: CaptroCommerceDraft

  private var supportsTiers: Bool { [.event, .party, .ticket].contains(kind) }
  private var supportsPass: Bool { [.event, .party, .ticket, .meetup, .deal].contains(kind) }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Divider()
      Toggle(accessToggleTitle, isOn: $draft.enabled)
        .font(.system(size: 15, weight: .semibold))

      if draft.enabled {
        Picker("Access", selection: $draft.isPaid) {
          Text("Free").tag(false)
          Text("Paid").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Free or paid")

        if draft.isPaid {
          VStack(alignment: .leading, spacing: 8) {
            Text("WHERE IT IS USED")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
            Picker("Where it is used", selection: $draft.isUsedOutsideApp) {
              Text("In person / service").tag(true)
              Text("Digital access").tag(false)
            }
            .pickerStyle(.segmented)
            if !draft.isUsedOutsideApp {
              Text("Paid digital access needs an App Store product before buyers can check out. Free digital groups and clubs work now.")
                .font(.system(size: 12))
                .foregroundStyle(MIRATheme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          priceFields
          field("Refund / cancellation policy", text: $draft.refundPolicy, lineLimit: 2...5)
        }

        commonAccessFields
        typeSpecificFields

        if let error = draft.validationError {
          Text(error)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .font(.system(size: 15))
    .tint(MIRATheme.Color.forest)
    .onChange(of: kind) { _, newKind in draft.configureDefaults(for: newKind) }
  }

  @ViewBuilder
  private var priceFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(supportsTiers ? "TICKET TYPES" : "PRICE")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Spacer()
        Picker("Currency", selection: $draft.currency) {
          ForEach(Locale.commonISOCurrencyCodes, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
      }

      ForEach(Array(draft.prices.indices), id: \.self) { index in
        VStack(alignment: .leading, spacing: 10) {
          if supportsTiers {
            field("Name", text: $draft.prices[index].label)
          }
          HStack(alignment: .bottom, spacing: 12) {
            field("Price", text: $draft.prices[index].price, keyboard: .decimalPad)
            field("Quantity", text: $draft.prices[index].capacity, keyboard: .numberPad)
            if supportsTiers && draft.prices.count > 1 {
              Button(role: .destructive) { draft.prices.remove(at: index) } label: {
                Image(systemName: "trash")
                  .frame(width: 44, height: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove ticket type")
            }
          }
        }
        if index < draft.prices.count - 1 { Divider() }
      }

      if supportsTiers && draft.prices.count < 12 {
        Button {
          draft.prices.append(CaptroCommercePriceDraft(label: "Ticket \(draft.prices.count + 1)"))
        } label: {
          Label("Add ticket type", systemImage: "plus")
            .font(.system(size: 14, weight: .semibold))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var commonAccessFields: some View {
    VStack(alignment: .leading, spacing: 16) {
      Divider()
      field("Total capacity (leave empty for unlimited)", text: $draft.capacity, keyboard: .numberPad)
      Picker("Who can join or buy", selection: $draft.audience) {
        Text("Anyone").tag("anyone")
        Text("Followers").tag("followers")
        Text("Friends").tag("friends")
      }
      .pickerStyle(.menu)
      Toggle("Require creator approval", isOn: $draft.approvalRequired)
      if supportsPass {
        Toggle(kind == .deal ? "Create a redemption pass" : "Create a ticket / access pass", isOn: $draft.passRequired)
      }
      Toggle("Set expiration", isOn: $draft.hasExpiration)
      if draft.hasExpiration {
        DatePicker("Expires", selection: $draft.expiresAt, displayedComponents: [.date, .hourAndMinute])
      }
    }
  }

  @ViewBuilder
  private var typeSpecificFields: some View {
    switch kind {
    case .event, .party, .ticket:
      Divider()
      field("Age requirement", text: $draft.ageRequirement)
    case .club, .group:
      Divider()
      field("Benefits (one per line)", text: $draft.benefits, lineLimit: 2...8)
      field("Rules (one per line)", text: $draft.rules, lineLimit: 2...8)
    case .deal:
      Divider()
      field("Original price", text: $draft.originalPrice, keyboard: .decimalPad)
      field("Redemption rules", text: $draft.redemptionRules, lineLimit: 2...6)
    case .localOffer:
      Divider()
      Text("FULFILLMENT")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Toggle("Pickup", isOn: $draft.allowsPickup)
      Toggle("Delivery", isOn: $draft.allowsDelivery)
    case .booking:
      Divider()
      field("Availability", text: $draft.availability, lineLimit: 2...6)
      field("Duration in minutes", text: $draft.durationMinutes, keyboard: .numberPad)
    default:
      EmptyView()
    }
  }

  private var accessToggleTitle: String {
    switch kind {
    case .deal, .localOffer: return "Enable checkout"
    case .booking: return "Enable reservations"
    case .event, .party, .ticket: return "Enable tickets or access"
    default: return "Enable joining or access"
    }
  }

  private func field(
    _ title: String,
    text: Binding<String>,
    keyboard: UIKeyboardType = .default,
    lineLimit: ClosedRange<Int> = 1...3
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(MIRATheme.Color.textMuted)
      TextField(title, text: text, axis: .vertical)
        .lineLimit(lineLimit)
        .keyboardType(keyboard)
        .accessibilityLabel(title)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
