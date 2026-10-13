import AVFoundation
import Foundation

public enum MIRAPlaybackCoordinator {
  @MainActor private static weak var activeVideoPlayer: AVPlayer?
  @MainActor private static var activeVideoID: String?
  @MainActor public static func activateVideo(_ player: AVPlayer, id: String) {
    if activeVideoPlayer !== player {
      activeVideoPlayer?.pause()
      activeVideoPlayer?.isMuted = true
    }
    activeVideoPlayer = player
    activeVideoID = id
  }
  @MainActor public static func releaseVideo(_ player: AVPlayer) {
    // A stale/offscreen player must stop even after another owner took over.
    player.pause()
    player.isMuted = true
    guard activeVideoPlayer === player else { return }
    activeVideoPlayer = nil
    activeVideoID = nil
  }
  @MainActor static func ownsVideo(_ player: AVPlayer) -> Bool { activeVideoPlayer === player }
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

public enum MIRAStreamPlaybackResolver {
  private static let keychain = MIRAKeychainSessionProvider()

  public static func playbackInfo(for uid: String) async throws -> (info: MIRAStreamPlaybackInfo, status: Int, bytes: Int) {
    let cleanUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
    let endpoint = MIRAProductionBackend.apiURL("stream/video/\(cleanUID)")
    var request = URLRequest(url: endpoint)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(MIRALanguageResolver.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")
    request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
    if let token = await keychain.accessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let info = try decoder.decode(MIRAStreamPlaybackInfo.self, from: data)
    return (info, status, data.count)
  }
}

@MainActor
public final class MIRAVideoPrewarmManager {
  public static let shared = MIRAVideoPrewarmManager()

  private var cachedStreamInfo: [String: MIRAStreamPlaybackInfo] = [:]
  private var preparedPlayers: [String: AVPlayer] = [:]
  private var preparedOrder: [String] = []
  private struct PendingRequest {
    let id: UUID
    let task: Task<Void, Never>
  }
  private var pending: [String: PendingRequest] = [:]
  private var wantedMetadata = Set<String>()
  private var wantedPlayers = Set<String>()
  private var accountGeneration = 0
  private let maxMetadataPreloads = 10
  private let maxPreparedPlayers = 2
  private let resolve: (String) async throws -> MIRAStreamPlaybackInfo
  private var pauseObserver: NSObjectProtocol?
  private let notificationCenter: NotificationCenter

  init(
    notificationCenter: NotificationCenter = .default,
    resolve: @escaping (String) async throws -> MIRAStreamPlaybackInfo = {
      try await MIRAStreamPlaybackResolver.playbackInfo(for: $0).info
    }
  ) {
    self.resolve = resolve
    self.notificationCenter = notificationCenter
    pauseObserver = notificationCenter.addObserver(forName: .miraPlaybackShouldPause, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancelPendingPrewarm() }
    }
  }

  deinit {
    if let pauseObserver { notificationCenter.removeObserver(pauseObserver) }
    for request in pending.values { request.task.cancel() }
  }

  /// Playback/navigation interruption invalidates work, not just the players
  /// already prepared. A cancelled resolver may still return; identity checks
  /// below prevent it from resurrecting a player in the new viewing context.
  public func cancelPendingPrewarm() {
    for request in pending.values { request.task.cancel() }
    pending.removeAll()
    wantedMetadata.removeAll()
    wantedPlayers.removeAll()
    trimPreparedPlayers(keepOnly: [])
  }

  public func resetForAccountChange() {
    accountGeneration += 1
    cancelPendingPrewarm()
    cachedStreamInfo.removeAll()
  }

