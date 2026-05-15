import Foundation
import UIKit
import UniformTypeIdentifiers

public enum MIRAPickedMediaKind: String, Hashable {
  case image
  case video
}

public struct MIRAPickedMedia: Hashable {
  public let data: Data
  public let kind: MIRAPickedMediaKind
  public let fileName: String
  public let mimeType: String

  public init(data: Data, kind: MIRAPickedMediaKind, fileName: String, mimeType: String) {
    self.data = data
    self.kind = kind
    self.fileName = fileName
    self.mimeType = mimeType
  }
}

public final class MIRAMediaUploadService {
  private let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public func upload(_ media: MIRAPickedMedia) async throws -> String {
    switch media.kind {
    case .image:
      return try await uploadImage(media)
    case .video:
      return try await uploadVideo(media)
    }
  }

  private func uploadImage(_ media: MIRAPickedMedia) async throws -> String {
    let prepared = prepareImage(media.data) ?? media.data
    let base64 = "data:image/jpeg;base64,\(prepared.base64EncodedString())"
    let response: MIRAMediaUploadResponse = try await api.post(
      "/upload/image",
      body: MIRAUploadImageBody(image: base64, filename: normalizedImageName(media.fileName))
    )
    guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
    return url
  }

  private func uploadVideo(_ media: MIRAPickedMedia) async throws -> String {
    do {
      let setup: MIRAMediaUploadResponse = try await api.post("/upload/video", body: EmptyBody())
      if let uploadURL = setup.uploadUrl.flatMap(URL.init(string:)), let videoUID = setup.videoUid, !videoUID.isEmpty {
        let _: EmptyResponse = try await api.uploadMultipart(
          to: uploadURL,
          fieldName: "file",
          fileName: media.fileName,
          mimeType: media.mimeType,
          data: media.data
        )
        return "cfstream:\(videoUID)"
      }
    } catch {
      // Fall through to the Worker-backed path, which stores a backup if Stream direct upload is unavailable.
    }

    let response: MIRAMediaUploadResponse = try await api.uploadMultipart(
      "/upload/video-with-backup",
      fileName: media.fileName,
      mimeType: media.mimeType,
      data: media.data
    )
    guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
    return url
  }

  private func prepareImage(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let maxSide: CGFloat = 2160
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let rendered = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return rendered.jpegData(compressionQuality: 0.88)
  }

  private func normalizedImageName(_ fileName: String) -> String {
    let base = fileName.split(separator: ".").first.map(String.init) ?? UUID().uuidString
    return "\(base).jpg"
  }
}

public func pickedMediaKind(from contentTypes: [UTType], fallbackData: Data) -> (MIRAPickedMediaKind, String, String) {
  if contentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
    return (.video, "\(UUID().uuidString).mov", "video/quicktime")
  }
  if let first = contentTypes.first(where: { $0.conforms(to: .image) }), first.conforms(to: .png) {
    return (.image, "\(UUID().uuidString).png", "image/png")
  }
  if fallbackData.starts(with: [0x00, 0x00, 0x00]) {
    return (.video, "\(UUID().uuidString).mp4", "video/mp4")
  }
  return (.image, "\(UUID().uuidString).jpg", "image/jpeg")
}
