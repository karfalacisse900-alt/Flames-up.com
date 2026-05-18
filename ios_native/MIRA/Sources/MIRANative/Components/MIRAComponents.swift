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
  let content: (Image) -> Content
  let placeholder: () -> Placeholder
  @State private var uiImage: UIImage?
  @State private var loadedURL: URL?

  public init(
    url: String?,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
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

  @MainActor
  private func loadImage() async {
    guard let url, let remoteURL = URL(string: url) else {
      uiImage = nil
      loadedURL = nil
      return
    }

    if loadedURL == remoteURL, uiImage != nil { return }

    if let cached = MIRAImageMemoryCache.shared.image(for: remoteURL) {
      uiImage = cached
      loadedURL = remoteURL
      return
    }

    if loadedURL != remoteURL {
      uiImage = nil
    }

    do {
      var request = URLRequest(url: remoteURL)
      request.cachePolicy = .returnCacheDataElseLoad
      request.timeoutInterval = 20
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      guard (200..<300).contains(status) else { return }
      let decoded = UIImage(data: data)
      guard !Task.isCancelled, let decoded else { return }
      MIRAImageMemoryCache.shared.store(decoded, for: remoteURL, cost: data.count)
      uiImage = decoded
      loadedURL = remoteURL
    } catch {
      if loadedURL != remoteURL {
        uiImage = nil
      }
    }
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

  public init(url: String, isVideo: Bool, contentMode: ContentMode = .fill, shouldPlay: Bool = false) {
    self.url = url
    self.isVideo = isVideo
    self.contentMode = contentMode
    self.shouldPlay = shouldPlay
  }

  public var body: some View {
    Group {
      if isVideo {
        MIRAResolvedVideoPlayer(url: url, shouldPlay: shouldPlay)
      } else {
        MIRACachedImage(url: url) { image in
          image.resizable().aspectRatio(contentMode: contentMode)
        } placeholder: {
          placeholder.redacted(reason: .placeholder)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .transaction { transaction in
      transaction.animation = .easeInOut(duration: 0.18)
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
}

private struct MIRAResolvedVideoPlayer: View {
  let url: String
  let shouldPlay: Bool
  @State private var player: AVPlayer?
  @State private var thumbnailURL: String?
  @State private var failed = false
  @State private var endObserver: NSObjectProtocol?

  var body: some View {
    ZStack {
      if let player {
        MIRAFillVideoPlayer(player: player)
          .onAppear { syncPlayback(player) }
          .onDisappear {
            player.pause()
            removeLoopObserver()
          }
      } else if let thumbnailURL {
        MIRACachedImage(url: thumbnailURL) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          placeholder
        }
      } else {
        placeholder
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
    .task(id: url) { await configurePlayer() }
    .onChange(of: shouldPlay) { _, _ in
      guard let player else { return }
      syncPlayback(player)
    }
  }

  private var placeholder: some View {
    ZStack {
      MIRATheme.Color.surfaceSoft
      ProgressView().tint(MIRATheme.Color.textMuted)
    }
  }

  @MainActor
  private func configurePlayer() async {
    failed = false
    thumbnailURL = nil
    player = nil

    if let directURL = URL(string: url), let scheme = directURL.scheme, scheme.hasPrefix("http") || scheme == "file" {
      let avPlayer = AVPlayer(url: directURL)
      configurePlayback(for: avPlayer)
      player = avPlayer
      syncPlayback(avPlayer)
      return
    }

    guard url.lowercased().hasPrefix("cfstream:") else {
      failed = true
      return
    }

    let uid = String(url.dropFirst("cfstream:".count))
    let endpoint = MIRAProductionBackend.apiURL("stream/video/\(uid)")

    do {
      let (data, response) = try await URLSession.shared.data(from: endpoint)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let info = try decoder.decode(MIRAStreamPlaybackInfo.self, from: data)
      thumbnailURL = info.thumbnail
      if let hls = info.hls, let hlsURL = URL(string: hls), info.ready != false {
        let avPlayer = AVPlayer(url: hlsURL)
        configurePlayback(for: avPlayer)
        player = avPlayer
        syncPlayback(avPlayer)
      } else {
        failed = true
      }
    } catch {
      failed = true
    }
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
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    uiView.playerLayer.player = player
    uiView.playerLayer.videoGravity = .resizeAspectFill
  }

  final class PlayerView: UIView {
    override class var layerClass: AnyClass {
      AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
      layer as! AVPlayerLayer
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
  @State private var selectedIndex = 0

  public init(
    urls: [String],
    cornerRadius: CGFloat = 0,
    maxSingleImageHeight: CGFloat = min(UIScreen.main.bounds.width * 1.18, 560),
    carouselHeight: CGFloat = min(UIScreen.main.bounds.width * 1.08, 520),
    singleImageContentMode: ContentMode = .fill,
    shouldPlay: Bool = true
  ) {
    self.urls = urls
    self.cornerRadius = cornerRadius
    self.maxSingleImageHeight = maxSingleImageHeight
    self.carouselHeight = carouselHeight
    self.singleImageContentMode = singleImageContentMode
    self.shouldPlay = shouldPlay
  }

  public var body: some View {
    Group {
      if let url = urls.first, urls.count == 1, !url.isVideoURL {
        RemoteMediaView(url: url, isVideo: false, contentMode: singleImageContentMode)
          .frame(maxWidth: .infinity)
          .frame(height: maxSingleImageHeight)
          .background(MIRATheme.Color.surfaceSoft)
      } else {
        TabView(selection: $selectedIndex) {
          ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
            RemoteMediaView(url: url, isVideo: url.isVideoURL, shouldPlay: shouldPlay && selectedIndex == index)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
        .frame(maxWidth: .infinity)
        .frame(height: carouselHeight)
        .background(MIRATheme.Color.surfaceSoft)
        .onChange(of: urls) { _, _ in selectedIndex = 0 }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

public enum MIRAMediaSizing {
  public static func feedHeight(for urls: [String], width: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
    let lowercased = urls.map { $0.lowercased() }
    if let ratio = lowercased.compactMap({ dimensionsRatio(in: $0) }).first {
      return min(width * ratio, UIScreen.main.bounds.height * 0.74)
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
    return min(height, UIScreen.main.bounds.height * 0.74)
  }

  public static func mainFeedHeight(for urls: [String], width: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
    let ideal = feedHeight(for: urls, width: width)
    let visibleActionSafeHeight = UIScreen.main.bounds.height * 0.64
    return min(ideal, visibleActionSafeHeight)
  }

  private static func dimensionsRatio(in value: String) -> CGFloat? {
    let pattern = #"(?<!\d)(\d{3,5})[xX](\d{3,5})(?!\d)"#
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
    return min(max(mediaHeight / mediaWidth, 1.0), 16.0 / 9.0)
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
