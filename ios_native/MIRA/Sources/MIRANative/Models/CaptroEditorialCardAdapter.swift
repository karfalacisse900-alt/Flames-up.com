import Foundation

extension MIRAPost {
  /// Home selects useful facts without changing the underlying post or the
  /// separate Details/text-only adapters. Rendering, not this adapter, bounds copy.
  var captroMediaFeedCardContent: CaptroEditorialCardContent {
    let source = captroEditorialCardContent
    let commerce = detail?.commerce
    let event = detail?.event
    // New writing intents store a generated headline for indexing, not an
    // authored title. Legacy supplied titles (even "Club") are left intact.
    let authoredTitle = source.type == .moment && CaptroWritingIntent(rawValue: creationIntent ?? "") != nil ? nil
      : cleanEditorialText(source.type == .place ? placeDisplayName : commerce?.title) ?? captroCleanTitle
    let caption = cleanEditorialText(self.caption) ?? cleanEditorialText(content)
    var card = CaptroEditorialCardContent(type: source.type, title: authoredTitle ?? "",
      username: source.username ?? cleanEditorialText(userFullName), avatarURL: source.avatarURL)
    let context = CaptroHomeStampContext.specific(displayLocationText)
      ?? CaptroHomeStampContext.specific(placeCity)
    switch source.type {
    case .moment:
      card.description = caption == authoredTitle ? nil : caption
    case .place:
      card.subtitle = context
      card.chipText = source.chipText
      card.description = caption == authoredTitle ? nil : caption
    case .club:
      card.chipText = commerce.map { "\(max(0, $0.joinedCount)) MEMBERS" }
      card.priceText = source.supportingText
      card.availabilityText = CaptroStampAdapter.availability(commerce)
      card.description = cleanEditorialText(commerce?.description) ?? caption
    case .event, .meetup:
      card.scheduleText = source.scheduleText
      card.locationText = joinedEditorialText([
        CaptroHomeStampContext.specific(commerce?.locationName ?? event?.venueName),
        CaptroHomeStampContext.specific(commerce?.city ?? event?.city) ?? context])
      card.priceText = source.priceText
      card.availabilityText = source.availabilityText
      if source.type == .meetup {
        card.chipText = commerce.map { "\(max(0, $0.joinedCount)) GOING" }
          ?? event?.attendeesCount.map { "\(max(0, $0)) GOING" }
      }
      card.description = cleanEditorialText(commerce?.description) ?? caption
    case .deal:
      card.chipText = commerce?.publicData?.benefits?.compactMap(cleanEditorialText).first
      card.priceText = commerce?.resolvedLowestPrice?.stampPrice
      card.scheduleText = source.scheduleText
      card.locationText = (commerce?.locationName == authoredTitle ? nil : CaptroHomeStampContext.specific(commerce?.locationName))
        ?? CaptroHomeStampContext.specific(commerce?.city) ?? context
      card.availabilityText = source.availabilityText
      let description = cleanEditorialText(commerce?.description) ?? caption
      let rules = cleanEditorialText(commerce?.publicData?.redemptionRules)
      card.description = [description, rules == description ? nil : rules].compactMap { $0 }.joined(separator: "\n\n")
    }
    return card
  }

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

/// Only removes broad geographic components already supplied by the data.
/// Never infers a neighborhood from coordinates, a city, or a category.
enum CaptroHomeStampContext {
  static func specific(_ value: String?) -> String? {
    let generic: Set<String> = ["new york", "new york city", "new york ny", "nyc", "ny", "ny usa",
      "united states", "united states of america", "usa", "us", "u s", "u s a"]
    let parts = (value ?? "").components(separatedBy: CharacterSet(charactersIn: ",·"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !generic.contains($0.lowercased().replacingOccurrences(of: ".", with: " ")
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

extension CaptroEditorialCardContent {
  var homeStampMetadata: String {
    let values: [String?] = [.event, .meetup].contains(type)
      ? [scheduleText, locationText, chipText, priceText, availabilityText]
      : [subtitle ?? locationText, chipText, priceText, scheduleText, availabilityText]
    var parts: [String] = []
    for value in values {
      let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !value.isEmpty && !parts.contains(value) { parts.append(value) }
    }
    return parts.joined(separator: " · ")
  }

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
