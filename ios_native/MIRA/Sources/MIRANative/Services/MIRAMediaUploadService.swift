import AVFoundation
import CryptoKit
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
      size = await Task.detached(priority: .utility) {
        guard let image = UIImage(data: data) else { return nil }
        if let cgImage = image.cgImage {
          return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
      }.value
    case .video:
      size = await videoNaturalSize()
    }

    guard let size, size.width > 0, size.height > 0 else {
      return MIRAMediaDimension(width: nil, height: nil, ratio: nil, format: nil, type: kind.rawValue)
    }

    let width = Double(size.width)
    let height = Double(size.height)
    let supportedRatio = MIRASupportedPostAspectRatio.nearest(width: width, height: height)
    return MIRAMediaDimension(
      width: width,
      height: height,
      ratio: width / height,
      format: supportedRatio.rawValue,
      type: kind.rawValue,
      originalWidth: width,
      originalHeight: height,
      originalAspectRatio: width / height,
      feedWidth: supportedRatio.feedWidth,
      feedHeight: supportedRatio.feedHeight,
      feedAspectRatio: supportedRatio.widthToHeightRatio,
      displayAspectRatio: supportedRatio.widthToHeightRatio,
      cropMode: "center_crop",
      mediaType: kind.rawValue
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

}

public enum MIRAMediaUploadTarget: Hashable {
  case general
  case feedPost
}

public struct MIRAMediaUploadResult: Hashable {
  public let url: String
  public let mediaAssetId: String?
}

public final class MIRAMediaUploadService {
  private let api: MIRAAPIClient
  private let target: MIRAMediaUploadTarget

  public init(api: MIRAAPIClient, target: MIRAMediaUploadTarget = .general) {
    self.api = api
    self.target = target
  }

  public func upload(_ media: MIRAPickedMedia) async throws -> String {
    let result = try await uploadResult(media)
    return result.url
  }

  public func uploadResult(_ media: MIRAPickedMedia) async throws -> MIRAMediaUploadResult {
    switch media.kind {
    case .image:
      return try await uploadImageResult(media)
    case .video:
      return try await uploadVideoResult(media)
    }
  }

  public func uploadAudio(data: Data, fileName: String, mimeType: String = "audio/m4a") async throws -> String {
    let result = try await uploadAudioResult(data: data, fileName: fileName, mimeType: mimeType)
    return result.url
  }

  public func uploadAudioResult(
    data: Data,
    fileName: String,
    mimeType: String = "audio/m4a"
  ) async throws -> MIRAMediaUploadResult {
    try await performUpload(kind: "audio", bytes: data.count) {
      let response: MIRAMediaUploadResponse = try await api.uploadMultipart(
        "/upload/audio",
        fileName: fileName,
        mimeType: mimeType,
        data: data
      )
      guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
      return MIRAMediaUploadResult(url: url, mediaAssetId: response.mediaId ?? response.id)
    }
  }

  public func uploadFile(data: Data, fileName: String, mimeType: String) async throws -> String {
    try await performUpload(kind: "file", bytes: data.count) {
      let response: MIRAMediaUploadResponse = try await api.uploadMultipart(
        "/upload/file",
        fileName: fileName,
        mimeType: mimeType,
        data: data
      )
      guard let url = response.url, !url.isEmpty else { throw MIRAAPIError.emptyResponse }
      return url
    }
  }

  private struct PreparedImageUpload {
    let data: Data
    let mimeType: String
    let fileName: String
  }

  private struct MIRAMediaUploadIntentBody: Encodable {
    let mediaType: String
    let filename: String
    let mimeType: String
    let fileSize: Int
    let width: Double?
    let height: Double?
    let sha256Hash: String
  }

  private struct MIRAMediaUploadCompleteBody: Encodable {
    let mediaId: String
    let fileSize: Int
    let width: Double?
    let height: Double?
    let sha256Hash: String
  }

  private struct MIRAMediaStatusResponse: Decodable, Hashable {
    let mediaId: String?
    let uploadStatus: String?
    let moderationStatus: String?
    let publicUrl: String?
    let rejectionCode: String?
    let rejectionMessage: String?
  }

  private func uploadImageResult(_ media: MIRAPickedMedia) async throws -> MIRAMediaUploadResult {
    let prepared = await prepareImageUpload(media)
    return try await uploadModeratedMedia(
      media: media,
      uploadData: prepared.data,
      fileName: prepared.fileName,
      mimeType: prepared.mimeType,
      mediaType: "image"
    )
  }

  private func uploadVideoResult(_ media: MIRAPickedMedia) async throws -> MIRAMediaUploadResult {
    try await uploadModeratedMedia(
      media: media,
      uploadData: media.data,
      fileName: media.fileName,
      mimeType: media.mimeType,
      mediaType: "video"
    )
  }

