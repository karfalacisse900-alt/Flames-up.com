#if DEBUG
import Foundation
import SwiftUI
import UIKit
import AVFoundation

@MainActor
public struct CaptroHomeFeedVisualTestView: View {
  @State private var selectedTab = 0
  @StateObject private var model: MainFeedModel
  @State private var videoPrepared = !ProcessInfo.processInfo.arguments.contains("--captro-visual-video")

  public init() {
    let api = MIRAAPIClient()
    _model = StateObject(wrappedValue: MainFeedModel(api: api, visualPosts:
      ProcessInfo.processInfo.arguments.contains("--captro-visual-video") ? [] : CaptroHomeFeedVisualFixtures.posts()))
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      MainFeedView(api: model.api, model: model)
        .tag(0)
        .tabItem { Label("Home", systemImage: "house.fill") }
      Color.white
        .tag(1)
        .tabItem { Label("Scan", systemImage: "doc.viewfinder.fill") }
      Color.white
        .tag(2)
        .tabItem { Label("Me", systemImage: "person.fill") }
    }
    .environmentObject(MIRALocalization.shared)
    .tint(MIRATheme.Color.forest)
    .toolbarBackground(MIRATheme.Color.surface, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .background(MIRATheme.Color.appBackground)
    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--captro-quality-dark") ? .dark : .light)
    .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--captro-quality-large-text") ? .accessibility2 : .large)
    .task {
      guard !videoPrepared else { return }
      do {
        let url = try await CaptroHomeFeedVisualFixtures.video()
        model.posts = CaptroHomeFeedVisualFixtures.posts(videoURL: url)
        videoPrepared = true
      } catch { assertionFailure("Video fixture failed: \(error)") }
    }
  }
}

private enum CaptroHomeFeedVisualFixtures {
  static func posts(videoURL: URL? = nil) -> [MIRAPost] {
    if ProcessInfo.processInfo.arguments.contains("--captro-visual-text") {
      return (0..<2).compactMap { index in
        var value: [String: Any] = [
          "id": "text-system-\(index)", "userFullName": "Test Creator", "userUsername": "test_creator",
          "title": index == 0 ? "A walk around the neighborhood" : "Looking for people to build with",
          "caption": index == 0 ? "Anyone up for a walk?" : String(repeating: "A designer and developer to help build something together. ", count: 12),
          "images": [], "feedMediaUrls": [], "postType": "general", "createdAt": "2026-10-04T09:41:00Z"
        ]
        if index == 0 && ProcessInfo.processInfo.arguments.contains("--captro-visual-audio") {
          value["detail"] = ["voice": ["id": "voice-layout-test", "durationMs": 8000]]
          value["audioProvider"] = "audius"
          value["audioTrackId"] = "audio-layout-test"
          value["audioTitle"] = "Attached music"
          value["audioArtist"] = "Test artist"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(MIRAPost.self, from: data)
      }
    }
    let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--captro-visual-size=") }
    let name = argument?.components(separatedBy: "=").last ?? "portrait"
    let sizes: [String: CGSize] = [
      "landscape": CGSize(width: 1440, height: 1080),
      "portrait": CGSize(width: 999, height: 1536),
      "fourfive": CGSize(width: 1080, height: 1350),
      "threefour": CGSize(width: 1080, height: 1440),
      "square": CGSize(width: 1080, height: 1080),
    ]
    let size = sizes[name] ?? sizes["portrait"]!
    let isVideo = ProcessInfo.processInfo.arguments.contains("--captro-visual-video")
    do {
      let mediaURL: URL
      if isVideo {
        guard let videoURL else { return [] }
        mediaURL = videoURL
      } else {
        mediaURL = FileManager.default.temporaryDirectory.appendingPathComponent("full-bleed-\(name).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
          UIColor(red: 0.08, green: 0.58, blue: 0.64, alpha: 1).setFill()
          context.fill(CGRect(origin: .zero, size: size))
          UIColor(red: 0.94, green: 0.24, blue: 0.43, alpha: 1).setFill()
          context.fill(CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.2, height: size.height))
        }
        try image.pngData()!.write(to: mediaURL)
      }
      let pagerFixture = ProcessInfo.processInfo.arguments.contains("--captro-visual-pager")
      return try (0..<(pagerFixture ? 3 : 1)).map { index in
        let json: [String: Any] = [
          "id": "full-bleed-\(name)-\(index)", "userFullName": "Captro", "userUsername": "captro",
          "title": pagerFixture ? "Pager post \(index + 1)" : "Full-width media",
          "caption": String(repeating: "Layout fixture. ", count: 10),
          "images": [mediaURL.absoluteString], "feedMediaUrls": [mediaURL.absoluteString],
          "mediaDimensions": [["width": size.width, "height": size.height]],
          "postType": "place", "createdAt": "2026-09-04T09:41:00Z",
        ]
        return try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: json))
      }
    } catch {
      assertionFailure("Full-bleed visual fixture failed: \(error)")
      return []
    }
  }

  // Real decodable local video used only by DEBUG layout tests; no network,
  // production account, or fabricated playback success is involved.
  static func video() async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("viewport-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 480, AVVideoHeightKey: 640])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 640])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? MIRAAPIError.emptyResponse }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<30 {
      while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else { throw writer.error ?? MIRAAPIError.emptyResponse }
        try await Task.sleep(for: .milliseconds(10))
      }
      var optionalBuffer: CVPixelBuffer?
      guard let pool = adaptor.pixelBufferPool,
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
            let buffer = optionalBuffer else { throw MIRAAPIError.emptyResponse }
      CVPixelBufferLockBaseAddress(buffer, [])
      if let address = CVPixelBufferGetBaseAddress(buffer) {
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = address.assumingMemoryBound(to: UInt8.self)
        for y in 0..<640 { for x in 0..<480 {
          let offset = y * stride + x * 4
          pixels[offset] = 255; pixels[offset + 1] = UInt8(30 + frame * 3)
          pixels[offset + 2] = x < 240 ? 160 : 80; pixels[offset + 3] = 170
        } }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
        throw writer.error ?? MIRAAPIError.emptyResponse
      }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? MIRAAPIError.emptyResponse }
    return url
  }
}
#endif
