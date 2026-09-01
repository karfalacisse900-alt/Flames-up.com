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
}

struct CaptroPostStamp: View {
  let content: CaptroStampContent
  var onOpen: (() -> Void)? = nil
  var onAction: (() -> Void)? = nil
  var compact = false

  var body: some View {
    stampLayout
      .padding(.horizontal, compact ? 12 : 14)
      .padding(.vertical, compact ? 10 : 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.96))
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color.black.opacity(0.12), lineWidth: 0.75)
      )
      .contentShape(Rectangle())
      .onTapGesture { onOpen?() }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(onOpen == nil ? "" : "Opens details")
  }

  @ViewBuilder
  private var stampLayout: some View {
    switch content.kind {
    case .social:
      VStack(alignment: .leading, spacing: 7) {
        stampTitle
        stampDescription
        stampFooter
      }

    case .place:
      VStack(alignment: .leading, spacing: 7) {
        stampTitle
        stampMetadata
        Rectangle()
          .fill(Color.black.opacity(0.16))
          .frame(height: 0.75)
        stampDescription
        stampFooter
      }

    case .club, .group, .guide:
      VStack(alignment: .leading, spacing: 7) {
        stampMetadata
        stampTitle
        if !content.contributors.isEmpty {
          CaptroContributorAvatars(contributors: content.contributors)
        }
        stampDescription
        stampActionFooter
      }

    case .meetup, .event:
      VStack(alignment: .leading, spacing: 7) {
        stampTitle
        stampMetadata
        stampDescription
        Rectangle()
          .fill(Color.black.opacity(0.14))
          .frame(height: 0.75)
        stampActionFooter
      }

    case .deal, .localOffer:
      VStack(alignment: .leading, spacing: 7) {
        stampMetadata
        stampTitle
        stampDescription
        stampActionFooter
      }
    }
  }

  private var stampTitle: some View {
    Text(content.title.uppercased())
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.88))
      .lineLimit(2)
      .minimumScaleFactor(0.84)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private var stampMetadata: some View {
    if let metadata = content.metadata {
      Text(metadata.uppercased())
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.58))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var stampDescription: some View {
    if let description = content.description {
      Text(description)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.78))
        .lineSpacing(2)
        .lineLimit(compact ? 3 : 4)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var stampFooter: some View {
    if let footer = content.footer {
      Text(footer.uppercased())
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.56))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
  }

  private var stampActionFooter: some View {
    HStack(alignment: .center, spacing: 8) {
      if let footer = content.footer {
        Text(footer.uppercased())
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.56))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }

      Spacer(minLength: 6)

      if let actionTitle = content.actionTitle {
        if let onAction {
          Button(action: onAction) {
            Text(actionTitle)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.forest)
              .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(actionTitle.capitalized)
        } else {
          Text(actionTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
      }
    }
  }

  private var accessibilityLabel: String {
    [content.kind.displayName, content.title, content.metadata, content.description, content.footer, content.actionTitle]
      .compactMap { $0 }
      .joined(separator: ", ")
  }
}

private struct CaptroContributorAvatars: View {
  let contributors: [MIRATaggedUserPayload]

  private var visibleContributors: [MIRATaggedUserPayload] {
    Array(contributors.prefix(3))
  }

  var body: some View {
    HStack(spacing: -8) {
      ForEach(Array(visibleContributors.enumerated()), id: \.element.id) { index, contributor in
        RemoteAvatar(url: contributor.profileImage, size: 30)
          .overlay(Circle().stroke(Color.white, lineWidth: 2))
          .zIndex(Double(visibleContributors.count - index))
      }

      if contributors.count > visibleContributors.count {
        Text("+\(contributors.count - visibleContributors.count)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(width: 30, height: 30)
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
      contributors: captroGuideContributors
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
