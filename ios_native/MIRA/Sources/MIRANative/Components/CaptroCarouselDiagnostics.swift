#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
import SwiftUI
import UIKit

/// Opt-in, read-only diagnostics for the *same* native pager in Home and Details.
/// No state publication, scroll delegate replacement, gesture failure rule or
/// offset correction. All sampling is absent from Release builds.
@MainActor
final class CaptroCarouselTraceRecorder {
  static let shared = CaptroCarouselTraceRecorder(enabled: isEnabled)
  static let isEnabled = ProcessInfo.processInfo.arguments.contains("--captro-carousel-diagnostics")

  struct Sample: Codable {
    let time: Double
    let event: String
    let mediaID: String
    let pagerX: Double
    let feedY: Double
    let frame: [Double]
    let pagerGesture: Int
    let feedGesture: Int
    let tracking: Bool
    let dragging: Bool
    let decelerating: Bool
  }
  private struct Range {
    var minimum: Double
    var maximum: Double
    init(_ value: Double) { minimum = value; maximum = value }
    mutating func include(_ value: Double) { minimum = min(minimum, value); maximum = max(maximum, value) }
    var distance: Double { maximum - minimum }
  }
  private struct Gesture {
    var feed: Range
    var frameY: Range
    var width: Range
    var height: Range
    init(_ sample: Sample) {
      feed = Range(sample.feedY); frameY = Range(sample.frame[1])
      width = Range(sample.frame[2]); height = Range(sample.frame[3])
    }
    mutating func include(_ sample: Sample) {
      feed.include(sample.feedY); frameY.include(sample.frame[1])
      width.include(sample.frame[2]); height.include(sample.frame[3])
    }
  }
  private struct Trace {
    var samples: [Sample] = []
    var totalSamples = 0
    var gestures: [Gesture] = []
    var interactionOpen = false
    var lastSample: Sample?
    var startedAtFeedEvaluation = 0
  }
  private var traces: [String: Trace] = [:]
  private var feedEvaluations = 0
  private let enabled: Bool

  init(enabled: Bool) { self.enabled = enabled }

  func endInteraction(surface: String, postID: String) {
    let key = surface + ":" + postID
    guard var trace = traces[key] else { return }
    trace.interactionOpen = false
    trace.lastSample = nil
    traces[key] = trace
  }

  func noteFeedEvaluation() {
    guard enabled else { return }
    feedEvaluations += 1
  }

  func record(surface: String, postID: String, sample: Sample) {
    guard enabled, sample.frame.count == 4 else { return }
    let key = surface + ":" + postID
    var trace = traces[key] ?? Trace(startedAtFeedEvaluation: feedEvaluations)
    trace.totalSamples += 1
    trace.samples.append(sample)
    if trace.samples.count > 256 { trace.samples.removeFirst(trace.samples.count - 256) }
    let interacting = sample.tracking || sample.dragging || sample.decelerating
      || sample.event == "pan_began"
    if interacting && !trace.interactionOpen {
      // Include movement before the pager's recognizer begins (the Home
      // direction gate can still be .possible while the parent moves).
      trace.gestures.append(Gesture(trace.lastSample ?? sample))
      if trace.gestures.count > 64 { trace.gestures.removeFirst() }
      trace.interactionOpen = true
    }
    if trace.interactionOpen {
      trace.gestures[trace.gestures.count - 1].include(sample)
      if !interacting { trace.interactionOpen = false }
    }
    // Idle layout/navigation samples are not attributed to the previous swipe.
    trace.lastSample = sample
    traces[key] = trace
  }

  func summary(surface: String, postID: String) -> String {
    let trace = traces[surface + ":" + postID] ?? Trace()
    let samples = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(trace.samples))) ?? []
    let result: [String: Any] = [
      "surface": surface, "postID": postID,
      "totalSamples": trace.totalSamples, "gestureCount": trace.gestures.count,
      "parentFeedEvaluations": feedEvaluations - trace.startedAtFeedEvaluation,
      "maxGestureFeedOffsetRange": trace.gestures.map { $0.feed.distance }.max() ?? 0,
      "maxGestureFrameYRange": trace.gestures.map { $0.frameY.distance }.max() ?? 0,
      "maxGestureFrameWidthRange": trace.gestures.map { $0.width.distance }.max() ?? 0,
      "maxGestureFrameHeightRange": trace.gestures.map { $0.height.distance }.max() ?? 0,
      "samples": samples
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return "{}" }
    return text
  }
}

