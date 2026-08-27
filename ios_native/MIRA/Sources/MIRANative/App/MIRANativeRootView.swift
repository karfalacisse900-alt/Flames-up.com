import SwiftUI
import Darwin
import Foundation
import GoogleSignIn

public enum MIRATab: Hashable {
  case home
  case scan
  case wallet
  case me
}

public enum MIRAStartupPhase: Equatable {
  case launching
  case checkingSession
  case readyAuthenticated
  case readyUnauthenticated
  case failedWithRetry

  var statusText: String {
    switch self {
    case .launching:
      return "Opening Aura"
    case .checkingSession:
      return "Checking your session"
    case .readyAuthenticated, .readyUnauthenticated:
      return "Ready"
    case .failedWithRetry:
      return "Still getting Aura ready"
    }
  }
}

@MainActor
final class MIRAStartupCoordinator: ObservableObject {
  @Published private(set) var phase: MIRAStartupPhase = .launching
  @Published private(set) var isSplashMounted = true
  @Published private(set) var isSplashVisible = true
  @Published private(set) var showSlowStartupCopy = false

  private let api: MIRAAPIClient
  private var didStart = false
  private let minimumSplashDuration: TimeInterval = 0.88
  private let splashDismissDuration: TimeInterval = 0.32

  init(api: MIRAAPIClient) {
    self.api = api
  }

  func start(authSession: MIRAAuthSession) async {
    guard !didStart else { return }
    didStart = true
    let startedAt = Date()
    MIRAPerformanceTimeline.mark("startup_prepare_start")
    beginSlowMessageTimer()

    phase = .checkingSession
    await MIRAAppCacheStore.shared.reconcileServerDataState(api: api)
    await authSession.bootstrap(api: api)

    guard !Task.isCancelled else { return }
    if authSession.user == nil {
      phase = .readyUnauthenticated
      await waitForMinimumSplash(since: startedAt)
      dismissSplash()
      return
    }

    phase = .readyAuthenticated
    await waitForMinimumSplash(since: startedAt)
    MIRAPerformanceTimeline.mark(
      authSession.user?.needsUsernameOnboarding == true
        ? "startup_username_required"
        : "startup_prepare_ready",
      detail: "authenticated"
    )
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

}

public struct MIRANativeRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: MIRATab = .home
  @State private var loadedTabs: Set<MIRATab> = [.home]
  @State private var isPrivacyShieldVisible = false
  @State private var featureStatusBarHidden = false
  @State private var isCreateMenuPresented = false
  @State private var isCommunityComposerPresented = false
  @State private var pendingCreateAction: AuraRootCreateAction?
  @State private var communityHomeRefreshID = UUID()
  @AppStorage(MIRAAppearanceResolver.preferenceKey) private var appearancePreference = MIRAAppearance.system.rawValue
  @StateObject private var authSession: MIRAAuthSession
  @StateObject private var startup: MIRAStartupCoordinator
  @StateObject private var localization: MIRALocalization
  @StateObject private var auraWallet: AuraWalletStore
  @StateObject private var auraGateway: AuraWalletGatewayStore
  @StateObject private var auraProofs: AuraProofLifecycleStore
  private let api: MIRAAPIClient

  public init() {
    let session = MIRAAuthSession()
    let client = MIRAAPIClient(sessionProvider: session)
    _authSession = StateObject(wrappedValue: session)
    _startup = StateObject(wrappedValue: MIRAStartupCoordinator(api: client))
    _localization = StateObject(wrappedValue: MIRALocalization.shared)
    _auraWallet = StateObject(wrappedValue: AuraWalletStore())
    _auraGateway = StateObject(wrappedValue: AuraWalletGatewayStore(api: client))
    _auraProofs = StateObject(wrappedValue: AuraProofLifecycleStore(api: client))
    self.api = client
    MIRAPerformanceTimeline.mark("backend_client_initialized")
    MIRAPerformanceTimeline.mark("native_root_init")
  }

