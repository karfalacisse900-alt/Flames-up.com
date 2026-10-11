import SwiftUI

/// The single post framing contract. Source dimensions are display-oriented
/// (EXIF/track transform already applied); originals are never rewritten.
public struct CaptroPostMediaGeometry: Codable, Hashable, Sendable {
  public var version = 1
  public var sourceAspectRatio: Double
  public var displayAspectRatio: Double
  public var cropX: Double = 0.5
  public var cropY: Double = 0.5
  public var mediaId: String? = nil

  public static let ratios: [Double] = [0.8, 1, 0.75, 16.0 / 9]
  public static func selectedRatio(for source: Double) -> Double {
    guard source.isFinite, source > 0 else { return 0.8 }
    if source < 0.75 - 0.01 { return 0.8 }
    // A 4:3 source is equidistant in log-space: retain landscape orientation.
    if abs(source - 4.0 / 3) < 0.00001 { return 16.0 / 9 }
    return ratios.min { abs(log($0 / source)) < abs(log($1 / source)) } ?? 0.8
  }
  public init(sourceAspectRatio: Double, displayAspectRatio: Double? = nil, cropX: Double = 0.5, cropY: Double = 0.5) {
    self.sourceAspectRatio = sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 0.8
    self.displayAspectRatio = Self.selectedRatio(for: displayAspectRatio ?? self.sourceAspectRatio)
    self.cropX = cropX.isFinite ? min(1, max(0, cropX)) : 0.5
    self.cropY = cropY.isFinite ? min(1, max(0, cropY)) : 0.5
  }
  public var isValid: Bool {
    version == 1 && sourceAspectRatio.isFinite && sourceAspectRatio > 0
      && Self.ratios.contains { abs($0 - displayAspectRatio) < 0.00001 }
      && cropX.isFinite && cropY.isFinite && (0...1).contains(cropX) && (0...1).contains(cropY)
  }
  public func size(width: CGFloat) -> CGSize { CGSize(width: width, height: width / displayAspectRatio) }
  public func sourceRect(in container: CGSize) -> CGRect {
    let width = max(container.width, container.height * sourceAspectRatio)
    let height = width / sourceAspectRatio
    return CGRect(x: (container.width - width) * cropX, y: (container.height - height) * cropY, width: width, height: height)
  }
  public func applying(to writing: CaptroMediaWriting) -> CaptroMediaWriting {
    var writing = writing
    writing.sourceAspectRatio = sourceAspectRatio
    writing.homeAspectRatio = displayAspectRatio
    writing.cropX = cropX; writing.cropY = cropY
    return writing
  }
}

extension MIRAPost {
  /// All carousel slides share the selected post format; each retains its own
  /// source geometry and focal position. Details uses this same contract.
  public func mediaGeometry(at index: Int) -> CaptroPostMediaGeometry {
    let dimensions = mediaDimensions?.values ?? []
    let dimension = dimensions.indices.contains(index) ? dimensions[index] : nil
    let first = dimensions.first?.framing
    let writing = mediaWriting(at: index)
    let source = dimension?.heightToWidthRatio.map { Double(1 / $0) }
      ?? writing.map { Double($0.sourceAspectRatio) } ?? 0.8
    let legacyFirst = dimensions.first?.heightToWidthRatio.map { Double(1 / $0) }
      ?? mediaWriting(at: 0).map { Double($0.sourceAspectRatio) } ?? 0.8
    let display = first?.isValid == true ? first!.displayAspectRatio
      : CaptroPostMediaGeometry.selectedRatio(for: mediaWriting(at: 0)?.homeAspectRatio.map { Double($0) } ?? legacyFirst)
    var result = CaptroPostMediaGeometry(sourceAspectRatio: source, displayAspectRatio: display,
      cropX: Double(writing?.cropX ?? 0.5), cropY: Double(writing?.cropY ?? 0.5))
    if let saved = dimension?.framing, saved.isValid,
       saved.mediaId == nil || (mediaURLs.indices.contains(index) && saved.mediaId == Self.mediaIdentity(mediaURLs[index])) {
      result = saved
      result.displayAspectRatio = display
    }
    return result
  }
}
