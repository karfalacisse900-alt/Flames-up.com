import AVFoundation
import Foundation
import Network
import UIKit

/// A device/network preference, not account data. No feed-observed publication:
/// a path change must not reconstruct rows or reset a carousel's selection.
final class MIRAMediaNetworkPolicy: @unchecked Sendable {
  static let shared = MIRAMediaNetworkPolicy()
  static let dataSaverKey = "captro.media.dataSaver"
  static let didChange = Notification.Name("captro.media.networkPolicyChanged")

  struct Budget: Equatable, Sendable {
    var dataSaver = false
    var constrained = false
    var connected = true
    var memoryPressure = false
    var reducesData: Bool { dataSaver || constrained }
    var permitsPrefetch: Bool { connected && !reducesData && !memoryPressure }
    var maximumImageLoads: Int { reducesData || memoryPressure ? 3 : 6 }
    var maximumImagePrefetches: Int { permitsPrefetch ? 2 : 0 }
    var maximumPreparedPlayers: Int { permitsPrefetch ? 2 : 0 }
    var imagePixelLimit: CGFloat { reducesData ? 720 : MIRAMediaSizing.feedTargetHeight }
    // An upper preference for adaptive HLS, not a promise for progressive MP4.
    var preferredVideoBitRate: Double { reducesData ? 700_000 : 0 }
    var preferredVideoResolution: CGSize {
      reducesData ? CGSize(width: 854, height: 854) : CGSize(width: 1920, height: 1920)
    }
  }

  private let lock = NSLock()
  private var budget: Budget
  private let monitor = NWPathMonitor()
  private var observers: [NSObjectProtocol] = []

  private init() {
    budget = Budget(dataSaver: UserDefaults.standard.bool(forKey: Self.dataSaverKey))
    monitor.pathUpdateHandler = { [weak self] path in
      self?.update { $0.constrained = path.isConstrained; $0.connected = path.status == .satisfied }
    }
    monitor.start(queue: DispatchQueue(label: "captro.media.network", qos: .utility))
    observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
      object: nil, queue: nil) { [weak self] _ in
      self?.update { $0.dataSaver = UserDefaults.standard.bool(forKey: Self.dataSaverKey) }
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil, queue: nil) { [weak self] _ in self?.update { $0.memoryPressure = true } })
    // Resume speculation next foreground session, not repeatedly during a
    // memory-pressure burst. Visible requests always retain admission slots.
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
      object: nil, queue: nil) { [weak self] _ in self?.update { $0.memoryPressure = false } })
  }

  var current: Budget { lock.withLock { budget } }
  private func update(_ change: (inout Budget) -> Void) {
    let changed = lock.withLock {
      let previous = budget
      change(&budget)
      return budget != previous
    }
    guard changed else { return }
    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
  }
}

enum MIRAVideoBufferingPolicy {
  static func apply(to item: AVPlayerItem, budget: MIRAMediaNetworkPolicy.Budget) {
    // Let AVFoundation estimate sustainable buffering. A forced sub-second
    // buffer + playImmediately defeats its native stall-avoidance behavior.
    item.preferredForwardBufferDuration = 0
    item.preferredPeakBitRate = budget.preferredVideoBitRate
    item.preferredMaximumResolution = budget.preferredVideoResolution
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
  }
}

struct CaptroImageDelivery: Equatable {
  let source: String
  let display: String
  let preview: String?

  /// Only accept server-supplied, uncropped derivatives for this exact source.
  /// Never manufacture variants, remove signatures or proxy private originals.
  static func uncropped(_ candidate: String?, of source: String) -> String? {
    guard let candidate, !candidate.isEmpty else { return nil }
    if candidate == source { return source }
    guard let outer = URLComponents(string: candidate), outer.scheme == "https",
          ["api.flames-up.com", "api.captro.app"].contains(outer.host?.lowercased() ?? ""),
          let prefix = candidate.range(of: "/cdn-cgi/image/"),
          let separator = candidate.range(of: "/https://", range: prefix.upperBound..<candidate.endIndex)
    else { return nil }
    let options = candidate[prefix.upperBound..<separator.lowerBound].split(separator: ",")
    guard options.contains("fit=scale-down"),
          !options.contains(where: { $0.hasPrefix("crop=") || $0.hasPrefix("trim=") || $0.hasPrefix("rotate=") })
    else { return nil }
    let embedded = String(candidate[separator.lowerBound...].dropFirst())
    guard embedded == source else { return nil }
    return candidate
  }
}

extension MIRAPost {
  func imageDelivery(at index: Int, dataSaver: Bool) -> CaptroImageDelivery? {
    let originals = mediaURLs.isEmpty ? feedMediaURLs : mediaURLs
    guard originals.indices.contains(index), !originals[index].isVideoURL else { return nil }
    let source = originals[index]
    // A partial list may be compressed by an old API. Never associate by index
    // unless the complete list has exactly one entry per original.
    let feeds = feedMediaUrls?.values ?? []
    let thumbnails = thumbnailUrls?.values ?? []
    let feed = CaptroImageDelivery.uncropped(feeds.count == originals.count ? feeds[index] : nil, of: source)
    let preview = CaptroImageDelivery.uncropped(thumbnails.count == originals.count ? thumbnails[index] : nil, of: source)
    let small = preview != source ? preview : nil
    let display = dataSaver ? (small ?? feed ?? source) : (feed ?? source)
    return CaptroImageDelivery(source: source, display: display, preview: small == display ? nil : small)
  }
}
