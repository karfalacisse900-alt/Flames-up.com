import Foundation

/// A bounded presentation cache on the existing API client, never an authority
/// for access, payment, capacity or price. No private snapshots persist to disk.
@MainActor
final class CaptroTeaDetailStore {
  struct Snapshot {
    let detail: CaptroTeaDetails
    let receivedAt: Date
    var invalidated = false
  }
  private struct Flight {
    let id: UUID
    let task: Task<CaptroTeaDetails, Error>
  }
  private let scope: () -> String
  private let fetch: (String) async throws -> CaptroTeaDetails
  private let now: () -> Date
  private var activeScope: String?
  private var snapshots: [String: Snapshot] = [:]
  private var flights: [String: Flight] = [:]
  private var latest: [String: UUID] = [:]
  private let freshness: TimeInterval = 60
  private let retention: TimeInterval = 600

  init(scope: @escaping () -> String, now: @escaping () -> Date = Date.init,
       fetch: @escaping (String) async throws -> CaptroTeaDetails) {
    self.scope = scope; self.now = now; self.fetch = fetch
  }

  func snapshot(for entry: CaptroTeaEntry) -> CaptroTeaDetails? {
    synchronizeScope()
    guard let key = entry.destination.detailPath, let value = snapshots[key],
          now().timeIntervalSince(value.receivedAt) < retention else { return nil }
    return value.detail
  }

  func load(_ entry: CaptroTeaEntry, force: Bool = false) async throws -> CaptroTeaDetails {
    synchronizeScope()
    guard let key = entry.destination.detailPath else { throw MIRAAPIError.badStatus(404) }
    if !force, let value = snapshots[key], !value.invalidated,
       now().timeIntervalSince(value.receivedAt) < freshness { return value.detail }
    let owner = activeScope
    let flight: Flight
    if let existing = flights[key] { flight = existing }
    else {
      let task = Task { try await fetch(key) }
      flight = Flight(id: UUID(), task: task)
      flights[key] = flight
      latest[key] = flight.id
    }
    do {
      let detail = try await flight.task.value
      guard scope() == owner, latest[key] == flight.id else { throw CancellationError() }
      guard detail.item.destination == entry.destination,
            detail.business != nil || (detail.post != nil && detail.commerce != nil) else {
        snapshots[key] = nil
        throw MIRAAPIError.decodingFailed
      }
      snapshots[key] = Snapshot(detail: detail, receivedAt: now())
      // Completion remains available to all subscribers until their resumes finish.
      // A new request uses the fresh snapshot; subsequent force reads get new work.
      flights[key] = nil
      if snapshots.count > 24, let oldest = snapshots.min(by: { $0.value.receivedAt < $1.value.receivedAt })?.key {
        snapshots[oldest] = nil
        latest[oldest] = nil
      }
      return detail
    } catch {
      if scope() == owner, latest[key] == flight.id {
        let status: Int?
        switch error {
        case MIRAAPIError.server(let code, _, _): status = code
        case MIRAAPIError.badStatus(let code): status = code
        default: status = nil
        }
        if let status, [401, 403, 404, 410].contains(status) { snapshots[key] = nil }
        if flights[key]?.id == flight.id { flights[key] = nil }
      }
      throw error
    }
  }

  /// Any attempted mutation can have committed despite a lost response.
  /// Keep display data, but require a fresh read on the next visit.
  func invalidate(discard: Bool = false) {
    synchronizeScope()
    if discard { snapshots.removeAll() }
    for key in snapshots.keys { snapshots[key]?.invalidated = true }
    for value in flights.values { value.task.cancel() }
    flights.removeAll()
    latest.removeAll()
  }

  private func synchronizeScope() {
    let current = scope()
    guard current != activeScope else { return }
    for value in flights.values { value.task.cancel() }
    flights.removeAll(); latest.removeAll(); snapshots.removeAll(); activeScope = current
  }
}
