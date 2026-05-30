import AVFoundation
import AVKit
import Foundation
import SwiftUI
import UIKit

public struct MIRAPrimaryButton: View {
  let title: String
  let systemImage: String?
  let action: () -> Void

  public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: MIRATheme.Space.xs) {
        if let systemImage {
          Image(systemName: systemImage)
        }
        Text(title).font(.system(size: 16, weight: .semibold))
      }
      .foregroundStyle(.white)
      .frame(minHeight: 42)
      .padding(.horizontal, MIRATheme.Space.lg)
      .background(MIRATheme.Color.forest)
      .clipShape(Capsule())
    }
    .buttonStyle(.miraPress)
  }
}

public struct MIRAIconButton: View {
  let systemImage: String
  let action: () -> Void

  public var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
  }
}

public struct MIRAAudioPreviewButton: View {
  public let api: MIRAAPIClient?
  public let trackId: String?
  public let title: String
  public let artist: String
  public let artworkUrl: String?
  public let streamUrl: String?
  public let compact: Bool

  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var isLoading = false

  public init(
    api: MIRAAPIClient? = nil,
    trackId: String?,
    title: String,
    artist: String,
    artworkUrl: String? = nil,
    streamUrl: String? = nil,
    compact: Bool = false
  ) {
    self.api = api
    self.trackId = trackId
    self.title = title
    self.artist = artist
    self.artworkUrl = artworkUrl
    self.streamUrl = streamUrl
    self.compact = compact
  }

  public var body: some View {
    Button {
      Task { await togglePlayback() }
    } label: {
      HStack(spacing: compact ? 9 : 12) {
        artworkView
          .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
          .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
          Text(artist)
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        ZStack {
          if isLoading {
            ProgressView()
              .scaleEffect(0.76)
              .tint(MIRATheme.Color.forest)
          } else {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: compact ? 11 : 13, weight: .bold))
              .foregroundStyle(.white)
          }
        }
        .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
        .background(MIRATheme.Color.forest)
        .clipShape(Circle())
      }
      .padding(.leading, compact ? 8 : 10)
      .padding(.trailing, compact ? 8 : 10)
      .frame(height: compact ? 46 : 58)
      .background(MIRATheme.Color.forestSoft.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.miraPress)
    .onDisappear { stopPlayback() }
  }

  @ViewBuilder
  private var artworkView: some View {
    if let artworkUrl, !artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      RemoteMediaView(url: artworkUrl, isVideo: false)
    } else {
      ZStack {
        MIRATheme.Color.forestSoft
        Image(systemName: "music.note")
          .font(.system(size: compact ? 15 : 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
      }
    }
  }

  @MainActor
  private func togglePlayback() async {
    if isPlaying {
      stopPlayback()
      return
    }

    isLoading = true
    defer { isLoading = false }
    guard let urlString = await resolveStreamURL(), let url = URL(string: urlString) else { return }
    let nextPlayer = AVPlayer(url: url)
    player = nextPlayer
    nextPlayer.play()
    isPlaying = true
  }

  private func resolveStreamURL() async -> String? {
    let cleanStream = streamUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleanStream.isEmpty { return cleanStream }
    guard
      let api,
      let encoded = trackId?.trimmingCharacters(in: .whitespacesAndNewlines)
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      !encoded.isEmpty
    else {
      return nil
    }
    do {
      let track: MIRAAudiusTrack = try await api.get("/music/audius/stream/\(encoded)")
      return track.streamUrl
    } catch {
      return nil
    }
  }

  @MainActor
  private func stopPlayback() {
    player?.pause()
    player = nil
    isPlaying = false
  }
}

public struct MIRAHeaderCircleButton: View {
  let systemImage: String
  let size: CGFloat

  public init(systemImage: String, size: CGFloat = 38) {
    self.systemImage = systemImage
    self.size = size
  }

  public var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(width: size, height: size)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Circle())
  }
}

public enum MIRAScreenEnterStyle {
  case push
  case modal
  case tab

  fileprivate var offset: CGSize {
    switch self {
    case .push: return CGSize(width: 12, height: 0)
    case .modal: return CGSize(width: 0, height: 18)
    case .tab: return CGSize(width: 0, height: 8)
    }
  }

  fileprivate var scale: CGFloat {
    switch self {
    case .push: return 0.996
    case .modal: return 0.985
    case .tab: return 0.998
    }
  }

  fileprivate var duration: Double {
    switch self {
    case .push: return 0.22
    case .modal: return 0.26
    case .tab: return 0.18
    }
  }

  fileprivate var initialOpacity: Double {
    switch self {
    case .push: return 0.96
    case .modal: return 0.94
    case .tab: return 1.0
    }
  }
}

private struct MIRAScreenEnterModifier: ViewModifier {
  let style: MIRAScreenEnterStyle
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false

  func body(content: Content) -> some View {
    let offset = reduceMotion ? .zero : style.offset
    content
      .opacity(isVisible ? 1 : style.initialOpacity)
      .scaleEffect(isVisible || reduceMotion ? 1 : style.scale)
      .offset(x: isVisible ? 0 : offset.width, y: isVisible ? 0 : offset.height)
      .onAppear {
        guard !isVisible else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.08 : style.duration)) {
          isVisible = true
        }
      }
  }
}

public extension View {
  func miraScreenEnter(_ style: MIRAScreenEnterStyle = .push) -> some View {
    modifier(MIRAScreenEnterModifier(style: style))
  }
}

public enum MIRAScrollFeel {
  case feed
  case chat
  case sheet

