import Foundation

@main struct RefreshPolicyChecks {
  static func main() {
    let start = Date(timeIntervalSince1970: 100)
    var checks = 0
    func check(_ name: String, _ condition: Bool) {
      guard condition else { print("FAIL: \(name)"); exit(1) }
      checks += 1; print("PASS: \(name)")
    }
    var sync = CaptroChatSyncState()
    sync.failed(CancellationError(), now: start)
    sync.failed(URLError(.cancelled), now: start)
    check("Navigation cancellation is not a reconnect failure", sync.failures == 0 && sync.notice(now: start.addingTimeInterval(60)) == nil)
    sync.failed(URLError(.networkConnectionLost), now: start)
    check("One brief disconnect stays quiet", sync.notice(now: start.addingTimeInterval(30)) == nil)
    sync.failed(URLError(.notConnectedToInternet), now: start.addingTimeInterval(2))
    check("Repeated errors do not flash a banner immediately", sync.notice(now: start.addingTimeInterval(3)) == nil)
    check("Persistent offline state is visible", sync.notice(now: start.addingTimeInterval(9)) == "Offline · showing saved messages")
    check("API failures back off even with a healthy socket", sync.pollDelay(socketConnected: true) == 20)
    for n in 0..<20 { sync.failed(URLError(.timedOut), now: start.addingTimeInterval(Double(n + 10))) }
    check("Retry delay is capped", sync.pollDelay(socketConnected: false) == 60 && sync.failures == 4)
    check("Online service trouble differs from offline", sync.notice(now: start.addingTimeInterval(90)) == "Updates delayed · reconnecting")
    sync.succeeded()
    check("Recovery clears notice and restores reconciliation cadence", sync.notice() == nil && sync.failures == 0 && sync.pollDelay(socketConnected: true) == 45)
    check("Cached offline copy differs from first load", CaptroRefreshFailure.message(URLError(.notConnectedToInternet), content: "messages", cached: true) == "Offline. Showing saved messages." && CaptroRefreshFailure.message(URLError(.notConnectedToInternet), content: "messages", cached: false).contains("Connect to load"))
    check("Service failure does not claim an empty successful result", CaptroRefreshFailure.message(URLError(.badServerResponse), content: "messages", cached: false) == "Couldn’t load messages. Try again.")
    print("\(checks) host Swift policy checks passed; no app/device UI executed.")
  }
}