  public func prewarm(urls: [String], keepOnly: Set<String> = []) {
    let candidates = Array(orderedUnique(urls).filter(\.isVideoURL).prefix(maxMetadataPreloads))
    let playerCandidates = Set(candidates.prefix(maxPreparedPlayers).map { normalized($0) })
    wantedMetadata = Set(candidates.map { normalized($0) })
    wantedPlayers = playerCandidates.union(keepOnly.map { normalized($0) })
    for key in Array(pending.keys) where !wantedMetadata.contains(key) {
      pending.removeValue(forKey: key)?.task.cancel()
    }
    // Bound metadata as well as players; signed playback URLs from distant
    // neighborhoods must not accumulate for the lifetime of the account.
    cachedStreamInfo = cachedStreamInfo.filter { wantedMetadata.contains($0.key) }
    trimPreparedPlayers(keepOnly: wantedPlayers)

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
    guard let info = cachedStreamInfo[normalized(url)] else { return nil }
    let hls = info.hls?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard info.ready != false || !hls.isEmpty else { return nil }
    return info
  }

  private func prewarm(url: String, shouldPreparePlayer: Bool) {
    let key = normalized(url)
    guard !key.isEmpty, pending[key] == nil else {
      if shouldPreparePlayer, let info = cachedStreamInfo[key], let hls = info.hls, let hlsURL = URL(string: hls) {
        preparePlayer(for: key, playbackURL: hlsURL)
      }
      return
    }
    if let info = cachedStreamInfo[key], (info.ready != false || info.hls?.isEmpty == false) {
      if shouldPreparePlayer, let hls = info.hls, let hlsURL = URL(string: hls) {
        preparePlayer(for: key, playbackURL: hlsURL)
      }
      return
    }
    MIRAApplePerformanceLogger.event("video_prewarm_started", detail: key.videoPrewarmLogLabel)

    if preparedPlayers[key] != nil {
      MIRAApplePerformanceLogger.event("video_prewarm_skipped", detail: "prepared")
      return
    }

    if key.lowercased().hasPrefix("cfstream:") {
      let generation = accountGeneration
      let requestID = UUID()
      let task = Task<Void, Never> { [weak self] in
        guard let self else { return }
        await self.resolveCloudflareStream(
          for: key, requestID: requestID, generation: generation
        )
      }
      pending[key] = PendingRequest(id: requestID, task: task)
      return
    }

    guard shouldPreparePlayer else {
      return
    }

    guard let url = URL(string: key), url.isPlayableFileOrRemoteVideo else {
      MIRAApplePerformanceLogger.event("video_prewarm_skipped", detail: key.videoPrewarmLogLabel)
      return
    }

    preparePlayer(for: key, playbackURL: url)
  }

  private func resolveCloudflareStream(
    for key: String, requestID: UUID, generation: Int
  ) async {
    let uid = String(key.dropFirst("cfstream:".count))

    do {
      let info = try await resolve(uid)
      guard !Task.isCancelled, generation == accountGeneration,
            pending[key]?.id == requestID, wantedMetadata.contains(key) else { return }
      pending.removeValue(forKey: key)
      let hls = info.hls?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if info.ready != false || !hls.isEmpty {
        cachedStreamInfo[key] = info
        MIRAApplePerformanceLogger.event("video_ready_to_play", detail: "stream_info")
        if wantedPlayers.contains(key), let hls = info.hls, let hlsURL = URL(string: hls) {
          preparePlayer(for: key, playbackURL: hlsURL)
        }
      } else {
        MIRAApplePerformanceLogger.event("video_prewarm_processing", detail: key.videoPrewarmLogLabel)
      }
    } catch {
      guard generation == accountGeneration, pending[key]?.id == requestID else { return }
      pending.removeValue(forKey: key)
      guard !Task.isCancelled else { return }
      MIRAApplePerformanceLogger.event("video_prewarm_failed", detail: key.videoPrewarmLogLabel)
    }
  }

  private func preparePlayer(for key: String, playbackURL: URL) {
    guard wantedPlayers.contains(key), preparedPlayers[key] == nil else { return }
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
      preparedPlayers[key]?.replaceCurrentItem(with: nil)
      preparedPlayers.removeValue(forKey: key)
    }
    preparedOrder.removeAll { keysToRemove.contains($0) }
  }

  #if DEBUG
  var pendingKeysForTesting: Set<String> { Set(pending.keys) }
  var preparedKeysForTesting: Set<String> { Set(preparedPlayers.keys) }
  var pendingTasksForTesting: [String: Task<Void, Never>] { pending.mapValues(\.task) }
  #endif

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
