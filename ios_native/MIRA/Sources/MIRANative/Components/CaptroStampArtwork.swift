import SwiftUI
import UIKit

/// Only bundled, build-time compiled geometry is accepted. Titles remain live text.
struct CaptroStampTemplate: Decodable {
  let id: String
  let type: String
  let label: String
  let colors: [String: String]
  let compact: Layout
  let full: Layout

  struct Layout: Decodable {
    let width: CGFloat
    let height: CGFloat
    let fields: [Field]
    let layers: [Layer]
  }
  struct Field: Decodable {
    let key: String
    let x, y, maxWidth, size, minSize, tracking: CGFloat
    let font: String
    let weight: Int
    let anchor, overflow, color: String
    let italic: Bool

    func nativeFont(_ size: CGFloat) -> UIFont {
      if font == "serif", let font = UIFont(name: italic ? "Georgia-Italic" : "Georgia", size: size) { return font }
      return UIFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : .medium)
    }
    func attributes(size: CGFloat, color: UIColor = .black) -> [NSAttributedString.Key: Any] {
      [.font: nativeFont(size), .kern: tracking, .foregroundColor: color]
    }
    func fits(_ value: String, size: CGFloat) -> Bool {
      (value as NSString).size(withAttributes: attributes(size: size)).width <= maxWidth
    }
    func fitted(_ value: String) -> (String, CGFloat) {
      var size = self.size
      while size > minSize && !fits(value, size: size) { size -= 1 }
      if fits(value, size: size) { return (value, size) }
      if overflow != "ellipsis" {
        return (maxWidth < 160 ? "INFO" : (overflow == "offer" ? "VIEW OFFER" : "SEE DETAILS"), min(size, 30))
      }
      let characters = Array(value)
      var lower = 0, upper = characters.count
      while lower < upper {
        let middle = (lower + upper + 1) / 2
        if fits(String(characters.prefix(middle)) + "…", size: size) { lower = middle }
        else { upper = middle - 1 }
      }
      return (String(characters.prefix(lower)) + "…", size)
    }
    func fittedLines(_ value: String, maximumLines: Int) -> [(String, CGFloat)]? {
      let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
      guard maximumLines == 2, words.count > 1 else { return nil }
      var candidateSize = size
      while candidateSize >= minSize {
        var best: ([String], CGFloat)?
        for split in 1..<words.count {
          let lines = [words[..<split].joined(separator: " "), words[split...].joined(separator: " ")]
          guard lines.allSatisfy({ fits($0, size: candidateSize) }) else { continue }
          let widths = lines.map { ($0 as NSString).size(withAttributes: attributes(size: candidateSize)).width }
          let imbalance = abs(widths[0] - widths[1])
          if best == nil || imbalance < best!.1 { best = (lines, imbalance) }
        }
        if let best { return best.0.map { ($0, candidateSize) } }
        candidateSize -= 1
      }
      return nil
    }
  }
  struct Layer: Decodable {
    let commands: [[CGFloat]]
    let fill, stroke: String
    let width, opacity: CGFloat
    let evenOdd, round, texture, paper: Bool
    let dash: [CGFloat]
    // Cached at catalogue load, not parsed every time a cell scrolls.
    var path: CGPath {
      let path = CGMutablePath()
      for c in commands {
        switch Int(c[0]) {
        case 0: path.move(to: CGPoint(x: c[1], y: c[2]))
        case 1: path.addLine(to: CGPoint(x: c[1], y: c[2]))
        case 2: path.addQuadCurve(to: CGPoint(x: c[3], y: c[4]), control: CGPoint(x: c[1], y: c[2]))
        case 3: path.addCurve(to: CGPoint(x: c[5], y: c[6]), control1: CGPoint(x: c[1], y: c[2]), control2: CGPoint(x: c[3], y: c[4]))
        case 4: path.closeSubpath()
        default: break
        }
      }
      return path
    }
  }
  static let catalog: [String: CaptroStampTemplate] = {
    guard let url = Bundle.module.url(forResource: "CaptroStampTemplates", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let catalog = try? JSONDecoder().decode([String: CaptroStampTemplate].self, from: data) else {
      assertionFailure("Missing compiled Captro stamp templates")
      return [:]
    }
    return catalog
  }()
  static let paths: [String: [[CGPath]]] = catalog.mapValues { template in
    [template.compact.layers.map(\.path), template.full.layers.map(\.path)]
  }
}

struct CaptroStampArtwork: UIViewRepresentable {
  let content: CaptroStampContent
  let compact: Bool
  func makeUIView(context: Context) -> CaptroStampDrawingView { CaptroStampDrawingView() }
  func updateUIView(_ view: CaptroStampDrawingView, context: Context) {
    view.content = content
    view.compact = compact
    view.setNeedsDisplay()
  }
}

