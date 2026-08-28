import Foundation
import SwiftUI

struct CaptroGuideOverlay: View {
  let post: MIRAPost

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title = post.captroCleanTitle {
        Text(title)
          .font(.title3.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.86)
      }

      if let supportingText = post.captroGuideSupportingText {
        Text(supportingText)
          .font(.body)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }

      if !post.captroGuideContributors.isEmpty {
        CaptroContributorAvatars(contributors: post.captroGuideContributors)
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.95))
    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .stroke(Color.white.opacity(0.72), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Captro Guide")
  }
}

struct CaptroCapturedStamp: View {
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("CAPTURED")
        .font(.caption2.weight(.bold))
      Text(detail)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .foregroundStyle(Color.black.opacity(0.76))
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(0.86), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Captured, \(detail)")
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
    let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  var captroIsGuidePost: Bool {
    let value = postType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return value == "guide" ||
      value == "album" ||
      value == "collaborative_album" ||
      value == "collaborative-album" ||
      value.contains("collab")
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

  var captroGuideContributors: [MIRATaggedUserPayload] {
    (taggedUsers ?? []).filter {
      !($0.profileImage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
  }

  var captroGuideSupportingText: String? {
    if let caption = captroFeedCaptionText {
      let firstLine = caption
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
      if let firstLine, !firstLine.isEmpty { return firstLine }
    }
    if feedMediaURLs.count > 1 { return "\(feedMediaURLs.count) photos" }
    return cleanedCaptroFeedValue(placeDisplayName)
  }

  var captroHasGuideOverlayContent: Bool {
    captroCleanTitle != nil || captroGuideSupportingText != nil || !captroGuideContributors.isEmpty
  }

  var captroCapturedStampText: String? {
    guard let location = captroCapturedLocation,
          let date = captroCreatedDate else { return nil }
    return "\(location.uppercased()) · \(CaptroFeedDateFormatters.stamp.string(from: date).uppercased())"
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