  private func uploadModeratedMedia(
    media: MIRAPickedMedia,
    uploadData: Data,
    fileName: String,
    mimeType: String,
    mediaType: String
  ) async throws -> MIRAMediaUploadResult {
    let validatedMimeType = try validateUpload(
      data: uploadData,
      kind: media.kind,
      fileName: fileName,
      declaredMimeType: mimeType
    )
    let checksum = SHA256.hash(data: uploadData).map { String(format: "%02x", $0) }.joined()
    let preparedMedia = MIRAPickedMedia(
      data: uploadData,
      kind: media.kind,
      fileName: fileName,
      mimeType: validatedMimeType,
      editorMetadata: media.editorMetadata
    )
    let dimensions = await preparedMedia.mediaDimension()
    return try await performUpload(kind: mediaType, bytes: uploadData.count) {
      let intent: MIRAMediaUploadResponse = try await api.post(
        "/media/upload-intent",
        body: MIRAMediaUploadIntentBody(
          mediaType: mediaType,
          filename: fileName,
          mimeType: validatedMimeType,
          fileSize: uploadData.count,
          width: dimensions.feedWidth ?? dimensions.width,
          height: dimensions.feedHeight ?? dimensions.height,
          sha256Hash: checksum
        )
      )
      guard
        let mediaId = intent.mediaId,
        !mediaId.isEmpty,
        let uploadURL = intent.uploadUrl.flatMap(URL.init(string:))
      else {
        throw MIRAAPIError.emptyResponse
      }

      let _: EmptyResponse = try await api.uploadMultipart(
        to: uploadURL,
        fieldName: "file",
        fileName: fileName,
        mimeType: validatedMimeType,
        data: uploadData
      )

      let complete = try await completeModeratedUpload(
        MIRAMediaUploadCompleteBody(
          mediaId: mediaId,
          fileSize: uploadData.count,
          width: dimensions.feedWidth ?? dimensions.width,
          height: dimensions.feedHeight ?? dimensions.height,
          sha256Hash: checksum
        )
      )
      let approved = try await waitForModeratedMediaApproval(mediaId: mediaId, initial: complete)
      return MIRAMediaUploadResult(url: approved, mediaAssetId: mediaId)
    }
  }

  private func completeModeratedUpload(_ body: MIRAMediaUploadCompleteBody) async throws -> MIRAMediaStatusResponse {
    for attempt in 0..<6 {
      do {
        return try await api.post("/media/complete", body: body)
      } catch {
        let providerIsPending: Bool
        if case MIRAAPIError.badStatus(let status) = error {
          providerIsPending = status == 425
        } else if case MIRAAPIError.server(let status, _, _) = error {
          providerIsPending = status == 425
        } else {
          providerIsPending = false
        }
        guard providerIsPending, attempt < 5 else { throw error }
        try await Task.sleep(nanoseconds: 500_000_000)
      }
    }
    throw MIRAAPIError.server(
      status: 409,
      code: "MEDIA_PROVIDER_PENDING",
      detail: "The uploaded media is still processing. Please try again."
    )
  }

  private func validateUpload(
    data: Data,
    kind: MIRAPickedMediaKind,
    fileName: String,
    declaredMimeType: String
  ) throws -> String {
    guard !data.isEmpty else {
      throw MIRAAPIError.server(status: 400, code: "EMPTY_UPLOAD", detail: "The selected file is empty.")
    }
    let normalizedMimeType = declaredMimeType
      .split(separator: ";", maxSplits: 1)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()

    switch kind {
    case .image:
      guard data.count <= 10_000_000 else {
        throw MIRAAPIError.server(status: 413, code: "IMAGE_TOO_LARGE", detail: "Images must be 10 MB or smaller.")
      }
      guard let detected = detectedImageMimeType(data) else {
        throw MIRAAPIError.server(status: 400, code: "INVALID_IMAGE", detail: "The selected file is not a supported image.")
      }
      let declared = normalizedMimeType == "image/jpg" ? "image/jpeg" : normalizedMimeType
      let allowedExtensions = [
        "image/jpeg": ["jpg", "jpeg"],
        "image/png": ["png"],
        "image/webp": ["webp"],
        "image/heic": ["heic"],
        "image/heif": ["heif"],
      ]
      guard declared == detected,
            fileExtension.isEmpty || (allowedExtensions[detected] ?? []).contains(fileExtension)
      else {
        throw MIRAAPIError.server(status: 400, code: "IMAGE_TYPE_MISMATCH", detail: "The image contents do not match the selected file type.")
      }
      return detected

    case .video:
      guard data.count <= 200_000_000 else {
        throw MIRAAPIError.server(status: 413, code: "VIDEO_TOO_LARGE", detail: "Videos must be 200 MB or smaller.")
      }
      guard let detected = detectedVideoContainer(data) else {
        throw MIRAAPIError.server(status: 400, code: "INVALID_VIDEO", detail: "The selected file is not a supported video.")
      }
      let declaredIsISO = normalizedMimeType == "video/mp4" || normalizedMimeType == "video/quicktime"
      let extensionIsISO = fileExtension.isEmpty || ["mp4", "mov"].contains(fileExtension)
      let matches = detected == "iso" ? declaredIsISO && extensionIsISO : normalizedMimeType == "video/webm" && (fileExtension.isEmpty || fileExtension == "webm")
      guard matches else {
        throw MIRAAPIError.server(status: 400, code: "VIDEO_TYPE_MISMATCH", detail: "The video contents do not match the selected file type.")
      }
      return normalizedMimeType
    }
  }

