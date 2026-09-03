import Foundation
import SwiftUI
import UIKit

struct CaptroMediaPager: View {
  let post: MIRAPost
  let isVideoActive: Bool
  @Binding var selectedMediaIndex: Int
  let onOpenPost: () -> Void
  let showsCoverMediaOnly: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @GestureState private var isHoldingStamp = false
  @State private var measuredCoverHeightToWidthRatio: CGFloat?
  @State private var suppressTapAfterStampPeek = false
  @State private var stampTapResetTask: Task<Void, Never>?
  @State private var isVideoPaused = false
  @State private var isVideoMuted = true

  private var mediaURLs: [String] { post.feedMediaURLs }
  private var naturalMediaHeightToWidthRatio: CGFloat {
    boundedHomeMediaRatio(
      declaredCoverHeightToWidthRatio
        ?? measuredCoverHeightToWidthRatio
        ?? MIRAMediaSizing.mainFeedDisplayRatio(
          for: mediaURLs,
          aspectRatios: post.mediaHeightToWidthRatios
      )
    )
  }
  private var mediaHeightToWidthRatio: CGFloat {
    naturalMediaHeightToWidthRatio
  }
  private var stampWidthFraction: CGFloat {
    naturalMediaHeightToWidthRatio < 0.8 ? 0.66 : (naturalMediaHeightToWidthRatio > 1.3 ? 0.68 : 0.70)
  }
  private var showsStampOnCurrentSlide: Bool {
    showsCoverMediaOnly || selectedMediaIndex == 0
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        mediaContent
          .frame(width: proxy.size.width, height: proxy.size.height)
          .contentShape(Rectangle())
          .onTapGesture(perform: handleMediaTap)

        overlayContent(mediaWidth: proxy.size.width)

        if currentMediaIsVideo {
          videoControls
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(12)
        }

        if mediaURLs.count > 1 && !showsCoverMediaOnly {
          CaptroCarouselDots(
            total: mediaURLs.count,
            current: selectedMediaIndex,
            reduceMotion: reduceMotion
          )
          .padding(.bottom, 12)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(false)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .aspectRatio(CGSize(width: 1, height: mediaHeightToWidthRatio), contentMode: .fit)
    .clipped()
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityLabel(mediaAccessibilityLabel)
    .accessibilityHint(currentMediaIsVideo ? "Tap to pause or play video" : "Opens the post detail screen")
    .accessibilityAction(named: "Open post") { openPostUnlessPeeking() }
    .onAppear(perform: prefetchCarouselNeighbors)
    .onChange(of: mediaURLs) { _, urls in
      measuredCoverHeightToWidthRatio = nil
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: selectedMediaIndex) { _, _ in
      isVideoPaused = false
      isVideoMuted = true
      prefetchCarouselNeighbors()
    }
    .onChange(of: post.id) { _, _ in
      isVideoPaused = false
      isVideoMuted = true
    }
    .onChange(of: isVideoActive) { _, active in
      if !active {
        isVideoPaused = false
        isVideoMuted = true
      }
    }
    .onChange(of: isHoldingStamp) { _, isHidden in
      updateStampPeekTapSuppression(isHidden: isHidden)
    }
    .onDisappear {
      stampTapResetTask?.cancel()
    }
  }

  @ViewBuilder
  private var mediaContent: some View {
    if let url = mediaURLs.first, showsCoverMediaOnly || mediaURLs.count == 1 {
      mediaView(url: url, index: 0)
        .allowsHitTesting(false)
    } else {
      TabView(selection: $selectedMediaIndex) {
        ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
          mediaView(url: url, index: index)
            .background(CaptroCarouselDirectionGateInstaller())
            .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
    }
  }

  private func mediaView(url: String, index: Int) -> some View {
    RemoteMediaView(
      url: url,
      isVideo: url.isVideoURL,
      placeholderURL: mediaPlaceholderURL(for: index, mediaURL: url),
      fallbackURL: mediaFallbackURL(for: index, mediaURL: url),
      contentMode: .fill,
      shouldPlay: isVideoActive && !isVideoPaused && (showsCoverMediaOnly ? index == 0 : (mediaURLs.count == 1 || selectedMediaIndex == index)),
      videoMuted: isVideoMuted,
      maxPixelSize: MIRAMediaSizing.feedTargetHeight,
      placeholderColor: MIRATheme.Color.mediaPlaceholder,
      onMeasuredRatio: { ratio in
        guard index == 0 else { return }
        let boundedRatio = boundedHomeMediaRatio(ratio)
        guard abs((measuredCoverHeightToWidthRatio ?? 0) - boundedRatio) > 0.001 else { return }
        measuredCoverHeightToWidthRatio = boundedRatio
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private var declaredCoverHeightToWidthRatio: CGFloat? {
    post.mediaDimensions?.values.first?.heightToWidthRatio
  }

  private func boundedHomeMediaRatio(_ ratio: CGFloat) -> CGFloat {
    MIRAMediaSizing.supportedPostHeightToWidthRatio(ratio)
  }

  private func overlayContent(mediaWidth: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Spacer(minLength: 0)

        if mediaURLs.count > 1 && !showsCoverMediaOnly {
          CaptroCarouselCounter(current: selectedMediaIndex + 1, total: mediaURLs.count)
        }
      }

      Spacer(minLength: 12)

      CaptroPostStamp(
        content: post.captroStampContent,
        onOpen: openPostUnlessPeeking,
        onAction: openPostUnlessPeeking,
        compact: true
      )
      .frame(width: mediaWidth * stampWidthFraction, alignment: .leading)
      .contentShape(Rectangle())
      .opacity(showsStampOnCurrentSlide && !isHoldingStamp ? 1 : 0)
      .allowsHitTesting(showsStampOnCurrentSlide)
      .accessibilityHidden(!showsStampOnCurrentSlide)
      .animation(stampPeekAnimation, value: isHoldingStamp)
      .simultaneousGesture(stampPeekGesture)
      .padding(.bottom, mediaURLs.count > 1 && !showsCoverMediaOnly ? 24 : 0)
    }
    .padding(16)
  }

  private var stampPeekGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.25, maximumDistance: 10)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .updating($isHoldingStamp) { phase, state, _ in
        switch phase {
        case let .second(true, drag):
          guard let drag else {
            state = true
            return
          }
          state = hypot(drag.translation.width, drag.translation.height) <= 22
        default:
          state = false
        }
      }
  }

  private var stampPeekAnimation: Animation? {
    guard !reduceMotion else { return nil }
    return isHoldingStamp
      ? .easeOut(duration: 0.20)
      : .easeInOut(duration: 0.24)
  }

  private func openPostUnlessPeeking() {
    guard !suppressTapAfterStampPeek else { return }
    onOpenPost()
  }

  private var currentMediaIsVideo: Bool {
    let index = showsCoverMediaOnly ? 0 : selectedMediaIndex
    return mediaURLs.indices.contains(index) && mediaURLs[index].isVideoURL
  }

  private func handleMediaTap() {
    guard !suppressTapAfterStampPeek else { return }
    if currentMediaIsVideo {
      isVideoPaused.toggle()
    } else {
      onOpenPost()
    }
  }

  private var videoControls: some View {
    HStack(spacing: 0) {
      videoButton(icon: isVideoPaused ? "play.fill" : "pause.fill", label: isVideoPaused ? "Play video" : "Pause video") {
        isVideoPaused.toggle()
      }
      videoButton(icon: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isVideoMuted ? "Turn sound on" : "Mute video") {
        isVideoMuted.toggle()
      }
    }
  }

  private func videoButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(.black.opacity(0.48), in: Circle())
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  private func updateStampPeekTapSuppression(isHidden: Bool) {
    stampTapResetTask?.cancel()
    if isHidden {
      suppressTapAfterStampPeek = true
      return
    }

    guard suppressTapAfterStampPeek else { return }
    stampTapResetTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled, !isHoldingStamp else { return }
      suppressTapAfterStampPeek = false
    }
  }

