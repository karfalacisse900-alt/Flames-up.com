import Foundation

@MainActor private final class MIRAAuthRefreshCoordinator {
  private var inFlight: (id: UUID, token: String, task: Task<MIRAAuthResponse, Error>)?

  func cancel() {
    inFlight?.task.cancel()
    inFlight = nil
  }

  func refresh(api: MIRAAPIClient, refreshToken: String) async throws -> MIRAAuthResponse {
    if let inFlight, inFlight.token == refreshToken {
      return try await inFlight.task.value
    }
    cancel()
    let id = UUID()
    let task = Task<MIRAAuthResponse, Error> {
      try await api.post(
        "/auth/refresh",
        body: MIRARefreshSessionBody(refreshToken: refreshToken)
      )
    }
    inFlight = (id, refreshToken, task)
    defer { if inFlight?.id == id { inFlight = nil } }
    return try await task.value
  }
}

public struct MIRAPasswordResetContext: Equatable {
  public let accessToken: String
  public let refreshToken: String?
  public let email: String?
}

/// Keep session lifecycle tests independent of the app's Keychain entitlement.
/// Production continues to use the same Keychain implementation by default.
public protocol MIRAAuthSessionStorage: MIRASessionProviding {
  func refreshToken() async -> String?
  func saveSession(accessToken: String, refreshToken: String?)
  func clearSession()
}

extension MIRAKeychainSessionProvider: MIRAAuthSessionStorage {}

@MainActor public final class MIRAAuthSession: ObservableObject, MIRARefreshableSessionProviding {
  @Published public private(set) var user: MIRAUser?
  @Published public private(set) var isGuest: Bool
  @Published public private(set) var isBootstrapping = true
  @Published public private(set) var isWorking = false
  @Published public var errorMessage: String?
  @Published public var passwordResetContext: MIRAPasswordResetContext?

  private let keychain: MIRAAuthSessionStorage
  private let defaults: UserDefaults
  private var token: String?
  private var refreshToken: String?
  private let refreshCoordinator = MIRAAuthRefreshCoordinator()
  private var cachedRefreshTask: Task<Void, Never>?
  // Session identity, not token identity: refresh rotation must not invalidate
  // legitimate in-flight work, but logout/login must invalidate all old work.
  public private(set) var sessionGeneration: UInt64 = 0
  private let cachedUserKey = "native.auth.user.v2"
  private static let guestModeKey = "native.auth.guest.v1"

  public init(
    keychain: MIRAAuthSessionStorage = MIRAKeychainSessionProvider(),
    defaults: UserDefaults = .standard
  ) {
    self.keychain = keychain
    self.defaults = defaults
    self.isGuest = defaults.bool(forKey: Self.guestModeKey)
  }

  public func accessToken() async -> String? {
    if let token {
      return token
    }
    let generation = sessionGeneration
    let stored = await keychain.accessToken()
    return generation == sessionGeneration ? stored : nil
  }

  public func refreshAccessTokenIfNeeded(api: MIRAAPIClient) async -> Bool {
    let generation = sessionGeneration
    let expectedUserID = user?.id
    let keychainRefreshToken = await keychain.refreshToken()
    guard generation == sessionGeneration else { return false }
    let storedRefreshToken = refreshToken ?? keychainRefreshToken
    guard let storedRefreshToken, !storedRefreshToken.isEmpty else { return false }

    do {
      let response = try await refreshCoordinator.refresh(api: api, refreshToken: storedRefreshToken)
      guard generation == sessionGeneration, !Task.isCancelled,
            expectedUserID == nil || expectedUserID == response.user.id else { return false }
      token = response.accessToken
      refreshToken = response.refreshToken ?? storedRefreshToken
      MIRALocalJSONCache.setAccountScope(userId: response.user.id)
      user = response.user
      keychain.saveSession(accessToken: response.accessToken, refreshToken: refreshToken)
      await persistProfile(response.user)
      guard generation == sessionGeneration else { return false }
      errorMessage = nil
      return true
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      let shouldInvalidateSession = error.isUnauthorizedAPIError || error.isForbiddenAPIError
      guard shouldInvalidateSession else {
        errorMessage = nil
        return false
      }
      clearSessionState()
      return false
    }
  }

