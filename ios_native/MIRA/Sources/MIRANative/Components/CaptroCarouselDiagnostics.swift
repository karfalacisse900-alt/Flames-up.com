#if DEBUG
import SwiftUI
import UIKit

/// Opt-in, read-only diagnostics for the *same* native pager in Home and Details.
/// No state publication, scroll delegate replacement, gesture failure rule or
/// offset correction. All sampling is absent from Release builds.
@MainActor
final class CaptroCarouselTraceRecorder {
  static let shared = CaptroCarouselTraceRecorder()
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
    var width: Range
    var height: Range
    init(_ sample: Sample) {
      feed = Range(sample.feedY); width = Range(sample.frame[2]); height = Range(sample.frame[3])
    }
    mutating func include(_ sample: Sample) {
      feed.include(sample.feedY); width.include(sample.frame[2]); height.include(sample.frame[3])
    }
  }
  private struct Trace {
    var samples: [Sample] = []
    var totalSamples = 0
    var gestures: [Gesture] = []
    var startedAtFeedEvaluation = 0
  }
  private var traces: [String: Trace] = [:]
  private var feedEvaluations = 0

  func noteFeedEvaluation() {
    guard Self.isEnabled else { return }
    feedEvaluations += 1
  }

  func record(surface: String, postID: String, sample: Sample) {
    guard Self.isEnabled else { return }
    let key = surface + ":" + postID
    var trace = traces[key] ?? Trace(startedAtFeedEvaluation: feedEvaluations)
    trace.totalSamples += 1
    trace.samples.append(sample)
    if trace.samples.count > 256 { trace.samples.removeFirst(trace.samples.count - 256) }
    if sample.event == "pan_began" {
      trace.gestures.append(Gesture(sample))
      if trace.gestures.count > 64 { trace.gestures.removeFirst() }
    } else if (sample.dragging || sample.decelerating), !trace.gestures.isEmpty {
      trace.gestures[trace.gestures.count - 1].include(sample)
    }
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
    var selected = false
    private weak var pager: UIScrollView?
    private weak var feed: UIScrollView?
    private var observations: [NSKeyValueObservation] = []

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
      pager?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
      observations.removeAll(); pager = nil; feed = nil
    }
    @objc private func panChanged(_ gesture: UIPanGestureRecognizer) {
      sample(gesture.state == .began ? "pan_began" : "pan_changed")
    }
    func sample(_ event: String) {
      guard selected, let pager, let window, bounds.width > 0, bounds.height > 0 else { return }
      let rect = convert(bounds, to: window)
      CaptroCarouselTraceRecorder.shared.record(surface: surface, postID: postID,
        sample: .init(time: ProcessInfo.processInfo.systemUptime, event: event, mediaID: mediaID,
          pagerX: pager.contentOffset.x, feedY: feed?.contentOffset.y ?? 0,
          frame: [rect.minX, rect.minY, rect.width, rect.height],
          pagerGesture: pager.panGestureRecognizer.state.rawValue,
          feedGesture: feed?.panGestureRecognizer.state.rawValue ?? -1,
          dragging: pager.isDragging, decelerating: pager.isDecelerating))
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
