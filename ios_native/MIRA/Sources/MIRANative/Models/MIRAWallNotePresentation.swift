import CoreGraphics
import Foundation

public enum MIRAWallNoteVisualStyle: String, CaseIterable, Identifiable {
  case sticky
  case editorial
  case handwritten
  case poster
  case polaroid
  case receipt
  case tornPaper = "torn_paper"
  case notebook
  case postcard
  case minimal

  public var id: String { rawValue }
}

public enum MIRAWallTypographyPersonality: String, CaseIterable {
  case confession
  case loud
  case thought
  case editorial
  case chaos
}

public enum MIRAWallNoteAttachment: String {
  case tape
  case pin
  case paperclip
  case foldedCorner
  case none
}

public enum MIRAWallNoteEntrance: String {
  case drop
  case attach
  case unfold
  case slide
  case print
  case reveal
  case settle
}

public enum MIRAWallNoteRenderDetail: Equatable {
  case distant
  case compact
  case full
}

public enum MIRAWallPaperMaterial: String, CaseIterable {
  case ivory
  case notebook
  case kraft
  case graph
  case aged
  case photographic
  case coated
}

public enum MIRAWallPaperWarp: String, CaseIterable {
  case flat
  case topLeftLifted
  case bottomRightLifted
  case curledBottom
  case centerBend
}

public enum MIRAWallNoteVisualScale: String, CaseIterable {
  case hero
  case standard
  case tiny

  public var factor: CGFloat {
    switch self {
    case .hero: 1.34
    case .standard: 1.27
    case .tiny: 0.84
    }
  }
}

public struct MIRAWallNotePresentation: Equatable {
  public let style: MIRAWallNoteVisualStyle
  public let typography: MIRAWallTypographyPersonality
  public let attachment: MIRAWallNoteAttachment
  public let entrance: MIRAWallNoteEntrance
  public let material: MIRAWallPaperMaterial
  public let warp: MIRAWallPaperWarp
  public let visualScale: MIRAWallNoteVisualScale
  public let size: CGSize
  public let microRotation: Double
  public let usesAccentColor: Bool
  public let usesDarkPaper: Bool
}

public enum MIRAWallNotePresentationResolver {
  public static let supportedStyleTokens = Set(MIRAWallNoteVisualStyle.allCases.map(\.rawValue))

  public static func renderDetail(forWallScale scale: CGFloat, isFocused: Bool = false) -> MIRAWallNoteRenderDetail {
    if isFocused || scale >= 0.72 { return .full }
    if scale >= 0.42 { return .compact }
    return .distant
  }

  public static func wallLegibilityScale(forWallScale scale: CGFloat, isFocused: Bool = false) -> CGFloat {
    // A note's typography must remain part of one fixed physical composition.
    // The wall camera scales the complete card; scaling ink independently causes
    // text to jump and escape its paper bounds at pinch-gesture thresholds.
    _ = scale
    _ = isFocused
    return 1
  }

  public static func resolve(_ note: MIRAWallNote, hasLocalMedia: Bool = false) -> MIRAWallNotePresentation {
    let hash = stableHash(layoutSeed(for: note))
    let explicitCanvas = note.document?.canvas ?? note.canvas
    let hasMedia = hasLocalMedia || cleanMediaURL(note.mediaThumbnailUrl ?? note.mediaUrl) != nil
    let style = resolvedStyle(token: note.styleToken, hash: hash, hasMedia: hasMedia)
    let typography = typography(for: style, hash: hash, category: note.category)
    let attachment = attachment(for: style, hash: hash)
    let material = material(for: style, hash: hash)
    let warp = warp(for: style, hash: hash)
    let visualScale = visualScale(for: style, hash: hash, hasMedia: hasMedia)
    let baseSize = resolvedSize(note: note, style: style)
    let maxWidth: CGFloat = explicitCanvas == nil ? 470 : 520
    let maxHeight: CGFloat = explicitCanvas == nil ? 540 : 680
    let size = CGSize(
      width: min(maxWidth, baseSize.width * visualScale.factor),
      height: min(maxHeight, baseSize.height * visualScale.factor)
    )
    let rotationStep = Double(Int(hash % 23) - 11) / 10
    let microRotation = style == .receipt ? rotationStep * 0.35 : rotationStep
    let usesAccentColor = [MIRAWallNoteVisualStyle.sticky, .handwritten, .poster].contains(style)
      && hash % 5 != 0
    let usesDarkPaper = style == .poster && hash % 7 == 0

    return MIRAWallNotePresentation(
      style: style,
      typography: typography,
      attachment: attachment,
      entrance: entrance(for: style),
      material: material,
      warp: warp,
      visualScale: visualScale,
      size: size,
      microRotation: microRotation,
      usesAccentColor: usesAccentColor,
      usesDarkPaper: usesDarkPaper
    )
  }

