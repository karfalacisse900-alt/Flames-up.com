import SwiftUI
import Darwin
import Foundation

public enum MIRATab: Hashable {
  case main
  case discover
  case chat
  case profile
}

public enum MIRAStartupPhase: Equatable {
  case launching
  case checkingSession
  case loadingUser
  case preparingFeed
  case preparingDiscover
  case preparingProfile
  case preparingMainTabs
  case readyAuthenticated
  case readyUnauthenticated
  case failedWithRetry

  var statusText: String {
    switch self {
    case .launching:
      return "Opening Captro"
    case .checkingSession:
      return "Checking your session"
    case .loadingUser:
      return "Loading your profile"
    case .preparingFeed:
      return "Preparing your feed"
    case .preparingDiscover:
      return "Preparing Discover"
    case .preparingProfile:
      return "Preparing your profile"
    case .preparingMainTabs:
      return "Building your tabs"
    case .readyAuthenticated, .readyUnauthenticated:
      return "Ready"
    case .failedWithRetry:
      return "Still getting Captro ready"
    }
  }
}

@MainActor
final class MIRAStartupCoordinator: ObservableObject {
  @Published private(set) var phase: MIRAStartupPhase = .launching
  @Published private(set) var isSplashMounted = true
  @Published private(set) var isSplashVisible = true
  @Published private(set) var showSlowStartupCopy = false
  @Published private(set) var shouldMountAllAuthenticatedTabs = false

  let feedModel: MainFeedModel
  let discoverModel: DiscoverNativeModel
  let profileModel: ProfileNativeModel

  private let api: MIRAAPIClient
  private var didStart = false
  private let minimumSplashDuration: TimeInterval = 0.88
  private let splashDismissDuration: TimeInterval = 0.32

  init(api: MIRAAPIClient) {
    self.api = api
    self.feedModel = MainFeedModel(api: api)
    self.discoverModel = DiscoverNativeModel(api: api)
    self.profileModel = ProfileNativeModel(api: api)
  }

  func start(authSession: MIRAAuthSession) async {
    guard !didStart else { return }
    didStart = true
    let startedAt = Date()
    MIRAPerformanceTimeline.mark("startup_prepare_start")
    beginSlowMessageTimer()

    phase = .checkingSession
    await authSession.bootstrap(api: api)

    guard !Task.isCancelled else { return }
    if authSession.user == nil {
      phase = .readyUnauthenticated
      await waitForMinimumSplash(since: startedAt)
      dismissSplash()
      return
    }

    shouldMountAllAuthenticatedTabs = true
    phase = .loadingUser
    profileModel.primeUser(authSession.user)
    await Task.yield()

    phase = .preparingMainTabs
    await Task.yield()

    phase = .preparingFeed
    let feedTask = Task { await feedModel.prepareForStartup() }

    phase = .preparingDiscover
    let discoverTask = Task { await discoverModel.prepareForStartup() }

    phase = .preparingProfile
    let profileTask = Task { await profileModel.prepareForStartup(signedInUser: authSession.user) }

    _ = await (feedTask.value, discoverTask.value, profileTask.value)
    startInitialMediaPrewarm()

    phase = .readyAuthenticated
    await waitForMinimumSplash(since: startedAt)
    MIRAPerformanceTimeline.mark("startup_prepare_ready", detail: "authenticated")
    dismissSplash()
  }

  private func beginSlowMessageTimer() {
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_650_000_000)
      await MainActor.run {
        guard let self, self.isSplashMounted else { return }
        withAnimation(.easeInOut(duration: 0.20)) {
          self.showSlowStartupCopy = true
        }
      }
    }
  }

  private func waitForMinimumSplash(since startedAt: Date) async {
    let elapsed = Date().timeIntervalSince(startedAt)
    let remaining = max(0, minimumSplashDuration - elapsed)
    guard remaining > 0 else { return }
    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
  }

  private func dismissSplash() {
    let delay = splashDismissDuration
    withAnimation(.easeInOut(duration: splashDismissDuration)) {
      isSplashVisible = false
    }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      await MainActor.run {
        guard let self else { return }
        self.isSplashMounted = false
        self.showSlowStartupCopy = false
      }
    }
  }

  private func startInitialMediaPrewarm() {
    let posts = Array(feedModel.posts.prefix(4)) + Array(discoverModel.posts.prefix(9)) + Array(profileModel.posts.prefix(6))
    let urls = Array(
      posts
        .flatMap(\.mediaURLs)
        .filter { !$0.isVideoURL }
        .prefix(8)
    )
    guard !urls.isEmpty else { return }
    Task.detached(priority: .utility) {
      await MIRAStartupMediaPrewarmer.prewarm(urls: urls)
    }
  }
}

