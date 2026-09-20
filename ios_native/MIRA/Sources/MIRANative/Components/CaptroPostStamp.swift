import SwiftUI

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
    let supporting = terms ?? (family == "moment" ? metadata ?? footer : nil) ?? "View details"
    return ["title": family == "deal" && terms == nil ? "View offer" : title,
            "meta": metadata ?? "", "footer": supporting, "compactText": supporting,
            "sideTop": dateMonth ?? "", "sideMain": family == "deal" ? "VIEW" : resolvedVariant == "moment-voice" ? duration ?? "" : dateDay ?? "",
            "sideBottom": family == "deal" ? "TERMS" : ""]
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

  var body: some View {
    Group {
      if let onOpen {
        Button(action: onOpen) { artwork }
          .buttonStyle(.plain)
          .accessibilityHint("Opens details; does not join or make a payment")
      } else { artwork }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(content.accessibleStampLabel)
  }
  private var artwork: some View {
    VStack(alignment: .leading, spacing: 3) {
      CaptroStampArtwork(content: content, compact: compact)
        .aspectRatio(640 / (compact ? 224.0 : 288.0), contentMode: .fit)
        .allowsHitTesting(false)
      // Separate from the printed terms: SAVED can never conceal EXPIRED.
      let statuses = [content.availability, content.relationship].compactMap { $0 }
      if !statuses.isEmpty {
        Text(statuses.joined(separator: " · "))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.primary)
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(.background, in: Capsule())
      }
    }
    .contentShape(Rectangle())
  }
}
