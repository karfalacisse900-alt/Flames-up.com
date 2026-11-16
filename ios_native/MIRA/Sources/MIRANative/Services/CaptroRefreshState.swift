import Foundation

enum CaptroRefreshFailure {
  static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
  }
  static func isOffline(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet,
      NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed].contains(error.code)
  }
  static func message(_ error: Error, content: String, cached: Bool) -> String {
    if isOffline(error) { return cached ? "Offline. Showing saved \(content)." : "You’re offline. Connect to load \(content)." }
    return cached ? "Couldn’t refresh \(content). Showing the last loaded version." : "Couldn’t load \(content). Try again."
  }
}

/// Transport cancellation is lifecycle, not a connection outage. Persistent
/// sync trouble is distinct from individual send failures and socket state.
struct CaptroChatSyncState {
  private(set) var failures = 0
  private var firstFailureAt: Date?
  private var offline = false
  mutating func failed(_ error: Error, now: Date = Date()) {
    guard !CaptroRefreshFailure.isCancellation(error) else { return }
    failures = min(4, failures + 1)
    firstFailureAt = firstFailureAt ?? now
    offline = CaptroRefreshFailure.isOffline(error)
  }
  mutating func succeeded() { self = Self() }
  func notice(now: Date = Date()) -> String? {
    guard failures >= 2, let firstFailureAt, now.timeIntervalSince(firstFailureAt) >= 8 else { return nil }
    return offline ? "Offline · showing saved messages" : "Updates delayed · reconnecting"
  }
  func pollDelay(socketConnected: Bool) -> Int {
    failures == 0 && socketConnected ? 45 : min(60, 5 * (1 << failures))
  }
}
