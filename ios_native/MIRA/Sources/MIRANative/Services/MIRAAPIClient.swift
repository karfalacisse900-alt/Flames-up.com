import CryptoKit
import Foundation

public enum MIRAProductionBackend {
  public static let apiBaseURL = URL(string: "https://api.flames-up.com/api")!
  public static let siteBaseURL = URL(string: "https://captro.app")!

  public static func apiURL(_ path: String) -> URL {
    makeURL(baseURL: apiBaseURL, path: path)
  }

  public static func siteURL(_ path: String) -> URL {
    makeURL(baseURL: siteBaseURL, path: path)
  }

  private static func makeURL(baseURL: URL, path: String) -> URL {
    let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let baseString = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
    return URL(string: cleanPath, relativeTo: URL(string: baseString)!)!.absoluteURL
  }
}

public protocol MIRASessionProviding: AnyObject {
  func accessToken() async -> String?
}

public protocol MIRARefreshableSessionProviding: MIRASessionProviding {
  func refreshAccessTokenIfNeeded(api: MIRAAPIClient) async -> Bool
}

public final class StaticSessionProvider: MIRASessionProviding {
  private let token: String?

  public init(token: String? = nil) {
    self.token = token
  }

  public func accessToken() async -> String? {
    token
  }
}

public struct MIRAEventStreamFrame: Equatable, Sendable {
  public let id: String?
  public let event: String
  public let data: Data
}

public enum MIRAAPIError: Error, LocalizedError {
  case badURL
  case insecureURL
  case badStatus(Int)
  case server(status: Int, code: String?, detail: String?)
  case decodingFailed
  case emptyResponse

  public var errorDescription: String? {
    switch self {
    case .badURL: return "The request URL is not valid."
    case .insecureURL: return "The request was blocked because it is not a trusted secure connection."
    case .badStatus: return "The server could not finish this request."
    case .server(_, let code, let detail):
      if let detail, !detail.isEmpty {
        return detail
      }
      if let code, !code.isEmpty {
        return MIRALanguageResolver.localizedAPIError(code: code)
      }
      return MIRALanguageResolver.localizedAPIError(code: code)
    case .decodingFailed: return "The app could not read the server response."
    case .emptyResponse: return "The server returned an empty response."
    }
  }
}

private struct MIRAAPIErrorPayload: Decodable {
  let detail: String?
  let error: String?
  let code: String?
  let errorCode: String?
}

public enum MIRANetworkSecurityPolicy {
  private static let apiHosts: Set<String> = [
    "api.flames-up.com",
    "api.captro.app",
    "flames-up-api.karfalacisse900.workers.dev"
  ]

  private static let directUploadHostSuffixes = [
    "imagedelivery.net",
    "videodelivery.net",
    "cloudflarestream.com"
  ]

  public static func validateAPIURL(_ url: URL) throws {
    guard isHTTPS(url) || isLocalDebugURL(url) else { throw MIRAAPIError.insecureURL }
    guard isAllowedAPIHost(url) || isLocalDebugURL(url) else { throw MIRAAPIError.insecureURL }
  }

  public static func validateDirectUploadURL(_ url: URL) throws {
    guard isHTTPS(url) else { throw MIRAAPIError.insecureURL }
    guard let host = url.host?.lowercased(), directUploadHostSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
      throw MIRAAPIError.insecureURL
    }
  }

  public static func isSecureMediaURL(_ url: URL) -> Bool {
    guard isHTTPS(url) else { return false }
    return true
  }

  private static func isHTTPS(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
  }

  private static func isAllowedAPIHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return apiHosts.contains(host)
  }

  private static func isLocalDebugURL(_ url: URL) -> Bool {
    #if DEBUG
    guard let host = url.host?.lowercased(), let scheme = url.scheme?.lowercased() else { return false }
    return (scheme == "http" || scheme == "https") && (host == "localhost" || host == "127.0.0.1" || host == "::1")
    #else
    return false
    #endif
  }
}

private actor MIRAAPIRequestDeduplicator {
  static let shared = MIRAAPIRequestDeduplicator()

  private var inFlight: [String: Task<Data, Error>] = [:]

  func data(for key: String, start: @escaping () async throws -> Data) async throws -> Data {
    if let task = inFlight[key] {
      return try await task.value
    }

    let task = Task {
      try await start()
    }
    inFlight[key] = task
    do {
      let data = try await task.value
      inFlight[key] = nil
      return data
    } catch {
      inFlight[key] = nil
      throw error
    }
  }
}

