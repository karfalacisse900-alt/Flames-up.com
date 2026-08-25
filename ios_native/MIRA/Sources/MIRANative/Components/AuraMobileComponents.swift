import SwiftUI

public struct AuraDocumentTicketCard: View {
  let merchant: String?
  let documentType: String
  let date: String?
  let currency: String?
  let total: String?
  let status: String
  let statusSystemImage: String
  let statusColor: Color
  let detail: String?

  public init(
    merchant: String?,
    documentType: String,
    date: String?,
    currency: String?,
    total: String?,
    status: String,
    statusSystemImage: String,
    statusColor: Color,
    detail: String? = nil
  ) {
    self.merchant = merchant
    self.documentType = documentType
    self.date = date
    self.currency = currency
    self.total = total
    self.status = status
    self.statusSystemImage = statusSystemImage
    self.statusColor = statusColor
    self.detail = detail
  }

  public var body: some View {
    VStack(spacing: 0) {
      ticketHeader
      perforation
      ticketBody
    }
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.textPrimary.opacity(0.82), lineWidth: 1.4)
    }
    .shadow(color: .black.opacity(0.07), radius: 13, y: 7)
    .accessibilityElement(children: .combine)
  }

  private var ticketHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(MIRATheme.Color.auraVioletSoft)
        Image(systemName: documentType.lowercased() == "invoice" ? "doc.text.fill" : "receipt.fill")
          .font(.title2.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
      }
      .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 4) {
        Text(merchant?.isEmpty == false ? merchant! : "Merchant unavailable")
          .font(.headline)
          .fontWeight(.bold)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
        Text([documentType.capitalized, formattedDate].compactMap { $0 }.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      Spacer(minLength: 8)
      Text(formattedTotal)
        .font(.title3)
        .fontWeight(.bold)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .multilineTextAlignment(.trailing)
    }
    .padding(16)
  }

  private var perforation: some View {
    HStack(spacing: 5) {
      ForEach(0..<28, id: \.self) { _ in
        Capsule()
          .fill(MIRATheme.Color.divider)
          .frame(maxWidth: .infinity)
          .frame(height: 1)
      }
    }
  }

  private var ticketBody: some View {
    HStack(spacing: 10) {
      Label(status, systemImage: statusSystemImage)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(statusColor)
      Spacer()
      if let detail, !detail.isEmpty {
        Text(detail)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(MIRATheme.Color.textMuted)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  private var formattedTotal: String {
    guard let total, !total.isEmpty else { return "Amount unavailable" }
    guard let currency, !currency.isEmpty else { return total }
    if currency.uppercased() == "USD" { return "$\(total)" }
    return "\(currency.uppercased()) \(total)"
  }

  private var formattedDate: String? {
    guard let date, !date.isEmpty else { return nil }
    let input = ISO8601DateFormatter()
    if let value = input.date(from: date) {
      return value.formatted(date: .abbreviated, time: .omitted)
    }
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.dateFormat = "yyyy-MM-dd"
    if let value = dateOnly.date(from: date) {
      return value.formatted(date: .abbreviated, time: .omitted)
    }
    return date
  }
}

public struct AuraSectionHeader: View {
  let title: String
  let actionTitle: String?
  let action: (() -> Void)?

  public init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
    self.title = title
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    HStack {
      Text(title)
        .font(.headline)
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(MIRATheme.Color.auraViolet)
      }
    }
  }
}