  private func waitForModeratedMediaApproval(mediaId: String, initial: MIRAMediaStatusResponse) async throws -> String {
    var status = initial
    for attempt in 0..<18 {
      let moderation = (status.moderationStatus ?? "").lowercased()
      if moderation == "approved", let publicURL = status.publicUrl, !publicURL.isEmpty {
        return publicURL
      }
      if moderation == "rejected" {
        throw MIRAAPIError.server(
          status: 409,
          code: "MEDIA_REJECTED",
          detail: status.rejectionMessage ?? "This upload can't be posted because it may break Aura's safety rules."
        )
      }
      if moderation == "review_required" {
        throw MIRAAPIError.server(
          status: 409,
          code: "MEDIA_REVIEW_REQUIRED",
          detail: "This upload needs a quick safety review before it can be posted."
        )
      }
      if moderation == "failed" {
        throw MIRAAPIError.server(
          status: 409,
          code: "MEDIA_MODERATION_FAILED",
          detail: status.rejectionMessage ?? "This upload could not be checked. Please try again."
        )
      }
      guard attempt < 17 else { break }
      try await Task.sleep(nanoseconds: 700_000_000)
      status = try await api.get("/media/\(mediaId)/status")
    }
    throw MIRAAPIError.server(
      status: 409,
      code: "MEDIA_PENDING_MODERATION",
      detail: "Checking your upload before posting..."
    )
  }

  private func performUpload<T>(kind: String, bytes: Int, operation: () async throws -> T) async throws -> T {
    let started = Date()
    var lastError: Error?
    for attempt in 1...2 {
      do {
        let result = try await operation()
        await recordUploadEvent(kind: kind, status: "success", bytes: bytes, started: started, attempt: attempt)
        return result
      } catch {
        lastError = error
        guard attempt == 1, shouldRetryUpload(error) else {
          await recordUploadEvent(kind: kind, status: "error", bytes: bytes, started: started, attempt: attempt)
          throw error
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
      }
    }
    throw lastError ?? MIRAAPIError.emptyResponse
  }

  private func shouldRetryUpload(_ error: Error) -> Bool {
    if case MIRAAPIError.badStatus(let status) = error {
      return status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    }
    if case MIRAAPIError.server(let status, _, _) = error {
      return status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    }
    return true
  }

  private func recordUploadEvent(kind: String, status: String, bytes: Int, started: Date, attempt: Int) async {
    await MIRAObservability.record(
      "media_upload",
      category: "media",
      status: status,
      durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000),
      metadata: [
        "kind": kind,
        "bytes": String(bytes),
        "attempt": String(attempt),
      ],
      api: api
    )
  }

