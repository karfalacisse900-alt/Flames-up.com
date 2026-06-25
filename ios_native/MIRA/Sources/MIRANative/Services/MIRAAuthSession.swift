import Foundation

public final class MIRAAuthSession: ObservableObject, MIRARefreshableSessionProviding {
  @Published public private(set) var user: MIRAUser?
  @Published public private(set) var isBootstrapping = true
  @Published public private(set) var isWorking = false
  @Published public var errorMessage: String?

  private let keychain: MIRAKeychainSessionProvider
  private var token: String?
  private var refreshToken: String?
  private let cachedUserKey = "native.auth.user.v2"

  public init(keychain: MIRAKeychainSessionProvider = MIRAKeychainSessionProvider()) {
    self.keychain = keychain
  }

  public func accessToken() async -> String? {
    if let token {
      return token
    }
    return await keychain.accessToken()
  }

  public func refreshAccessTokenIfNeeded(api: MIRAAPIClient) async -> Bool {
    if isWorking { return false }
    let storedRefreshToken = refreshToken ?? await keychain.refreshToken()
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
    isBootstrapping = true
    guard let storedToken = await keychain.accessToken(), !storedToken.isEmpty else {
      token = nil
      refreshToken = nil
      user = nil
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_bootstrap_no_token")
      return
    }

    token = storedToken
    refreshToken = await keychain.refreshToken()

    var cachedUser = await MIRAAppCacheStore.shared.loadCurrentProfile()
    if cachedUser == nil {
      cachedUser = await MIRALocalJSONCache.load(MIRAUser.self, key: cachedUserKey)
    }
    if let cachedUser {
      user = cachedUser
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_cached_user_ready")
      Task { await refreshCachedSession(api: api) }
      return
    }

    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      user = freshUser
      await MIRAAppCacheStore.shared.saveCurrentProfile(freshUser)
      await MIRALocalJSONCache.save(freshUser, key: cachedUserKey)
      errorMessage = nil
    } catch {
      if (error.isUnauthorizedAPIError || error.isForbiddenAPIError), await refreshAccessTokenIfNeeded(api: api) {
        do {
          let refreshedUser: MIRAUser = try await api.get("/auth/me")
          user = refreshedUser
          await MIRAAppCacheStore.shared.saveCurrentProfile(refreshedUser)
          await MIRALocalJSONCache.save(refreshedUser, key: cachedUserKey)
          errorMessage = nil
        } catch {
          token = nil
          refreshToken = nil
          user = nil
          keychain.clearSession()
          await MIRALocalJSONCache.remove(key: cachedUserKey)
        }
      } else if error.isUnauthorizedAPIError || error.isForbiddenAPIError {
        token = nil
        refreshToken = nil
        user = nil
        keychain.clearSession()
        await MIRALocalJSONCache.remove(key: cachedUserKey)
      } else if user == nil {
        token = nil
        refreshToken = nil
        keychain.clearSession()
        await MIRALocalJSONCache.remove(key: cachedUserKey)
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
  public func login(email: String, password: String, api: MIRAAPIClient) async {
    await authenticate {
      try await api.post("/auth/login", body: MIRAAuthLoginBody(email: email, password: password))
    }
  }

  @MainActor
  public func register(email: String, password: String, username: String, fullName: String, api: MIRAAPIClient) async {
    await authenticate {
      try await api.post(
        "/auth/register",
        body: MIRAAuthRegisterBody(email: email, password: password, username: username, fullName: fullName)
      )
    }
  }

  @MainActor
  public func signInWithApple(idToken: String, email: String?, fullName: String?, appleUser: String?, nonce: String?, api: MIRAAPIClient) async {
    await authenticate {
      try await api.post(
        "/auth/oauth/apple",
        body: MIRAAppleOAuthBody(idToken: idToken, email: email, fullName: fullName, appleUser: appleUser, nonce: nonce)
      )
    }
  }

  @MainActor
  public func signInWithGoogle(idToken: String, accessToken: String?, api: MIRAAPIClient) async {
    await authenticate {
      try await api.post("/auth/oauth/google", body: MIRAGoogleOAuthBody(idToken: idToken, accessToken: accessToken))
    }
  }

  @MainActor
  public func logout() {
    token = nil
    refreshToken = nil
    user = nil
    errorMessage = nil
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
    Task {
      await MIRAAppCacheStore.shared.saveCurrentProfile(updatedUser)
      await MIRALocalJSONCache.save(updatedUser, key: cachedUserKey)
    }
  }

  @MainActor
  private func authenticate(_ operation: () async throws -> MIRAAuthResponse) async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let response = try await operation()
      token = response.accessToken
      refreshToken = response.refreshToken
      user = response.user
      keychain.saveSession(accessToken: response.accessToken, refreshToken: response.refreshToken)
      await MIRAAppCacheStore.shared.saveCurrentProfile(response.user)
      await MIRALocalJSONCache.save(response.user, key: cachedUserKey)
    } catch {
      if let apiError = error as? MIRAAPIError,
         let message = apiError.errorDescription,
         !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorMessage = message
      } else {
        errorMessage = "Could not sign in. Check your account and try again."
      }
    }
  }
}

private extension Error {
  var isUnauthorizedAPIError: Bool {
    if case MIRAAPIError.badStatus(let status) = self, status == 401 { return true }
    if case MIRAAPIError.server(let status, _, _) = self, status == 401 { return true }
    return false
  }

  var isForbiddenAPIError: Bool {
    if case MIRAAPIError.badStatus(let status) = self, status == 403 { return true }
    if case MIRAAPIError.server(let status, _, _) = self, status == 403 { return true }
    return false
  }
}
