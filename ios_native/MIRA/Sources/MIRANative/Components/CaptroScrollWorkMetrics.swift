#if CAPTRO_PERFORMANCE_REVIEW
import Foundation
import SwiftUI
import UIKit
import os.signpost

/// Explicit optimized diagnostic build only. Not included in TestFlight.
/// Fixed-size aggregate data; no post contents, media URLs or credentials.
enum CaptroScrollWorkMetrics {
  private struct Work: Codable {
    var count = 0
    var mainThreadCount = 0
    var totalMs = 0.0
    var maximumMs = 0.0
    var over8Ms = 0
    var over16Ms = 0
    var over50Ms = 0
  }
  private static let lock = NSLock()
  private static var work: [String: Work] = [:]
  private static let log = OSLog(subsystem: "com.captro.app", category: .pointsOfInterest)
  static func begin() -> Double { ProcessInfo.processInfo.systemUptime }
  static func end(_ name: String, start: Double) {
    let duration = (begin() - start) * 1000
    let main = Thread.isMainThread
    lock.withLock {
      var item = work[name] ?? Work()
      item.count += 1
      item.mainThreadCount += main ? 1 : 0
      item.totalMs += duration
      item.maximumMs = max(item.maximumMs, duration)
      if duration > 8 { item.over8Ms += 1 }
      if duration > 16 { item.over16Ms += 1 }
      if duration > 50 { item.over50Ms += 1 }
      work[name] = item
    }
    if duration > 8 {
      os_signpost(.event, log: log, name: "MeasuredWork", "%{public}@ ms=%.3f main=%d", name, duration, main ? 1 : 0)
    }
  }
  static var summary: String {
    lock.withLock {
      guard let data = try? JSONEncoder().encode(work) else { return "{}" }
      return String(data: data, encoding: .utf8) ?? "{}"
    }
  }
}

struct CaptroScrollWorkDiagnostics: UIViewRepresentable {
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "home.work.diagnostics"
    view.accessibilityLabel = "Optimized simulator diagnostic counters, not physical device evidence"
    view.isUserInteractionEnabled = false
  }
  final class Probe: UIView {
    override var accessibilityValue: String? {
      get { CaptroScrollWorkMetrics.summary }
      set { }
    }
  }
}
#endif