  public var body: some View {
    ZStack {
      destinationView
        .opacity(startup.isSplashVisible ? 0.001 : 1)
        .allowsHitTesting(!startup.isSplashMounted)
        .animation(.easeInOut(duration: 0.28), value: startup.isSplashVisible)

      if startup.isSplashMounted {
        AuraStartupView(phase: startup.phase, showSlowMessage: startup.showSlowStartupCopy)
          .opacity(startup.isSplashVisible ? 1 : 0)
          .scaleEffect(startup.isSplashVisible ? 1 : 0.985)
          .zIndex(10)
      }

      if isPrivacyShieldVisible {
        MIRAPrivacyShieldView()
          .transition(.opacity)
          .zIndex(100)
      }
    }
    .background(MIRATheme.Color.launchBackground.ignoresSafeArea())
    .environmentObject(localization)
    .preferredColorScheme(MIRAAppearanceResolver.colorScheme(for: appearancePreference))
    .statusBarHidden(shouldHideStatusBar)
    .onPreferenceChange(MIRAStatusBarHiddenPreferenceKey.self) { hidden in
      featureStatusBarHidden = hidden
    }
    .onAppear {
      MIRAMainThreadStallMonitor.shared.start()
      MIRAPerformanceTimeline.markOnce("time_to_first_screen")
    }
    .task {
      await MIRAAppCacheStore.shared.clearPostDraftFromPreviousProcessIfNeeded()
      await MIRAAppCacheStore.shared.purgeRetiredHomeCachesIfNeeded()
      await startup.start(authSession: authSession)
      registerCachedPushTokenIfPossible()
    }
    .onChange(of: authSession.user?.id) { _, userID in
      if userID == nil {
        selectedTab = .home
        loadedTabs = [.home]
        isCreateMenuPresented = false
        isCommunityComposerPresented = false
        pendingCreateAction = nil
      } else {
        loadedTabs.insert(.home)
      }
      registerCachedPushTokenIfPossible()
    }
    .onChange(of: scenePhase) { _, phase in
      withAnimation(.easeOut(duration: phase == .active ? 0.18 : 0.06)) {
        isPrivacyShieldVisible = phase != .active
      }
      if phase == .active {
        registerCachedPushTokenIfPossible()
      } else {
        MIRAPlaybackCoordinator.pauseAll(reason: "app_inactive")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraRemotePushTokenReceived)) { notification in
      guard let token = notification.object as? String else { return }
      registerPushToken(token)
    }
    .onOpenURL { url in
      _ = GIDSignIn.sharedInstance.handle(url)
      authSession.handleIncomingURL(url)
    }
  }

  private var shouldHideStatusBar: Bool {
    startup.isSplashMounted || featureStatusBarHidden
  }