  private var mediaAccessibilityLabel: String {
    let kind = currentMediaIsVideo ? "video" : "photo"
    guard mediaURLs.count > 1 && !showsCoverMediaOnly else { return "Post \(kind)" }
    return "Post \(kind) \(min(selectedMediaIndex + 1, mediaURLs.count)) of \(mediaURLs.count)"
  }

  private func mediaPlaceholderURL(for index: Int, mediaURL: String) -> String? {
    let posters = post.posterMediaURLs
    let thumbnails = post.thumbnailMediaURLs
    let poster = posters.indices.contains(index) ? posters[index] : nil
    let thumbnail = thumbnails.indices.contains(index) ? thumbnails[index] : nil
    let candidate = mediaURL.isVideoURL ? (poster ?? thumbnail) : (thumbnail ?? poster)
    let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty, trimmed != mediaURL else { return nil }
    return trimmed
  }

  private func mediaFallbackURL(for index: Int, mediaURL: String) -> String? {
    let originals = post.fallbackMediaURLs
    guard originals.indices.contains(index) else { return nil }
    let trimmed = originals[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != mediaURL, !trimmed.isVideoURL else { return nil }
    return trimmed
  }

  private func prefetchCarouselNeighbors() {
    guard !showsCoverMediaOnly, mediaURLs.count > 1 else { return }
    let selected = min(max(selectedMediaIndex, 0), mediaURLs.count - 1)
    var previews: [String] = []
    var priorityImages: [String] = []
    var remainingImages: [String] = []
    var videos: [String] = []

    for index in mediaURLs.indices {
      let url = mediaURLs[index]
      if let placeholder = mediaPlaceholderURL(for: index, mediaURL: url) {
        previews.append(placeholder)
      }
      let fallback = mediaFallbackURL(for: index, mediaURL: url)
      if url.isVideoURL {
        if abs(index - selected) <= 1 { videos.append(url) }
      } else if index >= selected && index <= min(mediaURLs.count - 1, selected + 2) {
        priorityImages.append(url)
        if let fallback { priorityImages.append(fallback) }
      } else {
        remainingImages.append(url)
        if let fallback { remainingImages.append(fallback) }
      }
    }

    if !videos.isEmpty {
      Task { @MainActor in
        MIRAVideoPrewarmManager.shared.prewarm(urls: videos, keepOnly: Set(videos))
      }
    }

    let imageURLs = orderedUniqueURLs(priorityImages + remainingImages)
    let previewURLs = orderedUniqueURLs(previews)
    guard !previewURLs.isEmpty || !imageURLs.isEmpty else { return }
    Task.detached(priority: .utility) {
      if !previewURLs.isEmpty {
        await MIRAImagePrefetcher.prefetch(urls: previewURLs, maxPixelSize: 560, limit: 16)
      }
      if !imageURLs.isEmpty {
        await MIRAImagePrefetcher.prefetch(
          urls: imageURLs,
          maxPixelSize: MIRAMediaSizing.feedTargetHeight,
          limit: max(18, imageURLs.count)
        )
      }
    }
  }

  private func orderedUniqueURLs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return !trimmed.isEmpty && seen.insert(trimmed).inserted ? trimmed : nil
    }
  }
}

private struct CaptroCarouselDirectionGateInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let marker = UIView(frame: .zero)
    marker.isUserInteractionEnabled = false
    DispatchQueue.main.async {
      installDirectionGate(from: marker)
    }
    return marker
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async {
      installDirectionGate(from: uiView)
    }
  }

  private func installDirectionGate(from marker: UIView) {
    guard let scrollView = pagingScrollView(above: marker) else { return }
    scrollView.isDirectionalLockEnabled = true

    if scrollView.gestureRecognizers?.contains(where: { $0 is CaptroVerticalIntentGestureRecognizer }) == true {
      return
    }

    let directionGate = CaptroVerticalIntentGestureRecognizer(threshold: 10)
    scrollView.addGestureRecognizer(directionGate)
    scrollView.panGestureRecognizer.require(toFail: directionGate)
  }

  private func pagingScrollView(above marker: UIView) -> UIScrollView? {
    var ancestor = marker.superview
    while let view = ancestor {
      if let scrollView = view as? UIScrollView {
        let hasHorizontalContent = scrollView.contentSize.width > scrollView.bounds.width + 1
        if scrollView.isPagingEnabled || scrollView.alwaysBounceHorizontal || hasHorizontalContent {
          return scrollView
        }
      }
      ancestor = view.superview
    }
    return nil
  }
}

private final class CaptroVerticalIntentGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
  private let threshold: CGFloat
  private var initialPoint: CGPoint?

  init(threshold: CGFloat) {
    self.threshold = threshold
    super.init(target: nil, action: nil)
    delegate = self
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard touches.count == 1, let touch = touches.first, let view else {
      state = .failed
      return
    }
    initialPoint = touch.location(in: view)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard state == .possible,
          let touch = touches.first,
          let view,
          let initialPoint else { return }

    let point = touch.location(in: view)
    let horizontalDistance = abs(point.x - initialPoint.x)
    let verticalDistance = abs(point.y - initialPoint.y)
    guard max(horizontalDistance, verticalDistance) >= threshold else { return }

    // Vertical intent blocks the pager; failing releases its existing horizontal pan.
    state = verticalDistance >= horizontalDistance ? .began : .failed
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    switch state {
    case .began, .changed:
      state = .ended
    case .possible:
      state = .failed
    default:
      break
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    state = .cancelled
  }

  override func reset() {
    initialPoint = nil
    super.reset()
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

private struct CaptroCarouselCounter: View {
  let current: Int
  let total: Int

  var body: some View {
    Text("\(min(max(current, 1), max(total, 1))) / \(max(total, 1))")
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color.black.opacity(0.78))
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(Color.white.opacity(0.90))
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1))
      .accessibilityLabel("Photo \(current) of \(total)")
  }
}

private struct CaptroCarouselDots: View {
  let total: Int
  let current: Int
  let reduceMotion: Bool

  private var visibleIndices: [Int] {
    guard total > 7 else { return Array(0..<total) }
    let start = min(max(current - 3, 0), total - 7)
    return Array(start..<(start + 7))
  }

  var body: some View {
    HStack(spacing: 5) {
      ForEach(visibleIndices, id: \.self) { index in
        Circle()
          .fill(index == current ? Color.white : Color.white.opacity(0.48))
          .frame(width: index == current ? 7 : 5, height: index == current ? 7 : 5)
          .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
      }
    }
    .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: current)
    .accessibilityHidden(true)
  }
}