  fileprivate var decelerationRate: UIScrollView.DecelerationRate {
    switch self {
    case .feed:
      return UIScrollView.DecelerationRate(rawValue: 0.988)
    case .chat:
      return UIScrollView.DecelerationRate(rawValue: 0.992)
    case .sheet:
      return UIScrollView.DecelerationRate(rawValue: 0.995)
    }
  }

  fileprivate var directionalLockEnabled: Bool {
    switch self {
    case .feed:
      return true
    case .chat, .sheet:
      return false
    }
  }
}

public extension View {
  func miraScrollFeel(_ feel: MIRAScrollFeel) -> some View {
    background(MIRAScrollTuningView(feel: feel).frame(width: 0, height: 0))
  }
}

private struct MIRAScrollTuningView: UIViewRepresentable {
  let feel: MIRAScrollFeel

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    DispatchQueue.main.async {
      configureScrollView(from: view)
    }
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async {
      configureScrollView(from: uiView)
    }
  }

  private func configureScrollView(from view: UIView) {
    var parent = view.superview
    while let candidate = parent {
      if let scrollView = candidate as? UIScrollView {
        scrollView.decelerationRate = feel.decelerationRate
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = feel.directionalLockEnabled
        scrollView.backgroundColor = .clear
        return
      }
      parent = candidate.superview
    }
  }
}

public struct MIRAPressButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

public extension ButtonStyle where Self == MIRAPressButtonStyle {
  static var miraPress: MIRAPressButtonStyle { MIRAPressButtonStyle() }
}

public struct MIRAEmptyState: View {
  let title: String
  let message: String
  let systemImage: String

  public var body: some View {
    VStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 42, weight: .light))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text(message)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(MIRATheme.Space.xxl)
    .frame(maxWidth: .infinity)
  }
}

private final class MIRAImageMemoryCache {
  static let shared = MIRAImageMemoryCache()
  private let cache = NSCache<NSString, UIImage>()

  private init() {
    cache.countLimit = 420
    cache.totalCostLimit = 160 * 1024 * 1024
  }

  func image(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
    cache.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize))
  }

  func store(_ image: UIImage, for url: URL, maxPixelSize: CGFloat, cost: Int) {
    cache.setObject(image, forKey: cacheKey(for: url, maxPixelSize: maxPixelSize), cost: cost)
  }

  func removeAll() {
    cache.removeAllObjects()
  }

  private func cacheKey(for url: URL, maxPixelSize: CGFloat) -> NSString {
    "\(url.absoluteString)#\(Int(maxPixelSize.rounded()))" as NSString
  }
}

public enum MIRAMediaCacheMaintenance {
  public static func clearMediaCaches() {
    MIRAImageMemoryCache.shared.removeAll()
    MIRAAPIClient.productionSession.configuration.urlCache?.removeAllCachedResponses()
    Task {
      await MIRAImageDiskCache.clear()
      MIRAApplePerformanceLogger.event("media_cache_cleared", detail: "manual")
    }
  }
}

private enum MIRAImageLoadSource: Equatable {
  case memory
  case disk
  case network
}

private struct MIRAImageLoadResult {
  let image: UIImage
  let source: MIRAImageLoadSource
}

