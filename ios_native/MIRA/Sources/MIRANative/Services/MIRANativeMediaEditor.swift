import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

public enum MIRANativeEditorMediaType: String, Codable, Hashable {
  case photo
  case video
}

public enum MIRANativeEditorAspectRatio: String, Codable, Hashable, CaseIterable, Identifiable {
  case original
  case square = "1:1"
  case portrait4x5 = "4:5"
  case story9x16 = "9:16"

  public var id: String { rawValue }
}

public enum MIRANativeEditorFilter: String, Codable, Hashable, CaseIterable, Identifiable {
  case original
  case warm
  case cool
  case blackWhite
  case vivid
  case soft
  case fade
  case highContrast

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .original: return "Original"
    case .warm: return "Warm"
    case .cool: return "Cool"
    case .blackWhite: return "B&W"
    case .vivid: return "Vivid"
    case .soft: return "Soft"
    case .fade: return "Fade"
    case .highContrast: return "Contrast"
    }
  }
}

public struct MIRANativeTextLayer: Identifiable, Codable, Hashable {
  public var id: String
  public var text: String
  public var x: CGFloat
  public var y: CGFloat
  public var scale: CGFloat
  public var rotation: CGFloat
  public var colorHex: String
  public var fontName: String?
  public var fontSize: CGFloat
  public var alignment: String
  public var zIndex: Int

  public init(
    id: String = UUID().uuidString,
    text: String = "Add text",
    x: CGFloat = 0.5,
    y: CGFloat = 0.5,
    scale: CGFloat = 1,
    rotation: CGFloat = 0,
    colorHex: String = "#FFFFFF",
    fontName: String? = nil,
    fontSize: CGFloat = 34,
    alignment: String = "center",
    zIndex: Int = 0
  ) {
    self.id = id
    self.text = text
    self.x = x
    self.y = y
    self.scale = scale
    self.rotation = rotation
    self.colorHex = colorHex
    self.fontName = fontName
    self.fontSize = fontSize
    self.alignment = alignment
    self.zIndex = zIndex
  }
}

public struct MIRANativeEditRecipe: Codable, Hashable {
  public var mediaId: String
  public var mediaType: MIRANativeEditorMediaType
  public var aspectRatio: MIRANativeEditorAspectRatio
  public var selectedFilter: MIRANativeEditorFilter
  public var brightness: Double
  public var contrast: Double
  public var saturation: Double
  public var textLayers: [MIRANativeTextLayer]

  public init(
    mediaId: String = UUID().uuidString,
    mediaType: MIRANativeEditorMediaType,
    aspectRatio: MIRANativeEditorAspectRatio = .original,
    selectedFilter: MIRANativeEditorFilter = .original,
    brightness: Double = 0,
    contrast: Double = 1,
    saturation: Double = 1,
    textLayers: [MIRANativeTextLayer] = []
  ) {
    self.mediaId = mediaId
    self.mediaType = mediaType
    self.aspectRatio = aspectRatio
    self.selectedFilter = selectedFilter
    self.brightness = brightness
    self.contrast = contrast
    self.saturation = saturation
    self.textLayers = textLayers
  }

  public var hasEdits: Bool {
    selectedFilter != .original ||
      abs(brightness) > 0.001 ||
      abs(contrast - 1) > 0.001 ||
      abs(saturation - 1) > 0.001 ||
      !textLayers.isEmpty
  }
}

public struct MIRANativeEditedMediaMetadata: Codable, Hashable {
  public let wasEdited: Bool
  public let editorVersion: String
  public let appliedFilter: String
  public let hasTextOverlay: Bool

  public init(wasEdited: Bool, editorVersion: String = "native_v1", appliedFilter: String, hasTextOverlay: Bool) {
    self.wasEdited = wasEdited
    self.editorVersion = editorVersion
    self.appliedFilter = appliedFilter
    self.hasTextOverlay = hasTextOverlay
  }
}

public enum MIRANativeMediaEditorError: LocalizedError {
  case invalidImage
  case invalidVideo
  case exportFailed

