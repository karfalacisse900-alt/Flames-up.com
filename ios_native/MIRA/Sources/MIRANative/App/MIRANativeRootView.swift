import SwiftUI

public enum MIRATab: Hashable {
  case main
  case discover
  case chat
  case profile
}

public struct MIRANativeRootView: View {
  @State private var selectedTab: MIRATab = .main
  @State private var loadedTabs: Set<MIRATab> = [.main]
  @StateObject private var authSession: MIRAAuthSession
  private let api: MIRAAPIClient

  public init() {
    let session = MIRAAuthSession()
    _authSession = StateObject(wrappedValue: session)
    self.api = MIRAAPIClient(sessionProvider: session)
  }

  public var body: some View {
    Group {
      if authSession.isBootstrapping {
        VStack(spacing: MIRATheme.Space.md) {
          ProgressView()
          Text("Opening MIRA")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MIRATheme.Color.appBackground)
      } else if authSession.user == nil {
        AuthNativeView(session: authSession, api: api)
      } else {
        TabView(selection: $selectedTab) {
          lazyTab(.main) {
            MainFeedView(api: api)
          }
            .tag(MIRATab.main)
            .tabItem { Label("Home", systemImage: "house.fill") }

          lazyTab(.discover) {
            DiscoverNativeView(api: api)
          }
            .tag(MIRATab.discover)
            .tabItem { Label("Discover", systemImage: "safari.fill") }

          lazyTab(.chat) {
            ChatNativeView(api: api)
          }
            .tag(MIRATab.chat)
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

          lazyTab(.profile) {
            ProfileNativeView(api: api, authSession: authSession)
          }
            .tag(MIRATab.profile)
            .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(MIRATheme.Color.forest)
        .toolbarBackground(MIRATheme.Color.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(MIRATheme.Color.appBackground)
        .statusBarHidden(selectedTab == .main)
        .onChange(of: selectedTab) { _, tab in
          loadedTabs.insert(tab)
        }
      }
    }
    .onAppear {
      MIRAMainThreadStallMonitor.shared.start()
    }
    .task { await authSession.bootstrap(api: api) }
  }

  @ViewBuilder
  private func lazyTab<Content: View>(_ tab: MIRATab, @ViewBuilder content: () -> Content) -> some View {
    if loadedTabs.contains(tab) || selectedTab == tab {
      content()
    } else {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MIRATheme.Color.appBackground)
    }
  }
}
