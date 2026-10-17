import XCTest
import SwiftUI
import UIKit
@testable import MIRANative

private final class ImageFixtureProtocol: URLProtocol {
  static var responder: ((URLRequest) throws -> (Int, String, Data))!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (code, mime, data) = try Self.responder(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
        httpVersion: nil, headerFields: ["Content-Type": mime])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class CaptroImageRecoveryTests: XCTestCase {
  private func pipeline() -> MIRAImageLoadPipeline {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageFixtureProtocol.self]
    return MIRAImageLoadPipeline(session: URLSession(configuration: configuration))
  }
  private func url() -> URL { URL(string: "https://image-fixture.invalid/\(UUID().uuidString).png")! }
  @MainActor private func redPNG() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
      UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }.pngData()!
  }

  func testHTTPFailureClassificationAndCorruptData() async {
    for (status, failure) in [(401, CaptroImageFailure.inaccessible), (403, .inaccessible),
                             (404, .removed), (410, .removed), (429, .throttled), (503, .transient)] {
      ImageFixtureProtocol.responder = { _ in (status, "image/png", Data()) }
      guard case .failed(let actual) = await pipeline().outcome(for: url(), maxPixelSize: 64) else {
        XCTFail("Expected failure for \(status)"); continue
      }
      XCTAssertEqual(actual, failure)
    }
    for (mime, expected) in [("text/html", CaptroImageFailure.invalidResponse), ("image/png", .invalidData)] {
      ImageFixtureProtocol.responder = { _ in (200, mime, Data("not an image".utf8)) }
      guard case .failed(let failure) = await pipeline().outcome(for: url(), maxPixelSize: 64) else { return XCTFail() }
      XCTAssertEqual(failure, expected)
    }
    XCTAssertFalse(CaptroImageFailure.inaccessible.permitsFallback)
    XCTAssertFalse(CaptroImageFailure.throttled.mayRetryAutomatically)
  }

  @MainActor func testDecodedPixelsCacheHitAndActualViewDisplay() async throws {
    let data = redPNG(), remote = url(), loader = pipeline()
    var requests = 0
    ImageFixtureProtocol.responder = { _ in requests += 1; return (200, "image/png", data) }
    let loaded = await loader.image(for: remote, maxPixelSize: 64)
    let first = try XCTUnwrap(loaded)
    XCTAssertNotNil(first.image.cgImage)
    _ = await loader.image(for: remote, maxPixelSize: 64)
    XCTAssertEqual(requests, 1, "A valid memory hit must not download or decode again")
    var view = MIRACachedImage(url: remote.absoluteString, maxPixelSize: 64, animatesNetworkLoad: false,
      allowsRetry: true) { $0.resizable().scaledToFill() } placeholder: { Color.blue }
    view.pipeline = loader
    let host = UIHostingController(rootView: view.frame(width: 120, height: 150).clipped())
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 150))
    window.rootViewController = host; window.isHidden = false
    defer { window.isHidden = true }
    host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    let rendered = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
      host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let cg = try XCTUnwrap(rendered.cgImage)
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    XCTAssertGreaterThan(pixel[0], 220); XCTAssertLessThan(pixel[2], 30, "Must render the red image, not the blue placeholder")
    XCTAssertEqual(host.view.bounds.size, CGSize(width: 120, height: 150))
  }

  func testOfflineRecoveryAndOldAccountRejection() async {
    let remote = url(), loader = pipeline()
    ImageFixtureProtocol.responder = { _ in throw URLError(.notConnectedToInternet) }
    guard case .failed(.transport) = await loader.outcome(for: remote, maxPixelSize: 64) else { return XCTFail() }
    let data = await redPNG()
    ImageFixtureProtocol.responder = { _ in (200, "image/png", data) }
    let recovered = await loader.image(for: remote, maxPixelSize: 64)
    XCTAssertNotNil(recovered)
    guard case .cancelled = await loader.outcome(for: remote, maxPixelSize: 64, expectedScope: "obsolete-account") else { return XCTFail() }
  }
}