public final class MIRAAPIClient {
  public static let productionSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.timeoutIntervalForRequest = 25
    configuration.timeoutIntervalForResource = 45
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 8
    configuration.urlCache = URLCache(
      memoryCapacity: 96 * 1024 * 1024,
      diskCapacity: 768 * 1024 * 1024,
      directory: nil
    )
    return URLSession(configuration: configuration)
  }()

  public let baseURL: URL
  private let sessionProvider: MIRASessionProviding?
  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  public init(
    baseURL: URL = MIRAProductionBackend.apiBaseURL,
    sessionProvider: MIRASessionProviding? = nil,
    session: URLSession = MIRAAPIClient.productionSession
  ) {
    self.baseURL = baseURL
    self.sessionProvider = sessionProvider
    self.session = session
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    self.decoder = decoder
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    self.encoder = encoder
  }

  public func get<T: Decodable>(_ path: String) async throws -> T {
    try await request(path, method: "GET", body: Optional<Data>.none)
  }

  /// Opens one authenticated server-sent-event stream. Values are transport notifications only;
  /// wallet callers must re-read validated gateway snapshots instead of applying amount deltas.
  public func eventStream(_ path: String) -> AsyncThrowingStream<MIRAEventStreamFrame, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let url = try makeURL(path)
          var request = URLRequest(url: url)
          request.httpMethod = "GET"
          request.timeoutInterval = 0
          try MIRANetworkSecurityPolicy.validateAPIURL(url)
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
          request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
          request.setValue(MIRALanguageResolver.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")
          request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
          if let token = await sessionProvider?.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          }
          let trustHeaders = await MIRADeviceTrustService.shared.headers(for: "GET", path: url.path)
          trustHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

          let (bytes, response) = try await session.bytes(for: request)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }

          var eventID: String?
          var eventName = "message"
          var dataLines: [String] = []
          for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
              if !dataLines.isEmpty {
                continuation.yield(
                  MIRAEventStreamFrame(
                    id: eventID,
                    event: eventName,
                    data: Data(dataLines.joined(separator: "\n").utf8)
                  )
                )
              }
              eventID = nil
              eventName = "message"
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("id:") {
              eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("event:") {
              eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(path, method: "POST", body: data, additionalHeaders: [:])
  }

  /// Sends a signed Aura transaction with the gateway's bounded replay-protection headers.
  /// Authorization still comes from the Keychain-backed session provider; callers cannot
  /// override it or inject arbitrary transport headers.
  public func postAuraTransaction<T: Decodable, Body: Encodable>(
    _ path: String,
    body: Body,
    idempotencyKey: String,
    timestampSeconds: UInt64
  ) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(
      path,
      method: "POST",
      body: data,
      additionalHeaders: [
        "Idempotency-Key": idempotencyKey,
        "X-Aura-Request-Timestamp": String(timestampSeconds)
      ]
    )
  }

  public func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(path, method: "PUT", body: data)
  }

  public func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(path, method: "PATCH", body: data)
  }

  public func delete<T: Decodable>(_ path: String) async throws -> T {
    try await request(path, method: "DELETE", body: Optional<Data>.none)
  }

  public func uploadMultipart<T: Decodable>(
    _ path: String,
    fieldName: String = "file",
    fileName: String,
    mimeType: String,
    data: Data,
    fields: [String: String] = [:]
  ) async throws -> T {
    let url = try makeURL(path)
    return try await uploadMultipart(to: url, fieldName: fieldName, fileName: fileName, mimeType: mimeType, data: data, fields: fields, authorize: true)
  }

  public func uploadMultipart<T: Decodable>(
    to absoluteURL: URL,
    fieldName: String = "file",
    fileName: String,
    mimeType: String,
    data: Data,
    fields: [String: String] = [:],
    authorize: Bool = false
  ) async throws -> T {
    var request = URLRequest(url: absoluteURL)
    let boundary = "mira-\(UUID().uuidString)"
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    if authorize {
      try MIRANetworkSecurityPolicy.validateAPIURL(absoluteURL)
    } else {
      try MIRANetworkSecurityPolicy.validateDirectUploadURL(absoluteURL)
    }
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(MIRALanguageResolver.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")
    request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
    request.httpBody = multipartBody(boundary: boundary, fieldName: fieldName, fileName: fileName, mimeType: mimeType, data: data, fields: fields)
    if authorize, let token = await sessionProvider?.accessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if authorize {
      let trustHeaders = await MIRADeviceTrustService.shared.headers(for: "POST", path: absoluteURL.path)
      trustHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }

    let metric = await MIRAPerformanceMetric.begin(category: "network", label: "UPLOAD \(absoluteURL.path)")
    let responseData: Data
    let response: URLResponse
    do {
      (responseData, response) = try await session.data(for: request)
    } catch {
      await metric.finish(status: "error")
      throw error
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    await metric.finish(status: "\(status)", bytes: responseData.count)
    guard (200..<300).contains(status) else { throw apiError(status: status, data: responseData) }
    if T.self == EmptyResponse.self {
      return EmptyResponse() as! T
    }
    guard !responseData.isEmpty else { throw MIRAAPIError.emptyResponse }
    do {
      return try decoder.decode(T.self, from: responseData)
    } catch {
      throw MIRAAPIError.decodingFailed
    }
  }

  private func request<T: Decodable>(
    _ path: String,
    method: String,
    body: Data?,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let url = try makeURL(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 25
    try MIRANetworkSecurityPolicy.validateAPIURL(url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(MIRALanguageResolver.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")
    request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
    let token = await sessionProvider?.accessToken()
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    for (name, value) in additionalHeaders {
      guard name == "Idempotency-Key" || name == "X-Aura-Request-Timestamp" else {
        throw MIRAAPIError.insecureURL
      }
      request.setValue(value, forHTTPHeaderField: name)
    }
    let trustHeaders = await MIRADeviceTrustService.shared.headers(for: method, path: url.path)
    trustHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

    let data: Data
    if method == "GET", body == nil {
      let key = "\(method) \(url.absoluteString) \(tokenFingerprint(token))"
      data = try await MIRAAPIRequestDeduplicator.shared.data(for: key) {
        try await self.responseData(for: request, metricLabel: "\(method) \(url.path)")
      }
    } else {
      data = try await responseData(for: request, metricLabel: "\(method) \(url.path)")
    }

    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw MIRAAPIError.decodingFailed
    }
  }

  private func responseData(for request: URLRequest, metricLabel: String) async throws -> Data {
    let metric = await MIRAPerformanceMetric.begin(category: "network", label: metricLabel)
    let response: URLResponse
    let data: Data
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      await metric.finish(status: "error")
      throw error
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    await metric.finish(status: "\(status)", bytes: data.count)
    let isRefreshRequest = request.url?.path.hasSuffix("/auth/refresh") == true
    if !isRefreshRequest,
       (status == 401 || status == 403),
       let refreshable = sessionProvider as? MIRARefreshableSessionProviding,
       await refreshable.refreshAccessTokenIfNeeded(api: self) {
      var retry = request
      if let refreshedToken = await sessionProvider?.accessToken(), !refreshedToken.isEmpty {
        retry.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
      }
      let retryMetric = await MIRAPerformanceMetric.begin(category: "network", label: "\(metricLabel) retry")
      let retryResponse: URLResponse
      let retryData: Data
      do {
        (retryData, retryResponse) = try await session.data(for: retry)
      } catch {
        await retryMetric.finish(status: "error")
        throw error
      }
      let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
      await retryMetric.finish(status: "\(retryStatus)", bytes: retryData.count)
      guard (200..<300).contains(retryStatus) else { throw apiError(status: retryStatus, data: retryData) }
      return retryData
    }
    guard (200..<300).contains(status) else { throw apiError(status: status, data: data) }
    return data
  }

  private func makeURL(_ path: String) throws -> URL {
    if let absolute = URL(string: path), absolute.scheme != nil {
      try MIRANetworkSecurityPolicy.validateAPIURL(absolute)
      return absolute
    }
    let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let baseString = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
    guard let base = URL(string: baseString), let url = URL(string: cleanPath, relativeTo: base)?.absoluteURL else {
      throw MIRAAPIError.badURL
    }
    try MIRANetworkSecurityPolicy.validateAPIURL(url)
    return url
  }

  private func tokenFingerprint(_ token: String?) -> String {
    guard let token, !token.isEmpty else { return "anonymous" }
    let digest = SHA256.hash(data: Data(token.utf8))
    return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
  }

  private func apiError(status: Int, data: Data) -> MIRAAPIError {
    guard
      let payload = try? decoder.decode(MIRAAPIErrorPayload.self, from: data),
      payload.detail != nil || payload.error != nil || payload.code != nil || payload.errorCode != nil
    else {
      return .badStatus(status)
    }
    return .server(
      status: status,
      code: payload.errorCode ?? payload.code ?? payload.error,
      detail: payload.detail
    )
  }

  private func multipartBody(
    boundary: String,
    fieldName: String,
    fileName: String,
    mimeType: String,
    data: Data,
    fields: [String: String]
  ) -> Data {
    var body = Data()
    for key in fields.keys.sorted() {
      guard let value = fields[key],
            key.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil else {
        continue
      }
      body.append("--\(boundary)\r\n".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
      body.append(value.data(using: .utf8)!)
      body.append("\r\n".data(using: .utf8)!)
    }
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    return body
  }
}

public struct EmptyResponse: Decodable {}
public struct EmptyBody: Encodable {}
