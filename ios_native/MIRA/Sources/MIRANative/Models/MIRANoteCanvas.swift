import Foundation

public enum MIRANoteCanvasTemplate: String, Codable, CaseIterable, Hashable {
  case journal
  case travelDiary = "travel_diary"
  case scrapbook
  case notebook
  case minimal
  case darkAlbum = "dark_album"
  case recipeBook = "recipe_book"
}

public enum MIRANoteCanvasElementKind: String, Codable, CaseIterable, Hashable {
  case photo
  case polaroid
  case text
  case handwrittenCaption = "handwritten_caption"
  case tornPaper = "torn_paper"
  case texturedPaper = "textured_paper"
  case tape
  case sticker
  case drawing
  case flower
  case shape
}

public enum MIRANoteCanvasTextAlignment: String, Codable, Hashable {
  case leading
  case center
  case trailing
}

public struct MIRANoteCanvasBackground: Codable, Hashable {
  public var material: String
  public var colorHex: String
  public var textureAsset: String?

  public init(
    material: String = "cotton_paper",
    colorHex: String = "#F4F0E7",
    textureAsset: String? = "captro-archival-paper"
  ) {
    self.material = material
    self.colorHex = colorHex
    self.textureAsset = textureAsset
  }

  private enum CodingKeys: String, CodingKey {
    case material
    case colorHex
    case textureAsset
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    material = try container.decodeIfPresent(String.self, forKey: .material) ?? "cotton_paper"
    colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#F4F0E7"
    textureAsset = try container.decodeIfPresent(String.self, forKey: .textureAsset)
      ?? "captro-archival-paper"
  }
}

public struct MIRANoteCanvasElementStyle: Codable, Hashable {
  public var material: String?
  public var colorHex: String?
  public var fontName: String?
  public var fontSize: Double?
  public var fontWeight: String?
  public var textAlignment: MIRANoteCanvasTextAlignment?
  public var cornerRadius: Double?
  public var borderWidth: Double?
  public var borderColorHex: String?
  public var shadowLevel: Int?
  public var stickerName: String?
  public var drawingName: String?
  public var shapeName: String?
  public var blendMode: String?

  public init(
    material: String? = nil,
    colorHex: String? = nil,
    fontName: String? = nil,
    fontSize: Double? = nil,
    fontWeight: String? = nil,
    textAlignment: MIRANoteCanvasTextAlignment? = nil,
    cornerRadius: Double? = nil,
    borderWidth: Double? = nil,
    borderColorHex: String? = nil,
    shadowLevel: Int? = nil,
    stickerName: String? = nil,
    drawingName: String? = nil,
    shapeName: String? = nil,
    blendMode: String? = nil
  ) {
    self.material = material
    self.colorHex = colorHex
    self.fontName = fontName
    self.fontSize = fontSize
    self.fontWeight = fontWeight
    self.textAlignment = textAlignment
    self.cornerRadius = cornerRadius
    self.borderWidth = borderWidth
    self.borderColorHex = borderColorHex
    self.shadowLevel = shadowLevel
    self.stickerName = stickerName
    self.drawingName = drawingName
    self.shapeName = shapeName
    self.blendMode = blendMode
  }

  private enum CodingKeys: String, CodingKey {
    case material
    case colorHex
    case fontName
    case fontSize
    case fontWeight
    case textAlignment
    case cornerRadius
    case borderWidth
    case borderColorHex
    case shadowLevel
    case stickerName
    case drawingName
    case shapeName
    case blendMode
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    material = try? container.decodeIfPresent(String.self, forKey: .material)
    colorHex = try? container.decodeIfPresent(String.self, forKey: .colorHex)
    fontName = try? container.decodeIfPresent(String.self, forKey: .fontName)
    fontWeight = try? container.decodeIfPresent(String.self, forKey: .fontWeight)
    borderColorHex = try? container.decodeIfPresent(String.self, forKey: .borderColorHex)
    stickerName = try? container.decodeIfPresent(String.self, forKey: .stickerName)
    drawingName = try? container.decodeIfPresent(String.self, forKey: .drawingName)
    shapeName = try? container.decodeIfPresent(String.self, forKey: .shapeName)
    blendMode = try? container.decodeIfPresent(String.self, forKey: .blendMode)

    if let rawAlignment = try? container.decode(String.self, forKey: .textAlignment) {
      textAlignment = MIRANoteCanvasTextAlignment(rawValue: rawAlignment)
    } else {
      textAlignment = nil
    }

