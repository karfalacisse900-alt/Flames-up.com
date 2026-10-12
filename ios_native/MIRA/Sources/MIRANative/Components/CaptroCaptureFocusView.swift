import SwiftUI

/// Media stays mounted while sheets open. Navigation recognizers belong only to
/// the background hit surface, never to the stamp, creator or reply controls.
struct CaptroCaptureFocusView<Media: View, Identity: View, Actions: View>: View {
  let captureID: String
  let counter: String
  let stamp: CaptroStoryStampPresentation?
  let caption: String?
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onClose: () -> Void
  let onDetails: () -> Void
  let media: Media
  let identity: Identity
  let actions: Actions
  @State private var drag: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack {
        media
          .frame(width: width, height: geometry.size.height)
          .offset(x: drag)
          .allowsHitTesting(false)
        Color.clear
          .contentShape(Rectangle())
          .gesture(storySwipeGesture(width: width))
          .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
              if value.location.x < width * 0.4 { onPrevious() }
              else if value.location.x > width * 0.6 { onNext() }
            }
          )
          .accessibilityLabel("Story, " + counter)
          .accessibilityAction(named: "Next story", onNext)
          .accessibilityAction(named: "Previous story", onPrevious)
        VStack(alignment: .leading, spacing: 12) {
          identity
          Spacer(minLength: 12)
          if let stamp {
            Button(action: onDetails) {
              VStack(alignment: .leading, spacing: 5) {
                Text(stamp.label).font(.caption2.weight(.semibold)).tracking(1.5)
                if let title = stamp.title {
                  Text(title).font(.subheadline.weight(.semibold)).lineLimit(3)
                }
                if let context = stamp.context {
                  Text(context).font(.caption).lineLimit(2)
                }
              }
              .fixedSize(horizontal: false, vertical: true)
              .padding(12)
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .background(MIRATheme.Color.editorialCream)
              .overlay(Rectangle().strokeBorder(MIRATheme.Color.hairline, lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: width * (textSize.isAccessibilitySize ? 0.88 : 0.68), alignment: .leading)
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("story.stamp")
            .accessibilityHint("Opens details without joining or purchasing.")
          }
          if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(caption).font(.subheadline).lineLimit(3)
              .foregroundStyle(.white)
              .padding(6).background(.black.opacity(0.55))
              .accessibilityIdentifier("story.caption")
          }
          actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
      .frame(width: width, height: geometry.size.height)
      .clipped()
    }
    .background(MIRATheme.Color.mediaPlaceholder.ignoresSafeArea())
    .onChange(of: captureID) { _, _ in drag = 0 }
  }

  private func storySwipeGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 18)
      .onChanged { swipe in
        if abs(swipe.translation.width) > abs(swipe.translation.height) * 1.2 {
          drag = swipe.translation.width
        }
      }
      .onEnded { swipe in
        let x = swipe.translation.width
        let y = swipe.translation.height
        if y > 110, abs(y) > abs(x) * 1.4 { onClose(); return }
        if abs(x) > 44, abs(x) > abs(y) * 1.3,
           abs(x) > width * 0.16 || abs(swipe.predictedEndTranslation.width) > width * 0.4 {
          if x < 0 { onNext() } else { onPrevious() }
        }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) { drag = 0 }
      }
  }
}
