import SwiftUI
import UIKit

/// Read-only visibility observation, with one-shot restoration only on a feed
/// switch, recreated scroll view, or required removal. Never seeks for playback.
@MainActor
final class CaptroFeedViewport: NSObject, ObservableObject {
  struct Anchor { var id: String; var y: CGFloat; var offset: CGFloat }
  private final class WeakView { weak var value: UIView?; init(_ value: UIView) { self.value = value } }
  private var cells: [String: WeakView] = [:]
  private weak var scroll: UIScrollView?
  private var observation: NSKeyValueObservation?
  private var sizeObservation: NSKeyValueObservation?
  private var snapshots: [String: Anchor] = [:]
  private var pending: Anchor?
  private var scheduled = false
  private var order: [String] = []
  private var scope = "forYou"
  private var activeID: String?
  private var isActive = true
  var onVisible: ((String?) -> Void)?
#if DEBUG
  struct ScrollCommand {
    let before: CGFloat
    let after: CGFloat
    let targetMounted: Bool
    let reason: String
  }
  private(set) var debugCommands: [ScrollCommand] = []
  private(set) var debugSampleCount = 0
  private(set) var debugMaxSampleMilliseconds: Double = 0
  var debugSummary: String {
    "commands=\(debugCommands.count);samples=\(debugSampleCount);maxSampleMs=\(debugMaxSampleMilliseconds);offset=\(scroll?.contentOffset.y ?? 0);mounted=\(cells.count)"
  }
  private func traceCommand(from: CGFloat, to: CGFloat, mounted: Bool, reason: String) {
    debugCommands.append(ScrollCommand(before: from, after: to, targetMounted: mounted, reason: reason))
    if debugCommands.count > 128 { debugCommands.removeFirst() }
    CaptroFeedDiagnostics.event("offset_write", feed: scope,
      reason: "\(reason),from=\(from),to=\(to),mounted=\(mounted)", post: pending?.id)
  }
#endif

  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    if !active {
      sample() // Capture before navigation/tab-bar layout starts changing.
      isActive = false
    } else {
      isActive = true
      if pending == nil { pending = snapshots[scope] }
      schedule()
    }
  }

  func cancelRestorationForUserInteraction() { pending = nil }

  func select(_ scope: String) {
    guard self.scope != scope else { return }
    self.scope = scope
    pending = snapshots[scope] ?? Anchor(id: "", y: 0, offset: 0)
    activeID = nil
    schedule()
  }

  func updateOrder(_ ids: [String]) {
    let validIDs = Set(ids)
    assert(validIDs.count == ids.count, "Duplicate Home post identity")
    if let anchor = snapshots[scope], !order.isEmpty, pending == nil,
       order.contains(where: { !validIDs.contains($0) }) {
      if validIDs.contains(anchor.id) { pending = anchor }
      else if !ids.isEmpty {
        let oldIndex = order.firstIndex(of: anchor.id) ?? 0
        pending = Anchor(id: ids[min(oldIndex, ids.count - 1)], y: anchor.y, offset: anchor.offset)
      }
    }
    order = ids
    schedule()
  }

  func register(_ view: UIView, id: String) {
    cells[id] = WeakView(view)
    attach(from: view)
    schedule()
  }

  private func attach(from view: UIView) {
    var ancestor = view.superview
    while let candidate = ancestor {
      if let target = candidate as? UIScrollView, !target.isPagingEnabled {
        guard scroll !== target else { return }
        scroll?.panGestureRecognizer.removeTarget(self, action: #selector(dragChanged))
        let recreating = scroll != nil || snapshots[scope] != nil
        scroll = target
        if recreating { pending = snapshots[scope] }
        target.panGestureRecognizer.addTarget(self, action: #selector(dragChanged))
        observation = target.observe(\.contentOffset, options: []) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.schedule() }
        }
        sizeObservation = target.observe(\.contentSize, options: []) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.schedule() }
        }
        return
      }
      ancestor = candidate.superview
    }
  }

  @objc private func dragChanged() {
    if scroll?.panGestureRecognizer.state == .began { cancelRestorationForUserInteraction() }
  }

  func schedule() {
    guard !scheduled else { return }
    scheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.scheduled = false
      self.sample()
    }
  }

  func sample() {
    guard isActive, let scroll, scroll.window != nil, scroll.bounds.height > 0 else { return }
#if DEBUG
    let sampleStart = ProcessInfo.processInfo.systemUptime
    defer {
      debugSampleCount += 1
      debugMaxSampleMilliseconds = max(debugMaxSampleMilliseconds, (ProcessInfo.processInfo.systemUptime - sampleStart) * 1000)
    }
#endif
    cells = cells.filter { $0.value.value?.window != nil }
    let frames = order.compactMap { id -> (String, CGRect)? in
      guard let view = cells[id]?.value else { return nil }
      return (id, view.convert(view.bounds, to: scroll))
    }
    // Do not clamp a saved offset against the previous feed's layout while
    // SwiftUI is still replacing its lazy targets.
    guard !frames.isEmpty else { return }
    if let pending, !scroll.isDragging, !scroll.isDecelerating {
      // If a lazy target isn't mounted, the saved offset first materializes it.
      // Complete once; don't retry/correct against subsequent user gestures.
      let y = frames.first(where: { $0.0 == pending.id }).map { $0.1.minY - pending.y } ?? pending.offset
      self.pending = nil
      let minimum = -scroll.adjustedContentInset.top
      let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
#if DEBUG
      traceCommand(from: scroll.contentOffset.y, to: min(maximum, max(minimum, y)),
        mounted: frames.contains { $0.0 == pending.id }, reason: "legacy_restore")
#endif
      scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(maximum, max(minimum, y))), animated: false)
      CaptroFeedDiagnostics.event("restore", feed: scope, reason: "feed_switch_or_removal", post: pending.id)
    }
    let viewport = scroll.bounds.inset(by: UIEdgeInsets(top: scroll.adjustedContentInset.top, left: 0,
      bottom: scroll.adjustedContentInset.bottom, right: 0))
    let visible = frames.filter { $0.1.intersects(viewport) && $0.1.height > 0 }
    if let first = visible.first {
      snapshots[scope] = Anchor(id: first.0, y: first.1.minY - scroll.contentOffset.y, offset: scroll.contentOffset.y)
    }
    func fraction(_ frame: CGRect) -> CGFloat {
      max(0, frame.intersection(viewport).height) / max(1, min(frame.height, viewport.height))
    }
    let best = visible.max { fraction($0.1) < fraction($1.1) }
    var next = best.flatMap { fraction($0.1) >= 0.50 ? $0.0 : nil }
    if let current = visible.first(where: { $0.0 == activeID }), fraction(current.1) >= 0.40,
       best.map({ fraction($0.1) < fraction(current.1) + 0.15 }) ?? true {
      next = activeID
    }
    if next != activeID {
      activeID = next
      onVisible?(next)
    }
  }
}

#if DEBUG
/// Read-only test instrumentation. No SwiftUI state publications per scroll tick.
struct CaptroFeedViewportDiagnostics: UIViewRepresentable {
  let owner: CaptroFeedViewport
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.owner = owner
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "home.viewport.diagnostics"
    view.accessibilityLabel = "Viewport diagnostics"
    view.isUserInteractionEnabled = false
  }
  final class Probe: UIView {
    weak var owner: CaptroFeedViewport?
    override var accessibilityValue: String? {
      get { owner?.debugSummary }
      set { }
    }
  }
}
#endif

struct CaptroFeedViewportMarker: UIViewRepresentable {
  let owner: CaptroFeedViewport
  let postID: String
  func makeUIView(context: Context) -> Marker { Marker() }
  func updateUIView(_ view: Marker, context: Context) {
    view.owner = owner; view.postID = postID
    owner.register(view, id: postID)
  }
  final class Marker: UIView {
    weak var owner: CaptroFeedViewport?
    var postID = ""
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { owner?.register(self, id: postID) } }
    override func layoutSubviews() { super.layoutSubviews(); owner?.register(self, id: postID) }
  }
}
