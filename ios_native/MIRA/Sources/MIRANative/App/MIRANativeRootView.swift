import SwiftUI
import Darwin

public enum MIRATab: Hashable {
  case main
  case discover
  case chat
  case profile
}

public struct MIRANativeRootView: View {
  @State private var selectedTab: MIRATab = .main
  @State private var loadedTabs: Set<MIRATab> = [.main]
  @State private var startupHoldComplete = false
  @State private var showSlowStartupCopy = false
  @StateObject private var authSession: MIRAAuthSession
  private let api: MIRAAPIClient

  public init() {
    let session = MIRAAuthSession()
    _authSession = StateObject(wrappedValue: session)
    self.api = MIRAAPIClient(sessionProvider: session)
    MIRAPerformanceTimeline.mark("native_root_init")
  }

  public var body: some View {
    ZStack {
      destinationView
        .opacity(shouldShowStartup ? 0 : 1)
        .animation(.easeInOut(duration: 0.28), value: shouldShowStartup)

      if shouldShowStartup {
        CaptroStartupView(showSlowMessage: showSlowStartupCopy && authSession.isBootstrapping)
          .transition(.opacity.combined(with: .scale(scale: 1.01)))
          .zIndex(10)
      }
    }
    .background(MIRATheme.Color.launchBackground.ignoresSafeArea())
    .statusBarHidden(shouldShowStartup || (authSession.user != nil && selectedTab == .main))
    .onAppear {
      MIRAMainThreadStallMonitor.shared.start()
      MIRAPerformanceTimeline.markOnce("time_to_first_screen")
    }
    .task { await authSession.bootstrap(api: api) }
    .task { await runStartupTiming() }
  }

  private var shouldShowStartup: Bool {
    authSession.isBootstrapping || !startupHoldComplete
  }

  @ViewBuilder
  private var destinationView: some View {
    if authSession.user == nil {
      AuthNativeView(session: authSession, api: api)
        .transition(.opacity)
    } else {
      mainTabs
        .transition(.opacity)
    }
  }

  private var mainTabs: some View {
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
        ChatNativeView(api: api, currentUserId: authSession.user?.id ?? "")
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
    .onChange(of: selectedTab) { _, tab in
      MIRAPerformanceTimeline.mark("tab_switch", detail: "\(tab)")
      loadedTabs.insert(tab)
    }
  }

  @MainActor
  private func runStartupTiming() async {
    try? await Task.sleep(nanoseconds: 850_000_000)
    withAnimation(.easeInOut(duration: 0.28)) {
      startupHoldComplete = true
    }

    try? await Task.sleep(nanoseconds: 1_650_000_000)
    withAnimation(.easeInOut(duration: 0.20)) {
      showSlowStartupCopy = true
    }
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

private struct CaptroStartupView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let showSlowMessage: Bool
  @State private var appeared = false

  var body: some View {
    ZStack {
      MIRATheme.Color.launchBackground.ignoresSafeArea()

      VStack(spacing: MIRATheme.Space.xl) {
        VStack(spacing: MIRATheme.Space.sm) {
          CaptroWordmarkView()
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.96))
            .opacity(appeared ? 1 : 0)

          Rectangle()
            .fill(Color.black.opacity(0.72))
            .frame(width: 128, height: 1)
            .opacity(appeared ? 1 : 0)

          Text("capture moments")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.52))
            .opacity(appeared ? 1 : 0)
        }

        VStack(spacing: MIRATheme.Space.sm) {
          CaptroStartupPulse()
            .opacity(appeared ? 1 : 0)

          if showSlowMessage {
            Text("Getting Captro ready")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.46))
              .transition(.opacity)
          }
        }
        .frame(height: 38)
      }
      .padding(.horizontal, MIRATheme.Space.xxl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      guard !appeared else { return }
      withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.46)) {
        appeared = true
      }
    }
    .contentShape(Rectangle())
  }
}

private struct CaptroWordmarkView: View {
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text("Cap")
      Text("Tro")
        .italic()
    }
    .font(.system(size: 58, weight: .regular, design: .serif))
    .foregroundStyle(Color.black.opacity(0.90))
    .lineLimit(1)
    .minimumScaleFactor(0.75)
    .accessibilityLabel("Captro")
  }
}

private struct CaptroStartupPulse: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation) { timeline in
      let now = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 7) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.black.opacity(dotOpacity(at: now, index: index)))
            .frame(width: 5, height: 5)
        }
      }
    }
    .frame(height: 12)
    .accessibilityHidden(true)
  }

  private func dotOpacity(at now: TimeInterval, index: Int) -> Double {
    if reduceMotion {
      return 0.34
    }
    let wave = Darwin.sin((now * 3.4) + Double(index) * 0.85)
    return 0.22 + ((wave + 1) / 2) * 0.42
  }
}
