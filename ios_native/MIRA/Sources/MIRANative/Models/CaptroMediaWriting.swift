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

  public init() {}

  public var fontFraction: CGFloat { size == "small" ? 0.065 : size == "large" ? 0.105 : 0.085 }
  public func font(mediaWidth: CGFloat) -> UIFont {
    let points = mediaWidth * fontFraction
    if style == "editorial" {
      let base = UIFont.systemFont(ofSize: points, weight: .semibold)
      return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: points)
    }
    let base = UIFont.systemFont(ofSize: points, weight: style == "bold" ? .heavy : .medium)
    return style == "bold"
      ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitCondensed) ?? base.fontDescriptor, size: points)
      : base
  }
  public func measuredSize(mediaWidth: CGFloat) -> CGSize {
    let font = font(mediaWidth: mediaWidth)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment == "center" ? .center : alignment == "right" ? .right : .left
    let rect = (text as NSString).boundingRect(with: CGSize(width: mediaWidth * width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph], context: nil)
    return CGSize(width: mediaWidth * width, height: ceil(rect.height))
  }
  public var validationMessage: String? {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    if text.count > 80 { return "Keep visual writing to 80 characters or fewer." }
    // Use a canonical source width, not device pixels or Dynamic Type, to keep
    // published creative geometry reproducible. Accessible text remains separate.
    let font = font(mediaWidth: 1000)
    if measuredSize(mediaWidth: 1000).height > ceil(font.lineHeight * 4) + 1 {
      return "Use up to four short lines. Shorten the phrase or choose Small."
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
    return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
  }
  public func textRect(in container: CGSize, fill: Bool) -> CGRect {
    let source = sourceRect(in: container, fill: fill)
    let size = measuredSize(mediaWidth: source.width)
    return CGRect(x: source.minX + source.width * x - size.width / 2,
      y: source.minY + source.height * y - size.height / 2, width: size.width, height: size.height)
  }
}

/// Tolerates legacy filter/native-editor records without rendering them twice.
public struct CaptroMediaWritingEnvelope: Codable, Hashable {
  public var type: String?
  public var mediaIndex: Int?
  public var writing: CaptroMediaWriting?
}

extension MIRAPost {
  func mediaWriting(at index: Int) -> CaptroMediaWriting? {
    editorOverlays?.first { $0.type == "media_writing" && $0.mediaIndex == index && $0.writing?.schemaVersion == 1 }?.writing
  }
}

struct CaptroMediaWritingLayer: View {
  let writing: CaptroMediaWriting
  let container: CGSize
  var fill = true
  var caption: String? = nil

  var body: some View {
    let source = writing.sourceRect(in: container, fill: fill)
    let rect = writing.textRect(in: container, fill: fill)
    Text(writing.text)
      .font(Font(writing.font(mediaWidth: source.width)))
      .foregroundStyle(writing.tint)
      .multilineTextAlignment(writing.alignment == "center" ? .center : writing.alignment == "right" ? .trailing : .leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: rect.width, alignment: writing.alignment == "center" ? .center : writing.alignment == "right" ? .trailing : .leading)
      .padding(writing.readability ? 5 : 0)
      .background(writing.readability ? (writing.color == "black" || writing.color == "green" ? Color.white.opacity(0.75) : Color.black.opacity(0.48)) : .clear)
      .position(x: rect.midX, y: rect.midY)
      .accessibilityLabel(writing.text)
      .accessibilityHidden(writing.text.trimmingCharacters(in: .whitespacesAndNewlines) == caption?.trimmingCharacters(in: .whitespacesAndNewlines))
      .allowsHitTesting(false)
  }
}