final class CaptroStampDrawingView: UIView {
  var content: CaptroStampContent?
  var compact = true
  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    contentMode = .redraw
  }
  required init?(coder: NSCoder) { return nil }

  override func draw(_ rect: CGRect) {
    guard let content, let template = CaptroStampTemplate.catalog[content.resolvedVariant],
          let context = UIGraphicsGetCurrentContext() else { return }
    let layout = compact ? template.compact : template.full
    let scale = bounds.width / layout.width
    context.saveGState()
    defer { context.restoreGState() }
    context.scaleBy(x: scale, y: scale)
    func color(_ key: String) -> UIColor {
      let paletteKey = key.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
      let value = template.colors[paletteKey] ?? key
      let hex = UInt32(value.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
      return UIColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    let paths = CaptroStampTemplate.paths[template.id]?[compact ? 0 : 1] ?? []
    // A very close contact shadow makes the label read as paper without turning
    // it into a floating UI card. It follows real cutouts and irregular edges.
    if let paperIndex = layout.layers.firstIndex(where: \.paper), paths.indices.contains(paperIndex) {
      context.saveGState()
      context.setShadow(offset: CGSize(width: 0, height: 2.2), blur: 4.2,
                        color: UIColor.black.withAlphaComponent(0.22).cgColor)
      context.addPath(paths[paperIndex])
      context.setFillColor(color("paper").cgColor)
      context.fillPath(using: layout.layers[paperIndex].evenOdd ? .evenOdd : .winding)
      context.restoreGState()
    }
    for (index, layer) in layout.layers.enumerated() {
      guard paths.indices.contains(index) else { continue }
      context.saveGState()
      context.setAlpha(layer.opacity)
      if layer.fill != "none" {
        context.addPath(paths[index]); context.setFillColor(color(layer.fill).cgColor)
        context.fillPath(using: layer.evenOdd ? .evenOdd : .winding)
      }
      if layer.stroke != "none" && layer.width > 0 {
        context.addPath(paths[index]); context.setStrokeColor(color(layer.stroke).cgColor)
        context.setLineWidth(layer.width)
        context.setLineCap(layer.round ? .round : .butt)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: layer.dash)
        context.strokePath()
      }
      context.restoreGState()
    }
    var fields = content.displayFields
    fields["label"] = content.family.uppercased()
    // Suppress the benefit too when its qualifying condition cannot fit intact.
    if content.family == "deal", let field = layout.fields.first(where: { $0.key == (compact ? "compactText" : "footer") }),
       !field.fits(fields[field.key] ?? "", size: field.minSize) {
      fields["title"] = "View offer"
      fields[field.key] = "Full terms in details"
    }
    for field in layout.fields {
      guard let raw = fields[field.key], !raw.isEmpty else { continue }
      if field.key == "title", ["event", "club", "meetup"].contains(content.family),
         let lines = field.fittedLines(raw, maximumLines: 2), lines.count > 1 {
        let lineHeight = lines[0].1 * 0.92
        let firstBaseline = field.y - lineHeight * CGFloat(lines.count - 1) / 2
        for (index, line) in lines.enumerated() {
          let attributes = field.attributes(size: line.1, color: color(field.color))
          let width = (line.0 as NSString).size(withAttributes: attributes).width
          let x = field.x - (field.anchor == "middle" ? width/2 : field.anchor == "end" ? width : 0)
          let baseline = firstBaseline + CGFloat(index) * lineHeight
          (line.0 as NSString).draw(at: CGPoint(x: x, y: baseline - field.nativeFont(line.1).ascender), withAttributes: attributes)
        }
        continue
      }
      let (text, size) = field.fitted(raw)
      let attributes = field.attributes(size: size, color: color(field.color))
      let width = (text as NSString).size(withAttributes: attributes).width
      let x = field.x - (field.anchor == "middle" ? width/2 : field.anchor == "end" ? width : 0)
      (text as NSString).draw(at: CGPoint(x: x, y: field.y - field.nativeFont(size).ascender), withAttributes: attributes)
    }
    if template.id == "moment-voice", let samples = content.waveform, !samples.isEmpty {
      let values = samples.prefix(40).map { $0.isFinite ? abs($0) : 0 }
      let peak = max(values.max() ?? 0, 0.00001)
      context.setStrokeColor(color("ink").cgColor)
      context.setLineWidth(3.2); context.setLineCap(.round)
      for (index, value) in values.enumerated() {
        let x = 37 + CGFloat(index) * 402 / CGFloat(max(1, values.count - 1))
        let height = 3 + CGFloat(value / peak) * 16
        context.move(to: CGPoint(x: x, y: layout.height - 50 - height))
        context.addLine(to: CGPoint(x: x, y: layout.height - 50 + height))
      }
      context.strokePath()
    }
  }
}
