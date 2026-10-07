import SwiftUI

/// Owned by Home, keyed by post ID. Reading state survives lazy-cell recycling
/// without modifying the post, media selection, playback, or detail navigation.
struct CaptroFeedStampReadingState: Equatable {
  var expanded = false
  var collapsedHeight: CGFloat = 0
}

enum CaptroFeedStampGeometry {
  static func leadingInset(width: CGFloat) -> CGFloat { min(22, max(16, width * 0.054)) }
  static func stampWidth(mediaWidth: CGFloat, accessibility: Bool) -> CGFloat {
    min(mediaWidth - leadingInset(width: mediaWidth) * 2, mediaWidth * (accessibility ? 0.90 : 0.73))
  }
  static func originY(mediaHeight: CGFloat, stampHeight: CGFloat, clearance: CGFloat) -> CGFloat {
    max(mediaHeight * 0.25, mediaHeight - clearance - stampHeight)
  }
}

/// Measures the actual SwiftUI text at the current font size and width. The
/// first candidate is unabridged. Only an overflowing full stamp selects the
/// six-line reading preview; there is no character-count heuristic.
struct CaptroFeedMediaStamp: View {
  let content: CaptroEditorialCardContent
  let readingBudget: CGFloat
  @Binding var reading: CaptroFeedStampReadingState
  let onOpen: () -> Void
  @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 21
  @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var metadataSize: CGFloat = 11.5
  @ScaledMetric(relativeTo: .caption) private var creatorSize: CGFloat = 12.5

  var body: some View {
    Group {
      if reading.expanded {
        card(captionLines: nil, readingAction: "Show less")
      } else {
        CaptroStampReadingBudget(height: readingBudget) {
          ViewThatFits(in: .vertical) {
            card(captionLines: nil, readingAction: nil).fixedSize(horizontal: false, vertical: true)
            card(captionLines: 6, readingAction: "Read more").fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.post.stamp.text")
  }

  private func card(captionLines: Int?, readingAction: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      // Title and creator remain independent detail actions. Caption reading
      // never sits inside a navigation button or the media's tap recognizer.
      Button(action: onOpen) {
        Text(content.title)
          .font(.system(size: titleSize, weight: .bold))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens post details")
      .accessibilityIdentifier("captro.editorialCard")

      if let location = clean(content.locationText) ?? clean(content.subtitle) {
        Text(location).font(.system(size: metadataSize))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !metadata.isEmpty {
        Text(metadata).font(.system(size: metadataSize, weight: .medium))
          .foregroundStyle(MIRATheme.Color.forest)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let caption = clean(content.description) ?? clean(content.summaryText) {
        Text(caption).font(.system(size: bodySize)).lineSpacing(2)
          .lineLimit(captionLines)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
          .accessibilityIdentifier("home.post.stamp.caption")
      }
      if let readingAction {
        Button(readingAction) {
          // A layout change, not navigation. Avoid a spring/scroll animation
          // that would move the reader or animate a playing video.
          var transaction = Transaction(); transaction.disablesAnimations = true
          withTransaction(transaction) { reading.expanded.toggle() }
        }
        .font(.system(size: bodySize, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityIdentifier(reading.expanded ? "home.post.stamp.collapse" : "home.post.stamp.expand")
      }
      if let username = clean(content.username) {
        Button(action: onOpen) {
          HStack(spacing: 7) {
            RemoteAvatar(url: content.avatarURL, size: 24)
            Text(username).font(.system(size: creatorSize, weight: .semibold))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .frame(minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens post details")
        .padding(.top, 2)
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var metadata: String {
    var parts: [String] = []
    for value in [content.chipText, content.scheduleText, content.priceText,
      content.type == .club ? content.supportingText : nil, content.availabilityText] {
      if let value = clean(value), !parts.contains(value) { parts.append(value) }
    }
    // No invented type label when all metadata is absent.
    return parts.joined(separator: " · ")
  }
  private func clean(_ value: String?) -> String? {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }
}

/// A proposal, not a fixed-height frame. ViewThatFits returns the chosen
/// candidate's intrinsic height, so short stamps never reserve empty space.
private struct CaptroStampReadingBudget: Layout {
  let height: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: height))
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews[0].place(at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: height))
  }
}

/// Media keeps its existing dimensions. Only real stamp overflow adds content
/// height below it. No per-post spacer, image stretching, nested scroll view,
/// or async image-size measurement. Expanded text keeps its collapsed top edge.
struct CaptroMediaStampLayout: Layout {
  let mediaSize: CGSize
  let stampWidth: CGFloat
  let clearance: CGFloat
  let reading: CaptroFeedStampReadingState

  private func placement(_ subviews: Subviews) -> (size: CGSize, y: CGFloat) {
    let size = subviews[1].sizeThatFits(ProposedViewSize(width: stampWidth, height: nil))
    let anchorHeight = reading.expanded && reading.collapsedHeight > 0 ? reading.collapsedHeight : size.height
    return (size, CaptroFeedStampGeometry.originY(mediaHeight: mediaSize.height,
      stampHeight: anchorHeight, clearance: clearance))
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let stamp = placement(subviews)
    return CGSize(width: mediaSize.width, height: max(mediaSize.height, stamp.y + stamp.size.height + 12))
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(mediaSize))
    let stamp = placement(subviews)
    subviews[1].place(at: CGPoint(x: bounds.minX + CaptroFeedStampGeometry.leadingInset(width: mediaSize.width),
      y: bounds.minY + stamp.y), anchor: .topLeading,
      proposal: ProposedViewSize(width: stampWidth, height: stamp.size.height))
  }
}
