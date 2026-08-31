import Foundation
import SwiftUI
import UIKit

struct CaptroMediaPager: View {
  let post: MIRAPost
  let isVideoActive: Bool
  @Binding var selectedMediaIndex: Int
  let onOpenPost: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @GestureState private var isHoldingStamp = false
  @State private var measuredCoverHeightToWidthRatio: CGFloat?
  @State private var suppressTapAfterStampPeek = false
  @State private var stampTapResetTask: Task<Void, Never>?

  private var mediaURLs: [String] { post.feedMediaURLs }
  private var mediaHeightToWidthRatio: CGFloat {
    boundedHomeMediaRatio(
      declaredCoverHeightToWidthRatio
        ?? measuredCoverHeightToWidthRatio
        ?? MIRAMediaSizing.mainFeedDisplayRatio(
          for: mediaURLs,
          aspectRatios: post.mediaHeightToWidthRatios
      )
    )
  }
  private var mediaCornerRadius: CGFloat {
    mediaHeightToWidthRatio < 0.9 ? 14 : (mediaHeightToWidthRatio > 1.35 ? 16 : 18)
  }
  private var stampWidthFraction: CGFloat {
    mediaHeightToWidthRatio < 0.9 ? 0.68 : (mediaHeightToWidthRatio > 1.35 ? 0.74 : 0.72)
  }

  var body: some View {
    CaptroNaturalMediaLayout(heightToWidthRatio: mediaHeightToWidthRatio) {
      GeometryReader { proxy in
        ZStack {
          mediaContent
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: openPostUnlessPeeking)

          overlayContent(mediaWidth: proxy.size.width)

          if mediaURLs.count > 1 {
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
    }
    .background(MIRATheme.Color.mediaPlaceholder)
    .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(mediaAccessibilityLabel)
    .accessibilityHint("Opens the post detail screen")
    .onAppear(perform: prefetchCarouselNeighbors)
    .onChange(of: mediaURLs) { _, urls in
      measuredCoverHeightToWidthRatio = nil
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: selectedMediaIndex) { _, _ in
      prefetchCarouselNeighbors()
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
    if mediaURLs.count == 1, let url = mediaURLs.first {
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
      contentMode: .fit,
      shouldPlay: isVideoActive && (mediaURLs.count == 1 || selectedMediaIndex == index),
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
    guard let dimensions = post.mediaDimensions?.values.first else { return nil }
    if let width = dimensions.originalWidth,
       let height = dimensions.originalHeight,
       width > 0,
       height > 0 {
      return CGFloat(height / width)
    }
    if let ratio = dimensions.originalAspectRatio, ratio > 0 {
      return CGFloat(1 / ratio)
    }
    return nil
  }

  private func boundedHomeMediaRatio(_ ratio: CGFloat) -> CGFloat {
    guard ratio.isFinite, ratio > 0 else { return 4.0 / 3.0 }
    return min(max(ratio, 9.0 / 16.0), 3.0 / 2.0)
  }

  private func overlayContent(mediaWidth: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Spacer(minLength: 0)

        if mediaURLs.count > 1 {
          CaptroCarouselCounter(current: selectedMediaIndex + 1, total: mediaURLs.count)
        }
      }

      Spacer(minLength: 12)

      CaptroPostStamp(
        content: post.captroStampContent,
        onOpen: openPostUnlessPeeking,
        onAction: openPostUnlessPeeking
      )
      .frame(width: mediaWidth * stampWidthFraction, alignment: .leading)
      .contentShape(Rectangle())
      .opacity(isHoldingStamp ? 0 : 1)
      .animation(stampPeekAnimation, value: isHoldingStamp)
      .simultaneousGesture(stampPeekGesture)
      .padding(.bottom, mediaURLs.count > 1 ? 24 : 0)
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
    guard mediaURLs.count > 1 else { return "Post photo" }
    return "Post photo \(min(selectedMediaIndex + 1, mediaURLs.count)) of \(mediaURLs.count)"
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
    guard mediaURLs.count > 1 else { return }
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

private struct CaptroNaturalMediaLayout: Layout {
  let heightToWidthRatio: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    guard let subview = subviews.first else { return .zero }
    let fallbackSize = subview.sizeThatFits(.unspecified)
    let width = proposal.width ?? fallbackSize.width
    return CGSize(width: width, height: width * heightToWidthRatio)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    guard let subview = subviews.first else { return }
    subview.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
    )
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
