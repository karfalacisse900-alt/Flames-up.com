import CryptoKit
import Foundation

public enum MIRAProductionBackend {
  public static let apiBaseURL = URL(string: "https://api.flames-up.com/api")!
  public static let siteBaseURL = URL(string: "https://flames-up.com")!

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
  case badStatus(Int)
  case decodingFailed
  case emptyResponse

  public var errorDescription: String? {
    switch self {
    case .badURL: return "The request URL is not valid."
    case .badStatus: return "The server could not finish this request."
    case .decodingFailed: return "The app could not read the server response."
    case .emptyResponse: return "The server returned an empty response."
    }
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
    configuration.httpMaximumConnectionsPerHost = 6
    configuration.urlCache = URLCache(
      memoryCapacity: 64 * 1024 * 1024,
      diskCapacity: 256 * 1024 * 1024,
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
    data: Data
  ) async throws -> T {
    let url = try makeURL(path)
    return try await uploadMultipart(to: url, fieldName: fieldName, fileName: fileName, mimeType: mimeType, data: data, authorize: true)
  }

  public func uploadMultipart<T: Decodable>(
    to absoluteURL: URL,
    fieldName: String = "file",
    fileName: String,
    mimeType: String,
    data: Data,
    authorize: Bool = false
  ) async throws -> T {
    var request = URLRequest(url: absoluteURL)
    let boundary = "mira-\(UUID().uuidString)"
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = multipartBody(boundary: boundary, fieldName: fieldName, fileName: fileName, mimeType: mimeType, data: data)
    if authorize, let token = await sessionProvider?.accessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
    guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
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
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let token = await sessionProvider?.accessToken()
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

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
    guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
    return data
  }

  private func makeURL(_ path: String) throws -> URL {
    if let absolute = URL(string: path), absolute.scheme != nil {
      return absolute
    }
    let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let baseString = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
    guard let base = URL(string: baseString), let url = URL(string: cleanPath, relativeTo: base)?.absoluteURL else {
      throw MIRAAPIError.badURL
    }
    return url
  }

  private func tokenFingerprint(_ token: String?) -> String {
    guard let token, !token.isEmpty else { return "anonymous" }
    let digest = SHA256.hash(data: Data(token.utf8))
    return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
  }

  private func multipartBody(boundary: String, fieldName: String, fileName: String, mimeType: String, data: Data) -> Data {
    var body = Data()
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
