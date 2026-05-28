import CryptoKit
import Darwin
import Foundation
import ImageIO
import UIKit
import os
#if canImport(MetricKit)
import MetricKit
#endif

public enum MIRAApplePerformanceLogger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.captro.ios"
  private static let logger = Logger(subsystem: subsystem, category: "performance")
  private static let signpostLog = OSLog(subsystem: subsystem, category: "performance")

  public static func event(_ name: String, detail: String? = nil) {
    let cleanName = sanitized(name, max: 80)
    let cleanDetail = sanitized(detail ?? "", max: 160)
    if cleanDetail.isEmpty {
      logger.info("\(cleanName, privacy: .public)")
      os_signpost(.event, log: signpostLog, name: "Captro Event", "%{public}@", cleanName as NSString)
    } else {
      logger.info("\(cleanName, privacy: .public) \(cleanDetail, privacy: .public)")
      os_signpost(.event, log: signpostLog, name: "Captro Event", "%{public}@ %{public}@", cleanName as NSString, cleanDetail as NSString)
    }
  }

  public static func beginInterval(_ name: String, detail: String? = nil) -> MIRAApplePerformanceInterval {
    let cleanName = sanitized(name, max: 80)
    let cleanDetail = sanitized(detail ?? "", max: 160)
    let id = OSSignpostID(log: signpostLog)
    os_signpost(.begin, log: signpostLog, name: "Captro Interval", signpostID: id, "%{public}@ %{public}@", cleanName as NSString, cleanDetail as NSString)
    logger.debug("begin \(cleanName, privacy: .public) \(cleanDetail, privacy: .public)")
    return MIRAApplePerformanceInterval(id: id, name: cleanName)
  }

  fileprivate static func endInterval(_ interval: MIRAApplePerformanceInterval, status: String?) {
    let cleanStatus = sanitized(status ?? "", max: 80)
    os_signpost(.end, log: signpostLog, name: "Captro Interval", signpostID: interval.id, "%{public}@ %{public}@", interval.name as NSString, cleanStatus as NSString)
    logger.debug("end \(interval.name, privacy: .public) \(cleanStatus, privacy: .public)")
  }

  private static func sanitized(_ value: String, max: Int) -> String {
    let lowered = value.lowercased()
    guard !lowered.contains("token"),
          !lowered.contains("password"),
          !lowered.contains("secret"),
          !lowered.contains("authorization"),
          !lowered.contains("message"),
          !lowered.contains("caption")
    else { return "redacted" }
    return String(value.replacingOccurrences(of: "\n", with: " ").prefix(max))
  }
}

public struct MIRAApplePerformanceInterval {
  fileprivate let id: OSSignpostID
  fileprivate let name: String

  public func end(status: String? = nil) {
    MIRAApplePerformanceLogger.endInterval(self, status: status)
  }
}

#if canImport(MetricKit)
public final class MIRAMetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
  public static let shared = MIRAMetricKitSubscriber()
  private var isStarted = false

  private override init() {}

  public func start() {
    guard !isStarted else { return }
    isStarted = true
    MXMetricManager.shared.add(self)
    MIRAApplePerformanceLogger.event("metrickit_started")
  }

  public func didReceive(_ payloads: [MXMetricPayload]) {
    MIRAApplePerformanceLogger.event("metrickit_metrics_received", detail: "count=\(payloads.count)")
  }

  public func didReceive(_ payloads: [MXDiagnosticPayload]) {
    MIRAApplePerformanceLogger.event("metrickit_diagnostics_received", detail: "count=\(payloads.count)")
  }
}
#endif

public enum MIRAAppleRuntimeDiagnostics {
  public static func start() {
    MIRAApplePerformanceLogger.event("runtime_diagnostics_start")
    #if canImport(MetricKit)
    MIRAMetricKitSubscriber.shared.start()
    #endif
  }
}

public enum MIRAPerformanceTimeline {
  private final class Storage: @unchecked Sendable {
    let lock = NSLock()
    var emittedOnce = Set<String>()
  }

  private static let start = DispatchTime.now()
  private static let storage = Storage()

  public static func mark(_ name: String, detail: String? = nil) {
    MIRAApplePerformanceLogger.event(name, detail: detail)
    #if DEBUG
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    let detailText = detail.map { " \($0)" } ?? ""
    print("[MIRA perf] mark \(name) \(Int(elapsed))ms\(detailText)")
    #endif
  }

