import Foundation

public final class MIRAAuthSession: ObservableObject, MIRASessionProviding {
  @Published public private(set) var user: MIRAUser?
  @Published public private(set) var isBootstrapping = true
  @Published public private(set) var isWorking = false
  @Published public var errorMessage: String?

  private let keychain: MIRAKeychainSessionProvider
  private var token: String?

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
    isBootstrapping = true
    defer { isBootstrapping = false }
    guard let storedToken = await keychain.accessToken(), !storedToken.isEmpty else {
      token = nil
      user = nil
      return
    }

    token = storedToken
    do {
      user = try await api.get("/auth/me")
      errorMessage = nil
    } catch {
      token = nil
      user = nil
      keychain.clearAccessToken()
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
  private func authenticate(_ operation: () async throws -> MIRAAuthResponse) async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let response = try await operation()
      token = response.accessToken
      user = response.user
      keychain.saveAccessToken(response.accessToken)
    } catch {
      errorMessage = "Could not sign in. Check your account and try again."
    }
  }
}
