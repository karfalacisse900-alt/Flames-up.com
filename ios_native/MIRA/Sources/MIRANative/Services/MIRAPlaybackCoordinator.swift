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
  private var inFlight = Set<String>()
  private let maxMetadataPreloads = 3

  private init() {}

  public func prewarm(urls: [String], keepOnly _: Set<String> = []) {
    let candidates = Array(orderedUnique(urls).filter(\.isVideoURL).prefix(maxMetadataPreloads))
    guard !candidates.isEmpty else { return }

    for url in candidates {
      prewarm(url: url)
    }
  }

  public func consumePreparedPlayer(for _: String) -> AVPlayer? {
    return nil
  }

  public func streamInfo(for url: String) -> MIRAStreamPlaybackInfo? {
    cachedStreamInfo[normalized(url)]
  }

  private func prewarm(url: String) {
    let key = normalized(url)
    guard !key.isEmpty, cachedStreamInfo[key] == nil, !inFlight.contains(key) else { return }
    inFlight.insert(key)
    MIRAApplePerformanceLogger.event("video_prewarm_started", detail: key.videoPrewarmLogLabel)

    if key.lowercased().hasPrefix("cfstream:") {
      Task { [weak self] in
        await self?.resolveCloudflareStream(for: key)
      }
      return
    }

    // Avoid creating offscreen AVPlayer instances from the feed preloader. The visible
    // media view owns playback; preloading stays limited to posters and Stream metadata.
    inFlight.remove(key)
    MIRAApplePerformanceLogger.event("video_prewarm_skipped", detail: key.videoPrewarmLogLabel)
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
      inFlight.remove(key)
      if info.ready != false {
        MIRAApplePerformanceLogger.event("video_ready_to_play", detail: "stream_info")
      }
    } catch {
      inFlight.remove(key)
      MIRAApplePerformanceLogger.event("video_prewarm_failed", detail: key.videoPrewarmLogLabel)
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

private extension String {
  var videoPrewarmLogLabel: String {
    if lowercased().hasPrefix("cfstream:") { return "cfstream" }
    guard let url = URL(string: self) else { return "video" }
    return url.host ?? "video"
  }
}
