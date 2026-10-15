import Foundation

/// One admission budget for all image consumers, not one budget per carousel.
/// A permit covers disk lookup, download, decode and cache write. Cancellation
/// cannot release an active permit until that work really finishes.
final class MIRAImageLoadAdmission: @unchecked Sendable {
  enum Priority: Equatable, Sendable { case visible, prefetch }
  struct Snapshot: Equatable, Sendable {
    let active: Int
    let activePrefetch: Int
    let waiting: Int
    let peakActive: Int
    let peakPrefetch: Int
    let admitted: Int
    let cancelledWaiting: Int
  }
  private struct Entry {
    var priority: Priority
    var continuation: CheckedContinuation<Bool, Never>?
    var active = false
  }
  private typealias Resume = (CheckedContinuation<Bool, Never>, Bool)
  private let lock = NSLock()
  private var maximumActive: Int
  private var maximumPrefetch: Int
  private var entries: [UUID: Entry] = [:]
  private var order: [UUID] = []
  private var peakActive = 0
  private var peakPrefetch = 0
  private var admitted = 0
  private var cancelledWaiting = 0

  init(maximumActive: Int = 6, maximumPrefetch: Int = 2) {
    precondition(maximumActive > 0 && maximumPrefetch >= 0 && maximumPrefetch <= maximumActive)
    self.maximumActive = maximumActive
    self.maximumPrefetch = maximumPrefetch
  }

  func updateBudget(maximumActive: Int, maximumPrefetch: Int) {
    precondition(maximumActive > 0 && maximumPrefetch >= 0 && maximumPrefetch <= maximumActive)
    let resumptions: [Resume] = lock.withLock {
      self.maximumActive = maximumActive
      self.maximumPrefetch = maximumPrefetch
      var result: [Resume] = []
      if maximumPrefetch == 0 {
        let cancelled = order.filter { entries[$0]?.active == false && entries[$0]?.priority == .prefetch }
        for id in cancelled {
          if let continuation = entries.removeValue(forKey: id)?.continuation { result.append((continuation, false)) }
          cancelledWaiting += 1
        }
        let removed = Set(cancelled)
        order.removeAll { removed.contains($0) }
      }
      // Already-running work retains its permit until completion; lowering a
      // budget cannot cancel a shared download needed by a visible reader.
      result += drainLocked()
      return result
    }
    resume(resumptions)
  }

  /// Register before starting the detached load so a visible reader can promote
  /// an existing speculative request even before it starts awaiting its permit.
  func register(_ id: UUID, priority: Priority) {
    lock.withLock {
      precondition(entries[id] == nil)
      entries[id] = Entry(priority: priority)
      order.append(id)
    }
  }

  func waitForSlot(_ id: UUID) async -> Bool {
    await withTaskCancellationHandler {
      if Task.isCancelled { cancelWaiting(id); return false }
      return await withCheckedContinuation { continuation in
        let resumptions: [Resume] = lock.withLock {
          guard var entry = entries[id] else { return [(continuation, false)] }
          entry.continuation = continuation
          entries[id] = entry
          return drainLocked()
        }
        resume(resumptions)
      }
    } onCancel: {
      self.cancelWaiting(id)
    }
  }

  func promote(_ id: UUID) {
    let resumptions: [Resume] = lock.withLock {
      guard var entry = entries[id], entry.priority == .prefetch else { return [] }
      entry.priority = .visible
      entries[id] = entry
      return drainLocked()
    }
    resume(resumptions)
  }

  func cancelWaiting(_ id: UUID) {
    let resumptions: [Resume] = lock.withLock {
      // A cancelled decode can still be unwinding. Do not admit replacement
      // work on top of it; its owner releases the slot in defer.
      guard let entry = entries[id], !entry.active else { return [] }
      entries[id] = nil
      order.removeAll { $0 == id }
      cancelledWaiting += 1
      var result: [Resume] = entry.continuation.map { [($0, false)] } ?? []
      result += drainLocked()
      return result
    }
    resume(resumptions)
  }

  func release(_ id: UUID) {
    let resumptions: [Resume] = lock.withLock {
      guard let entry = entries.removeValue(forKey: id) else { return [] }
      order.removeAll { $0 == id }
      var result: [Resume] = entry.continuation.map { [($0, false)] } ?? []
      result += drainLocked()
      return result
    }
    resume(resumptions)
  }

  var snapshot: Snapshot {
    lock.withLock {
      Snapshot(active: entries.values.filter(\.active).count,
        activePrefetch: entries.values.filter { $0.active && $0.priority == .prefetch }.count,
        waiting: entries.values.filter { !$0.active }.count,
        peakActive: peakActive, peakPrefetch: peakPrefetch, admitted: admitted,
        cancelledWaiting: cancelledWaiting)
    }
  }

  private func drainLocked() -> [Resume] {
    var result: [Resume] = []
    var active = entries.values.filter(\.active).count
    var prefetch = entries.values.filter { $0.active && $0.priority == .prefetch }.count
    while active < maximumActive {
      let visible = order.first { id in
        guard let entry = entries[id] else { return false }
        return !entry.active && entry.continuation != nil && entry.priority == .visible
      }
      let speculative = prefetch < maximumPrefetch ? order.first { id in
        guard let entry = entries[id] else { return false }
        return !entry.active && entry.continuation != nil && entry.priority == .prefetch
      } : nil
      guard let id = visible ?? speculative, var entry = entries[id],
            let continuation = entry.continuation else { break }
      entry.active = true
      entry.continuation = nil
      entries[id] = entry
      active += 1
      if entry.priority == .prefetch { prefetch += 1 }
      admitted += 1
      peakActive = max(peakActive, active)
      peakPrefetch = max(peakPrefetch, prefetch)
      result.append((continuation, true))
    }
    return result
  }

  private func resume(_ values: [Resume]) {
    // Never run a resumed task while holding the admission lock.
    for (continuation, granted) in values { continuation.resume(returning: granted) }
  }
}
