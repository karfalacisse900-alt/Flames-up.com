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
      ProcessInfo.processInfo.arguments.contains("--captro-visual-video") || ProcessInfo.processInfo.arguments.contains("--captro-public-feed-test") ? [] : CaptroHomeFeedVisualFixtures.posts()))
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      MainFeedView(api: model.api, model: model)
        .tag(0)
        .tabItem { Label("Home", systemImage: "house.fill") }
      Color.white
        .tag(1)
        .tabItem { Label("Capture", systemImage: "doc.viewfinder.fill") }
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
      if ProcessInfo.processInfo.arguments.contains("--captro-public-feed-test") {
        do {
          let posts: [MIRAPost] = try await model.api.get("/posts/world-board?limit=50&skip=0")
          let order = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--captro-public-posts=") }?
            .dropFirst("--captro-public-posts=".count).split(separator: ",").map(String.init) ?? []
          model.posts = order.compactMap { id in posts.first { $0.id == id } }
          if ProcessInfo.processInfo.arguments.contains("--captro-writing-overlays") {
            model.posts = model.posts.enumerated().map { index, original in
              var post = original
              post.editorOverlays = post.mediaURLs.enumerated().map { slide, _ in
                var writing = CaptroMediaWriting()
                writing.text = slide == 0 ? ["FRIDAY NIGHT\nNYC", "SUNDAY RUN\nBRONX", "PLACES FOR\nA FIRST DATE", "NYC AFTER\nMIDNIGHT"][index % 4] : "PHOTO \(slide + 1)"
                writing.sourceAspectRatio = 1 / (post.mediaHeightToWidthRatios.first ?? 1)
                writing.style = index % 2 == 0 ? "bold" : "editorial"
                writing.readability = true
                return CaptroMediaWritingEnvelope(type: "media_writing", mediaIndex: slide, writing: writing)
              }
              return post
            }
          }
          assert(model.posts.count == order.count, "Requested public post no longer available")
        } catch { assertionFailure("Public feed verification request failed") }
        return
      }
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
    if ProcessInfo.processInfo.arguments.contains("--captro-visual-stream") {
      return streamPosts(videoURL: videoURL)
    }
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
      "wide": CGSize(width: 1920, height: 1080),
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
          "caption": String(repeating: "Layout fixture. ", count:
            ProcessInfo.processInfo.arguments.contains("--captro-visual-long-text") ? 90 : 10),
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

  // Explicit DEBUG fixtures exercising the requested content types. These are
  // labeled test posts, not copies of private production posts or fake feed data.
  static func streamPosts(videoURL: URL?) -> [MIRAPost] {
    guard let videoURL else { return [] }
    let items: [(String, CGFloat, String)] = [
      ("NYPL — layout test", 1.25, "place"),
      ("Smart monkey — layout test", 1, "general"),
      ("16:9 photo — layout test", 9.0 / 16, "general"),
      ("Video — layout test", 4.0 / 3, "general"),
      ("Sunday Run Club — layout test", 1.25, "club"),
      ("Carousel — layout test", 4.0 / 3, "general"),
      ("Text only — layout test", 0, "general")
    ]
    return items.enumerated().compactMap { index, item in
      do {
        let size = CGSize(width: 480, height: 480 * item.1)
        var urls: [String] = []
        if item.1 > 0 {
          for slide in 0..<(index == 5 ? 3 : 1) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(index)-\(slide).png")
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
              UIColor(red: 0.18 + CGFloat(slide) * 0.14, green: 0.52, blue: 0.56, alpha: 1).setFill()
              context.fill(CGRect(origin: .zero, size: size))
              UIColor.white.setStroke()
              context.cgContext.setLineWidth(8)
              context.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
              let label = "TEST MEDIA · \(index + 1) / \(slide + 1)"
              label.draw(at: CGPoint(x: 20, y: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white])
            }
            try image.pngData()!.write(to: url)
            urls.append(index == 3 ? videoURL.absoluteString : url.absoluteString)
          }
        }
        var value: [String: Any] = [
          "id": "stream-\(index)", "userFullName": "Test Creator", "userUsername": "test_creator",
          "title": item.0, "caption": index == 1 ? "A short Moment." : String(repeating: "Layout test: complete content remains available in details. ", count: 14),
          "images": urls, "feedMediaUrls": urls,
          "mediaDimensions": urls.map { _ in ["width": size.width, "height": size.height] },
          "postType": item.2, "createdAt": "2026-10-06T09:41:00Z"
        ]
        if index == 0 { value["savesCount"] = 26; value["locationText"] = "New York — test location" }
        if index == 4 {
          value["detail"] = ["commerce": ["id": "test-club", "title": item.0,
            "contentType": "club", "fulfillmentType": "membership", "commerceClass": "community",
            "joinedCount": 23, "paymentModel": "free", "description": value["caption"]!,
            "refundPolicy": "none", "approvalRequired": false, "passRequired": false,
            "status": "active", "audience": "public", "prices": []]]
        }
        return try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: value))
      } catch { assertionFailure("Stream fixture failed: \(error)"); return nil }
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