  public var errorDescription: String? {
    switch self {
    case .invalidImage: return "That photo could not be edited."
    case .invalidVideo: return "That video could not be edited."
    case .exportFailed: return "The edited media could not be exported."
    }
  }
}

public enum MIRANativeMediaEditorRenderer {
  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  public static func previewImage(from data: Data, recipe: MIRANativeEditRecipe, maxSide: CGFloat = 1280) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
      guard let image = UIImage(data: data) else { return nil }
      let resized = downscaled(image, maxSide: maxSide)
      return applyPhotoFilter(to: resized, recipe: recipe)
    }.value
  }

  public static func videoThumbnail(from data: Data, fileName: String) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
      let ext = URL(fileURLWithPath: fileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: fileName).pathExtension
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
      do {
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: cgImage)
      } catch {
        try? FileManager.default.removeItem(at: url)
        return nil
      }
    }.value
  }

  public static func applyPhotoFilter(to image: UIImage, recipe: MIRANativeEditRecipe) -> UIImage {
    guard let ciImage = CIImage(image: image) else { return image }
    let oriented = ciImage.oriented(forExifOrientation: Int32(image.imageOrientation.exifOrientation))
    var output = oriented

    switch recipe.selectedFilter {
    case .original:
      break
    case .warm:
      let filter = CIFilter.temperatureAndTint()
      filter.inputImage = output
      filter.neutral = CIVector(x: 6500, y: 0)
      filter.targetNeutral = CIVector(x: 7600, y: 0)
      output = filter.outputImage ?? output
    case .cool:
      let filter = CIFilter.temperatureAndTint()
      filter.inputImage = output
      filter.neutral = CIVector(x: 6500, y: 0)
      filter.targetNeutral = CIVector(x: 5300, y: 0)
      output = filter.outputImage ?? output
    case .blackWhite:
      let filter = CIFilter.photoEffectNoir()
      filter.inputImage = output
      output = filter.outputImage ?? output
    case .vivid:
      let filter = CIFilter.colorControls()
      filter.inputImage = output
      filter.saturation = 1.24
      filter.contrast = 1.12
      filter.brightness = 0.02
      output = filter.outputImage ?? output
    case .soft:
      let filter = CIFilter.colorControls()
      filter.inputImage = output
      filter.saturation = 0.94
      filter.contrast = 0.94
      filter.brightness = 0.035
      output = filter.outputImage ?? output
    case .fade:
      let filter = CIFilter.colorControls()
      filter.inputImage = output
      filter.saturation = 0.82
      filter.contrast = 0.86
      filter.brightness = 0.04
      output = filter.outputImage ?? output
    case .highContrast:
      let filter = CIFilter.colorControls()
      filter.inputImage = output
      filter.saturation = 1.04
      filter.contrast = 1.32
      filter.brightness = -0.015
      output = filter.outputImage ?? output
    }

    let controls = CIFilter.colorControls()
    controls.inputImage = output
    controls.brightness = Float(recipe.brightness)
    controls.contrast = Float(recipe.contrast)
    controls.saturation = Float(recipe.saturation)
    output = controls.outputImage ?? output

    guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return image }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
  }

  public static func renderPhoto(_ image: UIImage, recipe: MIRANativeEditRecipe, maxSide: CGFloat = 2160) -> UIImage {
    let resized = downscaled(image, maxSide: maxSide)
    let filtered = applyPhotoFilter(to: resized, recipe: recipe)
    let size = filtered.size
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      filtered.draw(in: CGRect(origin: .zero, size: size))
      drawTextLayers(recipe.textLayers, in: size)
    }
  }

  private static func drawTextLayers(_ layers: [MIRANativeTextLayer], in size: CGSize) {
    for layer in layers.sorted(by: { $0.zIndex < $1.zIndex }) where !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      guard let context = UIGraphicsGetCurrentContext() else { continue }
      context.saveGState()
      let center = CGPoint(
        x: min(max(layer.x, 0.06), 0.94) * size.width,
        y: min(max(layer.y, 0.06), 0.94) * size.height
      )
      context.translateBy(x: center.x, y: center.y)
      context.rotate(by: layer.rotation)

      let fontSize = max(12, min(132, layer.fontSize * layer.scale))
      let font = layer.fontName.flatMap { UIFont(name: $0, size: fontSize) } ?? .systemFont(ofSize: fontSize, weight: .semibold)
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = layer.nsTextAlignment
      let attributed = NSAttributedString(
        string: layer.text,
        attributes: [
          .font: font,
          .foregroundColor: UIColor(hex: layer.colorHex),
          .paragraphStyle: paragraph,
          .shadow: NSShadow.miraDefaultTextShadow
        ]
      )
      let maxWidth = size.width * 0.82
      let bounding = attributed.boundingRect(
        with: CGSize(width: maxWidth, height: size.height * 0.5),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )
      attributed.draw(in: CGRect(x: -maxWidth / 2, y: -bounding.height / 2, width: maxWidth, height: bounding.height + 12))
      context.restoreGState()
    }
  }

  private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
    let side = max(image.size.width, image.size.height)
    guard side > maxSide else { return image.normalizedOrientation() }
    let scale = maxSide / side
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}

