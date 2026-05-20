import Foundation

public final class MIRAAuthSession: ObservableObject, MIRASessionProviding {
  @Published public private(set) var user: MIRAUser?
  @Published public private(set) var isBootstrapping = true
  @Published public private(set) var isWorking = false
  @Published public var errorMessage: String?

  private let keychain: MIRAKeychainSessionProvider
  private var token: String?
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

  @MainActor
  public func bootstrap(api: MIRAAPIClient) async {
    MIRAPerformanceTimeline.mark("auth_bootstrap_start")
    isBootstrapping = true
    guard let storedToken = await keychain.accessToken(), !storedToken.isEmpty else {
      token = nil
      user = nil
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_bootstrap_no_token")
      return
    }

    token = storedToken

    if let cachedUser: MIRAUser = await MIRALocalJSONCache.load(MIRAUser.self, key: cachedUserKey) {
      user = cachedUser
      isBootstrapping = false
      MIRAPerformanceTimeline.mark("auth_cached_user_ready")
    }

    do {
      let freshUser: MIRAUser = try await api.get("/auth/me")
      user = freshUser
      await MIRALocalJSONCache.save(freshUser, key: cachedUserKey)
      errorMessage = nil
    } catch {
      if case MIRAAPIError.badStatus(let status) = error, status == 401 || status == 403 {
        token = nil
        user = nil
        keychain.clearAccessToken()
      } else if user == nil {
        token = nil
        keychain.clearAccessToken()
      }
    }
    isBootstrapping = false
    MIRAPerformanceTimeline.mark("auth_bootstrap_finished", detail: user == nil ? "signed_out" : "signed_in")
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
  public func signInWithApple(idToken: String, email: String?, fullName: String?, appleUser: String?, api: MIRAAPIClient) async {
    await authenticate {
      try await api.post(
        "/auth/oauth/apple",
        body: MIRAAppleOAuthBody(idToken: idToken, email: email, fullName: fullName, appleUser: appleUser)
      )
    }
  }

  @MainActor
  public func logout() {
    token = nil
    user = nil
    errorMessage = nil
    keychain.clearAccessToken()
  }

  @MainActor
  public func replaceUser(_ updatedUser: MIRAUser) {
    user = updatedUser
    Task { await MIRALocalJSONCache.save(updatedUser, key: cachedUserKey) }
  }

  @MainActor
  private func authenticate(_ operation: () async throws -> MIRAAuthResponse) async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let response = try await operation()
      token = response.accessToken
      user = response.user
      keychain.saveAccessToken(response.accessToken)
      await MIRALocalJSONCache.save(response.user, key: cachedUserKey)
    } catch {
      errorMessage = "Could not sign in. Check your account and try again."
    }
  }
}
