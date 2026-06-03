import AVFoundation
import Foundation

public enum MIRAPlaybackCoordinator {
  public static func pauseAll(reason: String) {
    NotificationCenter.default.post(name: .miraPlaybackShouldPause, object: reason)
  }

  public static func resumeVisible(reason: String) {
    NotificationCenter.default.post(name: .miraPlaybackMayResume, object: reason)
  }
}

public extension Notification.Name {
  static let miraPlaybackShouldPause = Notification.Name("mira.playback.pauseAll")
  static let miraPlaybackMayResume = Notification.Name("mira.playback.resumeVisible")
}

@MainActor
public final class MIRAVideoPrewarmManager {
  public static let shared = MIRAVideoPrewarmManager()

  private var cachedStreamInfo: [String: MIRAStreamPlaybackInfo] = [:]
  private var preparedPlayers: [String: AVPlayer] = [:]
  private var preparedOrder: [String] = []
  private var inFlight = Set<String>()
  private let maxMetadataPreloads = 8
  private let maxPreparedPlayers = 5

  private init() {}

  public func prewarm(urls: [String], keepOnly: Set<String> = []) {
    let candidates = Array(orderedUnique(urls).filter(\.isVideoURL).prefix(maxMetadataPreloads))
    guard !candidates.isEmpty else { return }
    let playerCandidates = Set(candidates.prefix(maxPreparedPlayers).map { normalized($0) })

    trimPreparedPlayers(keepOnly: playerCandidates.union(keepOnly.map { normalized($0) }))

    for url in candidates {
      prewarm(url: url, shouldPreparePlayer: playerCandidates.contains(normalized(url)))
    }
  }

  public func consumePreparedPlayer(for url: String) -> AVPlayer? {
    let key = normalized(url)
    guard let player = preparedPlayers.removeValue(forKey: key) else { return nil }
    preparedOrder.removeAll { $0 == key }
    MIRAApplePerformanceLogger.event("video_prewarm_consumed", detail: key.videoPrewarmLogLabel)
    return player
  }

  public func streamInfo(for url: String) -> MIRAStreamPlaybackInfo? {
    cachedStreamInfo[normalized(url)]
  }

  private func prewarm(url: String, shouldPreparePlayer: Bool) {
    let key = normalized(url)
    guard !key.isEmpty, !inFlight.contains(key) else {
      if shouldPreparePlayer, let info = cachedStreamInfo[key], info.ready != false, let hls = info.hls, let hlsURL = URL(string: hls) {
        preparePlayer(for: key, playbackURL: hlsURL)
      }
      return
    }
    if cachedStreamInfo[key] != nil {
      if shouldPreparePlayer, let info = cachedStreamInfo[key], info.ready != false, let hls = info.hls, let hlsURL = URL(string: hls) {
        preparePlayer(for: key, playbackURL: hlsURL)
      }
      return
    }
    inFlight.insert(key)
    MIRAApplePerformanceLogger.event("video_prewarm_started", detail: key.videoPrewarmLogLabel)

    if preparedPlayers[key] != nil {
      inFlight.remove(key)
      MIRAApplePerformanceLogger.event("video_prewarm_skipped", detail: "prepared")
      return
    }

    if key.lowercased().hasPrefix("cfstream:") {
      Task { [weak self] in
        await self?.resolveCloudflareStream(for: key, shouldPreparePlayer: shouldPreparePlayer)
      }
      return
    }

    guard shouldPreparePlayer else {
      inFlight.remove(key)
      return
    }

    guard let url = URL(string: key), url.isPlayableFileOrRemoteVideo else {
      inFlight.remove(key)
      MIRAApplePerformanceLogger.event("video_prewarm_skipped", detail: key.videoPrewarmLogLabel)
      return
    }

    preparePlayer(for: key, playbackURL: url)
    inFlight.remove(key)
  }

  private func resolveCloudflareStream(for key: String, shouldPreparePlayer: Bool) async {
    let uid = String(key.dropFirst("cfstream:".count))
    let endpoint = MIRAProductionBackend.apiURL("stream/video/\(uid)")

    do {
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await MIRAAPIClient.productionSession.data(from: endpoint)
      } catch {
        throw error
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }

      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let info = try decoder.decode(MIRAStreamPlaybackInfo.self, from: data)
      cachedStreamInfo[key] = info
      inFlight.remove(key)
      if info.ready != false {
        MIRAApplePerformanceLogger.event("video_ready_to_play", detail: "stream_info")
        if shouldPreparePlayer, let hls = info.hls, let hlsURL = URL(string: hls) {
          preparePlayer(for: key, playbackURL: hlsURL)
        }
      }
    } catch {
      inFlight.remove(key)
      MIRAApplePerformanceLogger.event("video_prewarm_failed", detail: key.videoPrewarmLogLabel)
    }
  }

  private func preparePlayer(for key: String, playbackURL: URL) {
    guard preparedPlayers[key] == nil else { return }
    let item = AVPlayerItem(url: playbackURL)
    item.preferredForwardBufferDuration = 0.85
    item.preferredPeakBitRate = 0
    item.preferredMaximumResolution = CGSize(width: 1080, height: 1920)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    player.volume = 0
    player.automaticallyWaitsToMinimizeStalling = false
    player.pause()
    preparedPlayers[key] = player
    preparedOrder.removeAll { $0 == key }
    preparedOrder.append(key)
    trimPreparedPlayers(keepOnly: Set(preparedOrder.suffix(maxPreparedPlayers)))
    MIRAApplePerformanceLogger.event("video_prewarm_ready", detail: key.videoPrewarmLogLabel)
  }

  private func trimPreparedPlayers(keepOnly: Set<String>) {
    let normalizedKeepOnly = Set(keepOnly.map { normalized($0) })
    let overflow = max(0, preparedOrder.count - maxPreparedPlayers)
    let overflowKeys = Set(preparedOrder.prefix(overflow))
    let keysToRemove = Set(preparedPlayers.keys).filter { key in
      !normalizedKeepOnly.contains(key) || overflowKeys.contains(key)
    }
    guard !keysToRemove.isEmpty else { return }
    for key in keysToRemove {
      preparedPlayers[key]?.pause()
      preparedPlayers.removeValue(forKey: key)
    }
    preparedOrder.removeAll { keysToRemove.contains($0) }
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let trimmed = normalized(value)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }
}

private extension URL {
  var isPlayableFileOrRemoteVideo: Bool {
    guard let scheme else { return false }
    return scheme.hasPrefix("http") || scheme == "file"
  }
}

private extension String {
  var videoPrewarmLogLabel: String {
    if lowercased().hasPrefix("cfstream:") { return "cfstream" }
    guard let url = URL(string: self) else { return "video" }
    return url.host ?? "video"
  }
}