  public static func recommendedSize(styleToken: String, text: String, hasMedia: Bool = false) -> CGSize {
    let hash = stableHash("composer:\(styleToken)")
    let style = resolvedStyle(token: styleToken, hash: hash, hasMedia: hasMedia)
    return recommendedSize(style: style, textLength: text.count)
  }

  public static func wallFrame(for note: MIRAWallNote) -> CGRect {
    let presentation = resolve(note)
    let rawCenter = CGPoint(
      x: note.worldX + note.width * 0.5,
      y: note.worldY + note.height * 0.5
    )
    return CGRect(
      x: rawCenter.x - presentation.size.width * 0.5,
      y: rawCenter.y - presentation.size.height * 0.5,
      width: presentation.size.width,
      height: presentation.size.height
    )
  }

  public static func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
      (partial ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  public static func layoutSeed(for note: MIRAWallNote) -> String {
    var seed = note.id
    if let canvas = note.document?.canvas ?? note.canvas {
      seed += ":canvas-v\(canvas.version)"
    } else if let updatedAt = note.document?.updatedAt ?? note.updatedAt {
      seed += ":updated-\(updatedAt)"
    }
    return seed
  }

  private static func resolvedStyle(token: String, hash: UInt64, hasMedia: Bool) -> MIRAWallNoteVisualStyle {
    if let explicit = MIRAWallNoteVisualStyle(rawValue: token) {
      if explicit == .polaroid, !hasMedia { return .postcard }
      return explicit
    }

    switch token {
    case "vertical_card":
      return [.receipt, .notebook, .poster][Int(hash % 3)]
    case "editorial":
      return hash.isMultiple(of: 3) ? .minimal : .editorial
    case "question":
      return hash.isMultiple(of: 2) ? .notebook : .poster
    case "confession":
      return hash.isMultiple(of: 2) ? .tornPaper : .editorial
    case "recommendation":
      return hasMedia ? .polaroid : .postcard
    case "torn_paper":
      return .tornPaper
    default:
      let styles: [MIRAWallNoteVisualStyle] = [
        .sticky, .handwritten, .editorial, .poster, .receipt,
        .tornPaper, .notebook, .postcard, .minimal,
      ]
      return styles[Int(hash % UInt64(styles.count))]
    }
  }

  private static func typography(
    for style: MIRAWallNoteVisualStyle,
    hash: UInt64,
    category: String?
  ) -> MIRAWallTypographyPersonality {
    switch style {
    case .editorial, .postcard, .polaroid:
      return .editorial
    case .poster:
      return hash.isMultiple(of: 3) ? .chaos : .loud
    case .handwritten, .notebook:
      return hash.isMultiple(of: 4) ? .chaos : .thought
    case .tornPaper, .minimal:
      return category == "question" ? .thought : .confession
    case .receipt:
      return .chaos
    case .sticky:
      return category == "confession" ? .confession : .thought
    }
  }

  private static func attachment(for style: MIRAWallNoteVisualStyle, hash: UInt64) -> MIRAWallNoteAttachment {
    switch style {
    case .receipt: return .tape
    case .notebook: return hash.isMultiple(of: 2) ? .paperclip : .pin
    case .postcard: return .foldedCorner
    case .minimal: return .none
    case .poster: return hash.isMultiple(of: 2) ? .tape : .pin
    case .polaroid: return .tape
    case .tornPaper: return hash.isMultiple(of: 2) ? .pin : .tape
    case .editorial: return hash.isMultiple(of: 3) ? .paperclip : .tape
    case .handwritten, .sticky: return hash.isMultiple(of: 2) ? .pin : .tape
    }
  }

  private static func material(for style: MIRAWallNoteVisualStyle, hash: UInt64) -> MIRAWallPaperMaterial {
    switch style {
    case .polaroid:
      return .photographic
    case .notebook:
      return hash.isMultiple(of: 4) ? .graph : .notebook
    case .receipt, .minimal:
      return .ivory
    case .postcard:
      return hash.isMultiple(of: 3) ? .kraft : .aged
    case .tornPaper:
      return hash.isMultiple(of: 2) ? .kraft : .aged
    case .poster:
      return hash.isMultiple(of: 7) ? .coated : (hash.isMultiple(of: 3) ? .kraft : .ivory)
    case .editorial:
      return hash.isMultiple(of: 5) ? .aged : .ivory
    case .handwritten:
      return hash.isMultiple(of: 3) ? .aged : .ivory
    case .sticky:
      return .ivory
    }
  }

  private static func warp(for style: MIRAWallNoteVisualStyle, hash: UInt64) -> MIRAWallPaperWarp {
    let options: [MIRAWallPaperWarp]
    switch style {
    case .polaroid:
      options = [.flat, .flat, .bottomRightLifted, .centerBend]
    case .receipt:
      options = [.curledBottom, .curledBottom, .centerBend]
    case .postcard, .minimal:
      options = [.flat, .bottomRightLifted, .topLeftLifted]
    default:
      options = [.flat, .topLeftLifted, .bottomRightLifted, .curledBottom, .centerBend]
    }
    return options[Int((hash / 17) % UInt64(options.count))]
  }

  private static func visualScale(
    for style: MIRAWallNoteVisualStyle,
    hash: UInt64,
    hasMedia: Bool
  ) -> MIRAWallNoteVisualScale {
    if hasMedia || style == .polaroid { return .hero }
    if [MIRAWallNoteVisualStyle.poster, .editorial].contains(style), hash % 4 == 0 {
      return .hero
    }
    if [MIRAWallNoteVisualStyle.receipt, .minimal, .handwritten].contains(style), hash % 11 == 0 {
      return .tiny
    }
    return .standard
  }

  private static func entrance(for style: MIRAWallNoteVisualStyle) -> MIRAWallNoteEntrance {
    switch style {
    case .sticky: .drop
    case .editorial, .notebook, .postcard: .unfold
    case .handwritten, .minimal: .reveal
    case .poster: .attach
    case .polaroid, .tornPaper: .slide
    case .receipt: .print
    }
  }

  private static func resolvedSize(note: MIRAWallNote, style: MIRAWallNoteVisualStyle) -> CGSize {
    if let canvas = note.document?.canvas ?? note.canvas {
      return canvasBackedSize(note: note, canvas: canvas)
    }
    if note.styleToken == MIRAWallNoteVisualStyle.polaroid.rawValue, style != .polaroid {
      return recommendedSize(style: style, textLength: note.body.count)
    }
    let looksLikeLegacyUniformCard = abs(note.width - note.height) < 10
      && note.width >= 176 && note.width <= 194
      && note.height >= 176 && note.height <= 194
    if supportedStyleTokens.contains(note.styleToken), !looksLikeLegacyUniformCard {
      return CGSize(
        width: min(360, max(96, note.width)),
        height: min(420, max(96, note.height))
      )
    }
    return recommendedSize(style: style, textLength: note.body.count)
  }

  private static func canvasBackedSize(note: MIRAWallNote, canvas: MIRANoteCanvas) -> CGSize {
    let aspect = CGFloat(max(0.32, min(1.9, canvas.aspectRatio)))
    let storedWidth = CGFloat(note.width)
    let preferredWidth: CGFloat
    if storedWidth.isFinite, storedWidth >= 96 {
      preferredWidth = storedWidth
    } else if aspect < 0.70 {
      preferredWidth = 204
    } else if aspect > 1.25 {
      preferredWidth = 318
    } else {
      preferredWidth = 244
    }

    let widthCap: CGFloat = aspect > 1.25 ? 390 : (aspect < 0.70 ? 276 : 330)
    var width = min(widthCap, max(176, preferredWidth))
    var height = width / aspect

    if height > 620 {
      height = 620
      width = height * aspect
    } else if height < 168 {
      height = 168
      width = height * aspect
    }

    return CGSize(width: width, height: height)
  }

  private static func recommendedSize(style: MIRAWallNoteVisualStyle, textLength: Int) -> CGSize {
    var size: CGSize
    switch style {
    case .sticky: size = CGSize(width: 188, height: 184)
    case .editorial: size = CGSize(width: 252, height: 202)
    case .handwritten: size = CGSize(width: 218, height: 178)
    case .poster: size = CGSize(width: 214, height: 258)
    case .polaroid: size = CGSize(width: 224, height: 272)
    case .receipt: size = CGSize(width: 142, height: 262)
    case .tornPaper: size = CGSize(width: 230, height: 184)
    case .notebook: size = CGSize(width: 208, height: 232)
    case .postcard: size = CGSize(width: 264, height: 174)
    case .minimal: size = CGSize(width: 244, height: 188)
    }

    if textLength > 210 {
      size.height = min(390, size.height + 62)
      if style == .receipt { size.height = min(400, size.height + 38) }
    } else if textLength > 120 {
      size.height = min(350, size.height + 34)
    } else if textLength < 34, [.editorial, .minimal, .handwritten].contains(style) {
      size.height = max(156, size.height - 18)
    }
    return size
  }

  private static func cleanMediaURL(_ value: String?) -> URL? {
    guard let value else { return nil }
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: clean), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
      return nil
    }
    return url
  }
}
