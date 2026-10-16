#if DEBUG || CAPTRO_PERFORMANCE_REVIEW
import Foundation
import SwiftUI
import UIKit

/// Deterministic URLSession transport test, NOT a device network conditioner.
/// 500ms initial latency, 4096 bytes/64ms = 0.512 Mbps per request. Local videos
/// are intentionally unchanged; this fixture cannot establish HLS performance.
final class CaptroSlowMediaFixture: URLProtocol {
  static let slow = ProcessInfo.processInfo.arguments.contains("--captro-vertical-slow-network")
  static let enabled = slow || ProcessInfo.processInfo.arguments.contains("--captro-vertical-good-network")
  private static var latency: Double { slow ? 0.5 : 0.02 }
  private static var interval: Double { slow ? 0.064 : 0.002 }
  private static let statsLock = NSLock()
  private static var requests = 0
  private static var active = 0
  private static var peak = 0
  private static var bytes = 0
  private static var cancelled = 0
  private static var failures = 0
  private let delivery = DispatchQueue(label: "captro.test.media.transport", qos: .utility)
  private var stopped = false
  private var counted = false
  private var work: DispatchWorkItem?
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "captro-slow-media.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    delivery.async { [self] in
      guard !stopped, let url = request.url else { return }
      Self.statsLock.withLock { Self.requests += 1; Self.active += 1; Self.peak = max(Self.peak, Self.active) }
      counted = true
      let file = url.lastPathComponent
      guard file.range(of: #"^vertical-[0-9]+-[0-9]+\.png$"#, options: .regularExpression) != nil,
            let data = try? Data(contentsOf: FileManager.default.temporaryDirectory.appendingPathComponent(file)) else {
        finish(error: URLError(.fileDoesNotExist)); return
      }
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "image/png", "Content-Length": String(data.count)])!
      let next = DispatchWorkItem { [weak self] in
        guard let self, !self.stopped else { return }
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.send(data, offset: 0)
      }
      work = next
      delivery.asyncAfter(deadline: .now() + Self.latency, execute: next)
    }
  }
  private func send(_ data: Data, offset: Int) {
    guard !stopped else { return }
    guard offset < data.count else { finish(error: nil); return }
    let end = min(data.count, offset + 4096)
    let chunk = data.subdata(in: offset..<end)
    Self.statsLock.withLock { Self.bytes += chunk.count }
    client?.urlProtocol(self, didLoad: chunk)
    let next = DispatchWorkItem { [weak self] in self?.send(data, offset: end) }
    work = next
    delivery.asyncAfter(deadline: .now() + Self.interval, execute: next)
  }
  private func finish(error: Error?) {
    guard !stopped else { return }
    if counted { Self.statsLock.withLock { Self.active -= 1 }; counted = false }
    stopped = true
    if let error {
      Self.statsLock.withLock { Self.failures += 1 }
      client?.urlProtocol(self, didFailWithError: error)
    } else { client?.urlProtocolDidFinishLoading(self) }
    work = nil
  }
  override func stopLoading() {
    delivery.async { [self] in
      guard !stopped else { return }
      stopped = true; work?.cancel(); work = nil
      if counted {
        Self.statsLock.withLock { Self.active -= 1; Self.cancelled += 1 }
        counted = false
      }
    }
  }
  static var summary: String {
    statsLock.withLock {
      "latencyMs=\(Int(latency * 1000));bytesPerSecondPerRequest=\(Int(4096 / interval));requests=\(requests);active=\(active);peak=\(peak);bytes=\(bytes);cancelled=\(cancelled);failures=\(failures)"
    }
  }
}

struct CaptroSlowMediaDiagnostics: UIViewRepresentable {
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "vertical.network.diagnostics"
    view.accessibilityLabel = "Simulated slow image transport, not physical network evidence"
    view.isUserInteractionEnabled = false
  }
  final class Probe: UIView {
    override var accessibilityValue: String? {
      get { CaptroSlowMediaFixture.summary }
      set { }
    }
  }
}
#endif