private actor MIRAImageLoadPipeline {
  static let shared = MIRAImageLoadPipeline()
  private var inFlight: [String: Task<MIRAImageLoadResult?, Never>] = [:]

  func image(for remoteURL: URL, maxPixelSize: CGFloat) async -> MIRAImageLoadResult? {
    let resolvedMaxPixelSize = max(64, maxPixelSize)
    let key = "\(remoteURL.absoluteString)#\(Int(resolvedMaxPixelSize.rounded()))"

    if let cached = MIRAImageMemoryCache.shared.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) {
      MIRAApplePerformanceLogger.event("media_cache_hit", detail: "memory")
      return MIRAImageLoadResult(image: cached, source: .memory)
    }

    if let existing = inFlight[key] {
      return await existing.value
    }

    let task = Task.detached(priority: .userInitiated) { () -> MIRAImageLoadResult? in
      if remoteURL.isFileURL,
         let data = try? Data(contentsOf: remoteURL),
         let decoded = await MIRAImageDiskCache.decode(data, maxPixelSize: resolvedMaxPixelSize) {
        MIRAImageMemoryCache.shared.store(decoded, for: remoteURL, maxPixelSize: resolvedMaxPixelSize, cost: decoded.miraCacheCost)
        return MIRAImageLoadResult(image: decoded, source: .disk)
      }

      if let diskCached = await MIRAImageDiskCache.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) {
        MIRAImageMemoryCache.shared.store(diskCached, for: remoteURL, maxPixelSize: resolvedMaxPixelSize, cost: diskCached.miraCacheCost)
        MIRAApplePerformanceLogger.event("media_cache_hit", detail: "disk")
        return MIRAImageLoadResult(image: diskCached, source: .disk)
      }

      do {
        MIRAApplePerformanceLogger.event("media_cache_miss", detail: "network")
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 14
        request.setValue("image/jpeg,image/png,image/webp,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let metric = await MIRAPerformanceMetric.begin(category: "image", label: remoteURL.host ?? remoteURL.path)
        let data: Data
        let response: URLResponse
        do {
          (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
        } catch {
          await metric.finish(status: "error")
          throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        await metric.finish(status: String(status), bytes: data.count)
        guard (200..<300).contains(status), data.count <= 24 * 1024 * 1024 else { return nil }
        guard let decoded = await MIRAImageDiskCache.decode(data, maxPixelSize: resolvedMaxPixelSize) else { return nil }

        MIRAImageMemoryCache.shared.store(decoded, for: remoteURL, maxPixelSize: resolvedMaxPixelSize, cost: decoded.miraCacheCost)
        await MIRAImageDiskCache.store(data: data, for: remoteURL)
        return MIRAImageLoadResult(image: decoded, source: .network)
      } catch {
        return nil
      }
    }

    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    return result
  }
}

public struct MIRACachedImage<Content: View, Placeholder: View>: View {
  let url: String?
  let maxPixelSize: CGFloat
  let onImageLoaded: (UIImage) -> Void
  let content: (Image) -> Content
  let placeholder: () -> Placeholder
  @State private var uiImage: UIImage?
  @State private var loadedURL: URL?
  @State private var isImageVisible = false

  public init(
    url: String?,
    maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight,
    onImageLoaded: @escaping (UIImage) -> Void = { _ in },
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.maxPixelSize = maxPixelSize
    self.onImageLoaded = onImageLoaded
    self.content = content
    self.placeholder = placeholder
  }

  public var body: some View {
    Group {
      if let uiImage {
        content(Image(uiImage: uiImage))
          .opacity(isImageVisible ? 1 : 0)
      } else if let memoryImage = memoryImageForCurrentURL {
        content(Image(uiImage: memoryImage))
      } else {
        placeholder()
      }
    }
    .task(id: url) { await loadImage() }
  }

  private var memoryImageForCurrentURL: UIImage? {
    guard let url, let remoteURL = URL(string: url) else { return nil }
    return MIRAImageMemoryCache.shared.image(for: remoteURL, maxPixelSize: max(64, maxPixelSize))
  }

  private func loadImage() async {
    guard let url, let remoteURL = URL(string: url) else {
      await MainActor.run {
        uiImage = nil
        loadedURL = nil
      }
      return
    }

    let isAlreadyLoaded = await MainActor.run {
      loadedURL == remoteURL && uiImage != nil
    }
    if isAlreadyLoaded { return }

    let resolvedMaxPixelSize = max(64, maxPixelSize)

    if let memoryImage = MIRAImageMemoryCache.shared.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) {
      await MainActor.run {
        uiImage = memoryImage
        loadedURL = remoteURL
        isImageVisible = true
        onImageLoaded(memoryImage)
      }
      MIRAApplePerformanceLogger.event("media_cache_hit", detail: "memory_sync")
      return
    }

    let shouldClear = await MainActor.run {
      loadedURL != remoteURL
    }
    if shouldClear {
      await MainActor.run {
        uiImage = nil
        isImageVisible = false
      }
    }

    if let result = await MIRAImageLoadPipeline.shared.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) {
      guard !Task.isCancelled else { return }
      await MainActor.run {
        uiImage = result.image
        loadedURL = remoteURL
        if result.source == .network {
          withAnimation(.easeOut(duration: 0.16)) {
            isImageVisible = true
          }
        } else {
          isImageVisible = true
        }
        onImageLoaded(result.image)
      }
      let detail: String
      switch result.source {
      case .memory: detail = "memory"
      case .disk: detail = "disk"
      case .network: detail = "network"
      }
      MIRAPerformanceTimeline.markOnce("time_to_first_thumbnail", detail: detail)
    } else {
      let shouldClear = await MainActor.run {
        loadedURL != remoteURL
      }
      if shouldClear {
        await MainActor.run {
          uiImage = nil
          isImageVisible = false
        }
      }
    }
  }
}

private extension UIImage {
  var miraCacheCost: Int {
    guard let cgImage else { return 1_000_000 }
    return cgImage.bytesPerRow * cgImage.height
  }
}

private actor MIRAImagePrefetchState {
  static let shared = MIRAImagePrefetchState()
  private var inFlight = Set<String>()

  func begin(_ key: String) -> Bool {
    inFlight.insert(key).inserted
  }

  func finish(_ key: String) {
    inFlight.remove(key)
  }
}

public enum MIRAImagePrefetcher {
  public static func prefetch(
    urls: [String],
    maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight,
    limit: Int = 10
  ) async {
    let uniqueURLs = Array(orderedUnique(urls)
      .filter { !$0.isVideoURL }
      .prefix(limit))
    guard !uniqueURLs.isEmpty else { return }

    await withTaskGroup(of: Void.self) { group in
      let maxConcurrent = min(4, uniqueURLs.count)
      var nextIndex = 0

      for _ in 0..<maxConcurrent {
        guard !Task.isCancelled else { break }
        let value = uniqueURLs[nextIndex]
        nextIndex += 1
        group.addTask(priority: .utility) {
          await MIRAImagePrefetcher.prefetchImage(value, maxPixelSize: maxPixelSize)
        }
      }

      while await group.next() != nil {
        guard nextIndex < uniqueURLs.count, !Task.isCancelled else { continue }
        let value = uniqueURLs[nextIndex]
        nextIndex += 1
        group.addTask(priority: .utility) {
          await MIRAImagePrefetcher.prefetchImage(value, maxPixelSize: maxPixelSize)
        }
      }
    }
  }

  private static func prefetchImage(_ value: String, maxPixelSize: CGFloat) async {
    guard !Task.isCancelled else { return }
    guard let remoteURL = URL(string: value) else { return }
    guard MIRANetworkSecurityPolicy.isSecureMediaURL(remoteURL) else { return }

    let resolvedMaxPixelSize = max(64, maxPixelSize)
    let key = "\(remoteURL.absoluteString)#\(Int(resolvedMaxPixelSize.rounded()))"
    guard await MIRAImagePrefetchState.shared.begin(key) else { return }
    defer { Task { await MIRAImagePrefetchState.shared.finish(key) } }

    if MIRAImageMemoryCache.shared.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) != nil {
      return
    }
    if let diskCached = await MIRAImageDiskCache.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize) {
      MIRAImageMemoryCache.shared.store(diskCached, for: remoteURL, maxPixelSize: resolvedMaxPixelSize, cost: diskCached.miraCacheCost)
      return
    }

    guard !Task.isCancelled else { return }
    _ = await MIRAImageLoadPipeline.shared.image(for: remoteURL, maxPixelSize: resolvedMaxPixelSize)
  }

  private static func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }
}

