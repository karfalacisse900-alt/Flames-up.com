#if DEBUG
import Foundation
import SwiftUI

public struct CaptroHomeFeedVisualTestView: View {
  @State private var selectedTab = 0
  private let api = MIRAAPIClient()
  private let posts = CaptroHomeFeedVisualFixtures.posts

  public init() {}

  public var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        ScrollView(showsIndicators: false) {
          LazyVStack(spacing: 24) {
            if posts.isEmpty {
              Text("Home feed visual fixture could not load")
                .font(.headline)
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .padding(24)
            } else {
              ForEach(posts) { post in
                CaptroFeedPostView(
                  post: post,
                  api: api,
                  isVideoActive: false,
                  showsFeedControls: false,
                  onFollow: { false },
                  onOpenOptions: {},
                  onCreate: {},
                  onOpenPost: {},
                  onSave: {},
                  canFollowAuthor: false,
                  pageSize: nil,
                  selectedMediaIndex: .constant(0),
                  showsCoverMediaOnly: true
                )
              }
            }
          }
          .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .background(MIRATheme.Color.appBackground)
      }
      .tag(0)
      .tabItem { Label("Home", systemImage: "house.fill") }

      visualTestTab(systemImage: "doc.viewfinder.fill")
        .tag(1)
        .tabItem { Label("Scan", systemImage: "doc.viewfinder.fill") }

      visualTestTab(systemImage: "person.fill")
        .tag(2)
        .tabItem { Label("Me", systemImage: "person.fill") }
    }
    .tint(MIRATheme.Color.forest)
    .toolbarBackground(MIRATheme.Color.surface, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .background(MIRATheme.Color.appBackground)
  }

  private func visualTestTab(systemImage: String) -> some View {
    ZStack {
      MIRATheme.Color.appBackground.ignoresSafeArea()
      Image(systemName: systemImage)
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }

}

private enum CaptroHomeFeedVisualFixtures {
  static let posts: [MIRAPost] = [
    decode(
      """
      {
        "id": "home-feed-visual-guide",
        "userFullName": "Captro",
        "userUsername": "captro",
        "title": "City at Blue Hour",
        "caption": "A quiet walk through the city after the rain. The light kept changing from one block to the next, turning familiar streets into places worth seeing again.",
        "images": [
          "https://images.unsplash.com/photo-1522083165195-3424ed129620?auto=format&fit=crop&w=1080&q=85",
          "https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=1080&q=85"
        ],
        "feedMediaUrls": [
          "https://images.unsplash.com/photo-1522083165195-3424ed129620?auto=format&fit=crop&w=1080&q=85",
          "https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=1080&q=85"
        ],
        "location": "Brooklyn, New York",
        "displayCity": "Brooklyn",
        "displayRegion": "New York",
        "displayLocationLabel": "Brooklyn, New York",
        "displayLocationVisibility": "city",
        "placeName": "Brooklyn",
        "placeCity": "Brooklyn",
        "postType": "guide",
        "createdAt": "2026-08-28T09:41:00Z",
        "likesCount": 18,
        "isLiked": false
      }
      """
    ),
    decode(
      """
      {
        "id": "home-feed-visual-moment",
        "userFullName": "Captro",
        "userUsername": "captro",
        "caption": "Morning light across the neighborhood.",
        "images": [
          "https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=1080&q=85"
        ],
        "feedMediaUrls": [
          "https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=1080&q=85"
        ],
        "location": "New York",
        "displayCity": "New York",
        "displayLocationLabel": "New York",
        "displayLocationVisibility": "city",
        "placeCity": "New York",
        "postType": "moment",
        "createdAt": "2026-08-28T08:20:00Z",
        "likesCount": 7,
        "isLiked": true
      }
      """
    )
  ].compactMap { $0 }

  private static func decode(_ json: String) -> MIRAPost? {
    let decoder = JSONDecoder()
    guard let data = json.data(using: .utf8) else {
      print("[CaptroVisualQA] Fixture is not valid UTF-8")
      return nil
    }
    do {
      return try decoder.decode(MIRAPost.self, from: data)
    } catch {
      print("[CaptroVisualQA] Fixture decode failed: \(error)")
      return nil
    }
  }
}
#endif