  public static func markOnce(_ name: String, detail: String? = nil) {
    storage.lock.lock()
    let shouldEmit = storage.emittedOnce.insert(name).inserted
    storage.lock.unlock()
    if shouldEmit {
      mark(name, detail: detail)
    }
  }
}

public enum MIRAMemoryMetrics {
  public static func log(_ label: String) {
    #if DEBUG
    guard let value = residentMemoryMB() else { return }
    print("[MIRA perf] memory \(label) \(Int(value))MB")
    #endif
  }

  private static func residentMemoryMB() -> Double? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Double(info.resident_size) / 1_048_576
  }
}

public actor MIRAPerformanceMonitor {
  public static let shared = MIRAPerformanceMonitor()

  private var activeNetworkRequests = 0
  private var activeImageDownloads = 0
  private var activeVideoPlayers = 0

  public func begin(category: String, label: String) -> Int {
    switch category {
    case "network": activeNetworkRequests += 1
    case "image": activeImageDownloads += 1
    case "video": activeVideoPlayers += 1
    default: break
    }
    let count = activeCount(for: category)
    #if DEBUG
    print("[MIRA perf] begin \(category) active=\(count) \(label)")
    #endif
    return count
  }

  public func finish(category: String, label: String, elapsedMilliseconds: Double, status: String?, bytes: Int) {
    switch category {
    case "network": activeNetworkRequests = max(0, activeNetworkRequests - 1)
    case "image": activeImageDownloads = max(0, activeImageDownloads - 1)
    case "video": activeVideoPlayers = max(0, activeVideoPlayers - 1)
    default: break
    }
    #if DEBUG
    let statusText = status.map { " status=\($0)" } ?? ""
    let bytesText = bytes > 0 ? " bytes=\(bytes)" : ""
    print("[MIRA perf] end \(category) active=\(activeCount(for: category)) \(Int(elapsedMilliseconds))ms\(statusText)\(bytesText) \(label)")
    #endif
  }

  private func activeCount(for category: String) -> Int {
    switch category {
    case "network": return activeNetworkRequests
    case "image": return activeImageDownloads
    case "video": return activeVideoPlayers
    default: return 0
    }
  }
}

public struct MIRAPerformanceMetric {
  private let category: String
  private let label: String
  private let start: DispatchTime

  private init(category: String, label: String) {
    self.category = category
    self.label = label
    self.start = .now()
  }

  public static func begin(category: String, label: String) async -> MIRAPerformanceMetric {
    let metric = MIRAPerformanceMetric(category: category, label: label)
    _ = await MIRAPerformanceMonitor.shared.begin(category: category, label: label)
    return metric
  }

  public func finish(status: String? = nil, bytes: Int = 0) async {
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    await MIRAPerformanceMonitor.shared.finish(
      category: category,
      label: label,
      elapsedMilliseconds: elapsed,
      status: status,
      bytes: bytes
    )
    MIRAApplePerformanceLogger.event("\(category)_complete", detail: "status=\(status ?? "unknown") bytes=\(bytes)")
  }
}

public final class MIRAMainThreadStallMonitor {
  public static let shared = MIRAMainThreadStallMonitor()

  private var isRunning = false
  private let interval: TimeInterval = 0.35

  private init() {}

  public func start() {
    #if DEBUG
    guard !isRunning else { return }
    isRunning = true
    scheduleTick(expected: Date().addingTimeInterval(interval))
    #endif
  }

  private func scheduleTick(expected: Date) {
    #if DEBUG
    DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
      guard let self, self.isRunning else { return }
      let drift = Date().timeIntervalSince(expected)
      if drift > 0.10 {
        print("[MIRA perf] main-thread stall \(Int(drift * 1000))ms")
      }
      self.scheduleTick(expected: Date().addingTimeInterval(self.interval))
    }
    #endif
  }
}

