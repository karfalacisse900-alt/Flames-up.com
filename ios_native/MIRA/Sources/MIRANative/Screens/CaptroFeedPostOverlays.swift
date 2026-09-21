import Foundation
import SwiftUI

enum CaptroStampKind: String, Identifiable {
  case social = "general"
  case place
  case club
  case group
  case meetup
  case event
  case party
  case ticket
  case booking
  case deal
  case localOffer = "local_offer"
  case guide
  case travel
  case receipt
  case invoice

  static let creationCases: [CaptroStampKind] = [
    .social,
    .club,
    .meetup,
    .event,
    .deal,
  ]

  var id: String { rawValue }
  var backendPostType: String { rawValue }

  var displayName: String {
    switch self {
    case .social: return "Moment"
    case .place: return "Place"
    case .club: return "Club"
    case .group: return "Group"
    case .meetup: return "Meetup"
    case .event: return "Event"
    case .party: return "Party"
    case .ticket: return "Ticket / Pass"
    case .booking: return "Booking"
    case .deal: return "Deal"
    case .localOffer: return "Local Offer"
    case .guide: return "Guide"
    case .travel: return "Trip"
    case .receipt: return "Receipt"
    case .invoice: return "Invoice"
    }
  }

  var actionTitle: String? {
    switch self {
    case .club, .meetup: return "JOIN"
    case .party: return "JOIN"
    case .event: return "ATTEND"
    case .ticket: return "GET TICKET"
    case .booking: return "BOOK"
    case .deal, .localOffer: return "CLAIM"
    case .group: return "ACCESS"
    case .social, .place, .guide, .travel, .receipt, .invoice: return nil
    }
  }

  var commerceContentType: String? {
    switch self {
    case .club: return "club"
    case .group: return "group"
    case .meetup: return "meetup"
    case .event: return "event"
    case .party: return "party"
    case .ticket: return "ticket"
    case .booking: return "booking"
    case .deal: return "deal"
    case .localOffer: return "offer"
    case .social, .place, .guide, .travel, .receipt, .invoice: return nil
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
  var highlight: String? = nil
  var variant: String? = nil
  var terms: String? = nil
  var availability: String? = nil
  var relationship: String? = nil
  var postID: String? = nil
  var attachmentID: String? = nil
  var dateMonth: String? = nil
  var dateDay: String? = nil
  var waveform: [Float]? = nil
  var duration: String? = nil
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
    case "place", "location", "review", "check_in", "checkin": return .place
    case "club": return .club
    case "group", "access", "group_access": return .group
    case "meetup": return .meetup
    case "event", "concert", "show": return .event
    case "party": return .party
    case "ticket", "access_pass": return detail?.travel == nil ? .ticket : .travel
    case "booking", "reservation": return .booking
    case "travel", "trip", "boarding_pass", "train", "flight", "bus": return .travel
    case "receipt": return .receipt
    case "invoice": return .invoice
    case "deal": return .deal
    case "offer", "local_offer", "local-offer": return .localOffer
    case "guide", "collection", "list", "album", "collaborative_album", "collaborative-album": return .guide
    default:
      if value.contains("collab") { return .guide }
      if cleanedCaptroFeedValue(placeDisplayName) != nil { return .place }
      return .social
    }
  }

  var captroStampContent: CaptroStampContent {
    let kind = captroStampKind
    let commerce = detail?.commerce
    let location = commerce?.displayLocation ?? captroFeedLocationText
    let title: String
    switch kind {
    case .place:
      title = cleanedCaptroFeedValue(placeDisplayName) ?? captroCleanTitle ?? kind.displayName
    case .travel:
      title = detail?.travel?.operator ?? captroCleanTitle ?? kind.displayName
    case .receipt, .invoice:
      title = detail?.document?.merchantName ?? captroCleanTitle ?? kind.displayName
    default:
      title = commerce?.title ?? captroCleanTitle ?? captroFeedCaptionText ?? kind.displayName
    }

    let metadata: String?
    switch kind {
    case .social:
      metadata = nil
    case .place:
      metadata = cleanedCaptroFeedValue(displayLocationText) ?? cleanedCaptroFeedValue(placeCity)
    case .guide:
      metadata = location ?? (feedMediaURLs.count > 1 ? "\(feedMediaURLs.count) photos" : nil)
    case .travel:
      metadata = detail?.travel?.route
    case .receipt, .invoice:
      metadata = kind.displayName
    default:
      metadata = location
    }

    let summary: String?
    switch kind {
    case .event, .meetup, .party, .ticket, .booking, .club, .group, .deal, .localOffer:
      let event = detail?.event
      let price = commerce?.lowestPrice?.stampPrice
      let facts = [commerce?.scheduleLabel, event?.calendarDate, event?.timeRange, commerce?.locationName,
        event?.venueName, price, event?.priceLabel, commerce?.compactAvailabilityLabel].compactMap { $0 }
      summary = facts.isEmpty ? captroFeedCaptionText : facts.joined(separator: " · ")
    case .travel:
      summary = [detail?.travel?.duration, detail?.travel?.departure].compactMap { $0 }.joined(separator: " · ")
    case .receipt, .invoice:
      summary = [detail?.document?.total.map { [detail?.document?.currency, $0].compactMap { $0 }.joined(separator: " ") },
        detail?.document?.verdict].compactMap { $0 }.joined(separator: "\n")
    default: summary = captroFeedCaptionText
    }

    return CaptroStampContent(
      kind: kind,
      title: title,
      metadata: kind.stampFamily == "club" && commerce != nil
        ? [metadata, commerce.map { "\($0.joinedCount) members" }].compactMap { $0 }.joined(separator: " · ")
        : metadata,
      description: summary,
      footer: captroAuthorStampFooter,
      actionTitle: kind.actionTitle,
      contributors: captroGuideContributors,
      highlight: kind == .place ? savesCount.map { "\(max(0, $0)) SAVES" } : nil,
      variant: stampVariant,
      terms: CaptroStampAdapter.terms(commerce, family: kind.stampFamily),
      availability: CaptroStampAdapter.availability(commerce),
      relationship: CaptroStampAdapter.relationship(commerce, saved: viewerSaved),
      postID: id,
      attachmentID: commerce?.id,
      dateMonth: CaptroStampAdapter.datePart(commerce?.startsAt, timeZone: commerce?.timeZone, format: "MMM"),
      dateDay: CaptroStampAdapter.datePart(commerce?.startsAt, timeZone: commerce?.timeZone, format: "dd"),
      waveform: detail?.voice?.waveform,
      duration: detail?.voice.map { String(format: "%d:%02d", $0.durationMs / 60000, ($0.durationMs / 1000) % 60) }
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
