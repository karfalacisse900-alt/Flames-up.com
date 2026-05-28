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

  private var preparedPlayers: [String: AVPlayer] = [:]
  private var cachedStreamInfo: [String: MIRAStreamPlaybackInfo] = [:]
  private var inFlight = Set<String>()
  private var retainOrder: [String] = []
  private let maxPreparedPlayers = 3

  private init() {}

  public func prewarm(urls: [String], keepOnly: Set<String> = []) {
    let candidates = Array(orderedUnique(urls).filter(\.isVideoURL).prefix(maxPreparedPlayers))
    guard !candidates.isEmpty || !keepOnly.isEmpty else { return }

    trimPreparedPlayers(keeping: Set(candidates).union(keepOnly))

    for url in candidates {
      prewarm(url: url)
    }
  }

  public func consumePreparedPlayer(for url: String) -> AVPlayer? {
    let key = normalized(url)
    guard let player = preparedPlayers.removeValue(forKey: key) else { return nil }
    retainOrder.removeAll { $0 == key }
    MIRAApplePerformanceLogger.event("video_prewarm_consumed", detail: key.videoPrewarmLogLabel)
    return player
  }

  public func streamInfo(for url: String) -> MIRAStreamPlaybackInfo? {
    cachedStreamInfo[normalized(url)]
  }

  private func prewarm(url: String) {
    let key = normalized(url)
    guard !key.isEmpty, preparedPlayers[key] == nil, !inFlight.contains(key) else { return }
    inFlight.insert(key)
    MIRAApplePerformanceLogger.event("video_prewarm_started", detail: key.videoPrewarmLogLabel)

    if key.lowercased().hasPrefix("cfstream:") {
      Task { [weak self] in
        await self?.resolveCloudflareStream(for: key)
      }
      return
    }

    guard let directURL = URL(string: key), directURL.isPrewarmPlayableVideoURL else {
      inFlight.remove(key)
      return
    }

    let asset = AVURLAsset(url: directURL)
    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 2.5
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    player.isMuted = true
    player.volume = 0
    cachePreparedPlayer(player, for: key)
    player.preroll(atRate: 0) { _ in
      MIRAApplePerformanceLogger.event("video_ready_to_play", detail: key.videoPrewarmLogLabel)
    }
  }

  private func resolveCloudflareStream(for key: String) async {
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

      if let hls = info.hls, let hlsURL = URL(string: hls), info.ready != false {
        let item = AVPlayerItem(url: hlsURL)
        item.preferredForwardBufferDuration = 2.5
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = true
        player.volume = 0
        cachePreparedPlayer(player, for: key)
        player.preroll(atRate: 0) { _ in
          MIRAApplePerformanceLogger.event("video_ready_to_play", detail: key.videoPrewarmLogLabel)
        }
      } else {
        inFlight.remove(key)
      }
    } catch {
      inFlight.remove(key)
      MIRAApplePerformanceLogger.event("video_prewarm_failed", detail: key.videoPrewarmLogLabel)
    }
  }

  private func cachePreparedPlayer(_ player: AVPlayer, for key: String) {
    preparedPlayers[key] = player
    inFlight.remove(key)
    retainOrder.removeAll { $0 == key }
    retainOrder.append(key)
    trimPreparedPlayers(keeping: Set(retainOrder.suffix(maxPreparedPlayers)))
  }

  private func trimPreparedPlayers(keeping keep: Set<String>) {
    for key in retainOrder where !keep.contains(key) {
      preparedPlayers[key]?.pause()
      preparedPlayers[key] = nil
    }
    retainOrder.removeAll { !keep.contains($0) }

    while retainOrder.count > maxPreparedPlayers, let key = retainOrder.first {
      preparedPlayers[key]?.pause()
      preparedPlayers[key] = nil
      retainOrder.removeFirst()
    }
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
  var isPrewarmPlayableVideoURL: Bool {
    guard let scheme = scheme?.lowercased() else { return false }
    return scheme == "https" || scheme == "file"
  }
}

private extension String {
  var videoPrewarmLogLabel: String {
    if lowercased().hasPrefix("cfstream:") { return "cfstream" }
    guard let url = URL(string: self) else { return "video" }
    return url.host ?? "video"
  }
}