public struct RemoteAvatar: View {
  let url: String?
  let size: CGFloat

  public var body: some View {
    MIRACachedImage(url: url, maxPixelSize: max(96, size * 3)) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        MIRATheme.Color.surfaceSoft
        Image(systemName: "person.fill")
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

public struct MIRAFollowAvatar: View {
  let url: String?
  let size: CGFloat
  let isFollowing: Bool

  public init(url: String?, size: CGFloat, isFollowing: Bool = false) {
    self.url = url
    self.size = size
    self.isFollowing = isFollowing
  }

  public var body: some View {
    ZStack(alignment: .bottomTrailing) {
      RemoteAvatar(url: url, size: size)
      Circle()
        .fill(isFollowing ? MIRATheme.Color.textPrimary : MIRATheme.Color.forest)
        .frame(width: max(18, size * 0.42), height: max(18, size * 0.42))
        .overlay {
          Image(systemName: isFollowing ? "checkmark" : "plus")
            .font(.system(size: max(9, size * 0.22), weight: .bold))
            .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        .offset(x: 2, y: 2)
    }
  }
}

public struct RemoteMediaView: View {
  let url: String
  let isVideo: Bool
  let placeholderURL: String?
  let contentMode: ContentMode
  let shouldPlay: Bool
  let maxPixelSize: CGFloat
  let showsVideoPlaceholderIcon: Bool
  let placeholderColor: Color
  let placeholderTint: Color
  let onMeasuredRatio: (CGFloat) -> Void

  public init(
    url: String,
    isVideo: Bool,
    placeholderURL: String? = nil,
    contentMode: ContentMode = .fill,
    shouldPlay: Bool = false,
    maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight,
    showsVideoPlaceholderIcon: Bool = true,
    placeholderColor: Color = MIRATheme.Color.mediaPlaceholder,
    placeholderTint: Color = MIRATheme.Color.textSecondary.opacity(0.72),
    onMeasuredRatio: @escaping (CGFloat) -> Void = { _ in }
  ) {
    self.url = url
    self.isVideo = isVideo
    self.placeholderURL = placeholderURL
    self.contentMode = contentMode
    self.shouldPlay = shouldPlay
    self.maxPixelSize = maxPixelSize
    self.showsVideoPlaceholderIcon = showsVideoPlaceholderIcon
    self.placeholderColor = placeholderColor
    self.placeholderTint = placeholderTint
    self.onMeasuredRatio = onMeasuredRatio
  }

  public var body: some View {
    Group {
      if isVideo {
        MIRAResolvedVideoPlayer(
          url: url,
          posterURL: resolvedPlaceholderURL,
          contentMode: contentMode,
          shouldPlay: shouldPlay,
          showsPlaceholderIcon: showsVideoPlaceholderIcon,
          placeholderColor: placeholderColor,
          placeholderTint: placeholderTint,
          onMeasuredRatio: onMeasuredRatio
        )
          .background(Color.clear)
      } else {
        ZStack {
          placeholder
          if let previewURL = resolvedPlaceholderURL {
            MIRACachedImage(url: previewURL, maxPixelSize: min(maxPixelSize, 520), onImageLoaded: reportRatio) { image in
              image
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .blur(radius: contentMode == .fill ? 8 : 0)
                .scaleEffect(contentMode == .fill ? 1.035 : 1)
                .opacity(0.92)
            } placeholder: {
              Color.clear
            }
          }
          MIRACachedImage(url: url, maxPixelSize: maxPixelSize, onImageLoaded: reportRatio) { image in
            image.resizable().aspectRatio(contentMode: contentMode)
          } placeholder: {
            Color.clear
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private var placeholder: some View {
    ZStack {
      placeholderColor
      LinearGradient(
        colors: [
          MIRATheme.Color.mediaPlaceholderRaised.opacity(0.76),
          placeholderColor,
          MIRATheme.Color.textMuted.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image(systemName: "photo")
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(placeholderTint.opacity(0.36))
    }
  }

  private var resolvedPlaceholderURL: String? {
    let trimmed = placeholderURL?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty, trimmed != url else { return nil }
    return trimmed
  }

  private func reportRatio(_ image: UIImage) {
    guard image.size.width > 0, image.size.height > 0 else { return }
    onMeasuredRatio(image.size.height / image.size.width)
  }
}

private struct MIRAResolvedVideoPlayer: View {
  let url: String
  let posterURL: String?
  let contentMode: ContentMode
  let shouldPlay: Bool
  let showsPlaceholderIcon: Bool
  let placeholderColor: Color
  let placeholderTint: Color
  let onMeasuredRatio: (CGFloat) -> Void
  @State private var player: AVPlayer?
  @State private var thumbnailURL: String?
  @State private var failed = false
  @State private var endObserver: NSObjectProtocol?
  @State private var loadedVideoURL: String?
  @State private var videoMetric: MIRAPerformanceMetric?
  @State private var generatedThumbnail: UIImage?
  @State private var isPlayerReady = false
  @State private var globallyPaused = false

  var body: some View {
    ZStack {
      placeholder

      if let previewURL = currentPosterURL {
        MIRACachedImage(url: previewURL, maxPixelSize: MIRAMediaSizing.feedTargetHeight, onImageLoaded: reportRatio) { image in
          image.resizable().aspectRatio(contentMode: contentMode)
        } placeholder: {
          Color.clear
        }
      } else if let generatedThumbnail {
        Image(uiImage: generatedThumbnail)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      }

      if let player {
        MIRAVideoPlayerView(player: player, contentMode: contentMode)
          .opacity(isPlayerReady ? 1 : 0)
          .animation(.easeOut(duration: 0.18), value: isPlayerReady)
          .onAppear { syncPlayback(player) }
          .onDisappear {
            player.pause()
            removeLoopObserver()
            stopVideoMetric(status: "disappear")
          }
      }

      if failed {
        VStack(spacing: 8) {
          Image(systemName: "play.slash")
          Text("Video is processing")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
      }
    }
    .task(id: playbackTaskID) { await configurePlayer() }
    .onChange(of: shouldPlay) { _, _ in
      guard let player else { return }
      syncPlayback(player)
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { _ in
      pauseForGlobalInterruption()
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackMayResume)) { _ in
      resumeAfterGlobalInterruption()
    }
  }

  private var playbackTaskID: String {
    "\(url)|\(shouldPlay)"
  }

  private var placeholder: some View {
    ZStack {
      placeholderColor
      LinearGradient(
        colors: [
          MIRATheme.Color.mediaPlaceholderRaised.opacity(0.72),
          placeholderColor,
          MIRATheme.Color.textMuted.opacity(0.16)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      if showsPlaceholderIcon {
        Image(systemName: "play.fill")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(placeholderTint.opacity(0.42))
      }
    }
  }

  private var currentPosterURL: String? {
    normalizedPreviewURL(posterURL) ?? normalizedPreviewURL(thumbnailURL)
  }

  private func normalizedPreviewURL(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty, trimmed != url else { return nil }
    return trimmed
  }

  @MainActor
  private func configurePlayer() async {
    if loadedVideoURL != url {
      player?.pause()
      removeLoopObserver()
      stopVideoMetric(status: "url_changed")
      player = nil
      thumbnailURL = nil
      generatedThumbnail = nil
      failed = false
      isPlayerReady = false
      loadedVideoURL = url
    }

    let directURL = URL(string: url)
    if let directURL, directURL.isPlayableFileOrRemoteVideo, generatedThumbnail == nil {
      Task { await loadGeneratedThumbnail(for: directURL, expectedURL: url) }
    }

    if !shouldPlay {
      if let player {
        player.pause()
        self.player = nil
        isPlayerReady = false
        removeLoopObserver()
        stopVideoMetric(status: "not_visible")
      }
      if thumbnailURL == nil && url.lowercased().hasPrefix("cfstream:") {
        await resolveCloudflareStream(createPlayer: false)
      }
      return
    }

    failed = false
    if let player {
      syncPlayback(player)
      return
    }

    if let prewarmedPlayer = MIRAVideoPrewarmManager.shared.consumePreparedPlayer(for: url) {
      if let info = MIRAVideoPrewarmManager.shared.streamInfo(for: url) {
        thumbnailURL = info.thumbnail
      }
      configurePlayback(for: prewarmedPlayer)
      player = prewarmedPlayer
      isPlayerReady = false
      await startVideoMetric(label: "prewarmed")
      syncPlayback(prewarmedPlayer)
      Task { await markPlayerReady(prewarmedPlayer, expectedURL: url) }
      MIRAPerformanceTimeline.markOnce("time_to_first_video_frame", detail: "prewarmed")
      return
    }

    if let directURL, directURL.isPlayableFileOrRemoteVideo {
      let avPlayer = AVPlayer(url: directURL)
      configurePlayback(for: avPlayer)
      player = avPlayer
      isPlayerReady = false
      await startVideoMetric(label: directURL.host ?? directURL.path)
      syncPlayback(avPlayer)
      Task { await markPlayerReady(avPlayer, expectedURL: url) }
      MIRAPerformanceTimeline.markOnce("time_to_first_video_frame", detail: "direct")
      return
    }

    guard url.lowercased().hasPrefix("cfstream:") else {
      failed = true
      return
    }

    await resolveCloudflareStream(createPlayer: true)
  }

  @MainActor
  private func resolveCloudflareStream(createPlayer: Bool) async {
    if let cachedInfo = MIRAVideoPrewarmManager.shared.streamInfo(for: url) {
      applyStreamPlaybackInfo(cachedInfo, createPlayer: createPlayer)
      return
    }

    let uid = String(url.dropFirst("cfstream:".count))
    let endpoint = MIRAProductionBackend.apiURL("stream/video/\(uid)")

    do {
      let metric = await MIRAPerformanceMetric.begin(category: "network", label: "STREAM \(uid)")
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await MIRAAPIClient.productionSession.data(from: endpoint)
      } catch {
        await metric.finish(status: "error")
        throw error
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      await metric.finish(status: "\(status)", bytes: data.count)
      guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let info = try decoder.decode(MIRAStreamPlaybackInfo.self, from: data)
      applyStreamPlaybackInfo(info, createPlayer: createPlayer)
    } catch {
      failed = createPlayer
      if createPlayer {
        stopVideoMetric(status: "error")
      }
    }
  }

  @MainActor
  private func applyStreamPlaybackInfo(_ info: MIRAStreamPlaybackInfo, createPlayer: Bool) {
    thumbnailURL = info.thumbnail
    if createPlayer, let hls = info.hls, let hlsURL = URL(string: hls), info.ready != false {
      let avPlayer = AVPlayer(url: hlsURL)
      configurePlayback(for: avPlayer)
      player = avPlayer
      isPlayerReady = false
      Task { await startVideoMetric(label: "stream \(info.uid ?? "video")") }
      syncPlayback(avPlayer)
      Task { await markPlayerReady(avPlayer, expectedURL: url) }
      MIRAPerformanceTimeline.markOnce("time_to_first_video_frame", detail: "stream")
    } else if createPlayer {
      failed = true
      stopVideoMetric(status: "not_ready")
    } else {
      failed = false
    }
  }

  @MainActor
  private func loadGeneratedThumbnail(for directURL: URL, expectedURL: String) async {
    guard generatedThumbnail == nil else { return }
    let image = await Self.generateVideoThumbnail(for: directURL)
    guard loadedVideoURL == expectedURL else { return }
    generatedThumbnail = image
    if let image {
      reportRatio(image)
    }
  }

  @MainActor
  private func markPlayerReady(_ expectedPlayer: AVPlayer, expectedURL: String) async {
    for _ in 0..<30 {
      guard loadedVideoURL == expectedURL, player === expectedPlayer else { return }
      if expectedPlayer.currentItem?.status == .readyToPlay {
        withAnimation(.easeOut(duration: 0.18)) {
          isPlayerReady = true
        }
        stopVideoMetric(status: "ready")
        return
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    guard loadedVideoURL == expectedURL, player === expectedPlayer else { return }
    withAnimation(.easeOut(duration: 0.18)) {
      isPlayerReady = true
    }
    stopVideoMetric(status: "ready_timeout")
  }

  private func reportRatio(_ image: UIImage) {
    guard image.size.width > 0, image.size.height > 0 else { return }
    onMeasuredRatio(image.size.height / image.size.width)
  }

  nonisolated private static func generateVideoThumbnail(for url: URL) async -> UIImage? {
    await Task.detached(priority: .utility) {
      let asset = AVURLAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: MIRAMediaSizing.feedTargetWidth, height: MIRAMediaSizing.feedTargetHeight)
      let time = CMTime(seconds: 0.2, preferredTimescale: 600)
      guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
        return nil
      }
      return UIImage(cgImage: cgImage)
    }.value
  }

  @MainActor
  private func startVideoMetric(label: String) async {
    guard videoMetric == nil else { return }
    videoMetric = await MIRAPerformanceMetric.begin(category: "video", label: label)
  }

  @MainActor
  private func stopVideoMetric(status: String) {
    guard let metric = videoMetric else { return }
    videoMetric = nil
    Task { await metric.finish(status: status) }
  }

  @MainActor
  private func syncPlayback(_ player: AVPlayer) {
    if shouldPlay && !globallyPaused {
      configureAudioSession()
      player.isMuted = false
      player.volume = 1
      player.play()
    } else {
      player.pause()
    }
  }

  @MainActor
  private func configurePlayback(for player: AVPlayer) {
    configureAudioSession()
    player.actionAtItemEnd = .none
    player.automaticallyWaitsToMinimizeStalling = true
    player.isMuted = false
    player.volume = 1
    removeLoopObserver()
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { _ in
      player.seek(to: .zero)
      if shouldPlay {
        player.play()
      }
    }
  }

  @MainActor
  private func pauseForGlobalInterruption() {
    globallyPaused = true
    player?.pause()
  }

  @MainActor
  private func resumeAfterGlobalInterruption() {
    globallyPaused = false
    guard let player else { return }
    syncPlayback(player)
  }

  @MainActor
  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      // Keep the video visible even if iOS refuses the audio session.
    }
  }

  @MainActor
  private func removeLoopObserver() {
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }
}

private struct MIRAVideoPlayerView: UIViewRepresentable {
  let player: AVPlayer
  let contentMode: ContentMode

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    view.backgroundColor = .clear
    view.playerLayer.player = player
    view.playerLayer.backgroundColor = UIColor.clear.cgColor
    view.playerLayer.videoGravity = videoGravity
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    uiView.backgroundColor = .clear
    uiView.playerLayer.player = player
    uiView.playerLayer.backgroundColor = UIColor.clear.cgColor
    uiView.playerLayer.videoGravity = videoGravity
  }

  private var videoGravity: AVLayerVideoGravity {
    switch contentMode {
    case .fit:
      return .resizeAspect
    case .fill:
      return .resizeAspectFill
    }
  }

  final class PlayerView: UIView {
    override class var layerClass: AnyClass {
      AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
      layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      backgroundColor = .clear
    }
  }
}

public struct MIRAAdaptiveMediaView: View {
  let urls: [String]
  let cornerRadius: CGFloat
  let maxSingleImageHeight: CGFloat
  let carouselHeight: CGFloat
  let singleImageContentMode: ContentMode
  let shouldPlay: Bool
  let onMediaRatioChange: (String, CGFloat) -> Void
  @State private var selectedIndex = 0

  public init(
    urls: [String],
    cornerRadius: CGFloat = 0,
    maxSingleImageHeight: CGFloat = min(UIScreen.main.bounds.width * 1.18, 560),
    carouselHeight: CGFloat = min(UIScreen.main.bounds.width * 1.08, 520),
    singleImageContentMode: ContentMode = .fill,
    shouldPlay: Bool = true,
    onMediaRatioChange: @escaping (String, CGFloat) -> Void = { _, _ in }
  ) {
    self.urls = urls
    self.cornerRadius = cornerRadius
    self.maxSingleImageHeight = maxSingleImageHeight
    self.carouselHeight = carouselHeight
    self.singleImageContentMode = singleImageContentMode
    self.shouldPlay = shouldPlay
    self.onMediaRatioChange = onMediaRatioChange
  }

  public var body: some View {
    Group {
      if let url = urls.first, urls.count == 1, !url.isVideoURL {
        RemoteMediaView(
          url: url,
          isVideo: false,
          contentMode: singleImageContentMode,
          onMeasuredRatio: { onMediaRatioChange(url, $0) }
        )
          .frame(maxWidth: .infinity)
          .frame(height: maxSingleImageHeight)
          .background(Color.clear)
      } else {
        TabView(selection: $selectedIndex) {
          ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
            RemoteMediaView(
              url: url,
              isVideo: url.isVideoURL,
              shouldPlay: shouldPlay && selectedIndex == index,
              onMeasuredRatio: { onMediaRatioChange(url, $0) }
            )
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
        .frame(maxWidth: .infinity)
        .frame(height: carouselHeight)
        .background(Color.clear)
        .onChange(of: urls) { _, _ in selectedIndex = 0 }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

public enum MIRAMediaSizing {
  public static let feedTargetWidth: CGFloat = 1080
  public static let feedTargetHeight: CGFloat = 1440
  public static let feedPreviewRatio: CGFloat = 4.0 / 3.0
  public static let feedShortPortraitRatio: CGFloat = 5.0 / 4.0
  public static let feedTallRatio: CGFloat = 3.0 / 2.0
  public static let feedImmersiveRatio: CGFloat = 3.0 / 2.0
  public static let profileGridRatio: CGFloat = 5.0 / 4.0
  public static let fullVerticalRatio: CGFloat = 16.0 / 9.0
  public static let maxMainFeedScreenHeightFraction: CGFloat = 0.78

  public static func feedHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width
  ) -> CGFloat {
    if let ratio = aspectRatios.first(where: { $0.isFinite && $0 > 0 }) {
      return boundedHeight(width * supportedFeedHeightToWidthRatio(ratio), width: width)
    }

    let lowercased = urls.map { $0.lowercased() }
    if let ratio = lowercased.compactMap({ flexibleDimensionsRatio(in: $0) ?? aspectRatioHint(in: $0) }).first {
      return boundedHeight(width * supportedFeedHeightToWidthRatio(ratio), width: width)
    }

    return boundedHeight(width * feedPreviewRatio, width: width)
  }

  public static func mainFeedHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width,
    screenHeight: CGFloat = UIScreen.main.bounds.height
  ) -> CGFloat {
    let displayRatio = mainFeedDisplayRatio(for: urls, aspectRatios: aspectRatios)
    let height = width * displayRatio
    guard displayRatio > feedPreviewRatio else { return height }
    return min(height, screenHeight * maxMainFeedScreenHeightFraction)
  }

  public static func mainFeedDisplayRatio(
    for urls: [String],
    aspectRatios: [CGFloat] = []
  ) -> CGFloat {
    if let ratio = aspectRatios.first(where: { $0.isFinite && $0 > 0 }) {
      return supportedFeedHeightToWidthRatio(ratio)
    }
    let lowercased = urls.map { $0.lowercased() }
    if let ratio = lowercased.compactMap({ flexibleDimensionsRatio(in: $0) ?? aspectRatioHint(in: $0) }).first {
      return supportedFeedHeightToWidthRatio(ratio)
    }
    return feedPreviewRatio
  }

  public static func detailHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width
  ) -> CGFloat {
    let ideal = feedHeight(for: urls, aspectRatios: aspectRatios, width: width)
    // Detail pages need room for the title/caption and the fixed action/comment bar.
    // Tall 2:3 media is still displayed large, but it cannot push controls off-screen.
    let readableDetailHeight = UIScreen.main.bounds.height * 0.48
    return min(ideal, readableDetailHeight)
  }

  public static func heightToWidthRatio(forFormat format: String?) -> CGFloat? {
    guard let format else { return nil }
    return aspectRatioHint(in: format.lowercased()).map(supportedFeedHeightToWidthRatio)
  }

  private static func flexibleDimensionsRatio(in value: String) -> CGFloat? {
    let normalized = (value.removingPercentEncoding ?? value)
      .replacingOccurrences(of: "×", with: "x")
      .replacingOccurrences(of: "Ã—", with: "x")
      .replacingOccurrences(of: "%C3%97", with: "x")
      .replacingOccurrences(of: "%c3%97", with: "x")
    let pattern = #"(?<!\d)(\d{3,5})\s*[xX]\s*(\d{3,5})(?!\d)"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return dimensionsRatio(in: value) }
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    guard let match = expression.firstMatch(in: normalized, range: range), match.numberOfRanges == 3,
          let widthRange = Range(match.range(at: 1), in: normalized),
          let heightRange = Range(match.range(at: 2), in: normalized) else {
      return namedDimensionsRatio(in: normalized) ?? dimensionsRatio(in: value)
    }
    let mediaWidth = CGFloat(Double(String(normalized[widthRange])) ?? 0)
    let mediaHeight = CGFloat(Double(String(normalized[heightRange])) ?? 0)
    guard mediaWidth > 0, mediaHeight > 0 else { return namedDimensionsRatio(in: normalized) ?? dimensionsRatio(in: value) }
    return supportedFeedHeightToWidthRatio(mediaHeight / mediaWidth)
  }

  private static func boundedHeight(_ height: CGFloat, width: CGFloat) -> CGFloat {
    let minHeight = width * feedShortPortraitRatio
    let maxHeight = min(width * feedTallRatio, UIScreen.main.bounds.height * maxMainFeedScreenHeightFraction)
    return min(max(height, minHeight), maxHeight)
  }

  private static func supportedFeedHeightToWidthRatio(_ ratio: CGFloat) -> CGFloat {
    guard ratio.isFinite, ratio > 0 else { return feedPreviewRatio }
    let supported = MIRASupportedPostAspectRatio.allCases.map(\.heightToWidthRatio)
    return supported.min { lhs, rhs in
      abs(lhs - ratio) < abs(rhs - ratio)
    } ?? feedPreviewRatio
  }

  private static func dimensionsRatio(in value: String) -> CGFloat? {
    let pattern = #"(?<!\d)(\d{3,5})\s*[xX×]\s*(\d{3,5})(?!\d)"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: value, range: range), match.numberOfRanges == 3 else { return nil }
    guard
      let widthRange = Range(match.range(at: 1), in: value),
      let heightRange = Range(match.range(at: 2), in: value)
    else { return nil }
    let mediaWidth = CGFloat(Double(String(value[widthRange])) ?? 0)
    let mediaHeight = CGFloat(Double(String(value[heightRange])) ?? 0)
    guard mediaWidth > 0, mediaHeight > 0 else { return nil }
    return supportedFeedHeightToWidthRatio(mediaHeight / mediaWidth)
  }

  private static func namedDimensionsRatio(in value: String) -> CGFloat? {
    let width = captureNumber(in: value, pattern: #"(?i)(?:width|w)[=:_-](\d{2,5})"#)
    let height = captureNumber(in: value, pattern: #"(?i)(?:height|h)[=:_-](\d{2,5})"#)
    guard width > 0, height > 0 else { return nil }
    return supportedFeedHeightToWidthRatio(height / width)
  }

  private static func captureNumber(in value: String, pattern: String) -> CGFloat {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: value, range: range),
          match.numberOfRanges > 1,
          let numberRange = Range(match.range(at: 1), in: value) else {
      return 0
    }
    return CGFloat(Double(String(value[numberRange])) ?? 0)
  }

  private static func aspectRatioHint(in value: String) -> CGFloat? {
    let decoded = (value.removingPercentEncoding ?? value)
      .lowercased()
      .replacingOccurrences(of: "×", with: "x")
      .replacingOccurrences(of: "Ã—", with: "x")
    if containsRatio("4", "5", in: decoded) { return 5.0 / 4.0 }
    if containsRatio("3", "4", in: decoded) { return 4.0 / 3.0 }
    if containsRatio("2", "3", in: decoded) { return 3.0 / 2.0 }
    if decoded.contains("portrait") { return feedPreviewRatio }
    return nil
  }

  private static func containsRatio(_ width: String, _ height: String, in value: String) -> Bool {
    let normalized = value
      .replacingOccurrences(of: "×", with: "x")
      .replacingOccurrences(of: "Ã—", with: "x")
    let plainTokens = [
      "\(width):\(height)",
      "\(width)x\(height)",
      "\(width)_\(height)",
      "\(width)-\(height)"
    ]
    if plainTokens.contains(where: { normalized.contains($0) }) {
      return true
    }
    let escapedWidth = NSRegularExpression.escapedPattern(for: width)
    let escapedHeight = NSRegularExpression.escapedPattern(for: height)
    let pattern = #"(?<![\d.])\#(escapedWidth)\s*[:x×]\s*\#(escapedHeight)(?![\d.])"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return false
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.firstMatch(in: value, range: range) != nil
  }
}

public struct MIRAStatButton: View {
  let systemImage: String
  let value: Int
  let action: () -> Void

  public var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
        Text(compact(value))
      }
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
  }

  private func compact(_ value: Int) -> String {
    if value >= 1_000_000 { return "\(value / 1_000_000)M" }
    if value >= 1_000 { return "\(value / 1_000)K" }
    return "\(value)"
  }
}

public struct MIRASaveToCollectionSheet: View {
  private let options: [MIRASaveCollectionOption] = [
    .init(title: "Inspiration", systemImage: "lightbulb"),
    .init(title: "Outfits", systemImage: "tshirt"),
    .init(title: "Places", systemImage: "mappin.and.ellipse"),
    .init(title: "Food", systemImage: "fork.knife"),
    .init(title: "Photos", systemImage: "photo.on.rectangle"),
    .init(title: "Videos", systemImage: "play.rectangle")
  ]

  let isSaved: Bool
  let onSelect: (String) -> Void
  let onRemove: () -> Void
  let onClose: () -> Void

  public init(
    isSaved: Bool,
    onSelect: @escaping (String) -> Void,
    onRemove: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.isSaved = isSaved
    self.onSelect = onSelect
    self.onRemove = onRemove
    self.onClose = onClose
  }

  public var body: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.24))
        .frame(width: 42, height: 5)
        .padding(.top, 10)
        .padding(.bottom, MIRATheme.Space.sm)

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Save to")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text("Choose the collection for this post.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .frame(width: 34, height: 34)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
      }
      .padding(.horizontal, MIRATheme.Space.lg)
      .padding(.bottom, MIRATheme.Space.md)

      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(options) { option in
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(option.title)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: option.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(MIRATheme.Color.surface)
                .clipShape(Circle())
              Text(option.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
              Spacer(minLength: 0)
            }
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MIRATheme.Color.hairline, lineWidth: 1)
            }
          }
          .buttonStyle(.miraPress)
        }
      }
      .padding(.horizontal, MIRATheme.Space.lg)

      if isSaved {
        Button(role: .destructive) {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          onRemove()
        } label: {
          Label("Remove from saved", systemImage: "bookmark.slash")
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.miraPress)
        .padding(.horizontal, MIRATheme.Space.lg)
        .padding(.top, MIRATheme.Space.md)
      }

      Spacer(minLength: 0)
    }
    .background(MIRATheme.Color.surface)
  }
}

private struct MIRASaveCollectionOption: Identifiable {
  let title: String
  let systemImage: String
  var id: String { title }
}

extension String {
  var isVideoURL: Bool {
    let lower = lowercased()
    return lower.contains(".mp4") || lower.contains(".mov") || lower.contains(".m3u8") || lower.contains("stream")
  }
}

private extension URL {
  var isPlayableFileOrRemoteVideo: Bool {
    guard let scheme else { return false }
    return scheme.hasPrefix("http") || scheme == "file"
  }
}