  @ViewBuilder
  private var destinationView: some View {
    if authSession.user == nil {
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
      lazyTab(.home) {
        if let currentUser = authSession.user {
          AuraHomeView(api: api, currentUser: currentUser)
            .id(communityHomeRefreshID)
        } else {
          Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MIRATheme.Color.paperCanvas)
        }
      }
        .tag(MIRATab.home)
        .tabItem { Label("Home", systemImage: "house.fill") }

      lazyTab(.scan) {
        AuraScanView(
          api: api,
          wallet: auraWallet,
          gateway: auraGateway,
          proofs: auraProofs
        )
      }
        .tag(MIRATab.scan)
        .tabItem { Label("Scan", systemImage: "viewfinder") }

      lazyTab(.wallet) {
        AuraWalletView(
          api: api,
          wallet: auraWallet,
          gateway: auraGateway,
          proofs: auraProofs
        )
      }
        .tag(MIRATab.wallet)
        .tabItem { Label("Wallet", systemImage: "wallet.pass.fill") }

      lazyTab(.me) {
        AuraMeView(
          api: api,
          authSession: authSession,
          wallet: auraWallet,
          gateway: auraGateway,
          proofs: auraProofs,
          openWallet: { selectedTab = .wallet }
        )
      }
        .tag(MIRATab.me)
        .tabItem { Label("Me", systemImage: "face.smiling") }
    }
    .tint(MIRATheme.Color.auraViolet)
    .toolbar(.hidden, for: .tabBar)
    .overlay(alignment: .bottom) {
      AuraTactileTabBar(selection: $selectedTab) {
        isCreateMenuPresented = true
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
      .zIndex(2)
    }
    .background(MIRATheme.Color.paperCanvas)
    .sheet(
      isPresented: $isCreateMenuPresented,
      onDismiss: openPendingCreateAction
    ) {
      AuraRootCreateSheet { action in
        pendingCreateAction = action
      }
      .presentationDetents([.height(300)])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
      .presentationBackground(MIRATheme.Color.paperCanvas)
    }
    .fullScreenCover(isPresented: $isCommunityComposerPresented) {
      if let currentUser = authSession.user {
        AuraCreateCommunityPostView(api: api, currentUser: currentUser) {
          isCommunityComposerPresented = false
          communityHomeRefreshID = UUID()
          selectedTab = .home
          loadedTabs.insert(.home)
        }
      }
    }
    .task {
      await auraProofs.observeLifecycle()
    }
    .task(id: auraWallet.identity?.address) {
      if let identity = auraWallet.identity {
        auraGateway.start(identity: identity)
      } else {
        auraGateway.clear()
      }
    }
    .onChange(of: selectedTab) { _, tab in
      MIRAPerformanceTimeline.mark("tab_switch", detail: "\(tab)")
      loadedTabs.insert(tab)
      MIRAPlaybackCoordinator.pauseAll(reason: "tab_changed")
    }
  }

  @ViewBuilder
  private func lazyTab<Content: View>(_ tab: MIRATab, @ViewBuilder content: () -> Content) -> some View {
    if shouldMountTab(tab) {
      content()
    } else {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MIRATheme.Color.paperCanvas)
    }
  }

  private func shouldMountTab(_ tab: MIRATab) -> Bool {
    return loadedTabs.contains(tab) || selectedTab == tab
  }

  private func openPendingCreateAction() {
    guard let action = pendingCreateAction else { return }
    pendingCreateAction = nil
    switch action {
    case .communityPost:
      guard authSession.user != nil else { return }
      isCommunityComposerPresented = true
    case .scanDocument:
      selectedTab = .scan
      loadedTabs.insert(.scan)
    }
  }

  private func registerCachedPushTokenIfPossible() {
    guard authSession.user != nil else { return }
    if let token = MIRAPushNotificationRegistrar.cachedDeviceToken {
      registerPushToken(token)
    } else {
      MIRAPushNotificationRegistrar.registerForRemoteNotifications()
    }
  }

  private func registerPushToken(_ token: String) {
    guard authSession.user != nil else { return }
    Task {
      await MIRAPushTokenRegistry.shared.registerDeviceToken(token, api: api)
    }
  }
}

private enum AuraRootCreateAction {
  case communityPost
  case scanDocument
}

private struct AuraTactileTabBar: View {
  @Binding var selection: MIRATab
  let onCreate: () -> Void

