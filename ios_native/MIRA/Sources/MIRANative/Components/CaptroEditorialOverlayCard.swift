import SwiftUI

/// The single stamp treatment for Moment and attached content, including voice posts.
/// The entire card opens details; consequential actions remain on that screen.
enum CaptroEditorialCardType: String, CaseIterable, Equatable {
  case moment, place, club, event, meetup, deal

  init(stampKind: CaptroStampKind) {
    switch stampKind {
    case .place: self = .place
    case .club, .group: self = .club
    case .event, .party, .ticket: self = .event
    case .meetup, .booking: self = .meetup
    case .deal, .localOffer: self = .deal
    default: self = .moment
    }
  }
}

struct CaptroEditorialCardContent {
  let type: CaptroEditorialCardType
  let title: String
  var subtitle: String? = nil
  var chipText: String? = nil
  var description: String? = nil
  var supportingText: String? = nil
  var username: String? = nil
  var avatarURL: String? = nil

  var accessibilityLabel: String {
    [type.rawValue.capitalized, title, subtitle, chipText, description, supportingText, username]
      .compactMap { $0 }.joined(separator: ". ")
  }
}

enum CaptroEditorialCardLayout {
  static let inset: CGFloat = 14

  static func width(for mediaWidth: CGFloat) -> CGFloat {
    min(min(320, max(0, mediaWidth - inset * 2)), mediaWidth * 0.73)
  }

  static func isCondensed(mediaWidth: CGFloat, mediaHeight: CGFloat) -> Bool {
    mediaHeight < max(260, mediaWidth * 0.78)
  }
}

struct CaptroEditorialOverlayCard: View {
  let content: CaptroEditorialCardContent
  var condensed = false
  var onOpen: (() -> Void)? = nil

  private let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
  private let chipPink = Color(red: 0.98, green: 0.80, blue: 0.88)

  @ViewBuilder var body: some View {
    if let onOpen {
      Button(action: onOpen) { card.accessibilityHidden(true) }
        .buttonStyle(.plain)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens details; does not join or make a payment")
        .accessibilityIdentifier("captro.editorialCard")
    } else {
      card
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityIdentifier("captro.editorialCard.preview")
    }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: condensed ? 4 : 7) {
      Text(content.title)
        .font(.system(size: condensed ? 21 : 26, weight: .bold))
        .tracking(-0.65)
        .lineSpacing(-2)
        .lineLimit(2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)

      if let subtitle = nonempty(content.subtitle) {
        Text(subtitle.uppercased())
          .font(.system(size: condensed ? 11 : 12, weight: .medium))
          .tracking(1.2)
          .lineLimit(1)
      }

      if let chipText = nonempty(content.chipText) {
        Text(chipText.uppercased())
          .font(.system(size: condensed ? 11 : 12, weight: .semibold))
          .tracking(0.35)
          .lineLimit(1)
          .padding(.horizontal, 9)
          .padding(.vertical, condensed ? 4 : 5)
          .background(chipPink)
          .overlay(Rectangle().strokeBorder(ink, lineWidth: 0.8))
          .padding(.top, condensed ? 0 : 2)
      }

      if let supporting = nonempty(content.supportingText) {
        Text(supporting)
          .font(.system(size: condensed ? 13 : 15, weight: .regular))
          .lineLimit(condensed ? 1 : 2)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !condensed, let description = nonempty(content.description) {
        Text(description)
          .font(.system(size: 15, weight: .regular))
          .lineSpacing(2)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }

      if let username = nonempty(content.username) {
        HStack(spacing: 9) {
          RemoteAvatar(url: content.avatarURL, size: condensed ? 26 : 30)
          Text(username)
            .font(.system(size: condensed ? 13 : 15, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 0)
        }
        .padding(.top, condensed ? 1 : 5)
      }
    }
    .foregroundStyle(ink)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(condensed ? 11 : 14)
    .background(Color.white)
    .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
    .contentShape(Rectangle())
  }

  private func nonempty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
