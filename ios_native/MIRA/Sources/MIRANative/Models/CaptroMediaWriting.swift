import SwiftUI
import UIKit

/// Versioned, source-relative artwork. Never changes the media bytes.
public struct CaptroMediaWriting: Codable, Hashable {
  public var schemaVersion = 1
  public var text = ""
  public var style = "bold"
  public var alignment = "left"
  public var color = "white"
  public var readability = false
  public var x: CGFloat = 0.5
  public var y: CGFloat = 0.20
  public var width: CGFloat = 0.82
  public var size = "medium"
  public var sourceAspectRatio: CGFloat = 1
  public var showsStamp: Bool? = nil
  public var homeAspectRatio: CGFloat? = nil
  public var cropX: CGFloat? = nil
  public var cropY: CGFloat? = nil

  public init() {}
  public static func cover(sourceAspectRatio: CGFloat = 1) -> Self {
    var value = Self(); value.schemaVersion = 2; value.style = "handwritten"
    value.alignment = "center"; value.y = 0.46; value.width = 0.60
    value.color = "black"; value.readability = true
    value.sourceAspectRatio = sourceAspectRatio; value.showsStamp = false
    let sourceHeightToWidth = sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? 1 / sourceAspectRatio : 1
    value.homeAspectRatio = 1 / MIRAMediaSizing.homeDisplayRatio(sourceHeightToWidth)
    return value
  }
  public var characterLimit: Int { schemaVersion == 2 ? 70 : 60 }

  public var fontFraction: CGFloat { schemaVersion == 2 ? 0.057 : size == "small" ? 0.065 : size == "large" ? 0.105 : 0.085 }
  public func font(mediaWidth: CGFloat, visibleWidth: CGFloat? = nil) -> UIFont {
    // Cover type is proportional to the visible image, not the uncropped source.
    // It never grows to fill a short phrase or shrinks to hide overflow.
    makeFont(points: (schemaVersion == 2 ? (visibleWidth ?? mediaWidth) : mediaWidth) * fontFraction)
  }
  private func makeFont(points: CGFloat) -> UIFont {
    if style == "handwritten" {
      return UIFont(name: "MarkerFelt-Wide", size: points) ?? UIFont.systemFont(ofSize: points, weight: .medium)
    }
    if style == "editorial" || style == "classic" {
      let base = UIFont.systemFont(ofSize: points, weight: .semibold)
      return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: points)
    }
    let base = UIFont.systemFont(ofSize: points, weight: style == "bold" ? .heavy : .medium)
    return style == "bold"
      ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitCondensed) ?? base.fontDescriptor, size: points)
      : base
  }
  public func measuredSize(mediaWidth: CGFloat, visibleWidth: CGFloat? = nil) -> CGSize {
    let font = font(mediaWidth: mediaWidth, visibleWidth: visibleWidth)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment == "center" ? .center : alignment == "right" ? .right : .left
    if schemaVersion == 2 { paragraph.lineSpacing = -2 }
    let availableWidth = schemaVersion == 2
      ? max(1, min(mediaWidth * width, (visibleWidth ?? mediaWidth) * 0.60) - 14)
      : mediaWidth * width
    let renderedText = schemaVersion == 2 ? text.uppercased() : text
    let longestLine = renderedText.components(separatedBy: .newlines)
      .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    let textWidth = schemaVersion == 2 ? min(availableWidth, max(64, ceil(longestLine) + 3)) : availableWidth
    let rect = (renderedText as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph], context: nil)
    return CGSize(width: textWidth, height: max(font.lineHeight, ceil(rect.height)))
  }
  public var validationMessage: String? {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    if text.count > characterLimit { return "Keep \(schemaVersion == 2 ? "Cover headlines" : "visual writing") to \(characterLimit) characters or fewer." }
    if text.components(separatedBy: .newlines).count > 4 { return "Use up to four short lines." }
    // Use a canonical source width, not device pixels or Dynamic Type, to keep
    // published creative geometry reproducible. Accessible text remains separate.
    let font = font(mediaWidth: 1000)
    if schemaVersion == 2 {
      let availableWidth = 1000 * min(width, 0.60) - 14
      let longest = text.uppercased().split(whereSeparator: \.isWhitespace)
        .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
      if longest > availableWidth { return "Shorten the longest word so the headline fits on the photograph." }
    }
    if measuredSize(mediaWidth: 1000).height > ceil(font.lineHeight * 4) + 1 {
      return schemaVersion == 2 ? "Use up to four short lines. Shorten the headline to continue."
        : "Use up to four short lines. Shorten the phrase or choose Small."
    }
    return nil
  }
  public var tint: Color {
    switch color {
    case "black": return Color(red: 0.06, green: 0.07, blue: 0.06)
    case "green": return Color(red: 0.06, green: 0.20, blue: 0.13)
    case "cream": return Color(red: 0.98, green: 0.96, blue: 0.88)
    default: return .white
    }
  }
  public func sourceRect(in container: CGSize, fill: Bool) -> CGRect {
    let ratio = sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 1
    let source = CGSize(width: ratio, height: 1)
    let factor = fill ? max(container.width / source.width, container.height) : min(container.width / source.width, container.height)
    let size = CGSize(width: source.width * factor, height: factor)
    return CGRect(x: (container.width - size.width) * (fill ? (cropX ?? 0.5) : 0.5),
      y: (container.height - size.height) * (fill ? (cropY ?? 0.5) : 0.5), width: size.width, height: size.height)
  }
  public func textRect(in container: CGSize, fill: Bool) -> CGRect {
    let source = sourceRect(in: container, fill: fill)
    let size = measuredSize(mediaWidth: source.width, visibleWidth: container.width)
    return CGRect(x: source.minX + source.width * x - size.width / 2,
      y: source.minY + source.height * y - size.height / 2, width: size.width, height: size.height)
  }
}

