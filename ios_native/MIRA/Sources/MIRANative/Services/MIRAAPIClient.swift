import CryptoKit
import Foundation

public enum MIRAProductionBackend {
  public static let apiBaseURL = URL(string: "https://flames-up-api.karfalacisse900.workers.dev/api")!
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

  private static let directMediaUploadSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 900
    configuration.waitsForConnectivity = true
    return URLSession(configuration: configuration)
  }()
  private let sessionProvider: MIRASessionProviding?
  private let session: URLSession
  private let directUploadSession: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  public init(
    baseURL: URL = MIRAProductionBackend.apiBaseURL,
    sessionProvider: MIRASessionProviding? = nil,
    session: URLSession = MIRAAPIClient.productionSession,
    directUploadSession: URLSession? = nil
  ) {
    self.baseURL = baseURL
    self.sessionProvider = sessionProvider
    self.session = session
    self.directUploadSession = directUploadSession ?? Self.directMediaUploadSession
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

  public func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(path, method: "POST", body: data)
  }

  public func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
    let data = try encoder.encode(body)
    return try await request(path, method: "PUT", body: data)
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
    fields: [String: String] = [:],
    onProgress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> T {
    let url = try makeURL(path)
    return try await uploadMultipart(
      to: url,
      fieldName: fieldName,
      fileName: fileName,
      mimeType: mimeType,
      data: data,
      fields: fields,
      authorize: true,
      onProgress: onProgress
    )
  }

  /// Cloudflare Stream direct-creator tus upload. A lost PATCH is recovered by
  /// asking the provider for its committed offset before sending more bytes.
  /// The original media remains in Captro's durable composer draft for retry.
  public func uploadTusVideo(
    to url: URL,
    data: Data,
    onProgress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    try MIRANetworkSecurityPolicy.validateDirectUploadURL(url)
    guard !data.isEmpty else { throw MIRAAPIError.emptyResponse }
    let chunkBytes = 5 * 1024 * 1024 // Cloudflare minimum; divisible by 256 KiB.
    var offset = try await tusCommittedOffset(at: url, expectedLength: data.count)
    var failures = 0
    while offset < data.count {
      try Task.checkCancellation()
      let end = min(data.count, offset + chunkBytes)
      let chunkURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("captro-tus-\(UUID().uuidString).chunk")
      try Data(data[offset..<end]).write(to: chunkURL, options: [.atomic])
      defer { try? FileManager.default.removeItem(at: chunkURL) }
      var request = URLRequest(url: url)
      request.httpMethod = "PATCH"
      request.timeoutInterval = 120
      request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
      request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
      request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
      let start = offset
      let delegate = onProgress.map { callback in
        MIRAMultipartUploadProgressDelegate { fraction in
          callback(min(1, (Double(start) + Double(end - start) * fraction) / Double(data.count)))
        }
      }
      do {
        let (_, response) = try await directUploadSession.upload(
          for: request, fromFile: chunkURL, delegate: delegate
        )
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let nextString = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Upload-Offset"),
              let next = Int(nextString), next == end else {
          throw MIRAAPIError.badStatus(status)
        }
        offset = next
        failures = 0
        onProgress?(Double(offset) / Double(data.count))
      } catch {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
          throw error
        }
        if case MIRAAPIError.badStatus(let status) = error,
           (400..<500).contains(status),
           status != 408 && status != 409 && status != 425 && status != 429 {
          throw error
        }
        failures += 1
        guard failures < 5 else {
          throw error
        }
        try await Task.sleep(nanoseconds: UInt64(min(8, 1 << failures)) * 1_000_000_000)
        offset = try await tusCommittedOffset(at: url, expectedLength: data.count)
      }
    }
  }

  private func tusCommittedOffset(at url: URL, expectedLength: Int) async throws -> Int {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
    let (_, response) = try await directUploadSession.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw MIRAAPIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    guard let offsetString = http.value(forHTTPHeaderField: "Upload-Offset"),
          let offset = Int(offsetString), offset >= 0, offset <= expectedLength else {
      throw MIRAAPIError.emptyResponse
    }
    if let lengthString = http.value(forHTTPHeaderField: "Upload-Length"),
       let length = Int(lengthString), length != expectedLength {
      throw MIRAAPIError.server(status: 409, code: "UPLOAD_SIZE_CHANGED", detail: "The selected video changed. Choose it again to retry.")
    }
    return offset
  }

  public func uploadMultipart<T: Decodable>(
    to absoluteURL: URL,
    fieldName: String = "file",
    fileName: String,
    mimeType: String,
    data: Data,
    fields: [String: String] = [:],
    authorize: Bool = false,
    onProgress: (@Sendable (Double) -> Void)? = nil
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
    let uploadFile = try multipartBodyFile(
      boundary: boundary,
      fieldName: fieldName,
      fileName: fileName,
      mimeType: mimeType,
      data: data,
      fields: fields
    )
    defer { try? FileManager.default.removeItem(at: uploadFile) }
    if authorize, let token = await sessionProvider?.accessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if authorize {
      let trustHeaders = await MIRADeviceTrustService.shared.headers(for: "POST", path: absoluteURL.path)
      trustHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }

    let metric = await MIRAPerformanceMetric.begin(category: "network", label: authorize ? "UPLOAD \(absoluteURL.path)" : "UPLOAD direct-media")
    let responseData: Data
    let response: URLResponse
    do {
      let uploadSession = authorize ? session : directUploadSession
      let progressDelegate = onProgress.map(MIRAMultipartUploadProgressDelegate.init)
      (responseData, response) = try await uploadSession.upload(
        for: request,
        fromFile: uploadFile,
        delegate: progressDelegate
      )
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

  private func request<T: Decodable>(_ path: String, method: String, body: Data?) async throws -> T {
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
    let requestPath = request.url?.path ?? ""
    let isRefreshRequest = requestPath.hasSuffix("/auth/refresh")
    let isCredentialRequest = requestPath.hasSuffix("/auth/login")
      || requestPath.hasSuffix("/auth/register")
      || requestPath.hasSuffix("/auth/oauth/google")
      || requestPath.hasSuffix("/auth/oauth/apple")
      || requestPath.contains("/auth/password/reset/")
    if !isRefreshRequest,
       !isCredentialRequest,
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

  private func multipartBodyFile(
    boundary: String,
    fieldName: String,
    fileName: String,
    mimeType: String,
    data: Data,
    fields: [String: String]
  ) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-upload-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    do {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      func write(_ text: String) throws { try handle.write(contentsOf: Data(text.utf8)) }
      func safeHeader(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "")
          .replacingOccurrences(of: "\n", with: "")
          .replacingOccurrences(of: "\"", with: "")
      }
      for key in fields.keys.sorted() {
        guard let value = fields[key] else { continue }
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"\(safeHeader(key))\"\r\n\r\n")
        try write(value)
        try write("\r\n")
      }
      try write("--\(boundary)\r\n")
      try write("Content-Disposition: form-data; name=\"\(safeHeader(fieldName))\"; filename=\"\(safeHeader(fileName))\"\r\n")
      try write("Content-Type: \(safeHeader(mimeType))\r\n\r\n")
      try handle.write(contentsOf: data)
      try write("\r\n--\(boundary)--\r\n")
      return url
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }
}

private final class MIRAMultipartUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
  private let onProgress: @Sendable (Double) -> Void

  init(onProgress: @escaping @Sendable (Double) -> Void) {
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    onProgress(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
  }
}

public struct EmptyResponse: Decodable {}
public struct EmptyBody: Encodable {}
