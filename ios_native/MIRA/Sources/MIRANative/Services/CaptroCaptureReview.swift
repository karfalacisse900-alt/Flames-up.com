import AVFoundation
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Capture originals stay immutable. Enhancement creates a separate, opt-in derivative.
enum CaptroCaptureReview {
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func thumbnail(_ media: MIRAPickedMedia, maxPixelSize: Int = 1600) async -> UIImage? {
    guard !Task.isCancelled else { return nil }
    let pixelLimit = max(1, min(1600, maxPixelSize))
    let preparation = Task.detached(priority: .userInitiated) { () -> UIImage? in
      guard !Task.isCancelled else { return nil }
      if media.kind == .video {
        let fileExtension = URL(fileURLWithPath: media.fileName).pathExtension
        let file = FileManager.default.temporaryDirectory
          .appendingPathComponent("captro-capture-thumbnail-\(UUID().uuidString)")
          .appendingPathExtension(fileExtension.isEmpty ? "mov" : fileExtension)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
          try media.data.write(to: file, options: [.atomic, .completeFileProtection])
          try Task.checkCancellation()
          let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: CGFloat(pixelLimit), height: CGFloat(pixelLimit))
          return try await withTaskCancellationHandler {
            let frame = try await generator.image(at: .zero)
            try Task.checkCancellation()
            return UIImage(cgImage: frame.image)
          } onCancel: { generator.cancelAllCGImageGeneration() }
        } catch { return nil }
      }
      guard let source = CGImageSourceCreateWithData(media.data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
              kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary) else { return nil }
      guard !Task.isCancelled else { return nil }
      return UIImage(cgImage: image)
    }
    return await withTaskCancellationHandler {
      await preparation.value
    } onCancel: { preparation.cancel() }
  }

  static func enhanced(_ original: MIRAPickedMedia) async throws -> MIRAPickedMedia {
    try Task.checkCancellation()
    let processing = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      guard original.kind == .image,
            let source = CGImageSourceCreateWithData(original.data as CFData, nil),
            var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let image = CIImage(data: original.data, options: [.applyOrientationProperty: true]) else {
        throw ReviewError.unreadable
      }
      try Task.checkCancellation()
      // Restrained fixed adjustments; no hallucinated texture, face processing, or cloud call.
      let adjusted = image
        .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.10])
        .applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.015, "inputSharpness": 0.20])
        .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.18])
      let colorSpace = enhancementColorSpace(for: image.colorSpace)
      guard let output = context.createCGImage(adjusted, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
        throw ReviewError.unreadable
      }
      try Task.checkCancellation()
      let bytes = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw ReviewError.unreadable
      }
      // Pixels have been orientation-normalized; retain useful metadata, never introduce location.
      properties[kCGImagePropertyOrientation as String] = 1
      properties[kCGImagePropertyPixelWidth as String] = output.width
      properties[kCGImagePropertyPixelHeight as String] = output.height
      if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary as String] = tiff
      }
      if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
        exif[kCGImagePropertyExifPixelXDimension as String] = output.width
        exif[kCGImagePropertyExifPixelYDimension as String] = output.height
        properties[kCGImagePropertyExifDictionary as String] = exif
      }
      properties.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
      properties[kCGImageDestinationLossyCompressionQuality as String] = 0.96
      CGImageDestinationAddImage(destination, output, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { throw ReviewError.unreadable }
      try Task.checkCancellation()
      return MIRAPickedMedia(data: bytes as Data, kind: .image,
        fileName: "enhanced-\(original.localID.uuidString).jpg", mimeType: "image/jpeg")
    }
    return try await withTaskCancellationHandler {
      let result = try await processing.value
      try Task.checkCancellation()
      return result
    } onCancel: { processing.cancel() }
  }

  static func enhancementColorSpace(for source: CGColorSpace?) -> CGColorSpace {
    // RGBA8 output requires an RGB destination, even when the source is a valid
    // grayscale image. Core Image color-matches the input into this output space.
    // Keep supported wide-gamut RGB profiles instead of flattening every photo.
    if let source, source.model == .rgb, source.supportsOutput { return source }
    return CGColorSpace(name: CGColorSpace.sRGB)!
  }

  /// The existing server accepts these Story duration buckets. Never cut a 60s capture to 15s.
  static func storyDuration(for duration: Double?) -> Int? {
    guard let duration, duration.isFinite, duration > 0 else { return nil }
    return duration <= 15 ? 15 : duration <= 30 ? 30 : 60
  }

  enum ReviewError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This photo could not be enhanced. Your original is unchanged." }
  }
}