/// Tolerates legacy filter/native-editor records without rendering them twice.
public struct CaptroMediaWritingEnvelope: Codable, Hashable {
  public var type: String?
  public var mediaIndex: Int?
  public var writing: CaptroMediaWriting?

  public init(type: String?, mediaIndex: Int?, writing: CaptroMediaWriting?) {
    self.type = type; self.mediaIndex = mediaIndex; self.writing = writing
  }
  private enum CodingKeys: String, CodingKey { case type, mediaIndex, writing }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try? container.decode(String.self, forKey: .type)
    mediaIndex = try? container.decode(Int.self, forKey: .mediaIndex)
    // A legacy or future editor record must not prevent the whole feed loading.
    writing = try? container.decode(CaptroMediaWriting.self, forKey: .writing)
    if let version = writing?.schemaVersion, ![1, 2].contains(version) { writing = nil }
  }
}

extension MIRAPost {
  func mediaWriting(at index: Int) -> CaptroMediaWriting? {
    editorOverlays?.first { $0.type == "media_writing" && $0.mediaIndex == index && [1, 2].contains($0.writing?.schemaVersion ?? 0) }?.writing
  }
  var isCoverPost: Bool { creationIntent == "cover" }
}

struct CaptroMediaWritingLayer: View {
  let writing: CaptroMediaWriting
  let container: CGSize
  var fill = true
  var caption: String? = nil

  var body: some View {
    let source = writing.sourceRect(in: container, fill: fill)
    let rect = writing.textRect(in: container, fill: fill)
    let backingPadding: CGFloat = writing.schemaVersion == 2 ? 7 : 5
    Text(writing.schemaVersion == 2 ? writing.text.uppercased() : writing.text)
      .font(Font(writing.font(mediaWidth: source.width, visibleWidth: container.width)))
      .lineSpacing(writing.schemaVersion == 2 ? -2 : 0)
      .foregroundStyle(writing.tint)
      .multilineTextAlignment(writing.alignment == "center" ? .center : writing.alignment == "right" ? .trailing : .leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: rect.width, alignment: writing.alignment == "center" ? .center : writing.alignment == "right" ? .trailing : .leading)
      .padding(writing.readability ? backingPadding : 0)
      .background(writing.readability ? (writing.color == "black" || writing.color == "green" ? Color.white : Color.black) : .clear)
      .overlay { if writing.readability { Rectangle().strokeBorder(writing.color == "black" || writing.color == "green" ? Color.black : Color.white, lineWidth: writing.schemaVersion == 2 ? 1 : 0.7) } }
      .position(x: rect.midX, y: rect.midY)
      .accessibilityLabel(writing.text)
      .accessibilityHidden(writing.text.trimmingCharacters(in: .whitespacesAndNewlines) == caption?.trimmingCharacters(in: .whitespacesAndNewlines))
      .allowsHitTesting(false)
  }
}
