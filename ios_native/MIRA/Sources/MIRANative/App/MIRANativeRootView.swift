import SwiftUI

public enum MIRATab: Hashable {
  case main
  case discover
  case chat
  case profile
}

public struct MIRANativeRootView: View {
  @State private var selectedTab: MIRATab = .main
  private let api: MIRAAPIClient

  public init(api: MIRAAPIClient = MIRAAPIClient(sessionProvider: MIRAKeychainSessionProvider())) {
    self.api = api
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      MainFeedView(api: api)
        .tag(MIRATab.main)
        .tabItem { Label("Home", systemImage: "house.fill") }

      DiscoverNativeView(api: api)
        .tag(MIRATab.discover)
        .tabItem { Label("Discover", systemImage: "safari.fill") }

      ChatNativeView(api: api)
        .tag(MIRATab.chat)
        .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

      ProfileNativeView(api: api)
        .tag(MIRATab.profile)
        .tabItem { Label("Profile", systemImage: "person.fill") }
    }
    .tint(MIRATheme.Color.forest)
    .background(MIRATheme.Color.appBackground)
  }
}
