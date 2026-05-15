import Foundation

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

  public var errorDescription: String? {
    switch self {
    case .badURL: return "The request URL is not valid."
    case .badStatus: return "The server could not finish this request."
    case .decodingFailed: return "The app could not read the server response."
    }
  }
}

public final class MIRAAPIClient {
  public let baseURL: URL
  private let sessionProvider: MIRASessionProviding?
  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  public init(
    baseURL: URL = URL(string: "https://api.flames-up.com/api")!,
    sessionProvider: MIRASessionProviding? = nil,
    session: URLSession = .shared
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

  public func delete<T: Decodable>(_ path: String) async throws -> T {
    try await request(path, method: "DELETE", body: Optional<Data>.none)
  }

  private func request<T: Decodable>(_ path: String, method: String, body: Data?) async throws -> T {
    let url = try makeURL(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 25
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let token = await sessionProvider?.accessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw MIRAAPIError.badStatus(status) }
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw MIRAAPIError.decodingFailed
    }
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
}

public struct EmptyResponse: Decodable {}
public struct EmptyBody: Encodable {}
