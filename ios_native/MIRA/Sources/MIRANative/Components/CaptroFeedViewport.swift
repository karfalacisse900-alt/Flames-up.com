import SwiftUI
import UIKit

/// Read-only visibility observation, with one-shot restoration only on a feed
/// switch, recreated scroll view, or required removal. Never seeks for playback.
@MainActor
final class CaptroFeedViewport: NSObject, ObservableObject {
  struct Anchor { var id: String; var y: CGFloat; var offset: CGFloat; var contentHeight: CGFloat = 0 }
  private struct Restoration { let anchor: Anchor; let scope: String; let reason: String }
  private final class WeakView { weak var value: UIView?; init(_ value: UIView) { self.value = value } }
  private var cells: [String: WeakView] = [:]
  private weak var scroll: UIScrollView?
  private var observation: NSKeyValueObservation?
  private var sizeObservation: NSKeyValueObservation?
  private var snapshots: [String: Anchor] = [:]
  private var pending: Restoration?
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
      reason: "\(reason),from=\(from),to=\(to),mounted=\(mounted)", post: pending?.anchor.id)
  }
#endif

  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    if !active {
      sample() // Capture before navigation/tab-bar layout starts changing.
      isActive = false
    } else {
      isActive = true
      // A surviving UIScrollView owns its native offset, including deceleration.
      // Resuming observation/playback is not a navigation intent.
      schedule()
    }
  }

  func cancelRestorationForUserInteraction() {
    if pending != nil { CaptroFeedDiagnostics.event("restore_cancel", feed: scope, reason: "user_interaction") }
    pending = nil
  }

  private func requestRestoration(_ anchor: Anchor, reason: String) {
    // Never defer a correction until after an in-flight user gesture ends.
    guard scroll.map({ !$0.isTracking && !$0.isDragging && !$0.isDecelerating }) ?? true else { return }
    pending = Restoration(anchor: anchor, scope: scope, reason: reason)
    CaptroFeedDiagnostics.event("restore_request", feed: scope, reason: reason, post: anchor.id)
  }

  func select(_ scope: String) {
    guard self.scope != scope else { return }
    self.scope = scope
    pending = nil
    cells.removeAll()
    order = [] // Old feed markers cannot satisfy the new feed's restoration.
    requestRestoration(snapshots[scope] ?? Anchor(id: "", y: 0, offset: 0), reason: "feed_selection")
    activeID = nil
    schedule()
  }

  func updateOrder(_ ids: [String]) {
    let validIDs = Set(ids)
    assert(validIDs.count == ids.count, "Duplicate Home post identity")
    if let anchor = snapshots[scope], !order.isEmpty, pending == nil,
       order.contains(where: { !validIDs.contains($0) }) {
      if validIDs.contains(anchor.id) { requestRestoration(anchor, reason: "required_removal") }
      else if !ids.isEmpty {
        let oldIndex = order.firstIndex(of: anchor.id) ?? 0
        requestRestoration(Anchor(id: ids[min(oldIndex, ids.count - 1)], y: anchor.y, offset: anchor.offset), reason: "required_removal")
      }
    }
    order = ids
    schedule()
  }

  func register(_ view: UIView, id: String, feed: String? = nil) {
    guard feed == nil || feed == scope else { return }
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
        if recreating, pending == nil, let anchor = snapshots[scope] {
          requestRestoration(anchor, reason: "scroll_view_recreated")
        }
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
    if scroll.isTracking || scroll.isDragging || scroll.isDecelerating {
      cancelRestorationForUserInteraction()
    }
    cells = cells.filter { $0.value.value.map { $0.window != nil && $0.isDescendant(of: scroll) } ?? false }
    let frames = order.compactMap { id -> (String, CGRect)? in
      guard let view = cells[id]?.value else { return nil }
      return (id, view.convert(view.bounds, to: scroll))
    }
    // Do not clamp a saved offset against the previous feed's layout while
    // SwiftUI is still replacing its lazy targets.
    guard !frames.isEmpty else { return }
    if let pending, pending.scope == scope {
      let anchor = pending.anchor
      let target = frames.first(where: { $0.0 == anchor.id })
      let minimum = -scroll.adjustedContentInset.top
      let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
      // A lazy target can be absent. Only bootstrap an explicit navigation when
      // the saved content extent is available; never clamp against partial content.
      // Removals require the surviving target's actual frame, not the old offset.
      let canMaterialize = pending.reason != "required_removal" && anchor.contentHeight > 0 &&
        scroll.contentSize.height >= anchor.contentHeight - 1 && anchor.offset <= maximum
      guard anchor.id.isEmpty || target != nil || canMaterialize else { return }
      let y = target.map { $0.1.minY - anchor.y } ?? anchor.offset
      guard y <= maximum + 1 || pending.reason == "required_removal" else { return }
      let destination = min(maximum, max(minimum, y))
      // Complete once, including no-op restoration. No recursive correction loop.
      if abs(destination - scroll.contentOffset.y) > 0.5 {
#if DEBUG
        traceCommand(from: scroll.contentOffset.y, to: destination,
          mounted: target != nil, reason: pending.reason)
#endif
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: destination), animated: false)
      }
      self.pending = nil
    }
    let viewport = scroll.bounds.inset(by: UIEdgeInsets(top: scroll.adjustedContentInset.top, left: 0,
      bottom: scroll.adjustedContentInset.bottom, right: 0))
    let visible = frames.filter { $0.1.intersects(viewport) && $0.1.height > 0 }
    if let first = visible.first {
      snapshots[scope] = Anchor(id: first.0, y: first.1.minY - scroll.contentOffset.y,
        offset: scroll.contentOffset.y, contentHeight: scroll.contentSize.height)
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
  let feed: String
  func makeUIView(context: Context) -> Marker { Marker() }
  func updateUIView(_ view: Marker, context: Context) {
    view.owner = owner; view.postID = postID; view.feed = feed
    owner.register(view, id: postID, feed: feed)
  }
  final class Marker: UIView {
    weak var owner: CaptroFeedViewport?
    var postID = ""
    var feed = ""
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { owner?.register(self, id: postID, feed: feed) } }
    override func layoutSubviews() { super.layoutSubviews(); owner?.register(self, id: postID, feed: feed) }
  }
}
