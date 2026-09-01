import Foundation
import SwiftUI

enum CaptroStampKind: String, Identifiable {
  case social = "general"
  case place
  case club
  case group
  case meetup
  case event
  case deal
  case localOffer = "local_offer"
  case guide

  static let creationCases: [CaptroStampKind] = [
    .social,
    .place,
    .club,
    .group,
    .meetup,
    .event,
    .deal,
    .localOffer,
  ]

  var id: String { rawValue }
  var backendPostType: String { rawValue }

  var displayName: String {
    switch self {
    case .social: return "Just Post"
    case .place: return "Place"
    case .club: return "Club"
    case .group: return "Group"
    case .meetup: return "Meetup"
    case .event: return "Event"
    case .deal: return "Deal"
    case .localOffer: return "Local Offer"
    case .guide: return "Guide"
    }
  }

  var actionTitle: String? {
    switch self {
    case .club, .meetup: return "JOIN"
    case .event: return "ATTEND"
    case .deal, .localOffer: return "CLAIM"
    case .group: return "ACCESS"
    case .social, .place, .guide: return nil
    }
  }
}

struct CaptroStampContent {
  let kind: CaptroStampKind
  let title: String
  let metadata: String?
  let description: String?
  let footer: String?
  let actionTitle: String?
  let contributors: [MIRATaggedUserPayload]
  let savesCount: Int?
  let creatorUsername: String?
  let creatorProfileImage: String?
}

struct CaptroPostStamp: View {
  let content: CaptroStampContent
  var onOpen: (() -> Void)? = nil
  var onAction: (() -> Void)? = nil
  var usesCompactTypography = false

  var body: some View {
    editorialOverlay
      .contentShape(Rectangle())
      .onTapGesture { onOpen?() }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(onOpen == nil ? "" : "Opens details")
  }

  @ViewBuilder
  private var editorialOverlay: some View {
    switch content.kind {
    case .social:
      simplePostOverlay
    case .place:
      venueReviewOverlay
    case .guide:
      guideCoverOverlay
    case .club, .group, .meetup, .event, .deal, .localOffer:
      actionPostOverlay
    }
  }

  private var venueReviewOverlay: some View {
    VStack(alignment: .leading, spacing: usesCompactTypography ? 8 : 11) {
      Text(content.title)
        .font(.system(size: usesCompactTypography ? 24 : 28, weight: .bold))
        .foregroundStyle(Color.black)
        .lineLimit(2)
        .minimumScaleFactor(0.76)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if let metadata = content.metadata {
        Text(metadata.uppercased())
          .font(.system(size: usesCompactTypography ? 10 : 12, weight: .semibold))
          .tracking(0.7)
          .foregroundStyle(Color.black.opacity(0.88))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let savesLabel {
        Text(savesLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.90))
          .padding(.horizontal, 9)
          .frame(height: 27)
          .background(CaptroStampPalette.savesPink)
          .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 1, style: .continuous)
              .stroke(Color.black.opacity(0.82), lineWidth: 1)
          )
      }

      if let description = content.description {
        Text(description)
          .font(.system(size: usesCompactTypography ? 15 : 16, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.92))
          .lineSpacing(2)
          .lineLimit(usesCompactTypography ? 3 : 5)
          .fixedSize(horizontal: false, vertical: true)
      }

