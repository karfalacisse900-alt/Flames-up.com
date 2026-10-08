import Foundation
import SwiftUI
import UIKit

struct CaptroMediaPager: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  let isVideoActive: Bool
  var isAudioActive = true
  @Binding var selectedMediaIndex: Int
  let onOpenPost: () -> Void
  let onSave: () -> Void
  let showsCoverMediaOnly: Bool
  var frameSize: CGSize? = nil
  @Binding var stampReading: CaptroFeedStampReadingState

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var normalReadingBudget: CGFloat = 250
  @State private var isHoldingStamp = false
  @State private var suppressTapAfterStampPeek = false
  @State private var stampTapResetTask: Task<Void, Never>?
  @State private var isVideoPaused = false
  @State private var isVideoMuted = false

  // Cover coordinates refer to the source, not a provider's pre-cropped feed
  // variant. Downsample the source in the existing image cache; crop once here.
  private var mediaURLs: [String] { post.isCoverPost && !post.mediaURLs.isEmpty ? post.mediaURLs : post.feedMediaURLs }
  private var naturalMediaHeightToWidthRatio: CGFloat {
    boundedHomeMediaRatio(
      declaredCoverHeightToWidthRatio
        ?? MIRAMediaSizing.mainFeedDisplayRatio(
          for: mediaURLs,
          aspectRatios: post.mediaHeightToWidthRatios
      )
    )
  }
  private var mediaHeightToWidthRatio: CGFloat {
    naturalMediaHeightToWidthRatio
  }
  private var showsStampOnCurrentSlide: Bool {
    showsCoverMediaOnly || selectedMediaIndex == 0
  }
  private var needsTopVideoControls: Bool {
    guard currentMediaIsVideo, let frameSize else { return false }
    return dynamicTypeSize.isAccessibilitySize
      || stampReading.collapsedHeight > frameSize.height * 0.75 - 64
  }

  var body: some View {
    sizedMedia
      .contentShape(Rectangle())
      .accessibilityElement(children: .contain)
      .onAppear(perform: prefetchCarouselNeighbors)
      .onChange(of: mediaURLs) { _, urls in
        if selectedMediaIndex >= urls.count {
          selectedMediaIndex = max(0, urls.count - 1)
        }
      }
      .onChange(of: selectedMediaIndex) { _, _ in
        isVideoPaused = false
        isVideoMuted = false
        prefetchCarouselNeighbors()
      }
      .onChange(of: post.id) { _, _ in
        isVideoPaused = false
        isVideoMuted = false
      }
      .onChange(of: isVideoActive) { _, active in
        if !active {
          isVideoPaused = false
        }
      }
      .onChange(of: isHoldingStamp) { _, isHidden in
        updateStampPeekTapSuppression(isHidden: isHidden)
      }
      .onDisappear {
        stampTapResetTask?.cancel()
        isHoldingStamp = false
        suppressTapAfterStampPeek = false
      }
  }

  @ViewBuilder
  private var sizedMedia: some View {
    if let frameSize, post.isCoverPost {
      mediaLayers.frame(width: frameSize.width, height: frameSize.height).clipped()
    } else if let frameSize, post.mediaWriting(at: 0)?.showsStamp == false {
      mediaLayers.frame(width: frameSize.width, height: frameSize.height).clipped()
        .overlay(alignment: .bottomLeading) {
          if post.detail?.voice != nil || post.hasAudio {
            CaptroStampAudio(post: post, api: api, isActive: isAudioActive)
              .padding(8).background(MIRATheme.Color.surface).padding(.leading, 20).padding(.bottom, 64)
          }
        }
    } else if let frameSize {
      CaptroMediaStampLayout(mediaSize: frameSize,
        stampWidth: CaptroFeedStampGeometry.stampWidth(mediaWidth: frameSize.width,
          accessibility: dynamicTypeSize.isAccessibilitySize),
        clearance: currentMediaIsVideo || (mediaURLs.count > 1 && !showsCoverMediaOnly) ? 64 : 20,
        reading: stampReading, minimumStampTop: writingClearance(in: frameSize)) {
        mediaLayers.frame(width: frameSize.width, height: frameSize.height).clipped()
        feedStamp(readingBudget: dynamicTypeSize.isAccessibilitySize ? normalReadingBudget
          : min(normalReadingBudget, max(150, frameSize.height * 0.55)),
          stampWidth: CaptroFeedStampGeometry.stampWidth(mediaWidth: frameSize.width,
            accessibility: dynamicTypeSize.isAccessibilitySize))
      }
    } else {
      mediaLayers.aspectRatio(CGSize(width: 1, height: mediaHeightToWidthRatio), contentMode: .fit)
    }
  }

  private var mediaLayers: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black
        mediaContent
          .frame(width: proxy.size.width, height: proxy.size.height)
          .contentShape(Rectangle())
          .onTapGesture(perform: handleMediaTap)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier("home.post.media")
          .accessibilityLabel(mediaAccessibilityLabel)
          .accessibilityHint(currentMediaIsVideo ? "Tap to pause or play video" : "Opens the post detail screen")
          .accessibilityAction(named: "Open post") { openPostUnlessPeeking() }

        if mediaURLs.count > 1 && !showsCoverMediaOnly {
          CaptroCarouselCounter(current: selectedMediaIndex + 1, total: mediaURLs.count)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }

        if currentMediaIsVideo {
          if post.isCoverPost { videoControls.padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          } else if let writing = post.mediaWriting(at: selectedMediaIndex) {
            videoControls.padding(.trailing, 12)
              .padding(.top, min(proxy.size.height - 52, writing.textRect(in: proxy.size, fill: true).maxY + 8))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          } else { videoControls
            // Keep the existing actions. Only overflow reading moves them into
            // the clear upper-left strip, away from text and the slide counter.
            .frame(maxWidth: .infinity, maxHeight: .infinity,
              alignment: needsTopVideoControls ? .topLeading : .bottomTrailing)
            .padding(12)
          }
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
    let writing = post.mediaWriting(at: index)
    let crop = writing?.schemaVersion == 2 ? frameSize.map { writing!.sourceRect(in: $0, fill: true) } : nil
    return ZStack(alignment: .topLeading) {
    RemoteMediaView(
      url: url,
      isVideo: url.isVideoURL,
      placeholderURL: mediaPlaceholderURL(for: index, mediaURL: url),
      fallbackURL: mediaFallbackURL(for: index, mediaURL: url),
      contentMode: .fill,
      shouldPlay: isVideoActive && !isVideoPaused && (showsCoverMediaOnly ? index == 0 : (mediaURLs.count == 1 || selectedMediaIndex == index)),
      videoMuted: isVideoMuted,
      maxPixelSize: MIRAMediaSizing.feedTargetHeight,
      placeholderColor: .black,
      plainBackground: true
    )
    .frame(width: crop?.width, height: crop?.height)
    .frame(maxWidth: crop == nil ? .infinity : nil, maxHeight: crop == nil ? .infinity : nil)
    .offset(x: crop?.minX ?? 0, y: crop?.minY ?? 0)
      if let writing = post.mediaWriting(at: index) {
        GeometryReader { geometry in
          CaptroMediaWritingLayer(writing: writing, container: geometry.size, caption: post.caption ?? post.content)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipped()
  }

  private func writingClearance(in size: CGSize) -> CGFloat {
    let floor: CGFloat = currentMediaIsVideo ? 64 : 0
    // Keep published writing fixed. Move only the stamp/real continuation, not
    // the image or artwork, if the creator deliberately chose a low position.
    let bottom = mediaURLs.indices.compactMap { post.mediaWriting(at: $0)?.textRect(in: size, fill: true).maxY }.max() ?? 0
    return max(floor, bottom > 0 ? bottom + (mediaURLs.contains(where: { $0.isVideoURL }) ? 64 : 12) : 0)
  }

  private var declaredCoverHeightToWidthRatio: CGFloat? {
    post.mediaDimensions?.values.first?.heightToWidthRatio
  }

  private func boundedHomeMediaRatio(_ ratio: CGFloat) -> CGFloat {
    MIRAMediaSizing.supportedPostHeightToWidthRatio(ratio)
  }

  private func feedStamp(readingBudget: CGFloat, stampWidth: CGFloat) -> some View {
    VStack(spacing: 0) {
      CaptroFeedMediaStamp(content: post.captroMediaFeedCardContent,
        readingBudget: max(90, readingBudget - stampAudioHeight), stampWidth: stampWidth,
        onOpen: openPostUnlessPeeking)
      if post.detail?.voice != nil || post.hasAudio {
        CaptroStampAudio(post: post, api: api, isActive: isAudioActive)
          .padding(.horizontal, 14).padding(.bottom, 10)
      }
    }
    .background(MIRATheme.Color.surface)
    .overlay(Rectangle().strokeBorder(MIRATheme.Color.textPrimary, lineWidth: 1))
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
      if abs(stampReading.collapsedHeight - height) > 0.5 {
        stampReading.collapsedHeight = height
      }
    }
    .opacity(showsStampOnCurrentSlide && !isHoldingStamp ? 1 : 0)
    .allowsHitTesting(showsStampOnCurrentSlide)
    .accessibilityHidden(!showsStampOnCurrentSlide)
    .animation(stampPeekAnimation, value: isHoldingStamp)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.post.stamp")
    .contentShape(Rectangle())
    .background {
      if showsStampOnCurrentSlide { CaptroStampPeekGesture(isHolding: $isHoldingStamp) }
    }
  }

  private var stampAudioHeight: CGFloat {
    (post.detail?.voice == nil ? 0 : 54) + (post.hasAudio ? 54 : 0)
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
    var label = mediaURLs.count > 1 && !showsCoverMediaOnly
      ? "Post \(kind) \(min(selectedMediaIndex + 1, mediaURLs.count)) of \(mediaURLs.count)" : "Post \(kind)"
    if let text = post.mediaWriting(at: selectedMediaIndex)?.text,
       text.trimmingCharacters(in: .whitespacesAndNewlines) != (post.caption ?? post.content)?.trimmingCharacters(in: .whitespacesAndNewlines) {
      label += ". " + text
    }
    return label
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

/// Native long-press recognizes only inside the visible stamp and never owns a
/// drag. Parent scrolling and child buttons keep their normal gesture handling.
private struct CaptroStampPeekGesture: UIViewRepresentable {
  @Binding var isHolding: Bool

  func makeCoordinator() -> Coordinator { Coordinator(isHolding: $isHolding) }
  func makeUIView(context: Context) -> Marker {
    let marker = Marker()
    marker.isUserInteractionEnabled = false
    marker.onWindowChange = { [weak coordinator = context.coordinator] marker in
      coordinator?.attach(to: marker)
    }
    return marker
  }
  func updateUIView(_ view: Marker, context: Context) {
    context.coordinator.isHolding = $isHolding
    context.coordinator.attach(to: view)
  }
  static func dismantleUIView(_ view: Marker, coordinator: Coordinator) { coordinator.detach() }

  final class Marker: UIView {
    var onWindowChange: ((Marker) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); onWindowChange?(self) }
  }
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var isHolding: Binding<Bool>
    weak var marker: Marker?
    private var recognizer: UILongPressGestureRecognizer?
    init(isHolding: Binding<Bool>) { self.isHolding = isHolding }
    func attach(to marker: Marker) {
      guard recognizer?.view !== marker.window || self.marker !== marker else { return }
      detach()
      self.marker = marker
      guard let window = marker.window else { return }
      let gesture = UILongPressGestureRecognizer(target: self, action: #selector(changed(_:)))
      gesture.minimumPressDuration = 0.25
      gesture.allowableMovement = 10
      gesture.cancelsTouchesInView = false
      gesture.delaysTouchesBegan = false
      gesture.delaysTouchesEnded = false
      gesture.delegate = self
      window.addGestureRecognizer(gesture)
      recognizer = gesture
    }
    func detach() {
      if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
      recognizer = nil
    }
    @objc private func changed(_ gesture: UILongPressGestureRecognizer) {
      isHolding.wrappedValue = gesture.state == .began || gesture.state == .changed
    }
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard let marker, marker.window != nil, marker.bounds.contains(touch.location(in: marker)) else { return false }
      var ancestor: UIView? = marker
      while let view = ancestor {
        if view.isHidden || (view.clipsToBounds && !view.bounds.contains(touch.location(in: view))) { return false }
        ancestor = view.superview
      }
      return true
    }
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
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
