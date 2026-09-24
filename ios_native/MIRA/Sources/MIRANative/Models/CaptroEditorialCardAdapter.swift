import Foundation

extension MIRAPost {
  /// Image-free posts have no separate caption below the card. Keep their
  /// caption in the same surface, without repeating a title or offer terms.
  var captroTextOnlyCardContent: CaptroEditorialCardContent {
    var content = captroEditorialCardContent
    let caption = captroFeedCaptionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !caption.isEmpty && caption != content.title {
      if [.event, .meetup, .deal].contains(content.type) && content.summaryText == nil {
        content.summaryText = caption
      } else if content.description == nil {
        content.description = caption
      }
    }
    return content
  }

  /// Live feed data only. Example content belongs in the DEBUG visual fixture, not here.
  var captroEditorialCardContent: CaptroEditorialCardContent {
    let type = CaptroEditorialCardType(stampKind: captroStampKind)
    let commerce = detail?.commerce
    let event = detail?.event
    let unavailable = CaptroStampAdapter.availability(commerce)
    let title = cleanEditorialText(type == .place ? placeDisplayName : commerce?.title)
      ?? captroCleanTitle ?? (type == .moment && detail?.voice != nil ? "Voice post" : type.rawValue.capitalized)
    let area = cleanEditorialText(type == .place
      ? (displayLocationText ?? placeCity)
      : (commerce?.city ?? event?.city ?? commerce?.locationName ?? captroFeedLocationText))
    let handle = cleanEditorialText(userUsername).map {
      "@" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }
    let price = commerce?.resolvedLowestPrice?.stampPrice ?? event?.priceLabel
      ?? (commerce?.paymentModel == "free" ? "Free"
        : (commerce?.paymentModel == "paid" ? "View pricing" : nil))
    let start = commerce?.startsAt ?? event?.startsAt
    let timeZone = commerce?.timeZone ?? event?.timeZone
    let date = CaptroStampAdapter.datePart(start, timeZone: timeZone, format: "MMM d")
    let time = CaptroStampAdapter.datePart(start, timeZone: timeZone, format: "jmm")
    let schedule = commerce?.scheduleLabel ?? joinedEditorialText([date, time])
    let eventLocation = commerce?.displayLocation
      ?? joinedEditorialText([event?.venueName, event?.city])
      ?? cleanEditorialText(captroFeedLocationText)
    let eventSummary = cleanEditorialText(commerce?.description) ?? cleanEditorialText(captroFeedCaptionText)

    var content = CaptroEditorialCardContent(type: type, title: title,
      subtitle: area, username: handle, avatarURL: userProfileImage)
    switch type {
    case .moment:
      let caption = cleanEditorialText(captroFeedCaptionText)
      content.description = caption == title ? nil : caption
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
      content.scheduleText = schedule
      content.priceText = price
      content.locationText = eventLocation
      content.summaryText = eventSummary == title ? nil : eventSummary
      content.availabilityText = unavailable
    case .meetup:
      content.chipText = unavailable ?? commerce.map { "\(max(0, $0.joinedCount)) GOING" }
        ?? event?.attendeesCount.map { "\(max(0, $0)) GOING" }
      content.supportingText = joinedEditorialText([date, time, price])
      content.scheduleText = schedule
      let spots = commerce?.remaining.flatMap { $0 > 0 ? "\($0) SPOTS LEFT" : nil }
      content.priceText = joinedEditorialText([price, spots])
      content.locationText = eventLocation
      content.summaryText = eventSummary == title ? nil : eventSummary
      content.availabilityText = unavailable
    case .deal:
      // Benefits and conditions come from structured offer fields, never caption parsing.
      let benefit = commerce?.publicData?.benefits?.compactMap { cleanEditorialText($0) }.first
      let rules = cleanEditorialText(commerce?.publicData?.redemptionRules)
      let conciseRules = rules.flatMap { $0.count <= 70 ? $0 : nil }
      content.chipText = unavailable ?? (rules != nil && conciseRules == nil ? "VIEW OFFER" : benefit ?? "VIEW OFFER")
      let expiry = CaptroStampAdapter.datePart(commerce?.expiresAt,
        timeZone: commerce?.timeZone, format: "MMM d jmm").map { "Until \($0)" }
      content.supportingText = conciseRules ?? (rules == nil ? expiry : "Full conditions in details")
      if content.chipText == "VIEW OFFER", content.supportingText == nil {
        content.supportingText = "See offer details"
      }
      content.headline = rules == nil || conciseRules != nil
        ? benefit.flatMap { $0.count <= 42 ? $0 : nil } : nil
      content.scheduleText = CaptroStampAdapter.datePart(commerce?.expiresAt,
        timeZone: commerce?.timeZone, format: "MMM d").map { "Ends \($0)" }
      content.priceText = unavailable == nil && (rules == nil || conciseRules != nil)
        ? (commerce?.paymentModel == "free" ? "Claim free" : price ?? "View offer")
        : "View offer"
      content.locationText = joinedEditorialText([commerce?.title,
        commerce?.locationName == commerce?.title ? nil : commerce?.locationName, commerce?.city])
        ?? area
      content.summaryText = conciseRules
        ?? (rules == nil ? cleanEditorialText(commerce?.description) ?? cleanEditorialText(captroFeedCaptionText)
          : "Full qualifying conditions in details")
      content.availabilityText = unavailable
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
  init(draftStamp stamp: CaptroStampContent) {
    let type = CaptroEditorialCardType(stampKind: stamp.kind)
    let date = [stamp.dateMonth, stamp.dateDay].compactMap { $0 }.joined(separator: " ")
    self.init(type: type, title: stamp.title, subtitle: stamp.metadata,
      chipText: type == .event && !date.isEmpty ? date : (type == .deal ? "VIEW OFFER" : nil),
      description: type == .moment || type == .club || type == .place ? stamp.description : nil,
      supportingText: stamp.terms,
      username: nil, avatarURL: nil)
    if [.event, .meetup, .deal].contains(type) {
      scheduleText = type == .deal ? nil : (stamp.terms ?? (date.isEmpty ? nil : date))
      locationText = stamp.metadata
      summaryText = type == .deal ? (stamp.terms ?? stamp.description) : stamp.description
      availabilityText = stamp.availability
    }
  }
}
