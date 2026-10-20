import SwiftUI
import UIKit
import StripePayments
import Foundation
import GoogleSignIn

public enum MIRATab: Hashable {
  case main
  case scan
  case chat
  case profile
}

public enum MIRAStartupPhase: Equatable {
  case launching
  case checkingSession
  case loadingUser
  case preparingFeed
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
  @Published private(set) var isRoutingReady = false

  let feedModel: MainFeedModel
  let chatModel: ChatNativeModel
  let profileModel: ProfileNativeModel
  let paymentsModel: CaptroPaymentsModel

  private let api: MIRAAPIClient
  private var didStart = false
  private let splashDismissDuration: TimeInterval = 0.18
  private var brandingDeadline: Task<Void, Never>?

  init(api: MIRAAPIClient) {
    self.api = api
    self.feedModel = MainFeedModel(api: api)
    self.chatModel = ChatNativeModel(api: api)
    self.profileModel = ProfileNativeModel(api: api)
    self.paymentsModel = CaptroPaymentsModel(api: api)
  }

  func start(authSession: MIRAAuthSession) async {
    guard !didStart else { return }
    didStart = true
    MIRAPerformanceTimeline.mark("startup_prepare_start")
    // A maximum, never a minimum wait. Session work starts concurrently and
    // can outlive this decorative overlay without revealing the wrong route.
    brandingDeadline = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 720_000_000) } catch { return }
      self?.dismissSplash()
    }

    phase = .checkingSession
    await authSession.bootstrap(api: api)
    api.favorites.configure(accountID: authSession.user?.id ?? "")

    guard !Task.isCancelled else { return }
    if authSession.user == nil {
      phase = authSession.needsSessionRetry ? .failedWithRetry : .readyUnauthenticated
      isRoutingReady = true
      dismissSplash()
      return
    }

    if authSession.user?.needsUsernameOnboarding == true {
      phase = .readyAuthenticated
      isRoutingReady = true
      MIRAPerformanceTimeline.mark("startup_username_required")
      dismissSplash()
      return
    }

    profileModel.primeUser(authSession.user)
    chatModel.configure(currentUserId: authSession.user?.id ?? "")
    paymentsModel.configure(currentUserId: authSession.user?.id ?? "")
    phase = .preparingFeed
    // Home may hydrate its scoped snapshot while the brief splash is visible.
    // Profile, chat and payment requests belong to their own screens.
    await feedModel.prepareForStartup()

    phase = .readyAuthenticated
    isRoutingReady = true
    MIRAPerformanceTimeline.mark("startup_prepare_ready", detail: "authenticated")
    dismissSplash()
    let accountID = authSession.user?.id
    Task { [weak self, weak authSession] in
      guard let self, let authSession else { return }
      let invalidated = await MIRAAppCacheStore.shared.reconcileServerDataState(api: self.api)
      guard invalidated, authSession.user?.id == accountID else { return }
      MIRAPlaybackCoordinator.pauseAll(reason: "server_data_reset")
      MIRAVideoPrewarmManager.shared.resetForAccountChange()
      MIRAMediaCacheMaintenance.clearMemoryForAccountChange()
      self.feedModel.resetForAccountChange()
      self.profileModel.resetForAccountChange()
      self.chatModel.configure(currentUserId: "")
      self.chatModel.configure(currentUserId: accountID ?? "")
      self.paymentsModel.configure(currentUserId: "")
      self.paymentsModel.configure(currentUserId: accountID ?? "")
      self.profileModel.primeUser(authSession.user)
      await self.feedModel.load(forceRefresh: true)
    }
  }

  func leaveForeground() {
    // Never leave an invisible touch-blocking overlay after interruption.
    brandingDeadline?.cancel()
    isSplashVisible = false
    isSplashMounted = false
  }

  private func dismissSplash() {
    guard isSplashVisible else { return }
    brandingDeadline?.cancel()
    let delay = splashDismissDuration
    withAnimation(.easeInOut(duration: splashDismissDuration)) {
      isSplashVisible = false
    }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      await MainActor.run {
        guard let self else { return }
        self.isSplashMounted = false
        MIRAPerformanceTimeline.markOnce("startup_branding_dismissed")
      }
    }
  }

}

