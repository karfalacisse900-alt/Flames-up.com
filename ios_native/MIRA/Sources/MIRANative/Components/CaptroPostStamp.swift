import SwiftUI

enum CaptroStampLayout {
  static let feedInset: CGFloat = 14
  static func feedWidth(for mediaWidth: CGFloat) -> CGFloat {
    let responsiveTarget = min(214, max(184, mediaWidth * 0.54))
    return min(responsiveTarget, max(0, mediaWidth - feedInset * 2))
  }
}

extension CaptroStampKind {
  var stampFamily: String {
    switch self {
    case .club, .group: return "club"
    case .event, .party, .ticket: return "event"
    case .meetup, .booking: return "meetup"
    case .deal, .localOffer: return "deal"
    default: return "moment"
    }
  }
  var stampVariants: [String] {
    switch stampFamily {
    case "club": return ["club-oval", "club-member", "club-tag"]
    case "event": return ["event-ticket", "event-screening", "event-postal"]
    case "meetup": return ["meetup-note", "meetup-fold", "meetup-route"]
    case "deal": return ["deal-coupon", "deal-cashback", "deal-drop"]
    default: return ["moment-paper", "moment-postal", "moment-voice"]
    }
  }
}

extension CaptroStampContent {
  var family: String { kind.stampFamily }
  var resolvedVariant: String {
    if let variant, kind.stampVariants.contains(variant) { return variant }
    return kind.stampVariants[0]
  }
  var displayFields: [String: String] {
    // Moment is already surrounded by the post author/date UI. Keep the default
    // stamp quiet and never repeat that row inside the paper label.
    let supporting = family == "moment" ? (metadata ?? "") : (terms ?? metadata ?? "View details")
    return ["title": family == "deal" && terms == nil ? "View offer" : title,
            "meta": metadata?.uppercased() ?? "", "footer": supporting, "compactText": supporting,
            "sideTop": dateMonth ?? "", "sideMain": family == "deal" ? "VIEW" : resolvedVariant == "moment-voice" ? duration ?? "" : dateDay ?? "",
            "sideBottom": family == "deal" ? "TERMS" : ""]
      .mapValues { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
  }
  var accessibleStampLabel: String {
    [family.capitalized, title, metadata, description, terms, availability, relationship]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
  }
}

/// One button opens existing details. Never purchase/join/redeem from the stamp.
struct CaptroPostStamp: View {
  let content: CaptroStampContent
  var onOpen: (() -> Void)? = nil
  // Kept source-compatible with older callers; no nested actions are rendered.
  var onAction: (() -> Void)? = nil
  var isSaved: Bool? = nil
  var onSave: (() -> Void)? = nil
  var compact = false

  @ViewBuilder var body: some View {
    if let onOpen {
      Button(action: onOpen) { artwork.accessibilityHidden(true) }
        .buttonStyle(.plain)
        .accessibilityLabel(content.accessibleStampLabel)
        .accessibilityHint("Opens details; does not join or make a payment")
        .accessibilityIdentifier("captro.stamp")
    } else {
      artwork
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibleStampLabel)
        .accessibilityIdentifier("captro.stamp.preview")
    }
  }
  private var artwork: some View {
    VStack(alignment: .leading, spacing: 3) {
      CaptroStampArtwork(content: content, compact: compact)
        .aspectRatio(640 / (compact ? 224.0 : 288.0), contentMode: .fit)
        .allowsHitTesting(false)
      // Separate from the printed terms: SAVED can never conceal EXPIRED.
      let statuses = [content.availability, content.relationship].compactMap { $0 }
      if !statuses.isEmpty {
        Text(statuses.joined(separator: " · ").uppercased())
          .font(.system(size: 9.5, weight: .bold, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.14))
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background {
            CaptroStampStatusSlip()
              .fill(Color(red: 0.965, green: 0.945, blue: 0.895))
              .overlay { CaptroStampStatusSlip().stroke(.black.opacity(0.16), lineWidth: 0.55) }
              .shadow(color: .black.opacity(0.18), radius: 1.2, x: 0, y: 0.8)
          }
          .rotationEffect(.degrees(-0.6))
      }
    }
    .contentShape(Rectangle())
  }
}

private struct CaptroStampStatusSlip: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 1, y: 2))
    path.addLine(to: CGPoint(x: rect.maxX - 1.5, y: 0.6))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1.2))
    path.addLine(to: CGPoint(x: 1.8, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