    if let decodedFontSize = try? container.decode(Double.self, forKey: .fontSize) {
      fontSize = min(360, max(8, decodedFontSize))
    } else {
      fontSize = nil
    }
    if let decodedCornerRadius = try? container.decode(Double.self, forKey: .cornerRadius) {
      cornerRadius = min(240, max(0, decodedCornerRadius))
    } else {
      cornerRadius = nil
    }
    if let decodedBorderWidth = try? container.decode(Double.self, forKey: .borderWidth) {
      borderWidth = min(80, max(0, decodedBorderWidth))
    } else {
      borderWidth = nil
    }
    if let decodedShadow = try? container.decode(Int.self, forKey: .shadowLevel) {
      shadowLevel = min(8, max(0, decodedShadow))
    } else {
      shadowLevel = nil
    }
  }
}

/// A single object on a NoteCanvas. Geometry is normalized to the document's
/// coordinate space so the same composition renders identically at every size.
public struct MIRANoteCanvasElement: Codable, Identifiable, Hashable {
  public var id: String
  public var kind: MIRANoteCanvasElementKind
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public var rotation: Double
  public var zIndex: Int
  public var opacity: Double
  public var isLocked: Bool
  public var text: String?
  public var mediaAssetId: String?
  public var mediaUrl: String?
  public var thumbnailUrl: String?
  public var cropX: Double
  public var cropY: Double
  public var cropScale: Double
  public var style: MIRANoteCanvasElementStyle

  public init(
    id: String = UUID().uuidString,
    kind: MIRANoteCanvasElementKind,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    rotation: Double = 0,
    zIndex: Int = 0,
    opacity: Double = 1,
    isLocked: Bool = false,
    text: String? = nil,
    mediaAssetId: String? = nil,
    mediaUrl: String? = nil,
    thumbnailUrl: String? = nil,
    cropX: Double = 0.5,
    cropY: Double = 0.5,
    cropScale: Double = 1,
    style: MIRANoteCanvasElementStyle = MIRANoteCanvasElementStyle()
  ) {
    self.id = id
    self.kind = kind
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.rotation = rotation
    self.zIndex = zIndex
    self.opacity = opacity
    self.isLocked = isLocked
    self.text = text
    self.mediaAssetId = mediaAssetId
    self.mediaUrl = mediaUrl
    self.thumbnailUrl = thumbnailUrl
    self.cropX = cropX
    self.cropY = cropY
    self.cropScale = cropScale
    self.style = style
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case x
    case y
    case width
    case height
    case rotation
    case zIndex
    case opacity
    case isLocked
    case text
    case mediaAssetId
    case mediaUrl
    case thumbnailUrl
    case cropX
    case cropY
    case cropScale
    case style
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)

    id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    kind = rawKind.flatMap(MIRANoteCanvasElementKind.init(rawValue:)) ?? .text
    x = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5, -0.25...1.25)
    y = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5, -0.25...1.25)
    width = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .width) ?? 0.6, 0.02...1.5)
    height = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .height) ?? 0.25, 0.02...1.5)
    rotation = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0, -1_080...1_080)
    zIndex = min(1_000, max(-1_000, try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0))
    opacity = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1, 0...1)
    isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    text = try container.decodeIfPresent(String.self, forKey: .text)
    mediaAssetId = try container.decodeIfPresent(String.self, forKey: .mediaAssetId)
    mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
    thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
    cropX = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .cropX) ?? 0.5, 0...1)
    cropY = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .cropY) ?? 0.5, 0...1)
    cropScale = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .cropScale) ?? 1, 1...4)
    style = try container.decodeIfPresent(MIRANoteCanvasElementStyle.self, forKey: .style)
      ?? MIRANoteCanvasElementStyle()
  }

  private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, value))
  }
}

public struct MIRANoteCanvas: Codable, Hashable {
  public static let currentVersion = 1
  public static let defaultDesignWidth = 1080.0
  public static let defaultDesignHeight = 1620.0

  public var version: Int
  public var template: MIRANoteCanvasTemplate
  public var designWidth: Double
  public var designHeight: Double
  public var background: MIRANoteCanvasBackground
  public var elements: [MIRANoteCanvasElement]