  private let items: [(tab: MIRATab, title: String, systemImage: String, selectedImage: String)] = [
    (.home, "Home", "house", "house.fill"),
    (.scan, "Scan", "viewfinder", "viewfinder"),
    (.wallet, "Wallet", "wallet.pass", "wallet.pass.fill"),
    (.me, "Me", "face.smiling", "face.smiling")
  ]

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 3) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          Button {
            selection = item.tab
          } label: {
            Image(systemName: selection == item.tab ? item.selectedImage : item.systemImage)
              .font(.system(size: 19, weight: .semibold))
              .foregroundStyle(
                selection == item.tab
                  ? MIRATheme.Color.auraViolet
                  : MIRATheme.Color.textPrimary.opacity(0.72)
              )
              .frame(width: 46, height: 46)
              .background(
                selection == item.tab ? MIRATheme.Color.auraVioletSoft : Color.clear,
                in: Circle()
              )
          }
          .buttonStyle(.plain)
          .contentShape(Circle())
          .accessibilityLabel(item.title)
          .accessibilityAddTraits(selection == item.tab ? .isSelected : [])
        }
      }
      .padding(6)
      .background(MIRATheme.Color.paperSurface, in: Capsule())
      .overlay {
        Capsule()
          .stroke(MIRATheme.Color.inkBorder.opacity(0.16), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.17), radius: 18, x: 0, y: 9)
      .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 2)

      Button(action: onCreate) {
        Image(systemName: "plus")
          .font(.system(size: 21, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary.opacity(0.72))
          .frame(width: 56, height: 56)
          .background(MIRATheme.Color.paperSurface, in: Circle())
          .overlay {
            Circle()
              .stroke(MIRATheme.Color.inkBorder.opacity(0.22), lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .contentShape(Circle())
      .shadow(color: Color.black.opacity(0.20), radius: 16, x: 0, y: 8)
      .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
      .accessibilityLabel("Create")
    }
    .frame(maxWidth: .infinity)
  }
}

private struct AuraRootCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  let onSelect: (AuraRootCreateAction) -> Void

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Text("Choose what you want to make in Aura.")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)

        createRow(
          title: "Post or Meetup",
          subtitle: "Share with your community",
          systemImage: "square.and.pencil",
          action: .communityPost
        )

        createRow(
          title: "Scan Document",
          subtitle: "Scan or import a receipt or invoice",
          systemImage: "viewfinder",
          action: .scanDocument
        )

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 18)
      .padding(.top, 6)
      .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.circle)
          .accessibilityLabel("Close")
        }
      }
    }
  }

  private func createRow(
    title: String,
    subtitle: String,
    systemImage: String,
    action: AuraRootCreateAction
  ) -> some View {
    Button {
      onSelect(action)
      dismiss()
    } label: {
      HStack(spacing: 14) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .frame(width: 42, height: 42)
          .background(MIRATheme.Color.auraVioletSoft, in: Circle())

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }

        Spacer(minLength: 8)

        Image(systemName: "chevron.right")
          .font(.footnote.weight(.bold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(MIRATheme.Color.paperSurface)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(MIRATheme.Color.inkBorder.opacity(0.16), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
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

            Text("This Aura account is scheduled for deletion. Restore it now to keep using it, or sign out and deletion will continue.")
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
      AuraWordmarkView()
        .scaleEffect(0.74)
        .opacity(0.92)
        .accessibilityHidden(true)
    }
  }
}

private struct AuraStartupView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let phase: MIRAStartupPhase
  let showSlowMessage: Bool
  @State private var appeared = false

  var body: some View {
    ZStack {
      MIRATheme.Color.launchBackground.ignoresSafeArea()

      VStack(spacing: MIRATheme.Space.xl) {
        VStack(spacing: MIRATheme.Space.sm) {
          AuraWordmarkView()
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.96))
            .opacity(appeared ? 1 : 0)

          Rectangle()
            .fill(Color.black.opacity(0.72))
            .frame(width: 128, height: 1)
            .opacity(appeared ? 1 : 0)

          Text("verified purchases, real reputation")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.52))
            .opacity(appeared ? 1 : 0)
        }

        VStack(spacing: MIRATheme.Space.sm) {
          AuraStartupPulse()
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

private struct AuraWordmarkView: View {
  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        Image(systemName: "hexagon")
          .font(.system(size: 48, weight: .semibold))
        Circle()
          .stroke(lineWidth: 3)
          .frame(width: 20, height: 20)
      }
      .foregroundStyle(MIRATheme.Color.forest)

      Text("AURA")
        .font(.system(size: 44, weight: .bold, design: .rounded))
        .tracking(4)
        .foregroundStyle(MIRATheme.Color.textPrimary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Aura")
  }
}

private struct AuraStartupPulse: View {
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
