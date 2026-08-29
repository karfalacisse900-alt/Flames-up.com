import Foundation
import Security

public final class MIRAKeychainSessionProvider: MIRASessionProviding {
  private let service: String
  private let legacyService: String?
  private let accessTokenAccount: String
  private let refreshTokenAccount: String

  public init(
    service: String = "com.captro.auth",
    legacyService: String? = "com.mira.auth",
    accessTokenAccount: String = "access-token",
    refreshTokenAccount: String = "refresh-token"
  ) {
    self.service = service
    self.legacyService = legacyService
    self.accessTokenAccount = accessTokenAccount
    self.refreshTokenAccount = refreshTokenAccount
  }

  public func accessToken() async -> String? {
    loadToken(account: accessTokenAccount)
  }

  public func refreshToken() async -> String? {
    loadToken(account: refreshTokenAccount)
  }

  public func saveSession(accessToken: String, refreshToken: String?) {
    saveToken(accessToken, account: accessTokenAccount)
    if let refreshToken, !refreshToken.isEmpty {
      saveToken(refreshToken, account: refreshTokenAccount)
    } else {
      clearRefreshToken()
    }
  }

  public func saveAccessToken(_ token: String) {
    saveToken(token, account: accessTokenAccount)
  }

  public func saveRefreshToken(_ token: String) {
    saveToken(token, account: refreshTokenAccount)
  }

  public func clearSession() {
    clearAccessToken()
    clearRefreshToken()
  }

  public func clearAccessToken() {
    deleteToken(service: service, account: accessTokenAccount)
    if let legacyService {
      deleteToken(service: legacyService, account: accessTokenAccount)
    }
  }

  public func clearRefreshToken() {
    deleteToken(service: service, account: refreshTokenAccount)
    if let legacyService {
      deleteToken(service: legacyService, account: refreshTokenAccount)
    }
  }

  private func saveToken(_ token: String, account: String) {
    let data = Data(token.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      SecItemAdd(insert as CFDictionary, nil)
    }
  }

  private func deleteToken(service: String, account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func loadToken(account: String) -> String? {
    if let token = loadToken(service: service, account: account) {
      return token
    }
    if let legacyService, let legacyToken = loadToken(service: legacyService, account: account) {
      saveToken(legacyToken, account: account)
      deleteToken(service: legacyService, account: account)
      return legacyToken
    }
    return nil
  }

  private func loadToken(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
