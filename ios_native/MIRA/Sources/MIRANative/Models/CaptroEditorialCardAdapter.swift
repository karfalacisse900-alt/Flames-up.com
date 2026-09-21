import Foundation

extension MIRAPost {
  /// Live feed data only. Example content belongs in the DEBUG visual fixture, not here.
  var captroEditorialCardContent: CaptroEditorialCardContent? {
    guard let type = CaptroEditorialCardType(stampKind: captroStampKind) else { return nil }
    let commerce = detail?.commerce
    let event = detail?.event
    let unavailable = CaptroStampAdapter.availability(commerce)
    let title = cleanEditorialText(type == .place ? placeDisplayName : commerce?.title)
      ?? captroCleanTitle ?? type.rawValue.capitalized
    let area = cleanEditorialText(type == .place
      ? (displayLocationText ?? placeCity)
      : (commerce?.city ?? event?.city ?? commerce?.locationName ?? captroFeedLocationText))
    let handle = cleanEditorialText(userUsername).map {
      "@" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }
    let price = commerce?.lowestPrice?.stampPrice ?? event?.priceLabel
    let start = commerce?.startsAt ?? event?.startsAt
    let timeZone = commerce?.timeZone ?? event?.timeZone
    let date = CaptroStampAdapter.datePart(start, timeZone: timeZone, format: "MMM d")
    let time = CaptroStampAdapter.datePart(start, timeZone: timeZone, format: "jmm")

    var content = CaptroEditorialCardContent(type: type, title: title,
      subtitle: area, username: handle, avatarURL: userProfileImage)
    switch type {
    case .place:
      content.chipText = savesCount.map { "\(max(0, $0)) SAVES" }
      content.description = cleanEditorialText(captroFeedCaptionText)
    case .club:
      content.chipText = unavailable ?? commerce.map { "\(max(0, $0.joinedCount)) MEMBERS" }
      content.description = cleanEditorialText(commerce?.description) ?? cleanEditorialText(captroFeedCaptionText)
      content.supportingText = price
    case .event:
      content.chipText = unavailable ?? date
      content.supportingText = joinedEditorialText([time, price])
      content.description = cleanEditorialText(commerce?.description) ?? cleanEditorialText(captroFeedCaptionText)
    case .meetup:
      content.chipText = unavailable ?? commerce.map { "\(max(0, $0.joinedCount)) GOING" }
        ?? event?.attendeesCount.map { "\(max(0, $0)) GOING" }
      content.supportingText = joinedEditorialText([date, time, price])
      content.description = cleanEditorialText(commerce?.description) ?? cleanEditorialText(captroFeedCaptionText)
    case .deal:
      // Never parse a discount or minimum spend from decorative post text.
      // A long/unavailable condition gets a neutral summary, not a misleading offer.
      let benefit = commerce?.publicData?.benefits?.compactMap { cleanEditorialText($0) }.first
      let rules = cleanEditorialText(commerce?.publicData?.redemptionRules)
      let conciseRules = rules.flatMap { $0.count <= 70 ? $0 : nil }
      content.chipText = unavailable ?? (rules != nil && conciseRules == nil ? "VIEW OFFER" : benefit ?? "VIEW OFFER")
      content.supportingText = conciseRules ?? (rules == nil ? nil : "Full conditions in details")
      if content.chipText == "VIEW OFFER", content.supportingText == nil {
        content.supportingText = "See offer details"
      }
    }
    return content
  }

  private func cleanEditorialText(_ value: String?) -> String? {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? nil : clean
  }

  private func joinedEditorialText(_ values: [String?]) -> String? {
    let parts = values.compactMap(cleanEditorialText)
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

extension CaptroEditorialCardContent {
  /// Draft preview uses only entered fields. Counts, benefits, and payment
  /// states are never invented before the attached object exists on the server.
  init?(draftStamp stamp: CaptroStampContent) {
    guard let type = CaptroEditorialCardType(stampKind: stamp.kind) else { return nil }
    let date = [stamp.dateMonth, stamp.dateDay].compactMap { $0 }.joined(separator: " ")
    self.init(type: type, title: stamp.title, subtitle: stamp.metadata,
      chipText: type == .event && !date.isEmpty ? date : (type == .deal ? "VIEW OFFER" : nil),
      description: type == .club || type == .place ? stamp.description : nil,
      supportingText: stamp.terms,
      username: nil, avatarURL: nil)
  }
}
