import SwiftUI

/// Gesture and dock state stay here, away from the media loader and its player.
struct CaptroCaptureFocusView<Media: View, Identity: View>: View {
  let captureID: String
  let counter: String
  let stamp: String
  let title: String
  let subtitle: String?
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onClose: () -> Void
  let onDetails: () -> Void
  let media: Media
  let identity: Identity
  @State private var hidden = false
  @State private var drag: CGFloat = 0
  @State private var showCounter = false
  @GestureState private var holding = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var chromeVisible: Bool { !hidden && !holding }
  private var fade: Animation { .easeOut(duration: reduceMotion ? 0.1 : 0.2) }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .leading) {
        Color.black
        media
          .frame(width: width, height: geometry.size.height)
          .clipped()
          .offset(x: drag)
          .allowsHitTesting(false)
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { withAnimation(fade) { hidden.toggle() } }
          .gesture(focusGesture(width: width))
          .accessibilityLabel("Capture. Tap to hide controls, swipe to change capture.")
          .accessibilityAction(named: "Next capture", onNext)
          .accessibilityAction(named: "Previous capture", onPrevious)
          .accessibilityAction(named: "Capture details", onDetails)

        VStack {
          identity
            .padding(.horizontal, 16)
            .padding(.top, geometry.safeAreaInsets.top + 8)
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
          Spacer()
          if showCounter && chromeVisible {
            Text(counter)
              .font(.system(size: 11, weight: .medium, design: .monospaced))
              .foregroundStyle(.white)
              .padding(.horizontal, 9).padding(.vertical, 5)
              .background(.black.opacity(0.42), in: Capsule())
              .padding(.bottom, max(18, geometry.safeAreaInsets.bottom + 8))
              .transition(.opacity)
          }
        }
        CaptroCaptureEdgeDock(stamp: stamp, title: title, subtitle: subtitle, onOpen: onDetails)
          .opacity(chromeVisible ? 1 : 0)
          .allowsHitTesting(chromeVisible)
          .accessibilityHidden(!chromeVisible)
        RoundedRectangle(cornerRadius: 2)
          .fill(.white.opacity(0.6)).frame(width: 3, height: 22)
          .opacity(hidden && !holding ? 1 : 0)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      .frame(width: width, height: geometry.size.height)
      .clipped()
      .animation(fade, value: holding)
    }
    .ignoresSafeArea()
    .task(id: captureID) {
      withAnimation(fade) { showCounter = true }
      do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
      withAnimation(fade) { showCounter = false }
    }
  }

  // Exclusivity locks a touch into hold OR swipe. Releasing a hold cannot
  // accidentally navigate, and a moving finger cancels the hold recognizer.
  private func focusGesture(width: CGFloat) -> some Gesture {
    LongPressGesture(minimumDuration: 0.28, maximumDistance: 10)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .exclusively(before: DragGesture(minimumDistance: 18))
      .updating($holding) { value, state, _ in
        if case .first(.second(true, _)) = value { state = true }
      }
      .onChanged { value in
        if case .second(let swipe) = value,
           abs(swipe.translation.width) > abs(swipe.translation.height) * 1.2 {
          drag = swipe.translation.width
        }
      }
      .onEnded { value in
        guard case .second(let swipe) = value else { return }
        let x = swipe.translation.width
        let y = swipe.translation.height
        if y > 110, abs(y) > abs(x) * 1.4 { onClose(); return }
        if abs(x) > 44, abs(x) > abs(y) * 1.3,
           abs(x) > width * 0.16 || abs(swipe.predictedEndTranslation.width) > width * 0.4 {
          if x < 0 { onNext() } else { onPrevious() }
          var transaction = Transaction(); transaction.disablesAnimations = true
          withTransaction(transaction) { drag = reduceMotion ? 0 : (x < 0 ? 24 : -24) }
        }
        withAnimation(reduceMotion ? fade : .interactiveSpring(response: 0.25, dampingFraction: 0.96)) { drag = 0 }
      }
  }

}

private struct CaptroCaptureEdgeDock: View {
  let stamp: String
  let title: String
  let subtitle: String?
  let onOpen: () -> Void
  @State private var reveal: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 10) {
        Circle().fill(CaptroDetailStyle.accent).frame(width: 5, height: 5)
        Text(stamp)
          .font(.system(size: 10, weight: .bold)).tracking(1.2)
          .rotationEffect(.degrees(-90))
          .fixedSize().frame(width: 24, height: 76)
        Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium))
      }
      .frame(width: 38, height: 138)
      if reveal > 0 {
        VStack(alignment: .leading, spacing: 7) {
          Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(3)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
          }
          Text("View details").font(.system(size: 11, weight: .medium))
        }
        .frame(width: 176, alignment: .leading)
        .opacity(min(1, reveal / 75))
      }
    }
    .frame(width: 38 + min(196, reveal), height: 138, alignment: .leading)
    .foregroundStyle(.white)
    .background(.black.opacity(0.72), in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 8, topTrailingRadius: 8))
    .clipped()
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
    .gesture(
      DragGesture(minimumDistance: 10)
        .onChanged { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          reveal = max(0, min(196, value.translation.width))
        }
        .onEnded { value in
          let shouldOpen = reveal > 78 && value.translation.width > abs(value.translation.height)
          withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.92)) { reveal = 0 }
          if shouldOpen { onOpen() }
        }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(stamp), \(title). View details")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(onOpen)
  }
}
