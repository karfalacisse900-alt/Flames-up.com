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
    .buttonStyle(.plain)
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
    .buttonStyle(.plain)
  }
}

public struct MIRAHeaderCircleButton: View {
  let systemImage: String

  public init(systemImage: String) {
    self.systemImage = systemImage
  }

  public var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(width: 38, height: 38)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Circle())
  }
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
  private let cache = NSCache<NSURL, UIImage>()

  private init() {
    cache.countLimit = 420
    cache.totalCostLimit = 160 * 1024 * 1024
  }

  func image(for url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  func store(_ image: UIImage, for url: URL, cost: Int) {
    cache.setObject(image, forKey: url as NSURL, cost: cost)
  }
}

public struct MIRACachedImage<Content: View, Placeholder: View>: View {
  let url: String?
  let onImageLoaded: (UIImage) -> Void
  let content: (Image) -> Content
  let placeholder: () -> Placeholder
  @State private var uiImage: UIImage?
  @State private var loadedURL: URL?

  public init(
    url: String?,
    onImageLoaded: @escaping (UIImage) -> Void = { _ in },
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.onImageLoaded = onImageLoaded
    self.content = content
    self.placeholder = placeholder
  }

  public var body: some View {
    Group {
      if let uiImage {
        content(Image(uiImage: uiImage))
      } else {
        placeholder()
      }
    }
    .task(id: url) { await loadImage() }
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

    if let cached = MIRAImageMemoryCache.shared.image(for: remoteURL) {
      await MainActor.run {
        uiImage = cached
        loadedURL = remoteURL
        onImageLoaded(cached)
      }
      MIRAPerformanceTimeline.markOnce("time_to_first_thumbnail", detail: "memory")
      return
    }

    if let diskCached = await MIRAImageDiskCache.image(for: remoteURL) {
      MIRAImageMemoryCache.shared.store(diskCached, for: remoteURL, cost: diskCached.miraCacheCost)
      await MainActor.run {
        uiImage = diskCached
        loadedURL = remoteURL
        onImageLoaded(diskCached)
      }
      MIRAPerformanceTimeline.markOnce("time_to_first_thumbnail", detail: "disk")
      return
    }

    let shouldClear = await MainActor.run {
      loadedURL != remoteURL
    }
    if shouldClear {
      await MainActor.run { uiImage = nil }
    }

    do {
      var request = URLRequest(url: remoteURL)
      request.cachePolicy = .returnCacheDataElseLoad
      request.timeoutInterval = 20
      let metric = await MIRAPerformanceMetric.begin(category: "image", label: remoteURL.host ?? remoteURL.path)
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
      } catch {
        await metric.finish(status: "error")
        throw error
      }
      await metric.finish(status: String((response as? HTTPURLResponse)?.statusCode ?? 200), bytes: data.count)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      guard (200..<300).contains(status) else { return }
      let decoded = await MIRAImageDiskCache.decode(data)
      guard !Task.isCancelled, let decoded else { return }
      MIRAImageMemoryCache.shared.store(decoded, for: remoteURL, cost: decoded.miraCacheCost)
      await MIRAImageDiskCache.store(data: data, for: remoteURL)
      await MainActor.run {
        uiImage = decoded
        loadedURL = remoteURL
        onImageLoaded(decoded)
      }
      MIRAPerformanceTimeline.markOnce("time_to_first_thumbnail", detail: "network")
    } catch {
      let shouldClear = await MainActor.run {
        loadedURL != remoteURL
      }
      if shouldClear {
        await MainActor.run { uiImage = nil }
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

public struct RemoteAvatar: View {
  let url: String?
  let size: CGFloat

  public var body: some View {
    MIRACachedImage(url: url) { image in
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
  let contentMode: ContentMode
  let shouldPlay: Bool
  let onMeasuredRatio: (CGFloat) -> Void

  public init(
    url: String,
    isVideo: Bool,
    contentMode: ContentMode = .fill,
    shouldPlay: Bool = false,
    onMeasuredRatio: @escaping (CGFloat) -> Void = { _ in }
  ) {
    self.url = url
    self.isVideo = isVideo
    self.contentMode = contentMode
    self.shouldPlay = shouldPlay
    self.onMeasuredRatio = onMeasuredRatio
  }

  public var body: some View {
    Group {
      if isVideo {
        MIRAResolvedVideoPlayer(url: url, shouldPlay: shouldPlay, onMeasuredRatio: onMeasuredRatio)
          .background(Color.clear)
      } else {
        MIRACachedImage(url: url, onImageLoaded: reportRatio) { image in
          image.resizable().aspectRatio(contentMode: contentMode)
        } placeholder: {
          placeholder.redacted(reason: .placeholder)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  private var placeholder: some View {
    ZStack {
      MIRATheme.Color.surfaceSoft
      Image(systemName: "photo")
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
  }

  private func reportRatio(_ image: UIImage) {
    guard image.size.width > 0, image.size.height > 0 else { return }
    onMeasuredRatio(image.size.height / image.size.width)
  }
}

private struct MIRAResolvedVideoPlayer: View {
  let url: String
  let shouldPlay: Bool
  let onMeasuredRatio: (CGFloat) -> Void
  @State private var player: AVPlayer?
  @State private var thumbnailURL: String?
  @State private var failed = false
  @State private var endObserver: NSObjectProtocol?
  @State private var loadedVideoURL: String?
  @State private var videoMetric: MIRAPerformanceMetric?
  @State private var generatedThumbnail: UIImage?

  var body: some View {
    ZStack {
      if let thumbnailURL {
        MIRACachedImage(url: thumbnailURL, onImageLoaded: reportRatio) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          placeholder
        }
      } else if let generatedThumbnail {
        Image(uiImage: generatedThumbnail)
          .resizable()
          .scaledToFill()
      } else if player == nil {
        placeholder
      }

      if let player {
        MIRAFillVideoPlayer(player: player)
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
  }

  private var playbackTaskID: String {
    "\(url)|\(shouldPlay)"
  }

  private var placeholder: some View {
    ZStack {
      MIRATheme.Color.surfaceSoft
      Image(systemName: "play.fill")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.38))
    }
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

    if let directURL, directURL.isPlayableFileOrRemoteVideo {
      let avPlayer = AVPlayer(url: directURL)
      configurePlayback(for: avPlayer)
      player = avPlayer
      await startVideoMetric(label: directURL.host ?? directURL.path)
      syncPlayback(avPlayer)
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
      thumbnailURL = info.thumbnail
      if createPlayer, let hls = info.hls, let hlsURL = URL(string: hls), info.ready != false {
        let avPlayer = AVPlayer(url: hlsURL)
        configurePlayback(for: avPlayer)
        player = avPlayer
        await startVideoMetric(label: "stream \(uid)")
        syncPlayback(avPlayer)
        MIRAPerformanceTimeline.markOnce("time_to_first_video_frame", detail: "stream")
      } else if createPlayer {
        failed = true
        stopVideoMetric(status: "not_ready")
      } else {
        failed = false
      }
    } catch {
      failed = createPlayer
      if createPlayer {
        stopVideoMetric(status: "error")
      }
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

  private func reportRatio(_ image: UIImage) {
    guard image.size.width > 0, image.size.height > 0 else { return }
    onMeasuredRatio(image.size.height / image.size.width)
  }

  nonisolated private static func generateVideoThumbnail(for url: URL) async -> UIImage? {
    await Task.detached(priority: .utility) {
      let asset = AVURLAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 900, height: 900)
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
    if shouldPlay {
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

private struct MIRAFillVideoPlayer: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    view.backgroundColor = .clear
    view.playerLayer.player = player
    view.playerLayer.backgroundColor = UIColor.clear.cgColor
    view.playerLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    uiView.backgroundColor = .clear
    uiView.playerLayer.player = player
    uiView.playerLayer.backgroundColor = UIColor.clear.cgColor
    uiView.playerLayer.videoGravity = .resizeAspectFill
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
  public static func feedHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width
  ) -> CGFloat {
    if let ratio = aspectRatios.first(where: { $0.isFinite && $0 > 0 }) {
      return boundedHeight(width * ratio, width: width)
    }

    let lowercased = urls.map { $0.lowercased() }
    if let ratio = lowercased.compactMap({ flexibleDimensionsRatio(in: $0) ?? aspectRatioHint(in: $0) }).first {
      return boundedHeight(width * ratio, width: width)
    }

    let prefersSquare = lowercased.contains { value in
      value.contains("1x1") || value.contains("1:1") || value.contains("square")
    }
    let prefersLongVertical = lowercased.contains { value in
      value.contains("9x16") || value.contains("9:16") || value.contains("story") || value.contains("vertical")
    }
    let height: CGFloat
    if prefersSquare {
      height = width
    } else if prefersLongVertical {
      height = width * (16.0 / 9.0)
    } else {
      height = width * 1.25
    }
    return boundedHeight(height, width: width)
  }

  public static func mainFeedHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width
  ) -> CGFloat {
    let ideal = feedHeight(for: urls, aspectRatios: aspectRatios, width: width)
    // Keep the feed action row visible for tall 9:16 posts instead of letting media
    // consume the whole viewport.
    let visibleActionSafeHeight = max(width * 1.25, UIScreen.main.bounds.height * 0.56)
    return min(ideal, visibleActionSafeHeight)
  }

  public static func detailHeight(
    for urls: [String],
    aspectRatios: [CGFloat] = [],
    width: CGFloat = UIScreen.main.bounds.width
  ) -> CGFloat {
    let ideal = feedHeight(for: urls, aspectRatios: aspectRatios, width: width)
    // Detail pages need room for the title/caption and the fixed action/comment bar.
    // Tall 9:16 media is still displayed large, but it cannot push controls off-screen.
    let readableDetailHeight = UIScreen.main.bounds.height * 0.48
    return min(ideal, readableDetailHeight)
  }

  public static func heightToWidthRatio(forFormat format: String?) -> CGFloat? {
    guard let format else { return nil }
    return aspectRatioHint(in: format.lowercased())
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
    return min(max(mediaHeight / mediaWidth, 1.0 / 1.91), 16.0 / 9.0)
  }

  private static func boundedHeight(_ height: CGFloat, width: CGFloat) -> CGFloat {
    let minHeight = width / 1.91
    let maxHeight = UIScreen.main.bounds.height * 0.74
    return min(max(height, minHeight), maxHeight)
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
    return min(max(mediaHeight / mediaWidth, 1.0 / 1.91), 16.0 / 9.0)
  }

  private static func namedDimensionsRatio(in value: String) -> CGFloat? {
    let width = captureNumber(in: value, pattern: #"(?i)(?:width|w)[=:_-](\d{2,5})"#)
    let height = captureNumber(in: value, pattern: #"(?i)(?:height|h)[=:_-](\d{2,5})"#)
    guard width > 0, height > 0 else { return nil }
    return min(max(height / width, 1.0 / 1.91), 16.0 / 9.0)
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
    if decoded.contains("1.91:1")
      || decoded.contains("1_91_1")
      || decoded.contains("1-91-1")
      || decoded.contains("191:100")
      || decoded.contains("191x100") {
      return 1.0 / 1.91
    }
    if containsRatio("16", "9", in: decoded) { return 9.0 / 16.0 }
    if containsRatio("4", "5", in: decoded) { return 5.0 / 4.0 }
    if containsRatio("1", "1", in: decoded) { return 1.0 }
    if containsRatio("9", "16", in: decoded) { return 16.0 / 9.0 }
    if decoded.contains("square") { return 1.0 }
    if decoded.contains("portrait") { return 5.0 / 4.0 }
    if decoded.contains("landscape") { return 9.0 / 16.0 }
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
