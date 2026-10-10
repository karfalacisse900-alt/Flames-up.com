import SwiftUI
import UIKit

/// Owned by Home, keyed by post ID; measurements do not change post data.
struct CaptroFeedStampReadingState: Equatable {
  var expanded = false
  var collapsedHeight: CGFloat = 0
}

enum CaptroFeedStampGeometry {
  static func leadingInset(width: CGFloat) -> CGFloat { min(22, max(16, width * 0.054)) }
  static func stampWidth(mediaWidth: CGFloat, accessibility: Bool) -> CGFloat {
    min(mediaWidth - leadingInset(width: mediaWidth) * 2, mediaWidth * (accessibility ? 0.90 : 0.70))
  }
  static func originY(mediaHeight: CGFloat, stampHeight: CGFloat, clearance: CGFloat) -> CGFloat {
    max(mediaHeight * 0.25, mediaHeight - clearance - stampHeight)
  }
}

/// Home has a finished, content-sized annotation. Full copy remains in Details.
struct CaptroFeedMediaStamp: View {
  let content: CaptroEditorialCardContent
  let readingBudget: CGFloat
  let stampWidth: CGFloat
  let onOpen: () -> Void
  @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 21
  @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var metadataSize: CGFloat = 11.5
  @ScaledMetric(relativeTo: .caption) private var creatorSize: CGFloat = 12.5

  var body: some View {
    card
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.post.stamp.text")
  }

  private var captionLines: Int? {
    CaptroHomeStampTextBudget.captionLines(title: clean(content.title), metadata: metadata,
      caption: caption, creator: clean(content.username) != nil, width: stampWidth - 22,
      height: readingBudget, titleSize: titleSize, bodySize: bodySize,
      metadataSize: metadataSize, creatorSize: creatorSize)
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title = clean(content.title) {
      Button(action: onOpen) {
        Text(title)
          .font(.system(size: titleSize, weight: .bold))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens post details")
      .accessibilityIdentifier("captro.editorialCard")
      }
      if !metadata.isEmpty {
        Text(metadata).font(.system(size: metadataSize, weight: .medium))
          .foregroundStyle(MIRATheme.Color.forest)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, clean(content.title) == nil ? 0 : 5)
      }
      if let caption {
        Text(caption).font(.system(size: bodySize)).lineSpacing(2)
          .lineLimit(captionLines)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, metadata.isEmpty ? (clean(content.title) == nil ? 0 : 9) : 9)
          .accessibilityIdentifier("home.post.stamp.caption")
      }
      if let username = clean(content.username) {
        Button(action: onOpen) {
          HStack(spacing: 7) {
            RemoteAvatar(url: content.avatarURL, size: 24)
            Text(username).font(.system(size: creatorSize, weight: .semibold))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens post details")
        .padding(.top, caption != nil || !metadata.isEmpty || clean(content.title) != nil ? 11 : 0)
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var metadata: String { content.homeStampMetadata }
  private var caption: String? { clean(content.description) ?? clean(content.summaryText) }
  private func clean(_ value: String?) -> String? {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }
}

/// Measurement uses the actual width and scaled fonts. No caption is cut by
/// character count, and a short caption receives no reserved empty lines.
enum CaptroHomeStampTextBudget {
  static func textHeight(_ text: String, width: CGFloat, font: UIFont, spacing: CGFloat = 0) -> CGFloat {
    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing
    return ceil((text as NSString).boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height)
  }
  static func captionLines(title: String?, metadata: String, caption: String?, creator: Bool,
    width: CGFloat, height: CGFloat, titleSize: CGFloat, bodySize: CGFloat,
    metadataSize: CGFloat, creatorSize: CGFloat) -> Int? {
    guard let caption else { return nil }
    let titleFont = UIFont.systemFont(ofSize: titleSize, weight: .bold)
    let metadataFont = UIFont.systemFont(ofSize: metadataSize, weight: .medium)
    let bodyFont = UIFont.systemFont(ofSize: bodySize)
    var used: CGFloat = 22
    if let title { used += min(textHeight(title, width: width, font: titleFont), ceil(titleFont.lineHeight * 2)) }
    if !metadata.isEmpty {
      used += (title == nil ? 0 : 5) + min(textHeight(metadata, width: width, font: metadataFont), ceil(metadataFont.lineHeight * 2))
    }
    if title != nil || !metadata.isEmpty { used += 9 }
    if creator { used += 11 + max(24, UIFont.systemFont(ofSize: creatorSize, weight: .semibold).lineHeight) }
    let available = max(bodyFont.lineHeight, height - used)
    if textHeight(caption, width: width, font: bodyFont, spacing: 2) <= available { return nil }
    return max(1, Int(floor((available + 2) / (bodyFont.lineHeight + 2))))
  }
}

/// Media keeps its existing dimensions. Only real stamp overflow adds content
/// height below it. No per-post spacer, image stretching, nested scroll view,
/// or async image-size measurement. Accessibility/audio may need real overflow.
struct CaptroMediaStampLayout: Layout {
  let mediaSize: CGSize
  let stampWidth: CGFloat
  let clearance: CGFloat
  let reading: CaptroFeedStampReadingState
  var minimumStampTop: CGFloat = 0
  var visibleMediaRect: CGRect? = nil

  private func placement(_ subviews: Subviews) -> (size: CGSize, y: CGFloat) {
    let visible = visibleMediaRect ?? CGRect(origin: .zero, size: mediaSize)
    let size = subviews[1].sizeThatFits(ProposedViewSize(width: stampWidth, height: nil))
    return (size, max(minimumStampTop, visible.minY + CaptroFeedStampGeometry.originY(mediaHeight: visible.height,
      stampHeight: size.height, clearance: clearance)))
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let stamp = placement(subviews)
    return CGSize(width: mediaSize.width, height: max(mediaSize.height, stamp.y + stamp.size.height + 12))
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(mediaSize))
    let stamp = placement(subviews)
    let visible = visibleMediaRect ?? CGRect(origin: .zero, size: mediaSize)
    subviews[1].place(at: CGPoint(x: bounds.minX + visible.minX + CaptroFeedStampGeometry.leadingInset(width: visible.width),
      y: bounds.minY + stamp.y), anchor: .topLeading,
      proposal: ProposedViewSize(width: stampWidth, height: stamp.size.height))
  }
}
