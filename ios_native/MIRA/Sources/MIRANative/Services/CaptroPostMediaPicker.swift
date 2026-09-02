import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum CaptroPostVideoLimits {
  static let maxBytes = 200_000_000
  static let maxDurationSeconds = 60.0

  static func validate(byteCount: Int, duration: Double) throws {
    guard byteCount > 0, byteCount <= maxBytes else {
      throw MIRAAPIError.server(status: 413, code: "VIDEO_TOO_LARGE", detail: "Choose a video smaller than 200 MB.")
    }
    guard duration.isFinite, duration > 0, duration <= maxDurationSeconds else {
      throw MIRAAPIError.server(status: 400, code: "VIDEO_DURATION", detail: "Choose a video up to 60 seconds long.")
    }
  }
}

private struct CaptroPickedMovie: Transferable {
  let media: MIRAPickedMedia

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .movie) { received in
      let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= CaptroPostVideoLimits.maxBytes else {
        throw MIRAAPIError.server(status: 413, code: "VIDEO_TOO_LARGE", detail: "Choose a video smaller than 200 MB.")
      }
      let isQuickTime = received.file.pathExtension.lowercased() == "mov"
      // Read the picker-owned file before its temporary URL expires.
      return CaptroPickedMovie(media: MIRAPickedMedia(
        data: try Data(contentsOf: received.file),
        kind: .video,
        fileName: "\(UUID().uuidString).\(isQuickTime ? "mov" : "mp4")",
        mimeType: isQuickTime ? "video/quicktime" : "video/mp4"
      ))
    }
  }
}

enum CaptroPostMediaPicker {
  static func load(_ item: PhotosPickerItem) async throws -> MIRAPickedMedia {
    if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
      guard let movie = try await item.loadTransferable(type: CaptroPickedMovie.self) else {
        throw MIRAAPIError.emptyResponse
      }
      _ = try await movie.media.validatedVideoDuration()
      return movie.media
    }
    guard let data = try await item.loadTransferable(type: Data.self) else {
      throw MIRAAPIError.emptyResponse
    }
    let (kind, fileName, mimeType) = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
    return MIRAPickedMedia(data: data, kind: kind, fileName: fileName, mimeType: mimeType)
  }
}

extension MIRAPickedMedia {
  func validatedVideoDuration() async throws -> Double? {
    guard kind == .video else { return nil }
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("captro-video-check-\(UUID().uuidString)")
      .appendingPathExtension(URL(fileURLWithPath: fileName).pathExtension)
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let asset = AVURLAsset(url: file)
    let duration = try await asset.load(.duration).seconds
    try CaptroPostVideoLimits.validate(byteCount: data.count, duration: duration)
    return duration
  }
}