  private func prepareImage(_ data: Data) async -> Data? {
    await Task.detached(priority: .utility) {
      guard let image = UIImage(data: data) else { return nil }
      let maxSide = MIRAMediaSizing.feedTargetHeight
      let scale = min(1, maxSide / max(image.size.width, image.size.height))
      let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      let renderer = UIGraphicsImageRenderer(size: targetSize)
      let rendered = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }
      return rendered.jpegData(compressionQuality: 0.92)
    }.value
  }

  private func prepareImageUpload(_ media: MIRAPickedMedia) async -> PreparedImageUpload {
    if target == .feedPost, let feedImage = await prepareFeedImage(media.data) {
      return PreparedImageUpload(
        data: feedImage,
        mimeType: "image/jpeg",
        fileName: normalizedImageName(media.fileName, mimeType: "image/jpeg")
      )
    }

    if let detectedMimeType = detectedImageMimeType(media.data), media.data.count <= 10_000_000 {
      return PreparedImageUpload(
        data: media.data,
        mimeType: detectedMimeType,
        fileName: normalizedImageName(media.fileName, mimeType: detectedMimeType)
      )
    }

    let prepared = await prepareImage(media.data) ?? media.data
    return PreparedImageUpload(
      data: prepared,
      mimeType: "image/jpeg",
      fileName: normalizedImageName(media.fileName, mimeType: "image/jpeg")
    )
  }

  private func prepareFeedImage(_ data: Data) async -> Data? {
    await Task.detached(priority: .userInitiated) {
      guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
      let selectedRatio = MIRASupportedPostAspectRatio.nearest(
        width: Double(image.size.width),
        height: Double(image.size.height)
      )
      let targetSize = CGSize(width: CGFloat(selectedRatio.feedWidth), height: CGFloat(selectedRatio.feedHeight))
      let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
      let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      let drawOrigin = CGPoint(
        x: (targetSize.width - drawSize.width) / 2,
        y: (targetSize.height - drawSize.height) / 2
      )
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
      let rendered = renderer.image { _ in
        UIColor.black.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
        image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
      }
      let renderedData = rendered.jpegData(compressionQuality: 0.94)
      #if DEBUG
      if let renderedData {
        print(
          "CaptroCameraQuality original=\(Int(image.size.width))x\(Int(image.size.height)) bytes=\(data.count) " +
          "feed=\(Int(targetSize.width))x\(Int(targetSize.height)) ratio=\(selectedRatio.rawValue) bytes=\(renderedData.count) compression=0.94"
        )
      }
      #endif
      return renderedData
    }.value
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
      let isISOBaseMedia = header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70
      if isISOBaseMedia {
        let brand = String(bytes: header[8...11], encoding: .ascii)?.lowercased() ?? ""
        if ["heic", "heix", "hevc", "hevx"].contains(brand) {
          return "image/heic"
        }
        if ["mif1", "msf1"].contains(brand) {
          return "image/heif"
        }
      }
    }
    return nil
  }

  private func detectedVideoContainer(_ data: Data) -> String? {
    guard data.count >= 12 else { return nil }
    let header = Array(data.prefix(12))
    if header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70 {
      let brand = String(bytes: header[8...11], encoding: .ascii)?.lowercased() ?? ""
      let imageBrands = ["heic", "heix", "hevc", "hevx", "mif1", "msf1"]
      return imageBrands.contains(brand) ? nil : "iso"
    }
    if header[0] == 0x1a && header[1] == 0x45 && header[2] == 0xdf && header[3] == 0xa3 {
      return "webm"
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
    case "image/heic":
      ext = "heic"
    case "image/heif":
      ext = "heif"
    default:
      ext = "jpg"
    }
    return "\(base).\(ext)"
  }
}

public func pickedMediaKind(from contentTypes: [UTType], fallbackData: Data) -> (MIRAPickedMediaKind, String, String) {
  if let videoType = contentTypes.first(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
    let mimeType = ["video/mp4", "video/quicktime", "video/webm"].contains(videoType.preferredMIMEType ?? "")
      ? (videoType.preferredMIMEType ?? "video/quicktime")
      : "video/quicktime"
    let ext = videoType.preferredFilenameExtension ?? (mimeType == "video/mp4" ? "mp4" : mimeType == "video/webm" ? "webm" : "mov")
    return (.video, "\(UUID().uuidString).\(ext)", mimeType)
  }
  if let imageType = contentTypes.first(where: { $0.conforms(to: .image) }) {
    let mimeType = imageType.preferredMIMEType ?? "image/jpeg"
    let ext = imageType.preferredFilenameExtension ?? (mimeType == "image/png" ? "png" : "jpg")
    return (.image, "\(UUID().uuidString).\(ext)", mimeType)
  }
  if fallbackData.count >= 12 {
    let header = Array(fallbackData.prefix(12))
    let hasISOBaseMediaSignature = header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70
    let hasQuickTimeSignature = header[4] == 0x6d && header[5] == 0x6f && header[6] == 0x6f && header[7] == 0x76
    let brand = hasISOBaseMediaSignature ? (String(bytes: header[8...11], encoding: .ascii)?.lowercased() ?? "") : ""
    if ["heic", "heix", "hevc", "hevx"].contains(brand) {
      return (.image, "\(UUID().uuidString).heic", "image/heic")
    }
    if ["mif1", "msf1"].contains(brand) {
      return (.image, "\(UUID().uuidString).heif", "image/heif")
    }
    if hasISOBaseMediaSignature || hasQuickTimeSignature {
      return (.video, "\(UUID().uuidString).mp4", "video/mp4")
    }
    if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
      && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50 {
      return (.image, "\(UUID().uuidString).webp", "image/webp")
    }
    if header[0] == 0x1a && header[1] == 0x45 && header[2] == 0xdf && header[3] == 0xa3 {
      return (.video, "\(UUID().uuidString).webm", "video/webm")
    }
  }
  if fallbackData.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
    return (.image, "\(UUID().uuidString).png", "image/png")
  }
  return (.image, "\(UUID().uuidString).jpg", "image/jpeg")
}
