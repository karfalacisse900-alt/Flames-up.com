#if DEBUG
import Foundation
import SwiftUI
import UIKit

@MainActor
public struct CaptroHomeFeedVisualTestView: View {
  @State private var selectedTab = 0
  @StateObject private var model: MainFeedModel

  public init() {
    let api = MIRAAPIClient()
    _model = StateObject(wrappedValue: MainFeedModel(api: api, visualPosts: CaptroHomeFeedVisualFixtures.posts()))
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
  }
}

private enum CaptroHomeFeedVisualFixtures {
  static func posts() -> [MIRAPost] {
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
        mediaURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("full-bleed-fixture.mp4")
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
      let json: [String: Any] = [
        "id": "full-bleed-\(name)", "userFullName": "Captro", "userUsername": "captro",
        "title": "Full-width media", "caption": String(repeating: "Layout fixture. ", count: 10),
        "images": [mediaURL.absoluteString], "feedMediaUrls": [mediaURL.absoluteString],
        "mediaDimensions": [["width": size.width, "height": size.height]],
        "postType": "place", "createdAt": "2026-09-04T09:41:00Z",
      ]
      return [try JSONDecoder().decode(MIRAPost.self, from: JSONSerialization.data(withJSONObject: json))]
    } catch {
      assertionFailure("Full-bleed visual fixture failed: \(error)")
      return []
    }
  }
}
#endif