struct CaptroCarouselTraceProbe: UIViewRepresentable {
  let surface: String
  let postID: String
  let mediaID: String
  let selected: Bool

  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.surface = surface; view.postID = postID; view.mediaID = mediaID; view.selected = selected
    view.isUserInteractionEnabled = false
    view.attach()
    view.sample("view_update")
  }
  static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

  final class Probe: UIView {
    var surface = ""
    var postID = ""
    var mediaID = ""
    var selected = false {
      didSet { if !selected { stopInteractionSampling() } }
    }
    private weak var pager: UIScrollView?
    private weak var feed: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var interactionDisplayLink: CADisplayLink?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil { detach() } else { attach(); sample("mounted") }
    }
    override func layoutSubviews() { super.layoutSubviews(); attach(); sample("layout") }

    func attach() {
      guard window != nil else { return }
      var ancestor = superview
      var nextPager: UIScrollView?
      var nextFeed: UIScrollView?
      while let view = ancestor {
        if let scroll = view as? UIScrollView {
          let horizontal = scroll.isPagingEnabled || scroll.alwaysBounceHorizontal
            || scroll.contentSize.width > scroll.bounds.width + 1
          if nextPager == nil && horizontal { nextPager = scroll }
          else if nextPager != nil && !scroll.isPagingEnabled { nextFeed = scroll; break }
        }
        ancestor = view.superview
      }
      guard nextPager !== pager || nextFeed !== feed else { return }
      detach(); pager = nextPager; feed = nextFeed
      if let pager {
        pager.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        observations.append(pager.observe(\.contentOffset, options: []) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.sample("pager_offset") }
        })
        observations.append(pager.observe(\.bounds, options: []) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.sample("pager_bounds") }
        })
      }
      if let feed {
        observations.append(feed.observe(\.contentOffset, options: []) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.sample("feed_offset") }
        })
      }
    }
    func detach() {
      stopInteractionSampling()
      if selected, pager != nil {
        CaptroCarouselTraceRecorder.shared.endInteraction(surface: surface, postID: postID)
      }
      pager?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
      observations.removeAll(); pager = nil; feed = nil
    }
    @objc private func panChanged(_ gesture: UIPanGestureRecognizer) {
      sample(gesture.state == .began ? "pan_began" : "pan_changed")
    }
    @objc private func sampleInteractionBoundary() { sample("interaction_frame") }
    private func stopInteractionSampling() {
      interactionDisplayLink?.invalidate()
      interactionDisplayLink = nil
    }
    func sample(_ event: String) {
      guard selected, let pager, let window, bounds.width > 0, bounds.height > 0 else { return }
      let tracking = pager.isTracking || (feed?.isTracking ?? false)
      let dragging = pager.isDragging || (feed?.isDragging ?? false)
      let decelerating = pager.isDecelerating || (feed?.isDecelerating ?? false)
      if tracking || dragging || decelerating {
        if interactionDisplayLink == nil {
          // Opt-in DEBUG only. End each range at its actual idle boundary so
          // later navigation is not folded into the last carousel gesture.
          let link = CADisplayLink(target: self, selector: #selector(sampleInteractionBoundary))
          link.add(to: .main, forMode: .common)
          interactionDisplayLink = link
        }
      } else { stopInteractionSampling() }
      let rect = convert(bounds, to: window)
      CaptroCarouselTraceRecorder.shared.record(surface: surface, postID: postID,
        sample: .init(time: ProcessInfo.processInfo.systemUptime, event: event, mediaID: mediaID,
          pagerX: Double(pager.contentOffset.x), feedY: Double(feed?.contentOffset.y ?? 0),
          frame: [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)],
          pagerGesture: pager.panGestureRecognizer.state.rawValue,
          feedGesture: feed?.panGestureRecognizer.state.rawValue ?? -1,
          tracking: tracking, dragging: dragging, decelerating: decelerating))
    }
  }
}

struct CaptroCarouselTraceSnapshot: UIViewRepresentable {
  let surface: String
  let postID: String
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.surface = surface; view.postID = postID
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "carousel.diagnostics.\(surface)"
    view.accessibilityLabel = "Carousel diagnostics"
    view.isUserInteractionEnabled = false
  }
  final class Probe: UIView {
    var surface = ""
    var postID = ""
    override var accessibilityValue: String? {
      get { CaptroCarouselTraceRecorder.shared.summary(surface: surface, postID: postID) }
      set { }
    }
  }
}
#endif
