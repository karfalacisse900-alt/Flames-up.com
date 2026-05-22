import AVFoundation
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
  public let editorMetadata: MIRANativeEditedMediaMetadata?

  public init(
    data: Data,
    kind: MIRAPickedMediaKind,
    fileName: String,
    mimeType: String,
    editorMetadata: MIRANativeEditedMediaMetadata? = nil
  ) {
    self.data = data
    self.kind = kind
    self.fileName = fileName
    self.mimeType = mimeType
    self.editorMetadata = editorMetadata
  }

  public func mediaDimension() async -> MIRAMediaDimension {
    let size: CGSize?
    switch kind {
    case .image:
      size = UIImage(data: data)?.size
    case .video:
      size = await videoNaturalSize()
    }

    guard let size, size.width > 0, size.height > 0 else {
      return MIRAMediaDimension(width: nil, height: nil, ratio: nil, format: nil, type: kind.rawValue)
    }

    let width = Double(size.width)
    let height = Double(size.height)
    return MIRAMediaDimension(
      width: width,
      height: height,
      ratio: width / height,
      format: Self.mediaFormat(width: width, height: height),
      type: kind.rawValue
    )
  }

  private func videoNaturalSize() async -> CGSize? {
    let ext = URL(fileURLWithPath: fileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: fileName).pathExtension
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    do {
      try data.write(to: url, options: .atomic)
      defer { try? FileManager.default.removeItem(at: url) }
      let asset = AVURLAsset(url: url)
      let tracks = try await asset.loadTracks(withMediaType: .video)
      guard let track = tracks.first else { return nil }
      let naturalSize = try await track.load(.naturalSize)
      let transform = try await track.load(.preferredTransform)
      let transformed = naturalSize.applying(transform)
      return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    } catch {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
  }

  private static func mediaFormat(width: Double, height: Double) -> String {
    guard width > 0, height > 0 else { return "" }
    let ratio = width / height
    if abs(ratio - 1.91) <= 0.08 { return "1.91:1" }
    if abs(ratio - (16.0 / 9.0)) <= 0.08 { return "16:9" }
    if abs(ratio - 1.0) <= 0.06 { return "1:1" }
    if abs(ratio - (4.0 / 5.0)) <= 0.07 { return "4:5" }
    if abs(ratio - (9.0 / 16.0)) <= 0.07 { return "9:16" }
    return ratio > 1 ? "landscape" : "portrait"
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

  public func uploadAudio(data: Data, fileName: String, mimeType: String = "audio/mp4") async throws -> String {
    let response: MIRAMediaUploadResponse = try await api.uploadMultipart(
      "/upload/audio",
      fileName: fileName,
      mimeType: mimeType,
      data: data
    )
    guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
    return url
  }

  public func uploadFile(data: Data, fileName: String, mimeType: String) async throws -> String {
    let response: MIRAMediaUploadResponse = try await api.uploadMultipart(
      "/upload/file",
      fileName: fileName,
      mimeType: mimeType,
      data: data
    )
    guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
    return url
  }

  private struct PreparedImageUpload {
    let data: Data
    let mimeType: String
    let fileName: String
  }

  private func uploadImage(_ media: MIRAPickedMedia) async throws -> String {
    let prepared = prepareImageUpload(media)
    let base64 = "data:\(prepared.mimeType);base64,\(prepared.data.base64EncodedString())"
    let response: MIRAMediaUploadResponse = try await api.post(
      "/upload/image",
      body: MIRAUploadImageBody(image: base64, filename: prepared.fileName)
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
    return rendered.jpegData(compressionQuality: 0.92)
  }

  private func prepareImageUpload(_ media: MIRAPickedMedia) -> PreparedImageUpload {
    if let detectedMimeType = detectedImageMimeType(media.data), media.data.count <= 10_000_000 {
      return PreparedImageUpload(
        data: media.data,
        mimeType: detectedMimeType,
        fileName: normalizedImageName(media.fileName, mimeType: detectedMimeType)
      )
    }

    let prepared = prepareImage(media.data) ?? media.data
    return PreparedImageUpload(
      data: prepared,
      mimeType: "image/jpeg",
      fileName: normalizedImageName(media.fileName, mimeType: "image/jpeg")
    )
  }

  private func detectedImageMimeType(_ data: Data) -> String? {
    if data.starts(with: [0xff, 0xd8, 0xff]) {
      return "image/jpeg"
    }
    if data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
      return "image/png"
    }
    if data.count >= 12 {
      let header = Array(data.prefix(12))
      let isRIFF = header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
      let isWEBP = header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50
      if isRIFF && isWEBP {
        return "image/webp"
      }
    }
    return nil
  }

  private func normalizedImageName(_ fileName: String, mimeType: String) -> String {
    let base = fileName.split(separator: ".").first.map(String.init) ?? UUID().uuidString
    let ext: String
    switch mimeType.lowercased() {
    case "image/png":
      ext = "png"
    case "image/webp":
      ext = "webp"
    default:
      ext = "jpg"
    }
    return "\(base).\(ext)"
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
