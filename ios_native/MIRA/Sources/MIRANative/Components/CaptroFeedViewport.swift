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
  // Built only when the feed order changes. Scroll ticks inspect mounted
  // markers, not every ID fetched by pagination.
  private var orderIndex: [String: Int] = [:]
  private var scope = "forYou"
  private var activeID: String?
  private var isActive = true
  var onVisible: ((String?) -> Void)?

  /// A read-only publication hint. An absent/hidden scroll view, pending
  /// navigation, rubber-banding or user motion is not an invitation to insert
  /// content above the reader. This never changes the native content offset.
  var isAtTopAndIdle: Bool {
    guard isActive, pending == nil, let scroll, scroll.window != nil,
          scroll.bounds.height > 0, !scroll.isTracking, !scroll.isDragging,
          !scroll.isDecelerating else { return false }
    return abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) <= 1
  }
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
  struct FrameCadenceMetrics {
    private(set) var intervals = 0
    private(set) var totalMilliseconds: Double = 0
    private(set) var maximumGapMilliseconds: Double = 0
    private(set) var overOneAndHalfBudget = 0
    private(set) var overTwoBudgets = 0
    private(set) var over50Milliseconds = 0
    private(set) var over100Milliseconds = 0
    private var previousTimestamp: Double?

    mutating func pause() { previousTimestamp = nil }
    mutating func record(timestamp: Double, budget: Double) {
      defer { previousTimestamp = timestamp }
      guard let previousTimestamp, timestamp > previousTimestamp, budget > 0 else { return }
      let interval = timestamp - previousTimestamp
      let milliseconds = interval * 1000
      intervals += 1
      totalMilliseconds += milliseconds
      maximumGapMilliseconds = max(maximumGapMilliseconds, milliseconds)
      if interval > budget * 1.5 { overOneAndHalfBudget += 1 }
      if interval > budget * 2 { overTwoBudgets += 1 }
      if milliseconds > 50 { over50Milliseconds += 1 }
      if milliseconds > 100 { over100Milliseconds += 1 }
    }
  }
  @MainActor
  private final class FrameCadenceTarget: NSObject {
    weak var owner: CaptroFeedViewport?
    init(owner: CaptroFeedViewport) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
      guard let owner else { link.invalidate(); return }
      owner.sampleFrameCadence(link)
    }
  }
  struct SampleMetrics: Codable {
    struct Row: Codable {
      let id: String
      let contentY: Double
      let height: Double
    }
    let time: Double
    let milliseconds: Double
    let geometryMilliseconds: Double
    let visibleCallbackMilliseconds: Double
    let loadedIDs: Int
    let visitedMarkers: Int
    let frameCount: Int
    let offsetY: Double
    let contentHeight: Double
    let viewportHeight: Double
    let activeID: String?
    let tracking: Bool
    let dragging: Bool
    let decelerating: Bool
    let rows: [Row]
  }
  struct ScrollCommand {
    let before: CGFloat
    let after: CGFloat
    let targetMounted: Bool
    let reason: String
  }
  private(set) var debugCommands: [ScrollCommand] = []
  private(set) var debugSampleCount = 0
  private(set) var debugSampleMilliseconds: Double = 0
  private(set) var debugMaxSampleMilliseconds: Double = 0
  private(set) var debugLastVisitedMarkerCount = 0
  private(set) var debugLastFrameCount = 0
  private(set) var debugVisiblePublicationCount = 0
  private(set) var debugLastVisibleIDs: [String] = []
  var debugRecordsSamples = ProcessInfo.processInfo.arguments.contains("--captro-vertical-diagnostics")
  private var debugSampleHistory: [SampleMetrics] = []
  private var debugHistoryCursor = 0
  private var debugFrameLink: CADisplayLink?
  private(set) var debugFrameCadence = FrameCadenceMetrics()
  var debugSummary: String {
    "commands=\(debugCommands.count);samples=\(debugSampleCount);maxSampleMs=\(debugMaxSampleMilliseconds);offset=\(scroll?.contentOffset.y ?? 0);mounted=\(cells.count);loaded=\(order.count);visited=\(debugLastVisitedMarkerCount);visibleChanges=\(debugVisiblePublicationCount);totalSampleMs=\(debugSampleMilliseconds);frameIntervals=\(debugFrameCadence.intervals);totalFrameMs=\(debugFrameCadence.totalMilliseconds);maxFrameGapMs=\(debugFrameCadence.maximumGapMilliseconds);frameOver1_5Budget=\(debugFrameCadence.overOneAndHalfBudget);frameOver2Budget=\(debugFrameCadence.overTwoBudgets);frameOver50Ms=\(debugFrameCadence.over50Milliseconds);frameOver100Ms=\(debugFrameCadence.over100Milliseconds)"
  }
  var debugTrace: String {
    // Serialize only on an explicit test/diagnostic read, never per frame.
    let samples = debugSampleHistory.count < 256 ? debugSampleHistory :
      Array(debugSampleHistory[debugHistoryCursor...]) + Array(debugSampleHistory[..<debugHistoryCursor])
    guard let data = try? JSONEncoder().encode(samples) else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
  }
  private func record(_ metrics: SampleMetrics) {
    guard debugRecordsSamples else { return }
    if debugSampleHistory.count < 256 { debugSampleHistory.append(metrics) }
    else { debugSampleHistory[debugHistoryCursor] = metrics }
    debugHistoryCursor = (debugHistoryCursor + 1) % 256
  }
  private func traceCommand(from: CGFloat, to: CGFloat, mounted: Bool, reason: String) {
    debugCommands.append(ScrollCommand(before: from, after: to, targetMounted: mounted, reason: reason))
    if debugCommands.count > 128 { debugCommands.removeFirst() }
    CaptroFeedDiagnostics.event("offset_write", feed: scope,
      reason: "\(reason),from=\(from),to=\(to),mounted=\(mounted)", post: pending?.anchor.id)
  }

  private func stopFrameCadence() {
    debugFrameLink?.invalidate()
    debugFrameLink = nil
    debugFrameCadence.pause()
  }
  private func updateFrameCadenceObservation() {
    guard debugRecordsSamples, isActive, let scroll, scroll.window != nil,
          scroll.isTracking || scroll.isDragging || scroll.isDecelerating else {
      stopFrameCadence()
      return
    }
    guard debugFrameLink == nil else { return }
    let target = FrameCadenceTarget(owner: self)
    let link = CADisplayLink(target: target, selector: #selector(FrameCadenceTarget.tick(_:)))
    link.add(to: .main, forMode: .common)
    debugFrameLink = link
  }
  private func sampleFrameCadence(_ link: CADisplayLink) {
    guard debugRecordsSamples, isActive, let scroll, scroll.window != nil,
          scroll.isTracking || scroll.isDragging || scroll.isDecelerating else {
      stopFrameCadence()
      return
    }
    // Fixed counters only: no logging, allocation, JSON, SwiftUI publication,
    // geometry walk or scroll command from this display-link callback.
    let budget = link.targetTimestamp > link.timestamp ? link.targetTimestamp - link.timestamp : link.duration
    debugFrameCadence.record(timestamp: link.timestamp, budget: budget)
  }
#endif

  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    if !active {
      sample() // Capture before navigation/tab-bar layout starts changing.
      isActive = false
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
      stopFrameCadence()
#endif
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
    orderIndex.removeAll()
    requestRestoration(snapshots[scope] ?? Anchor(id: "", y: 0, offset: 0), reason: "feed_selection")
    activeID = nil
    schedule()
  }

  func updateOrder(_ ids: [String]) {
    guard ids != order else { return }
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
    orderIndex = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    schedule()
  }

  func register(_ view: UIView, id: String, feed: String? = nil) {
    guard feed == nil || feed == scope else { return }
    if cells[id]?.value !== view { cells[id] = WeakView(view) }
    attach(from: view)
    schedule()
  }

  private func attach(from view: UIView) {
    var ancestor = view.superview
    while let candidate = ancestor {
      if let target = candidate as? UIScrollView, !target.isPagingEnabled {
        guard scroll !== target else { return }
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
        stopFrameCadence()
#endif
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
    guard isActive, let scroll, scroll.window != nil, scroll.bounds.height > 0 else {
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
      stopFrameCadence()
#endif
      return
    }
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
    let sampleStart = ProcessInfo.processInfo.systemUptime
    updateFrameCadenceObservation()
    var geometryMilliseconds: Double = 0
    var callbackMilliseconds: Double = 0
    var visibleRows: [SampleMetrics.Row] = []
    defer {
      let duration = (ProcessInfo.processInfo.systemUptime - sampleStart) * 1000
      debugSampleCount += 1
      debugSampleMilliseconds += duration
      debugMaxSampleMilliseconds = max(debugMaxSampleMilliseconds, duration)
      if debugRecordsSamples {
        record(SampleMetrics(time: sampleStart, milliseconds: duration,
          geometryMilliseconds: geometryMilliseconds, visibleCallbackMilliseconds: callbackMilliseconds,
          loadedIDs: order.count, visitedMarkers: debugLastVisitedMarkerCount, frameCount: debugLastFrameCount,
          offsetY: Double(scroll.contentOffset.y), contentHeight: Double(scroll.contentSize.height),
          viewportHeight: Double(scroll.bounds.height), activeID: activeID,
          tracking: scroll.isTracking, dragging: scroll.isDragging, decelerating: scroll.isDecelerating,
          rows: visibleRows))
      }
    }
#endif
    if scroll.isTracking || scroll.isDragging || scroll.isDecelerating {
      cancelRestorationForUserInteraction()
    }
    var detached: [String] = []
    var mounted: [(id: String, index: Int, frame: CGRect)] = []
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
    debugLastVisitedMarkerCount = cells.count
#endif
    for (id, marker) in cells {
      guard let view = marker.value, view.window != nil, view.isDescendant(of: scroll) else {
        detached.append(id)
        continue
      }
      guard let index = orderIndex[id] else { continue }
      mounted.append((id, index, view.convert(view.bounds, to: scroll)))
    }
    for id in detached { cells.removeValue(forKey: id) }
    // Preserve feed-order tie breaking and first-visible anchoring regardless
    // of dictionary/registration order. Only the mounted subset is sorted.
    mounted.sort { $0.index < $1.index }
    let frames = mounted.map { ($0.id, $0.frame) }
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
    debugLastFrameCount = frames.count
    debugLastVisibleIDs = []
    geometryMilliseconds = (ProcessInfo.processInfo.systemUptime - sampleStart) * 1000
#endif
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
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
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
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
    debugLastVisibleIDs = visible.map(\.0)
    if debugRecordsSamples {
      visibleRows = visible.map { SampleMetrics.Row(id: $0.0, contentY: Double($0.1.minY), height: Double($0.1.height)) }
    }
#endif
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
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
      debugVisiblePublicationCount += 1
      let callbackStart = ProcessInfo.processInfo.systemUptime
#endif
      onVisible?(next)
#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
      callbackMilliseconds = (ProcessInfo.processInfo.systemUptime - callbackStart) * 1000
#endif
    }
  }
}

#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
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
      get {
        guard let owner else { return nil }
        let loads = MIRAImageLoadPipeline.shared.diagnosticSnapshot
        return owner.debugSummary + ";imageActive=\(loads.active);imageWaiting=\(loads.waiting);imagePeak=\(loads.peakActive);prefetchPeak=\(loads.peakPrefetch);imageAdmitted=\(loads.admitted);imageCancelledWaiting=\(loads.cancelledWaiting)"
      }
      set { }
    }
  }
}

/// Optional bounded timing/geometry history, without any production observer
/// or recurring logger. Enable with --captro-vertical-diagnostics.
struct CaptroFeedViewportTraceDiagnostics: UIViewRepresentable {
  let owner: CaptroFeedViewport
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.owner = owner
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "home.viewport.trace"
    view.accessibilityLabel = "Vertical viewport trace"
    view.isUserInteractionEnabled = false
  }
  final class Probe: UIView {
    weak var owner: CaptroFeedViewport?
    override var accessibilityValue: String? {
      get { owner?.debugTrace }
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