public struct MIRANativeRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: MIRATab = .main
  @State private var loadedTabs: Set<MIRATab> = [.main]
  @State private var isPrivacyShieldVisible = false
  @State private var featureStatusBarHidden = false
  @State private var cameraDarkChrome = false
  @State private var profileLink: CaptroProfileLink?
  @State private var hasMountedDestination = false
  @StateObject private var supportReturns = CaptroSupportReturnStore()
  @AppStorage(MIRAAppearanceResolver.preferenceKey) private var appearancePreference = MIRAAppearance.system.rawValue
  @StateObject private var authSession: MIRAAuthSession
  @StateObject private var startup: MIRAStartupCoordinator
  @StateObject private var localization: MIRALocalization
  private let api: MIRAAPIClient

  public init() {
    // Keep the selected symbol readable independently of the photograph beneath
    // iOS's floating tab bar. Same system tabs/shape, stable opaque app material.
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = UIColor(MIRATheme.Color.surface)
    tabAppearance.backgroundEffect = nil
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    let session = MIRAAuthSession()
    let client = MIRAAPIClient(sessionProvider: session)
    _authSession = StateObject(wrappedValue: session)
    _startup = StateObject(wrappedValue: MIRAStartupCoordinator(api: client))
    _localization = StateObject(wrappedValue: MIRALocalization.shared)
    self.api = client
    MIRAPerformanceTimeline.mark("native_root_init")
  }

#if DEBUG
  init(reviewSession: MIRAAuthSession, api: MIRAAPIClient) {
    _authSession = StateObject(wrappedValue: reviewSession)
    _startup = StateObject(wrappedValue: MIRAStartupCoordinator(api: api))
    _localization = StateObject(wrappedValue: MIRALocalization.shared)
    self.api = api
  }