  @MainActor
  public func bootstrap(api: MIRAAPIClient) async {
    let generation = sessionGeneration
    MIRAPerformanceTimeline.mark("auth_bootstrap_start")
    MIRAAuthDiagnostics.sessionStage("restore_started")
    isBootstrapping = true
    let storedToken = await keychain.accessToken()
    guard generation == sessionGeneration else { return }
    guard let storedToken, !storedToken.isEmpty else {
      MIRALocalJSONCache.setAccountScope(userId: nil)
      token = nil
      refreshToken = nil
      user = nil
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_bootstrap_no_token")
      MIRAAuthDiagnostics.sessionStage("restore_no_session")
      return
    }

    token = storedToken
    let storedRefreshToken = await keychain.refreshToken()
    guard generation == sessionGeneration else { return }
    refreshToken = storedRefreshToken
    setGuestMode(false)

    var cachedUser = await MIRAAppCacheStore.shared.loadCurrentProfile()
    if cachedUser == nil {
      cachedUser = await MIRALocalJSONCache.load(MIRAUser.self, key: cachedUserKey)
    }
    guard generation == sessionGeneration else { return }
    if let cachedUser {
      MIRALocalJSONCache.setAccountScope(userId: cachedUser.id)
      user = cachedUser
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_cached_user_ready")
      MIRAAuthDiagnostics.sessionStage("restore_cached_session")
      cachedRefreshTask?.cancel()
      cachedRefreshTask = Task { await refreshCachedSession(api: api, generation: generation) }
      return
    }

    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      MIRALocalJSONCache.setAccountScope(userId: freshUser.id)
      user = freshUser
      await persistProfile(freshUser)
      guard generation == sessionGeneration else { return }
      errorMessage = nil
      MIRAAuthDiagnostics.sessionStage("restore_succeeded")
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      if (error.isUnauthorizedAPIError || error.isForbiddenAPIError), await refreshAccessTokenIfNeeded(api: api) {
        do {
          let refreshedUser: MIRAUser = try await api.get("/auth/me")
          guard generation == sessionGeneration, !Task.isCancelled else { return }
          MIRALocalJSONCache.setAccountScope(userId: refreshedUser.id)
          user = refreshedUser
          await persistProfile(refreshedUser)
          guard generation == sessionGeneration else { return }
          errorMessage = nil
          MIRAAuthDiagnostics.sessionStage("restore_refreshed")
        } catch {
          guard generation == sessionGeneration, !Task.isCancelled else { return }
          clearSessionState()
          MIRAAuthDiagnostics.sessionStage("restore_rejected")
        }
      } else if error.isUnauthorizedAPIError || error.isForbiddenAPIError {
        guard generation == sessionGeneration else { return }
        clearSessionState()
        MIRAAuthDiagnostics.sessionStage("restore_rejected")
      } else {
        // Keep the stored session intact on transient/network failures so the
        // user is not signed out unexpectedly during bootstrap.
        errorMessage = nil
        MIRAAuthDiagnostics.sessionStage("restore_deferred_network")
      }
    }
    isBootstrapping = false
    MIRAPerformanceTimeline.mark("auth_bootstrap_finished", detail: user == nil ? "signed_out" : "signed_in")
  }

  @MainActor
  private func refreshCachedSession(api: MIRAAPIClient, generation: UInt64) async {
    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      guard generation == sessionGeneration, !Task.isCancelled, user?.id == freshUser.id else { return }
      MIRALocalJSONCache.setAccountScope(userId: freshUser.id)
      user = freshUser
      await persistProfile(freshUser)
      guard generation == sessionGeneration else { return }
      errorMessage = nil
      MIRAPerformanceTimeline.mark("auth_cached_user_refreshed")
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      if (error.isUnauthorizedAPIError || error.isForbiddenAPIError), await refreshAccessTokenIfNeeded(api: api) {
        do {
          let refreshedUser: MIRAUser = try await api.get("/auth/me")
          guard generation == sessionGeneration, !Task.isCancelled, user?.id == refreshedUser.id else { return }
          MIRALocalJSONCache.setAccountScope(userId: refreshedUser.id)
          user = refreshedUser
          await persistProfile(refreshedUser)
          guard generation == sessionGeneration else { return }
          errorMessage = nil
          MIRAPerformanceTimeline.mark("auth_cached_user_recovered")
        } catch {
          guard generation == sessionGeneration, !Task.isCancelled else { return }
          clearSessionState()
          MIRAPerformanceTimeline.mark("auth_cached_user_rejected")
        }
      } else if error.isUnauthorizedAPIError || error.isForbiddenAPIError {
        guard generation == sessionGeneration else { return }
        clearSessionState()
        MIRAPerformanceTimeline.mark("auth_cached_user_rejected")
      }
    }
  }

  @MainActor
  public func login(email: String, password: String, termsVersion: String? = nil, termsAcceptedAt: String? = nil, api: MIRAAPIClient) async {
    await authenticate(provider: .email) {
      try await api.post("/auth/login", body: MIRAAuthLoginBody(email: email, password: password, termsVersion: termsVersion, termsAcceptedAt: termsAcceptedAt))
    }
  }

  @MainActor
  public func register(email: String, password: String, username: String, fullName: String, termsVersion: String? = nil, termsAcceptedAt: String? = nil, api: MIRAAPIClient) async {
    await authenticate(provider: .email) {
      try await api.post(
        "/auth/register",
        body: MIRAAuthRegisterBody(email: email, password: password, username: username, fullName: fullName, termsVersion: termsVersion, termsAcceptedAt: termsAcceptedAt)
      )
    }
  }

  @discardableResult
  @MainActor
  public func signInWithApple(idToken: String, email: String?, fullName: String?, appleUser: String?, nonce: String?, termsVersion: String? = nil, termsAcceptedAt: String? = nil, api: MIRAAPIClient) async -> Bool {
    await authenticate(provider: .apple) {
      try await api.post(
        "/auth/oauth/apple",
        body: MIRAAppleOAuthBody(idToken: idToken, email: email, fullName: fullName, appleUser: appleUser, nonce: nonce, termsVersion: termsVersion, termsAcceptedAt: termsAcceptedAt)
      )
    }
  }

  @discardableResult
  @MainActor
  public func signInWithGoogle(idToken: String, accessToken: String?, termsVersion: String? = nil, termsAcceptedAt: String? = nil, api: MIRAAPIClient) async -> Bool {
    await authenticate(provider: .google) {
      try await api.post("/auth/oauth/google", body: MIRAGoogleOAuthBody(idToken: idToken, accessToken: accessToken, termsVersion: termsVersion, termsAcceptedAt: termsAcceptedAt))
    }
  }

  @MainActor
  public func requestPasswordReset(email: String, api: MIRAAPIClient) async -> Bool {
    guard !isWorking else { return false }
    let generation = sessionGeneration
    isWorking = true
    errorMessage = nil
    defer { if generation == sessionGeneration { isWorking = false } }
    do {
      let _: MIRAPasswordResetRequestResponse = try await api.post(
        "/auth/password/reset/request",
        body: MIRAPasswordResetRequestBody(email: email, redirectTo: "https://captro.app/auth/reset-password")
      )
      return generation == sessionGeneration
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      if let apiError = error as? MIRAAPIError,
         let message = apiError.errorDescription,
         !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorMessage = message
      } else {
        errorMessage = "Could not send the reset email right now."
      }
      return false
    }
  }

  @MainActor
  public func completePasswordReset(password: String, api: MIRAAPIClient) async -> Bool {
    guard !isWorking else { return false }
    guard let passwordResetContext else {
      errorMessage = "Reset session is missing. Open the email link again."
      return false
    }
    invalidateSessionWork()
    let generation = sessionGeneration
    isWorking = true
    errorMessage = nil
    defer { if generation == sessionGeneration { isWorking = false } }
    do {
      let response: MIRAAuthResponse = try await api.post(
        "/auth/password/reset/confirm",
        body: MIRAPasswordResetConfirmBody(
          accessToken: passwordResetContext.accessToken,
          refreshToken: passwordResetContext.refreshToken,
          password: password
        )
      )
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      token = response.accessToken
      refreshToken = response.refreshToken
      MIRALocalJSONCache.setAccountScope(userId: response.user.id)
      user = response.user
      setGuestMode(false)
      isBootstrapping = false
      self.passwordResetContext = nil
      keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
      await persistProfile(response.user)
      return generation == sessionGeneration
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      if let apiError = error as? MIRAAPIError,
         let message = apiError.errorDescription,
         !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorMessage = message
      } else {
        errorMessage = "Could not reset the password right now."
      }
      return false
    }
  }

  @MainActor
  public func clearPasswordResetContext() {
    passwordResetContext = nil
    errorMessage = nil
  }

  @MainActor
  public func handleIncomingURL(_ url: URL) {
    guard let context = passwordResetContext(from: url) else { return }
    passwordResetContext = context
    errorMessage = nil
  }

  @MainActor
  public func continueAsGuest() {
    MIRAPlaybackCoordinator.pauseAll(reason: "account_switched_to_guest")
    clearSessionState()
    setGuestMode(true)
  }

  @MainActor
  public func exitGuestMode() {
    setGuestMode(false)
    errorMessage = nil
  }

  @MainActor
  public func logout() {
    MIRAPlaybackCoordinator.pauseAll(reason: "account_signed_out")
    clearSessionState()
    setGuestMode(false)
  }

  @MainActor
  public func replaceUser(_ updatedUser: MIRAUser) {
    guard updatedUser.id == user?.id else { return }
    user = updatedUser
    setGuestMode(false)
    Task {
      await persistProfile(updatedUser)
    }
  }

  @MainActor
  @discardableResult
  private func authenticate(
    provider: MIRAAuthProvider,
    _ operation: () async throws -> MIRAAuthResponse
  ) async -> Bool {
    guard !isWorking else {
      MIRAAuthDiagnostics.stage(provider, "duplicate_request_ignored")
      return false
    }
    invalidateSessionWork()
    let generation = sessionGeneration
    isWorking = true
    errorMessage = nil
    defer { if generation == sessionGeneration { isWorking = false } }
    do {
      MIRAAuthDiagnostics.stage(provider, "credential_exchange_started")
      let response = try await operation()
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      guard !response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw MIRAAPIError.emptyResponse
      }
      MIRAAuthDiagnostics.stage(provider, "backend_session_created")
      token = response.accessToken
      refreshToken = response.refreshToken
      MIRALocalJSONCache.setAccountScope(userId: response.user.id)
      user = response.user
      setGuestMode(false)
      isBootstrapping = false
      keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
      MIRAAuthDiagnostics.stage(provider, "session_persisted")
      await persistProfile(response.user)
      guard generation == sessionGeneration else { return false }
      MIRAAuthDiagnostics.stage(provider, "auth_state_updated")
      return true
    } catch {
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      MIRAAuthDiagnostics.failure(provider, stage: "credential_exchange", error: error)
      if provider == .google {
        errorMessage = "Could not sign in with Google. Please try again."
      } else if provider == .apple {
        errorMessage = "Could not sign in with Apple. Please try again."
      } else if let apiError = error as? MIRAAPIError,
                let message = apiError.errorDescription,
                !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorMessage = message
      } else {
        errorMessage = "Could not sign in. Check your account and try again."
      }
      return false
    }
  }

  private func invalidateSessionWork() {
    sessionGeneration &+= 1
    refreshCoordinator.cancel()
    cachedRefreshTask?.cancel()
    cachedRefreshTask = nil
  }

  private func clearSessionState() {
    invalidateSessionWork()
    // Capture the old binding before clearing credentials. Its DELETE uses a
    // pinned client, never whatever account happens to sign in next.
    MIRAPushTokenRegistry.shared.endSession()
    MIRALocalJSONCache.setAccountScope(userId: nil)
    token = nil
    refreshToken = nil
    user = nil
    errorMessage = nil
    passwordResetContext = nil
    isWorking = false
    isBootstrapping = false
    keychain.clearSession()
    MIRAAPIClient.productionSession.configuration.urlCache?.removeAllCachedResponses()
    // Caches/drafts are already account-namespaced. Delayed global cleanup here
    // used to erase the next account's draft/cache after a rapid re-login.
  }

  private func persistProfile(_ profile: MIRAUser) async {
    await MIRAAppCacheStore.shared.saveCurrentProfile(profile)
    await MIRALocalJSONCache.save(profile, key: cachedUserKey, accountUserID: profile.id)
  }

  @MainActor
  private func setGuestMode(_ enabled: Bool) {
    isGuest = enabled
    defaults.set(enabled, forKey: Self.guestModeKey)
  }

  private func passwordResetContext(from url: URL) -> MIRAPasswordResetContext? {
    let scheme = (url.scheme ?? "").lowercased()
    let host = (url.host ?? "").lowercased()
    let isCaptroScheme = scheme == "captro" && host == "auth" && url.path == "/reset-password"
    let isCaptroWebReset = scheme == "https" && (host == "captro.app" || host == "www.captro.app") && url.path == "/auth/reset-password"
    guard isCaptroScheme || isCaptroWebReset else { return nil }

    var values: [String: String] = [:]
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      for item in components.queryItems ?? [] {
        values[item.name] = item.value ?? ""
      }
    }
    if let fragment = url.fragment, !fragment.isEmpty {
      let fragmentItems = fragment.split(separator: "&")
      for entry in fragmentItems {
        let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
        guard let name = parts.first, !name.isEmpty else { continue }
        let rawValue = parts.count > 1 ? parts[1] : ""
        values[name.removingPercentEncoding ?? name] = rawValue.removingPercentEncoding ?? rawValue
      }
    }

    let resetType = (values["type"] ?? "").lowercased()
    let accessToken = values["access_token"] ?? values["accessToken"] ?? ""
    if !resetType.isEmpty && resetType != "recovery" { return nil }
    guard !accessToken.isEmpty else { return nil }

    return MIRAPasswordResetContext(
      accessToken: accessToken,
      refreshToken: values["refresh_token"] ?? values["refreshToken"],
      email: values["email"]
    )
  }
}

private extension Error {
  var isUnauthorizedAPIError: Bool {
    guard let apiError = self as? MIRAAPIError else { return false }
    if case .badStatus(let status) = apiError, status == 401 { return true }
    if case .server(let status, _, _) = apiError, status == 401 { return true }
    return false
  }

  var isForbiddenAPIError: Bool {
    guard let apiError = self as? MIRAAPIError else { return false }
    if case .badStatus(let status) = apiError, status == 403 { return true }
    if case .server(let status, _, _) = apiError, status == 403 { return true }
    return false
  }
}
