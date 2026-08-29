import Foundation

public struct MIRAPasswordResetContext: Equatable {
  public let accessToken: String
  public let refreshToken: String?
  public let email: String?
}

public final class MIRAAuthSession: ObservableObject, MIRARefreshableSessionProviding {
  @Published public private(set) var user: MIRAUser?
  @Published public private(set) var isGuest: Bool
  @Published public private(set) var isBootstrapping = true
  @Published public private(set) var isWorking = false
  @Published public var errorMessage: String?
  @Published public var passwordResetContext: MIRAPasswordResetContext?

  private let keychain: MIRAKeychainSessionProvider
  private let defaults: UserDefaults
  private var token: String?
  private var refreshToken: String?
  private let cachedUserKey = "native.auth.user.v2"
  private static let guestModeKey = "native.auth.guest.v1"

  public init(
    keychain: MIRAKeychainSessionProvider = MIRAKeychainSessionProvider(),
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
    return await keychain.accessToken()
  }

  public func refreshAccessTokenIfNeeded(api: MIRAAPIClient) async -> Bool {
    if isWorking { return false }
    let keychainRefreshToken = await keychain.refreshToken()
    let storedRefreshToken = refreshToken ?? keychainRefreshToken
    guard let storedRefreshToken, !storedRefreshToken.isEmpty else { return false }

    do {
      let response: MIRAAuthResponse = try await api.post(
        "/auth/refresh",
        body: MIRARefreshSessionBody(refreshToken: storedRefreshToken)
      )
      await MainActor.run {
        token = response.accessToken
        refreshToken = response.refreshToken ?? storedRefreshToken
        user = response.user
        keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken ?? storedRefreshToken)
      }
      await MIRAAppCacheStore.shared.saveCurrentProfile(response.user)
      await MIRALocalJSONCache.save(response.user, key: cachedUserKey)
      await MainActor.run {
        errorMessage = nil
      }
      return true
    } catch {
      let shouldInvalidateSession = error.isUnauthorizedAPIError || error.isForbiddenAPIError
      guard shouldInvalidateSession else {
        await MainActor.run {
          errorMessage = nil
        }
        return false
      }
      await MainActor.run {
        token = nil
        refreshToken = nil
        user = nil
        errorMessage = nil
        keychain.clearSession()
      }
      await MIRALocalJSONCache.remove(key: cachedUserKey)
      return false
    }
  }

  @MainActor
  public func bootstrap(api: MIRAAPIClient) async {
    MIRAPerformanceTimeline.mark("auth_bootstrap_start")
    MIRAAuthDiagnostics.sessionStage("restore_started")
    isBootstrapping = true
    guard let storedToken = await keychain.accessToken(), !storedToken.isEmpty else {
      token = nil
      refreshToken = nil
      user = nil
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_bootstrap_no_token")
      MIRAAuthDiagnostics.sessionStage("restore_no_session")
      return
    }

    token = storedToken
    refreshToken = await keychain.refreshToken()
    setGuestMode(false)

    var cachedUser = await MIRAAppCacheStore.shared.loadCurrentProfile()
    if cachedUser == nil {
      cachedUser = await MIRALocalJSONCache.load(MIRAUser.self, key: cachedUserKey)
    }
    if let cachedUser {
      user = cachedUser
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_cached_user_ready")
      MIRAAuthDiagnostics.sessionStage("restore_cached_session")
      Task { await refreshCachedSession(api: api) }
      return
    }

    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      user = freshUser
      await MIRAAppCacheStore.shared.saveCurrentProfile(freshUser)
      await MIRALocalJSONCache.save(freshUser, key: cachedUserKey)
      errorMessage = nil
      MIRAAuthDiagnostics.sessionStage("restore_succeeded")
    } catch {
      if (error.isUnauthorizedAPIError || error.isForbiddenAPIError), await refreshAccessTokenIfNeeded(api: api) {
        do {
          let refreshedUser: MIRAUser = try await api.get("/auth/me")
          user = refreshedUser
          await MIRAAppCacheStore.shared.saveCurrentProfile(refreshedUser)
          await MIRALocalJSONCache.save(refreshedUser, key: cachedUserKey)
          errorMessage = nil
          MIRAAuthDiagnostics.sessionStage("restore_refreshed")
        } catch {
          token = nil
          refreshToken = nil
          user = nil
          keychain.clearSession()
          await MIRALocalJSONCache.remove(key: cachedUserKey)
          MIRAAuthDiagnostics.sessionStage("restore_rejected")
        }
      } else if error.isUnauthorizedAPIError || error.isForbiddenAPIError {
        token = nil
        refreshToken = nil
        user = nil
        keychain.clearSession()
        await MIRALocalJSONCache.remove(key: cachedUserKey)
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
  private func refreshCachedSession(api: MIRAAPIClient) async {
    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      user = freshUser
      await MIRAAppCacheStore.shared.saveCurrentProfile(freshUser)
      await MIRALocalJSONCache.save(freshUser, key: cachedUserKey)
      errorMessage = nil
      MIRAPerformanceTimeline.mark("auth_cached_user_refreshed")
    } catch {
      if (error.isUnauthorizedAPIError || error.isForbiddenAPIError), await refreshAccessTokenIfNeeded(api: api) {
        do {
          let refreshedUser: MIRAUser = try await api.get("/auth/me")
          user = refreshedUser
          await MIRAAppCacheStore.shared.saveCurrentProfile(refreshedUser)
          await MIRALocalJSONCache.save(refreshedUser, key: cachedUserKey)
          errorMessage = nil
          MIRAPerformanceTimeline.mark("auth_cached_user_recovered")
        } catch {
          token = nil
          refreshToken = nil
          user = nil
          keychain.clearSession()
          await MIRALocalJSONCache.remove(key: cachedUserKey)
          MIRAPerformanceTimeline.mark("auth_cached_user_rejected")
        }
      } else if error.isUnauthorizedAPIError || error.isForbiddenAPIError {
        token = nil
        refreshToken = nil
        user = nil
        keychain.clearSession()
        await MIRALocalJSONCache.remove(key: cachedUserKey)
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
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let _: MIRAPasswordResetRequestResponse = try await api.post(
        "/auth/password/reset/request",
        body: MIRAPasswordResetRequestBody(email: email, redirectTo: "https://captro.app/auth/reset-password")
      )
      return true
    } catch {
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
    guard let passwordResetContext else {
      errorMessage = "Reset session is missing. Open the email link again."
      return false
    }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let response: MIRAAuthResponse = try await api.post(
        "/auth/password/reset/confirm",
        body: MIRAPasswordResetConfirmBody(
          accessToken: passwordResetContext.accessToken,
          refreshToken: passwordResetContext.refreshToken,
          password: password
        )
      )
      token = response.accessToken
      refreshToken = response.refreshToken
      user = response.user
      setGuestMode(false)
      self.passwordResetContext = nil
      keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
      await MIRAAppCacheStore.shared.saveCurrentProfile(response.user)
      await MIRALocalJSONCache.save(response.user, key: cachedUserKey)
      return true
    } catch {
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
    token = nil
    refreshToken = nil
    user = nil
    errorMessage = nil
    passwordResetContext = nil
    setGuestMode(true)
    keychain.clearSession()
    MIRAAPIClient.productionSession.configuration.urlCache?.removeAllCachedResponses()
    Task {
      await MIRALocalJSONCache.remove(key: cachedUserKey)
      await MIRAPostEngagementSync.clearCachedState()
    }
  }

  @MainActor
  public func exitGuestMode() {
    setGuestMode(false)
    errorMessage = nil
  }

  @MainActor
  public func logout() {
    token = nil
    refreshToken = nil
    user = nil
    errorMessage = nil
    setGuestMode(false)
    keychain.clearSession()
    MIRAAPIClient.productionSession.configuration.urlCache?.removeAllCachedResponses()
    Task {
      await MIRALocalJSONCache.remove(key: cachedUserKey)
      await MIRAPostEngagementSync.clearCachedState()
    }
  }

  @MainActor
  public func replaceUser(_ updatedUser: MIRAUser) {
    user = updatedUser
    setGuestMode(false)
    Task {
      await MIRAAppCacheStore.shared.saveCurrentProfile(updatedUser)
      await MIRALocalJSONCache.save(updatedUser, key: cachedUserKey)
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
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      MIRAAuthDiagnostics.stage(provider, "credential_exchange_started")
      let response = try await operation()
      guard !response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw MIRAAPIError.emptyResponse
      }
      MIRAAuthDiagnostics.stage(provider, "backend_session_created")
      token = response.accessToken
      refreshToken = response.refreshToken
      user = response.user
      setGuestMode(false)
      keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
      MIRAAuthDiagnostics.stage(provider, "session_persisted")
      await MIRAAppCacheStore.shared.saveCurrentProfile(response.user)
      await MIRALocalJSONCache.save(response.user, key: cachedUserKey)
      MIRAAuthDiagnostics.stage(provider, "auth_state_updated")
      return true
    } catch {
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