#endif

  public var body: some View {
    ZStack {
      destinationView
        .opacity(startup.isSplashVisible ? 0.001 : 1)
        .allowsHitTesting(!startup.isSplashMounted)
        .animation(.easeInOut(duration: 0.28), value: startup.isSplashVisible)

      if startup.isSplashMounted {
        CaptroStartupView()
          .opacity(startup.isSplashVisible ? 1 : 0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .zIndex(10)
      }

      if isPrivacyShieldVisible {
        MIRAPrivacyShieldView()
          .transition(.opacity)
          .zIndex(100)
      }
    }
    .background(MIRATheme.Color.launchBackground.ignoresSafeArea())
    .background(CaptroRecoveryPresenter(session: authSession, api: api,
      ready: startup.isRoutingReady && !startup.isSplashMounted).frame(width: 0, height: 0))
    .background(CaptroSupportReturnPresenter(store: supportReturns, session: authSession, api: api,
      ready: startup.isRoutingReady && !startup.isSplashMounted).frame(width: 0, height: 0))
    .sheet(item: Binding(get: { startup.isRoutingReady && !startup.isSplashMounted ? profileLink : nil },
      set: { profileLink = $0 })) { route in
      NavigationStack {
        UserProfileNativeView(userId: route.id, api: api)
          .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { profileLink = nil } } }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .captroProfileSignInRequested)) { _ in
      guard authSession.isGuest else { return }
      profileLink = nil
      leaveGuestModeForSignIn()
    }
    .environmentObject(localization)
    .environmentObject(supportReturns)
    .onReceive(NotificationCenter.default.publisher(for: .captroSupportReturned)) { notification in
      if CaptroSupportPolicy.enabled, let id = notification.object as? String, UUID(uuidString: id) != nil {
        supportReturns.pendingPurchaseID = id
      }
    }
    .environment(\.captroSupportViewerID, authSession.user?.id)
    .preferredColorScheme(selectedTab == .scan && cameraDarkChrome ? .dark : MIRAAppearanceResolver.colorScheme(for: appearancePreference))
    .onPreferenceChange(CaptroCameraDarkChromePreferenceKey.self) { cameraDarkChrome = $0 }
    .statusBarHidden(shouldHideStatusBar)
    .onPreferenceChange(MIRAStatusBarHiddenPreferenceKey.self) { hidden in
      featureStatusBarHidden = hidden
    }
    .onAppear {
      MIRAMainThreadStallMonitor.shared.start()
      MIRAPerformanceTimeline.markOnce("time_to_first_screen")
    }
    .task {
      async let draftCleanup: Void = MIRAAppCacheStore.shared.clearPostDraftFromPreviousProcessIfNeeded()
      await startup.start(authSession: authSession)
      await draftCleanup
      registerCachedPushTokenIfPossible()
    }
    .onChange(of: authSession.user?.id) { oldUserID, userID in
      if let oldUserID, oldUserID != userID { supportReturns.forget(accountID: oldUserID) }
      // A profile opened under the previous account must not retain its presentation.
      if let oldUserID, oldUserID != userID { profileLink = nil }
      api.favorites.configure(accountID: userID ?? "")
      MIRAPlaybackCoordinator.pauseAll(reason: "account_changed")
      MIRAVideoPrewarmManager.shared.resetForAccountChange()
      MIRAMediaCacheMaintenance.clearMemoryForAccountChange()
      if startup.isRoutingReady {
        startup.feedModel.resetForAccountChange()
        startup.profileModel.resetForAccountChange()
        startup.chatModel.configure(currentUserId: userID ?? "")
        startup.paymentsModel.configure(currentUserId: userID ?? "")
        if userID != nil {
          startup.profileModel.primeUser(authSession.user)
          startup.feedModel.configureGuestMode(false)
          Task { await startup.feedModel.prepareForStartup() }
        }
      }
      if userID == nil {
        selectedTab = .main
        loadedTabs = [.main]
      } else {
        loadedTabs.insert(.main)
      }
      registerCachedPushTokenIfPossible()
    }
    .onChange(of: authSession.isGuest) { _, isGuest in
      if isGuest {
        selectedTab = .main
        loadedTabs = [.main]
      } else if authSession.user == nil {
        selectedTab = .main
        loadedTabs = [.main]
      }
    }
    .onChange(of: selectedTab) { _, tab in
      guard scenePhase == .active else { return }
      Task {
        if tab == .main, authSession.user != nil || authSession.isGuest {
          await startup.feedModel.revalidateIfStale()
        } else if tab == .profile, authSession.user != nil {
          await startup.profileModel.revalidateIfStale()
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      withAnimation(.easeOut(duration: phase == .active ? 0.18 : 0.06)) {
        isPrivacyShieldVisible = phase != .active
      }
      if phase == .active {
        registerCachedPushTokenIfPossible()
        if selectedTab == .main {
          MIRAPlaybackCoordinator.resumeVisible(reason: "app_active_home")
          if authSession.user != nil || authSession.isGuest {
            Task { await startup.feedModel.revalidateIfStale() }
          }
        } else if selectedTab == .profile, authSession.user != nil {
          Task { await startup.profileModel.revalidateIfStale() }
        }
      } else {
        startup.leaveForeground()
        MIRAPlaybackCoordinator.pauseAll(reason: "app_inactive")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraRemotePushTokenReceived)) { notification in
      guard let token = notification.object as? String else { return }
      registerPushToken(token)
    }
    .onOpenURL { url in
      if CaptroSupportPolicy.enabled, let purchaseID = CaptroSupportPolicy.returnPurchase(url) {
        supportReturns.pendingPurchaseID = purchaseID
        NotificationCenter.default.post(name: .captroSupportReturned, object: purchaseID)
        return
      }
      if let route = CaptroProfileLink.parse(url) { profileLink = route; return }
      if StripeAPI.handleURLCallback(with: url) { return }
      let googleHandled = GIDSignIn.sharedInstance.handle(url)
      MIRAAuthDiagnostics.callbackReceived(url, googleHandled: googleHandled)
      authSession.handleIncomingURL(url)
    }
  }

  private var shouldHideStatusBar: Bool {
    startup.isSplashMounted || featureStatusBarHidden
  }

  @ViewBuilder
  private var destinationView: some View {
    if !startup.isRoutingReady {
      VStack(spacing: 16) {
        ProgressView()
        Text(startup.phase.statusText).font(.callout).foregroundStyle(.secondary)
        Text("Your saved session and destination are being restored.")
          .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.padding(24).accessibilityElement(children: .combine)
        .accessibilityIdentifier("startup.resolving")
    } else if !hasMountedDestination && (profileLink != nil || authSession.passwordResetContext != nil) {
      // The pending sheet owns this launch; do not flash Home or welcome first.
      Color.clear.accessibilityHidden(true)
    } else {
      resolvedDestination.onAppear { hasMountedDestination = true }
    }
  }

  @ViewBuilder
  private var resolvedDestination: some View {
    if authSession.needsSessionRetry && authSession.user == nil && !authSession.isGuest {
      VStack(spacing: 20) {
        Text("Couldn’t restore your session").font(.title2)
        Text("Your sign-in is saved. Check your connection and try again.").foregroundStyle(.secondary)
        Button("Try again") { Task { await authSession.bootstrap(api: api) } }
          .disabled(authSession.isBootstrapping)
        Button("Use a different account") { authSession.logout() }
      }.padding(24)
    } else if authSession.user == nil && !authSession.isGuest {
      AuthNativeView(session: authSession, api: api)
        .transition(.opacity)
    } else if let user = authSession.user, user.isDeletionPending {
      RestoreAccountNativeView(user: user, api: api, session: authSession)
        .transition(.opacity)
    } else if let user = authSession.user, user.needsUsernameOnboarding {
      ChooseUsernameNativeView(user: user, api: api, session: authSession)
        .transition(.opacity)
    } else {
      mainTabs
        .transition(.opacity)
    }
  }

  private var mainTabs: some View {
    TabView(selection: $selectedTab) {
      lazyTab(.main) {
        MainFeedView(
          api: api,
          model: startup.feedModel,
          isTabActive: selectedTab == .main,
          isGuest: authSession.isGuest
        )
      }
        .tag(MIRATab.main)
        .tabItem { Label("Home", systemImage: "house.fill") }

      lazyTab(.scan) {
        if authSession.isGuest {
          GuestSignInRequiredView(
            title: "Sign in to use Capture",
            message: "Create an account or sign in to capture photos and videos.",
            systemImage: "camera",
            onSignIn: leaveGuestModeForSignIn
          )
        } else {
          CaptroCameraNativeView(api: api, isActive: selectedTab == .scan)
            .id("capture-account-\(authSession.user?.id ?? "")")
        }
      }
        .tag(MIRATab.scan)
        .tabItem { Label("Capture", systemImage: "viewfinder") }

      lazyTab(.profile) {
        if authSession.isGuest {
          GuestSignInRequiredView(
            title: "Sign in to view your profile",
            message: "Create an account or sign in to save your activity and manage your Captro profile.",
            systemImage: "person.crop.circle.fill",
            onSignIn: leaveGuestModeForSignIn
          )
        } else {
          ProfileNativeView(
            api: api,
            authSession: authSession,
            model: startup.profileModel,
            chatModel: startup.chatModel,
            paymentsModel: startup.paymentsModel
          )
        }
      }
        .tag(MIRATab.profile)
        .tabItem { Label("Me", systemImage: "person.fill") }
    }
    .tint(selectedTab == .scan && cameraDarkChrome ? Color.white : MIRATheme.Color.textPrimary)
    .toolbarBackground(selectedTab == .scan && cameraDarkChrome ? Color.black : MIRATheme.Color.surface, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .modifier(CaptroStudioTabChrome(active: selectedTab == .scan && cameraDarkChrome,
      home: { selectedTab = .main }, capture: { selectedTab = .scan }, profile: { selectedTab = .profile }))
    .background(MIRATheme.Color.appBackground)
    .onChange(of: selectedTab) { _, tab in
      MIRAPerformanceTimeline.mark("tab_switch", detail: "\(tab)")
      loadedTabs.insert(tab)
      if tab == .main {
        MIRAPlaybackCoordinator.resumeVisible(reason: "home_tab_selected")
      } else {
        MIRAPlaybackCoordinator.pauseAll(reason: "tab_changed")
      }
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
    return loadedTabs.contains(tab) || selectedTab == tab
  }

  private func leaveGuestModeForSignIn() {
    selectedTab = .main
    loadedTabs = [.main]
    authSession.exitGuestMode()
  }

  private func registerCachedPushTokenIfPossible() {
    guard authSession.user != nil else {
      MIRAPushTokenRegistry.shared.endSession()
      return
    }
    // Logout disables delivery on this device even if the network is offline.
    // Re-enable APNs on login, including when a cached token is available.
    MIRAPushNotificationRegistrar.registerForRemoteNotifications()
    if let token = MIRAPushNotificationRegistrar.cachedDeviceToken {
      registerPushToken(token)
    }
  }

  private func registerPushToken(_ token: String) {
    guard let accountID = authSession.user?.id else { return }
    let generation = authSession.sessionGeneration
    Task {
      guard let accessToken = await authSession.accessToken(),
            generation == authSession.sessionGeneration, accountID == authSession.user?.id else { return }
      await MIRAPushTokenRegistry.shared.registerDeviceToken(token, accountID: accountID, accessToken: accessToken, api: api)
    }
  }
}

private struct GuestSignInRequiredView: View {
  let title: String
  let message: String
  let systemImage: String
  let onSignIn: () -> Void

  var body: some View {
    ZStack {
      MIRATheme.Color.appBackground.ignoresSafeArea()

      VStack(spacing: 18) {
        Image(systemName: systemImage)
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 68, height: 68)
          .background(MIRATheme.Color.surfaceSoft)
          .clipShape(Circle())

        VStack(spacing: 8) {
          Text(title)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .multilineTextAlignment(.center)

          Text(message)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button(action: onSignIn) {
          Text("Sign in or create account")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(MIRATheme.Color.forest)
            .clipShape(Capsule())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel("Sign in or create account")
      }
      .padding(.horizontal, 28)
      .frame(maxWidth: 430)
    }
  }
}

private struct RestoreAccountResponse: Decodable {
  let restored: Bool?
  let user: MIRAUser?
}

private struct RestoreAccountNativeView: View {
  let user: MIRAUser
  let api: MIRAAPIClient
  @ObservedObject var session: MIRAAuthSession

  @State private var isRestoring = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      MIRATheme.Color.appBackground.ignoresSafeArea()

      VStack(spacing: 22) {
        Spacer(minLength: 20)

        VStack(spacing: 18) {
          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
            .frame(width: 72, height: 72)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())

          VStack(spacing: 8) {
            Text("Restore your account?")
              .font(.system(size: 28, weight: .black, design: .rounded))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .multilineTextAlignment(.center)

            Text("This Captro account is scheduled for deletion. Restore it now to keep using it, or sign out and deletion will continue.")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }

          if let scheduled = user.deletionScheduledAt, !scheduled.isEmpty {
            Text("Scheduled deletion: \(scheduled)")
              .font(.system(size: 12.5, weight: .bold))
              .foregroundStyle(MIRATheme.Color.textMuted)
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(Capsule())
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(MIRATheme.Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 12)
        .padding(.horizontal, 20)

        VStack(spacing: 12) {
          Button {
            Task { await restore() }
          } label: {
            Text(isRestoring ? "Restoring..." : "Restore account")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(isRestoring ? MIRATheme.Color.textMuted.opacity(0.5) : MIRATheme.Color.forest)
              .clipShape(Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(isRestoring)

          Button {
            session.logout()
          } label: {
            Text("Sign out and keep deletion scheduled")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity)
              .frame(height: 50)
              .background(MIRATheme.Color.surfaceSoft)
              .clipShape(Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(isRestoring)
        }
        .padding(.horizontal, 22)

        Spacer(minLength: 20)
      }
    }
  }

  @MainActor
  private func restore() async {
    guard !isRestoring else { return }
    isRestoring = true
    defer { isRestoring = false }
    do {
      let response: RestoreAccountResponse = try await api.post("/account/restore", body: EmptyBody())
      if let restoredUser = response.user {
        session.replaceUser(restoredUser)
      } else {
        errorMessage = "Could not restore your account right now."
      }
    } catch {
      if let apiError = error as? MIRAAPIError, let message = apiError.errorDescription, !message.isEmpty {
        errorMessage = message
      } else {
        errorMessage = "Could not restore your account right now."
      }
    }
  }
}

private struct MIRAPrivacyShieldView: View {
  var body: some View {
    ZStack {
      MIRATheme.Color.launchBackground.ignoresSafeArea()
      CaptroWordmarkView()
        .scaleEffect(0.74)
        .opacity(0.92)
        .accessibilityHidden(true)
    }
  }
}

private struct CaptroStartupView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var upper: CGFloat = 0
  @State private var lower: CGFloat = 0
  @State private var wordmark = false

  var body: some View {
    ZStack {
      Color("MIRALaunchBackground", bundle: .main).ignoresSafeArea()
      ZStack {
        // Same asset, scale, center and initial opacity as LaunchScreen.
        logo("CaptroStartupLockup").opacity(reduceMotion ? 1 : 0.14)
        if !reduceMotion {
          stroke("CaptroStartupUpper", progress: upper)
          stroke("CaptroStartupLower", progress: lower)
          logo("CaptroStartupWordmark").opacity(wordmark ? 1 : 0)
        }
      }.frame(width: 292, height: 75.92)
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
    .onAppear {
      guard !wordmark, !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 0.32)) { upper = 1 }
      withAnimation(.easeInOut(duration: 0.36).delay(0.10)) { lower = 1 }
      withAnimation(.easeOut(duration: 0.22).delay(0.34)) { wordmark = true }
    }
  }
  private func logo(_ name: String) -> some View {
    Image(name, bundle: .main).resizable().renderingMode(.template)
      .scaledToFit().foregroundStyle(.primary)
      .frame(width: 292, height: 75.92)
  }
  private func stroke(_ name: String, progress: CGFloat) -> some View {
    logo(name).mask(alignment: .leading) {
      // Exact supplied filled paths; reveal masks do not deform the two curves.
      Rectangle().frame(width: 292 * 0.25 * progress)
    }
  }
}

private struct CaptroWordmarkView: View {
  var body: some View {
    Image("CaptroLaunchLogo", bundle: .main)
      .resizable().scaledToFit().frame(width: 292, height: 98)
      .accessibilityLabel("Captro")
  }
}