public enum MIRALocalJSONCache {
  public static func load<T: Decodable>(_ type: T.Type, key: String, maxAge: TimeInterval = 60 * 60 * 24) async -> T? {
    await Task.detached(priority: .utility) {
      guard let fileURL = cacheFileURL(for: key) else { return nil }
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let modified = attributes[.modificationDate] as? Date
      else { return nil }
      guard Date().timeIntervalSince(modified) <= maxAge else { return nil }
      guard let data = try? Data(contentsOf: fileURL) else { return nil }
      return try? JSONDecoder().decode(T.self, from: data)
    }.value
  }

  public static func save<T: Encodable>(_ value: T, key: String) async {
    await Task.detached(priority: .utility) {
      guard let fileURL = cacheFileURL(for: key) else { return }
      guard let data = try? JSONEncoder().encode(value) else { return }
      try? data.write(to: fileURL, options: [.atomic])
    }.value
  }

  public static func remove(key: String) async {
    await Task.detached(priority: .utility) {
      guard let fileURL = cacheFileURL(for: key) else { return }
      try? FileManager.default.removeItem(at: fileURL)
    }.value
  }

  public static func trim(maxAge: TimeInterval = 60 * 60 * 24 * 7) async {
    await Task.detached(priority: .utility) {
      guard let directory = cacheDirectory(),
            let files = try? FileManager.default.contentsOfDirectory(
              at: directory,
              includingPropertiesForKeys: [.contentModificationDateKey],
              options: [.skipsHiddenFiles]
            )
      else { return }
      let cutoff = Date().addingTimeInterval(-maxAge)
      for file in files {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if modified < cutoff {
          try? FileManager.default.removeItem(at: file)
        }
      }
    }.value
  }

  private static func cacheFileURL(for key: String) -> URL? {
    guard let directory = cacheDirectory() else { return nil }
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent("\(digest).json")
  }

  private static func cacheDirectory() -> URL? {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let directory = caches.appendingPathComponent("MIRAJSONCache", isDirectory: true)
    if !FileManager.default.fileExists(atPath: directory.path) {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }
}

public enum MIRAImageDiskCache {
  public static func image(for url: URL, maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight) async -> UIImage? {
    await Task.detached(priority: .utility) {
      guard let fileURL = cacheFileURL(for: url.absoluteString),
            let data = try? Data(contentsOf: fileURL)
      else { return nil }
      return decodedImage(from: data, maxPixelSize: maxPixelSize)
    }.value
  }

  public static func store(data: Data, for url: URL) async {
    await Task.detached(priority: .utility) {
      guard let fileURL = cacheFileURL(for: url.absoluteString) else { return }
      try? data.write(to: fileURL, options: [.atomic])
    }.value
  }

  public static func trim(maxAge: TimeInterval = 60 * 60 * 24 * 14, maxBytes: Int = 700 * 1024 * 1024) async {
    await Task.detached(priority: .utility) {
      guard let directory = cacheDirectory(),
            let files = try? FileManager.default.contentsOfDirectory(
              at: directory,
              includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
              options: [.skipsHiddenFiles]
            )
      else { return }
      let cutoff = Date().addingTimeInterval(-maxAge)
      var totalBytes = 0
      let entries = files.map { file -> (url: URL, modified: Date, size: Int) in
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (file, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
      }.sorted { $0.modified < $1.modified }

      for entry in entries {
        totalBytes += entry.size
        if entry.modified < cutoff {
          try? FileManager.default.removeItem(at: entry.url)
        }
      }

      if totalBytes > maxBytes {
        var bytesToRemove = totalBytes - maxBytes
        for entry in entries where bytesToRemove > 0 {
          try? FileManager.default.removeItem(at: entry.url)
          bytesToRemove -= entry.size
        }
      }
    }.value
  }

  public static func decode(_ data: Data, maxPixelSize: CGFloat = MIRAMediaSizing.feedTargetHeight) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
      decodedImage(from: data, maxPixelSize: maxPixelSize)
    }.value
  }

  private static func decodedImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let options = [
      kCGImageSourceShouldCache: false
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
      return UIImage(data: data)
    }
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return UIImage(data: data)
    }
    return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
  }

  private static func cacheFileURL(for key: String) -> URL? {
    guard let directory = cacheDirectory() else { return nil }
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent("\(digest).img")
  }

  private static func cacheDirectory() -> URL? {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let directory = caches.appendingPathComponent("MIRAImageCache", isDirectory: true)
    if !FileManager.default.fileExists(atPath: directory.path) {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }
}