private enum MIRAStartupMediaPrewarmer {
  static func prewarm(urls: [String]) async {
    guard !urls.isEmpty else { return }

    await withTaskGroup(of: Void.self) { group in
      for value in urls {
        group.addTask {
          await prewarmImage(value)
        }
      }
    }
  }

  private static func prewarmImage(_ value: String) async {
    guard let url = URL(string: value) else { return }
    if await MIRAImageDiskCache.image(for: url) != nil { return }
    do {
      var request = URLRequest(url: url)
      request.cachePolicy = .returnCacheDataElseLoad
      request.timeoutInterval = 5
      let (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      guard (200..<300).contains(status), data.count <= 10 * 1024 * 1024 else { return }
      await MIRAImageDiskCache.store(data: data, for: url)
    } catch {
      // Startup prewarming is opportunistic. Stable placeholders still cover misses.
    }
  }
}

public struct MIRANativeRootView: View {
  @State private var selectedTab: MIRATab = .main
  @State private var loadedTabs: Set<MIRATab> = [.main]
  @StateObject private var authSession: MIRAAuthSession
  @StateObject private var startup: MIRAStartupCoordinator
  @StateObject private var callCoordinator: MIRAAppCallCoordinator
  private let api: MIRAAPIClient

  public init() {
    let session = MIRAAuthSession()
    let client = MIRAAPIClient(sessionProvider: session)
    _authSession = StateObject(wrappedValue: session)
    _startup = StateObject(wrappedValue: MIRAStartupCoordinator(api: client))
    _callCoordinator = StateObject(wrappedValue: MIRAAppCallCoordinator.shared)
    self.api = client
    MIRAPerformanceTimeline.mark("native_root_init")
  }

  public var body: some View {
    ZStack {
      destinationView
        .opacity(startup.isSplashVisible ? 0.001 : 1)
        .allowsHitTesting(!startup.isSplashMounted)
        .animation(.easeInOut(duration: 0.28), value: startup.isSplashVisible)

      if startup.isSplashMounted {
        CaptroStartupView(phase: startup.phase, showSlowMessage: startup.showSlowStartupCopy)
          .opacity(startup.isSplashVisible ? 1 : 0)
          .scaleEffect(startup.isSplashVisible ? 1 : 0.985)
          .zIndex(10)
      }

      MIRACallOverlays(coordinator: callCoordinator)
        .zIndex(30)
    }
    .miraFullScreenOverlay(item: activeCallBinding, background: .black) { presentation, dismissCall in
      MIRAAgoraCallView(presentation: presentation, api: api) {
        Task { await callCoordinator.endActiveCall() }
        dismissCall()
      }
    }
    .background(MIRATheme.Color.launchBackground.ignoresSafeArea())
    .statusBarHidden(startup.isSplashMounted || (authSession.user != nil && selectedTab == .main))
    .onAppear {
      MIRAMainThreadStallMonitor.shared.start()
      MIRAPerformanceTimeline.markOnce("time_to_first_screen")
    }
    .task {
      await startup.start(authSession: authSession)
      callCoordinator.configure(api: api, currentUserId: authSession.user?.id)
    }
    .onChange(of: authSession.user?.id) { _, userID in
      if userID == nil {
        selectedTab = .main
        loadedTabs = [.main]
      } else {
        loadedTabs.formUnion([.main, .discover, .profile])
      }
      callCoordinator.configure(api: api, currentUserId: userID)
    }
  }

  private var activeCallBinding: Binding<MIRAAgoraCallPresentation?> {
    Binding(
      get: { callCoordinator.activeCall },
      set: { callCoordinator.activeCall = $0 }
    )
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
        MainFeedView(api: api, model: startup.feedModel)
      }
        .tag(MIRATab.main)
        .tabItem { Label("Home", systemImage: "house.fill") }

      lazyTab(.discover) {
        DiscoverNativeView(api: api, model: startup.discoverModel)
      }
        .tag(MIRATab.discover)
        .tabItem { Label("Discover", systemImage: "safari.fill") }

      lazyTab(.chat) {
        ChatNativeView(api: api, currentUserId: authSession.user?.id ?? "")
      }
        .tag(MIRATab.chat)
        .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

      lazyTab(.profile) {
        ProfileNativeView(api: api, authSession: authSession, model: startup.profileModel)
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

  @ViewBuilder
  private func lazyTab<Content: View>(_ tab: MIRATab, @ViewBuilder content: () -> Content) -> some View {
    if shouldMountTab(tab) {
      content()
    } else {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MIRATheme.Color.appBackground)
    }
  }

  private func shouldMountTab(_ tab: MIRATab) -> Bool {
    if authSession.user != nil && startup.shouldMountAllAuthenticatedTabs {
      return true
    }
    return loadedTabs.contains(tab) || selectedTab == tab
  }
}

private struct CaptroStartupView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let phase: MIRAStartupPhase
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
            Text(phase.statusText)
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
