import Foundation

/// Counts only transport/capture progress; never stores audio, text or levels.
/// Audio callbacks use this lock instead of scheduling a MainActor task per tap.
final class CaptroVoicePipelineHealth: @unchecked Sendable {
  enum Stall: String { case capture, conversion, transport }
  private let lock = NSLock()
  private var captureAt: TimeInterval
  private var convertedAt: TimeInterval
  private var sentAt: TimeInterval
  init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    captureAt = now; convertedAt = now; sentAt = now
  }
  func captured(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    lock.lock(); captureAt = now; lock.unlock()
  }
  func converted(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    lock.lock(); convertedAt = now; lock.unlock()
  }
  func sent(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    lock.lock(); sentAt = now; lock.unlock()
  }
  func stall(now: TimeInterval = ProcessInfo.processInfo.systemUptime, limit: TimeInterval = 5) -> Stall? {
    lock.lock(); defer { lock.unlock() }
    if now - captureAt > limit { return .capture }
    if now - convertedAt > limit { return .conversion }
    if now - sentAt > limit { return .transport }
    return nil
  }
}