public enum MIRANativeMediaEditorExporter {
  public static func exportPhoto(media: MIRAPickedMedia, recipe: MIRANativeEditRecipe) async throws -> MIRAPickedMedia {
    let start = DispatchTime.now()
    do {
      let edited = try await Task.detached(priority: .userInitiated) {
        guard let image = UIImage(data: media.data) else { throw MIRANativeMediaEditorError.invalidImage }
        let rendered = MIRANativeMediaEditorRenderer.renderPhoto(image, recipe: recipe)
        guard let data = rendered.jpegData(compressionQuality: 0.92) else { throw MIRANativeMediaEditorError.exportFailed }
        return MIRAPickedMedia(
          data: data,
          kind: .image,
          fileName: "\(UUID().uuidString).jpg",
          mimeType: "image/jpeg",
          editorMetadata: recipe.editorMetadata
        )
      }.value
      logExport(label: "photo", start: start, bytes: edited.data.count)
      return edited
    } catch {
      logExportFailure(label: "photo", start: start, error: error)
      throw error
    }
  }

  public static func exportVideo(media: MIRAPickedMedia, recipe: MIRANativeEditRecipe) async throws -> MIRAPickedMedia {
    let start = DispatchTime.now()
    do {
      let edited = try await Task.detached(priority: .userInitiated) {
        try await exportVideoDetached(media: media, recipe: recipe)
      }.value
      logExport(label: "video", start: start, bytes: edited.data.count)
      return edited
    } catch {
      logExportFailure(label: "video", start: start, error: error)
      throw error
    }
  }

  private static func exportVideoDetached(media: MIRAPickedMedia, recipe: MIRANativeEditRecipe) async throws -> MIRAPickedMedia {
    let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    try media.data.write(to: inputURL, options: .atomic)
    defer {
      try? FileManager.default.removeItem(at: inputURL)
      try? FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVURLAsset(url: inputURL)
    let composition = AVMutableComposition()
    guard
      let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
      let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw MIRANativeMediaEditorError.invalidVideo
    }

    let duration = try await asset.load(.duration)
    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)