  public init(
    version: Int = MIRANoteCanvas.currentVersion,
    template: MIRANoteCanvasTemplate = .journal,
    designWidth: Double = MIRANoteCanvas.defaultDesignWidth,
    designHeight: Double = MIRANoteCanvas.defaultDesignHeight,
    background: MIRANoteCanvasBackground = MIRANoteCanvasBackground(),
    elements: [MIRANoteCanvasElement] = []
  ) {
    self.version = version
    self.template = template
    self.designWidth = designWidth
    self.designHeight = designHeight
    self.background = background
    self.elements = elements
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case template
    case designWidth
    case designHeight
    case background
    case elements
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawTemplate = try container.decodeIfPresent(String.self, forKey: .template)

    version = max(1, try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion)
    template = rawTemplate.flatMap(MIRANoteCanvasTemplate.init(rawValue:)) ?? .journal
    designWidth = Self.clamp(
      try container.decodeIfPresent(Double.self, forKey: .designWidth) ?? Self.defaultDesignWidth,
      320...4_096
    )
    designHeight = Self.clamp(
      try container.decodeIfPresent(Double.self, forKey: .designHeight) ?? Self.defaultDesignHeight,
      320...8_192
    )
    background = try container.decodeIfPresent(MIRANoteCanvasBackground.self, forKey: .background)
      ?? MIRANoteCanvasBackground()
    elements = Array(
      (try container.decodeIfPresent([MIRANoteCanvasElement].self, forKey: .elements) ?? [])
        .prefix(80)
    )
  }

  public var aspectRatio: Double {
    max(0.25, designWidth / max(designHeight, 1))
  }

  public var orderedElements: [MIRANoteCanvasElement] {
    elements.sorted {
      if $0.zIndex == $1.zIndex { return $0.id < $1.id }
      return $0.zIndex < $1.zIndex
    }
  }

  public func replacingMedia(
    elementID: String,
    assetID: String?,
    url: String?,
    thumbnailURL: String?
  ) -> MIRANoteCanvas {
    var copy = self
    guard let index = copy.elements.firstIndex(where: { $0.id == elementID }) else { return copy }
    copy.elements[index].mediaAssetId = assetID
    copy.elements[index].mediaUrl = url
    copy.elements[index].thumbnailUrl = thumbnailURL
    return copy
  }

  private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, value))
  }

  /// Keeps legacy notes visible while all new notes use one persisted document.
  public static func legacyCanvas(for note: MIRAWallNote) -> MIRANoteCanvas {
    var elements: [MIRANoteCanvasElement] = []
    let cleanBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if note.mediaUrl != nil || note.mediaThumbnailUrl != nil {
      elements.append(
        MIRANoteCanvasElement(
          kind: .polaroid,
          x: 0.5,
          y: cleanBody.isEmpty ? 0.48 : 0.40,
          width: 0.82,
          height: cleanBody.isEmpty ? 0.72 : 0.60,
          rotation: note.rotation,
          zIndex: 10,
          mediaUrl: note.mediaUrl,
          thumbnailUrl: note.mediaThumbnailUrl,
          style: MIRANoteCanvasElementStyle(material: "polaroid", shadowLevel: 3)
        )
      )
    }

    if !cleanBody.isEmpty {
      elements.append(
        MIRANoteCanvasElement(
          kind: note.mediaUrl == nil ? .text : .handwrittenCaption,
          x: 0.5,
          y: note.mediaUrl == nil ? 0.48 : 0.78,
          width: note.mediaUrl == nil ? 0.76 : 0.72,
          height: note.mediaUrl == nil ? 0.50 : 0.18,
          rotation: note.mediaUrl == nil ? note.rotation : 0,
          zIndex: 20,
          text: cleanBody,
          style: MIRANoteCanvasElementStyle(
            material: note.styleToken,
            colorHex: "#16130F",
            fontName: note.mediaUrl == nil ? "NewYork" : "Noteworthy",
            fontSize: note.mediaUrl == nil ? 66 : 48,
            fontWeight: "regular",
            textAlignment: .leading,
            shadowLevel: 0
          )
        )
      )
    }

    return MIRANoteCanvas(
      template: note.mediaUrl == nil ? .journal : .scrapbook,
      background: MIRANoteCanvasBackground(
        material: note.styleToken.isEmpty ? "cotton_paper" : note.styleToken,
        colorHex: note.colorToken,
        textureAsset: "captro-archival-paper"
      ),
      elements: elements
    )
  }
}
