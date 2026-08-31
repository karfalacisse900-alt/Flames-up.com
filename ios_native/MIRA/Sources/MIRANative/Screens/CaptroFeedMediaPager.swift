import Foundation
import SwiftUI

struct CaptroMediaPager: View {
  let post: MIRAPost
  let isVideoActive: Bool
  @Binding var selectedMediaIndex: Int
  let onOpenPost: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @GestureState private var isHoldingPhoto = false
  @State private var suppressTapAfterStampPeek = false
  @State private var stampTapResetTask: Task<Void, Never>?

  private var mediaURLs: [String] { post.feedMediaURLs }

  var body: some View {
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
      .simultaneousGesture(stampPeekGesture)
    }
    .aspectRatio(4.0 / 5.0, contentMode: .fit)
    .background(MIRATheme.Color.mediaPlaceholder)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(mediaAccessibilityLabel)
    .accessibilityHint("Opens the post detail screen")
    .onAppear(perform: prefetchCarouselNeighbors)
    .onChange(of: mediaURLs) { _, urls in
      if selectedMediaIndex >= urls.count {
        selectedMediaIndex = max(0, urls.count - 1)
      }
    }
    .onChange(of: selectedMediaIndex) { _, _ in
      prefetchCarouselNeighbors()
    }
    .onChange(of: isHoldingPhoto) { _, isHidden in
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
      shouldPlay: isVideoActive && (mediaURLs.count == 1 || selectedMediaIndex == index),
      maxPixelSize: MIRAMediaSizing.feedTargetHeight,
      placeholderColor: MIRATheme.Color.mediaPlaceholder
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
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
      .frame(width: mediaWidth * 0.72, alignment: .leading)
      .padding(.bottom, mediaURLs.count > 1 ? 24 : 0)
      .opacity(isHoldingPhoto ? 0 : 1)
      .allowsHitTesting(!isHoldingPhoto)
      .animation(stampPeekAnimation, value: isHoldingPhoto)
    }
    .padding(16)
  }

  private var stampPeekGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.25, maximumDistance: 22)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .updating($isHoldingPhoto) { phase, state, _ in
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
    return isHoldingPhoto
      ? .easeOut(duration: 0.11)
      : .easeIn(duration: 0.16)
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
      guard !Task.isCancelled, !isHoldingPhoto else { return }
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