    if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
       let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
    }

    let naturalSize = try await sourceVideoTrack.load(.naturalSize)
    let transform = try await sourceVideoTrack.load(.preferredTransform)
    let renderSize = transformedSize(naturalSize: naturalSize, transform: transform)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = [instruction]

    if !recipe.textLayers.isEmpty {
      let parentLayer = CALayer()
      let videoLayer = CALayer()
      parentLayer.frame = CGRect(origin: .zero, size: renderSize)
      videoLayer.frame = parentLayer.frame
      parentLayer.addSublayer(videoLayer)

      for textLayer in recipe.textLayers.sorted(by: { $0.zIndex < $1.zIndex }) {
        let layer = CATextLayer()
        layer.string = textLayer.text
        layer.contentsScale = UIScreen.main.scale
        layer.alignmentMode = textLayer.caAlignmentMode
        layer.foregroundColor = UIColor(hex: textLayer.colorHex).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.32
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.isWrapped = true
        let font = textLayer.fontName.flatMap { UIFont(name: $0, size: textLayer.fontSize * textLayer.scale) } ??
          UIFont.systemFont(ofSize: textLayer.fontSize * textLayer.scale, weight: .semibold)
        layer.font = font
        layer.fontSize = font.pointSize
        let width = renderSize.width * 0.78
        let height = max(54, font.pointSize * 2.4)
        let centerX = min(max(textLayer.x, 0.08), 0.92) * renderSize.width
        let centerY = (1 - min(max(textLayer.y, 0.08), 0.92)) * renderSize.height
        layer.frame = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: textLayer.rotation))
        parentLayer.addSublayer(layer)
      }

      videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
      )
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      throw MIRANativeMediaEditorError.exportFailed
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.videoComposition = videoComposition
    exportSession.shouldOptimizeForNetworkUse = true

    try await exportSession.miraAwaitExport()
    let data = try Data(contentsOf: outputURL)
    return MIRAPickedMedia(
      data: data,
      kind: .video,
      fileName: "\(UUID().uuidString).mp4",
      mimeType: "video/mp4",
      editorMetadata: recipe.editorMetadata
    )
  }

  private static func transformedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
    let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
    return CGSize(width: max(1, abs(rect.width)), height: max(1, abs(rect.height)))
  }

  private static func logExport(label: String, start: DispatchTime, bytes: Int) {
    #if DEBUG
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    print("[MIRA editor] \(label) export \(Int(elapsed))ms bytes=\(bytes)")
    MIRAMemoryMetrics.log("editor_\(label)_export")
    #endif
  }

  private static func logExportFailure(label: String, start: DispatchTime, error: Error) {
    #if DEBUG
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    print("[MIRA editor] \(label) export failed \(Int(elapsed))ms error=\(error.localizedDescription)")
    #endif
  }
}

private extension MIRANativeEditRecipe {
  var editorMetadata: MIRANativeEditedMediaMetadata {
    MIRANativeEditedMediaMetadata(
      wasEdited: true,
      appliedFilter: selectedFilter.rawValue,
      hasTextOverlay: !textLayers.isEmpty
    )
  }
}

private extension AVAssetExportSession {
  func miraAwaitExport() async throws {
    try await withCheckedThrowingContinuation { continuation in
      exportAsynchronously {
        switch self.status {
        case .completed:
          continuation.resume()
        case .failed:
          continuation.resume(throwing: self.error ?? MIRANativeMediaEditorError.exportFailed)
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        default:
          continuation.resume(throwing: MIRANativeMediaEditorError.exportFailed)
        }
      }
    }
  }
}

private extension MIRANativeTextLayer {
  var nsTextAlignment: NSTextAlignment {
    switch alignment {
    case "left": return .left
    case "right": return .right
    default: return .center
    }
  }

  var caAlignmentMode: CATextLayerAlignmentMode {
    switch alignment {
    case "left": return .left
    case "right": return .right
    default: return .center
    }
  }
}

private extension NSShadow {
  static var miraDefaultTextShadow: NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = CGSize(width: 0, height: 2)
    shadow.shadowBlurRadius = 8
    return shadow
  }
}

private extension UIImage {
  func normalizedOrientation() -> UIImage {
    guard imageOrientation != .up else { return self }
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: size))
    }
  }
}

private extension UIImage.Orientation {
  var exifOrientation: UInt32 {
    switch self {
    case .up: return 1
    case .down: return 3
    case .left: return 8
    case .right: return 6
    case .upMirrored: return 2
    case .downMirrored: return 4
    case .leftMirrored: return 5
    case .rightMirrored: return 7
    @unknown default: return 1
    }
  }
}

extension UIColor {
  convenience init(hex: String) {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: clean).scanHexInt64(&value)
    let r, g, b, a: UInt64
    switch clean.count {
    case 8:
      (r, g, b, a) = ((value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff)
    case 6:
      (r, g, b, a) = ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff, 255)
    default:
      (r, g, b, a) = (255, 255, 255, 255)
    }
    self.init(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
}