      creatorRow
    }
    .padding(.horizontal, usesCompactTypography ? 15 : 19)
    .padding(.vertical, usesCompactTypography ? 14 : 18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .stroke(Color.black.opacity(0.82), lineWidth: 1.25)
    )
  }

  private var guideCoverOverlay: some View {
    Text(content.title.uppercased())
      .font(.system(size: usesCompactTypography ? 24 : 27, weight: .black, design: .rounded))
      .foregroundStyle(Color.black)
      .lineSpacing(0)
      .lineLimit(6)
      .minimumScaleFactor(0.72)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, usesCompactTypography ? 15 : 18)
      .padding(.vertical, usesCompactTypography ? 14 : 17)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .stroke(Color.black.opacity(0.88), lineWidth: 1.25)
      )
      .accessibilityAddTraits(.isHeader)
  }

  private var simplePostOverlay: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(content.title.uppercased())
        .font(.system(size: usesCompactTypography ? 18 : 20, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.90))
        .lineLimit(2)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      editorialDescription(fontSize: usesCompactTypography ? 13 : 14, lineLimit: 5)
      stampFooter
    }
    .padding(.horizontal, usesCompactTypography ? 13 : 16)
    .padding(.vertical, usesCompactTypography ? 12 : 15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .stroke(Color.black.opacity(0.62), lineWidth: 1)
    )
  }

  private var actionPostOverlay: some View {
    VStack(alignment: .leading, spacing: 8) {
      stampMetadata

      Text(content.title.uppercased())
        .font(.system(size: usesCompactTypography ? 18 : 21, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.92))
        .lineLimit(2)
        .minimumScaleFactor(0.80)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      editorialDescription(fontSize: usesCompactTypography ? 12 : 13, lineLimit: 4)

      Rectangle()
        .fill(Color.black.opacity(0.22))
        .frame(height: 1)

      stampActionFooter
    }
    .padding(.horizontal, usesCompactTypography ? 13 : 16)
    .padding(.vertical, usesCompactTypography ? 12 : 15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .stroke(Color.black.opacity(0.68), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func editorialDescription(fontSize: CGFloat, lineLimit: Int) -> some View {
    if let description = content.description {
      Text(description)
        .font(.system(size: fontSize, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.82))
        .lineSpacing(2)
        .lineLimit(lineLimit)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var creatorRow: some View {
    if creatorHandle != nil || creatorProfileImage != nil {
      HStack(spacing: 9) {
        if let creatorProfileImage {
          RemoteAvatar(url: creatorProfileImage, size: 32)
        }

        if let creatorHandle {
          Text(creatorHandle)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.90))
            .lineLimit(1)
            .minimumScaleFactor(0.80)
        }
      }
    }
  }

  @ViewBuilder
  private var stampMetadata: some View {
    if let metadata = content.metadata {
      Text(metadata.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(Color.black.opacity(0.62))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var stampFooter: some View {
    if let footer = content.footer {
      Text(footer.uppercased())
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.58))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
  }

  private var stampActionFooter: some View {
    HStack(alignment: .center, spacing: 8) {
      if let footer = content.footer {
        Text(footer.uppercased())
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.58))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }

      Spacer(minLength: 6)

      if let actionTitle = content.actionTitle {
        if let onAction {
          Button(action: onAction) {
            Text(actionTitle)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.forest)
              .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(actionTitle.capitalized)
        } else {
          Text(actionTitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
      }
    }
  }

  private var savesLabel: String? {
    guard let count = content.savesCount, count >= 0 else { return nil }
    let value = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
    return "\(value) SAVES"
  }

  private var creatorHandle: String? {
    let value = content.creatorUsername?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
    return value.isEmpty ? nil : "@\(value)"
  }

  private var creatorProfileImage: String? {
    let value = content.creatorProfileImage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private var accessibilityLabel: String {
    [
      content.kind.displayName,
      content.title,
      content.metadata,
      savesLabel,
      content.description,
      creatorHandle,
      content.footer,
      content.actionTitle,
    ]
      .compactMap { $0 }
      .joined(separator: ", ")
  }
}

private enum CaptroStampPalette {
  static let savesPink = Color(red: 0.97, green: 0.72, blue: 0.86)
}

struct CaptroContributorAvatars: View {
  let contributors: [MIRATaggedUserPayload]
  var avatarSize: CGFloat = 30

  private var visibleContributors: [MIRATaggedUserPayload] {
    Array(contributors.prefix(3))
  }

  var body: some View {
    HStack(spacing: -8) {
      ForEach(Array(visibleContributors.enumerated()), id: \.element.id) { index, contributor in
        RemoteAvatar(url: contributor.profileImage, size: avatarSize)
          .overlay(Circle().stroke(Color.white, lineWidth: 2))
          .zIndex(Double(visibleContributors.count - index))
      }

      if contributors.count > visibleContributors.count {
        Text("+\(contributors.count - visibleContributors.count)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: avatarSize, height: avatarSize)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white, lineWidth: 2))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(contributors.count) contributors")
  }
}

extension MIRAPost {
  var captroCleanTitle: String? {
    cleanedCaptroFeedValue(title)
  }

  var captroFeedCaptionText: String? {
    let value = ((caption?.isEmpty == false ? caption : content) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if let title = captroCleanTitle,
       value.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
      return nil
    }
    return value
  }

  var captroFeedHeaderLocation: String? {
    cleanedCaptroFeedValue(displayLocationText)
  }

  var captroFeedLocationText: String? {
    cleanedCaptroFeedValue(placeDisplayName) ??
      cleanedCaptroFeedValue(displayLocationText) ??
      cleanedCaptroFeedValue(location)
  }

  var captroStampKind: CaptroStampKind {
    let value = postType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    switch value {
    case "place", "location": return .place
    case "club": return .club
    case "group", "access", "group_access": return .group
    case "meetup": return .meetup
    case "event": return .event
    case "deal": return .deal
    case "offer", "local_offer", "local-offer": return .localOffer
    case "guide", "album", "collaborative_album", "collaborative-album": return .guide
    default:
      if value.contains("collab") { return .guide }
      if cleanedCaptroFeedValue(placeDisplayName) != nil { return .place }
      return .social
    }
  }

  var captroStampContent: CaptroStampContent {
    let kind = captroStampKind
    let location = captroFeedLocationText
    let title: String
    switch kind {
    case .place:
      title = cleanedCaptroFeedValue(placeDisplayName) ?? captroCleanTitle ?? kind.displayName
    default:
      title = captroCleanTitle ?? kind.displayName
    }

    let metadata: String?
    switch kind {
    case .social:
      metadata = nil
    case .place:
      metadata = cleanedCaptroFeedValue(displayLocationText) ?? cleanedCaptroFeedValue(placeCity)
    case .guide:
      metadata = location ?? (feedMediaURLs.count > 1 ? "\(feedMediaURLs.count) photos" : nil)
    default:
      metadata = location
    }

    return CaptroStampContent(
      kind: kind,
      title: title,
      metadata: metadata,
      description: captroFeedCaptionText,
      footer: captroCapturedStampText ?? captroAuthorStampFooter,
      actionTitle: kind.actionTitle,
      contributors: captroGuideContributors,
      savesCount: savesCount,
      creatorUsername: cleanedCaptroFeedValue(userUsername),
      creatorProfileImage: cleanedCaptroFeedValue(userProfileImage)
    )
  }

  var captroGuideContributors: [MIRATaggedUserPayload] {
    (taggedUsers ?? []).filter {
      !($0.profileImage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
  }

  var captroCapturedStampText: String? {
    guard let location = captroCapturedLocation,
          let date = captroCreatedDate else { return nil }
    return "\(location.uppercased()) · \(CaptroFeedDateFormatters.stamp.string(from: date).uppercased())"
  }

  private var captroAuthorStampFooter: String? {
    var values: [String] = []
    if let username = cleanedCaptroFeedValue(userUsername) {
      values.append("@\(username.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
    }
    if let date = captroCreatedDate {
      values.append(CaptroFeedDateFormatters.stamp.string(from: date))
    }
    return values.isEmpty ? nil : values.joined(separator: " · ")
  }

  private var captroCapturedLocation: String? {
    if let visible = cleanedCaptroFeedValue(displayLocationText) {
      return visible.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return cleanedCaptroFeedValue(placeCity) ?? cleanedCaptroFeedValue(placeDisplayName)
  }

  private var captroCreatedDate: Date? {
    guard let value = createdAt?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return CaptroFeedDateFormatters.fractional.date(from: value) ?? CaptroFeedDateFormatters.standard.date(from: value)
  }

  private func cleanedCaptroFeedValue(_ value: String?) -> String? {
    let clean = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression) ?? ""
    return clean.isEmpty ? nil : clean
  }
}

private enum CaptroFeedDateFormatters {
  static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let standard = ISO8601DateFormatter()

  static let stamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d"
    return formatter
  }()
}
