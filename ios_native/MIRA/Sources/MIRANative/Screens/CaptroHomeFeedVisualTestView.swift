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
    && !ProcessInfo.processInfo.arguments.contains("--captro-visual-mixed-carousel")

  public init() {
    let api = MIRAAPIClient()
    _model = StateObject(wrappedValue: MainFeedModel(api: api, visualPosts:
      ProcessInfo.processInfo.arguments.contains("--captro-visual-video")
        || ProcessInfo.processInfo.arguments.contains("--captro-visual-mixed-carousel")
        || ProcessInfo.processInfo.arguments.contains("--captro-public-feed-test") ? [] : CaptroHomeFeedVisualFixtures.posts()))
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        MainFeedView(api: model.api, model: model, isTabActive: selectedTab == 0)
      }
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
      guard ProcessInfo.processInfo.arguments.contains("--captro-stability-updates") else { return }
      // Deterministic DEBUG traffic through the same reconciliation used by
      // background refresh. No production writes or private content.
      for tick in 1...125 {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let updates = model.posts.reversed().map { $0.updating(likesCount: tick) }
        model.posts = CaptroFeedReconciliation.background(existing: model.posts, fresh: updates)
      }
    }
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
    if ProcessInfo.processInfo.arguments.contains("--captro-stability-forty") {
      let seed = streamPosts(videoURL: videoURL)
      guard !seed.isEmpty else { return [] }
      return (0..<40).compactMap { index in
        guard let data = try? JSONEncoder().encode(seed[index % seed.count]),
          var record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        record["id"] = "stress-\(index)"
        return (try? JSONSerialization.data(withJSONObject: record)).flatMap { try? JSONDecoder().decode(MIRAPost.self, from: $0) }
      }
    }
    if ProcessInfo.processInfo.arguments.contains("--captro-visual-mixed-carousel"), let videoURL {
      return mixedCarouselPosts(videoURL: videoURL)
    }
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
      if ProcessInfo.processInfo.arguments.contains("--captro-stamp-budget-test") {
        return budgetPosts(mediaURL: mediaURL, size: size)
      }
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

  static func mixedCarouselPosts(videoURL: URL) -> [MIRAPost] {
    let sizes = [CGSize(width: 480, height: 600), CGSize(width: 640, height: 360),
      CGSize(width: 480, height: 640), CGSize(width: 480, height: 480)]
    do {
      var urls: [String] = []
      for index in [0, 1, 3] {
        let size = sizes[index]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-carousel-\(index).png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
          UIColor(red: 0.18 + CGFloat(index) * 0.15, green: 0.48, blue: 0.52, alpha: 1).setFill()
          context.fill(CGRect(origin: .zero, size: size))
        }
        try image.pngData()!.write(to: url)
        urls.append(url.absoluteString)
      }
      urls.insert(videoURL.absoluteString, at: 2)
      let value: [String: Any] = ["id": "mixed-carousel", "userUsername": "test_creator",
        "userFullName": "Test Creator", "title": "Mixed media", "caption": "The original frame remains visible on every slide.",
        "images": urls, "feedMediaUrls": urls,
        "mediaDimensions": sizes.map { ["width": $0.width, "height": $0.height] },
        "postType": "general"]
      var post = try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: value))
      var first = CaptroMediaWriting(); first.text = "FIRST PHOTO"; first.sourceAspectRatio = 480 / 600
      var empty = CaptroMediaWriting(); empty.text = " \n "; empty.sourceAspectRatio = 640 / 360
      post.editorOverlays = [
        CaptroMediaWritingEnvelope(type: "media_writing", mediaIndex: 0, writing: first),
        CaptroMediaWritingEnvelope(type: "media_writing", mediaIndex: 1, writing: empty),
      ]
      return [post]
    } catch { assertionFailure("Mixed carousel fixture failed: \(error)"); return [] }
  }

  // Test-only data rendered by the actual Home cells, never published or bundled
  // in Release. Boundary cases supplement the unchanged real public examples.
  static func budgetPosts(mediaURL: URL, size: CGSize) -> [MIRAPost] {
    let ordinary = String(String(repeating: "Good food and company. ", count: 11).prefix(220))
    let captions = ["A quiet evening.", String(repeating: "A neighborhood walk. ", count: 5), ordinary,
      String(repeating: "Complete original writing remains available in Details. ", count: 20),
      "A two-line title without shrinking the type.", "An intimate neighborhood restaurant.",
      "Meet for a relaxed Sunday run, then coffee together.", "An evening outdoors with friends.",
      "Writing and a separate compact stamp.", "Only a caption and its creator."]
    return captions.enumerated().compactMap { index, caption in
      var value: [String: Any] = ["id": "stamp-budget-\(index)", "userUsername": "test_creator",
        "userFullName": "Test Creator", "title": index == 4 ? "A thoughtful evening around NYC" : "Stamp test \(index + 1)",
        "caption": caption, "images": [mediaURL.absoluteString], "feedMediaUrls": [mediaURL.absoluteString],
        "mediaDimensions": [["width": size.width, "height": size.height]],
        "postType": "general", "displayLocationLabel": "New York, United States", "displayLocationVisibility": "public"]
      if index == 5 {
        value["postType"] = "place"; value["placeName"] = "Neighborhood place — test"
        value["displayLocationLabel"] = "West Village"; value["savesCount"] = 721
      }
      if index == 6 || index == 7 {
        let kind = index == 6 ? "club" : "event"
        value["postType"] = kind
        value["detail"] = ["commerce": ["id": "budget-\(kind)", "title": index == 6 ? "Sunday Run Club — test" : "Outdoor evening — test",
          "contentType": kind, "fulfillmentType": index == 6 ? "membership" : "ticket", "commerceClass": "community",
          "joinedCount": 0, "paymentModel": "paid", "description": caption,
          "refundPolicy": "none", "approvalRequired": false, "passRequired": false,
          "locationName": "Washington Square Park", "city": "New York", "startsAt": "2026-10-10T20:00:00Z",
          "timeZone": "America/New_York", "status": "active", "audience": "public",
          "prices": [["id": "test-price", "label": "Access", "unitAmount": 200,
            "currency": "USD", "billingPeriod": "one_time", "active": true]]]]
      }
      if index == 9 { value.removeValue(forKey: "title") }
      guard let data = try? JSONSerialization.data(withJSONObject: value),
        var post = try? JSONDecoder().decode(MIRAPost.self, from: data) else { return nil }
      if index == 8 {
        var writing = CaptroMediaWriting(); writing.text = "FRIDAY NIGHT\nNYC"
        writing.sourceAspectRatio = size.width / size.height
        post.editorOverlays = [CaptroMediaWritingEnvelope(type: "media_writing", mediaIndex: 0, writing: writing)]
      }
      return post
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
