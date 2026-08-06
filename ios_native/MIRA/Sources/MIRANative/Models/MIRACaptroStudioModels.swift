import CoreGraphics
import Foundation

public enum MIRACaptroStudioLayerKind: String, Codable, Hashable {
  case paper
  case photo
  case text
  case object
  case qrCode
  case dateStamp
}

public enum MIRACaptroStudioFontStyle: String, Codable, CaseIterable, Identifiable {
  case modern
  case editorial
  case handwritten
  case typewriter
  case cutout
  case script

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .modern: return "Modern"
    case .editorial: return "Editorial"
    case .handwritten: return "Handwritten"
    case .typewriter: return "Typewriter"
    case .cutout: return "Cutout"
    case .script: return "Script"
    }
  }
}

public enum MIRACaptroStudioObject: String, Codable, CaseIterable, Identifiable {
  case tape
  case paperclip
  case pushPin
  case ticket
  case cassette
  case television
  case polaroidFrame
  case passportStamp
  case pressedFlower
  case coffeeStain

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .tape: return "Tape"
    case .paperclip: return "Paperclip"
    case .pushPin: return "Push pin"
    case .ticket: return "Ticket"
    case .cassette: return "Cassette"
    case .television: return "Vintage TV"
    case .polaroidFrame: return "Photo frame"
    case .passportStamp: return "Passport stamp"
    case .pressedFlower: return "Pressed flower"
    case .coffeeStain: return "Coffee stain"
    }
  }

  public var systemImage: String {
    switch self {
    case .tape: return "rectangle.fill"
    case .paperclip: return "paperclip"
    case .pushPin: return "pin.fill"
    case .ticket: return "ticket.fill"
    case .cassette: return "recordingtape"
    case .television: return "tv"
    case .polaroidFrame: return "photo"
    case .passportStamp: return "seal"
    case .pressedFlower: return "camera.macro"
    case .coffeeStain: return "circle.dashed"
    }
  }
}

public struct MIRACaptroStudioLayer: Identifiable, Codable, Hashable {
  public var id: String
  public var kind: MIRACaptroStudioLayerKind
  public var x: CGFloat
  public var y: CGFloat
  public var width: CGFloat
  public var height: CGFloat
  public var scale: CGFloat
  public var rotation: CGFloat
  public var zIndex: Int
  public var text: String?
  public var fontStyle: MIRACaptroStudioFontStyle?
  public var colorToken: String
  public var secondaryColorToken: String?
  public var object: MIRACaptroStudioObject?
  public var mediaKey: String?
  public var value: String?
  public var opacity: CGFloat

  public init(
    id: String = UUID().uuidString,
    kind: MIRACaptroStudioLayerKind,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    scale: CGFloat = 1,
    rotation: CGFloat = 0,
    zIndex: Int,
    text: String? = nil,
    fontStyle: MIRACaptroStudioFontStyle? = nil,
    colorToken: String = "ink",
    secondaryColorToken: String? = nil,
    object: MIRACaptroStudioObject? = nil,
    mediaKey: String? = nil,
    value: String? = nil,
    opacity: CGFloat = 1
  ) {
    self.id = id
    self.kind = kind
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.scale = scale
    self.rotation = rotation
    self.zIndex = zIndex
    self.text = text
    self.fontStyle = fontStyle
    self.colorToken = colorToken
    self.secondaryColorToken = secondaryColorToken
    self.object = object
    self.mediaKey = mediaKey
    self.value = value
    self.opacity = opacity
  }

  public static func paper(color: String, zIndex: Int = 0) -> Self {
    Self(kind: .paper, x: 0.5, y: 0.5, width: 1, height: 1, zIndex: zIndex, colorToken: color)
  }

  public static func photo(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    rotation: CGFloat = 0,
    zIndex: Int,
    mediaKey: String = UUID().uuidString
  ) -> Self {
    Self(
      kind: .photo,
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
      zIndex: zIndex,
      colorToken: "photoPaper",
      mediaKey: mediaKey
    )
  }

  public static func text(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat = 0.16,
    rotation: CGFloat = 0,
    zIndex: Int,
    font: MIRACaptroStudioFontStyle = .handwritten,
    color: String = "ink"
  ) -> Self {
    Self(
      kind: .text,
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
      zIndex: zIndex,
      text: text,
      fontStyle: font,
      colorToken: color
    )
  }

  public static func object(
    _ object: MIRACaptroStudioObject,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    rotation: CGFloat = 0,
    zIndex: Int,
    color: String = "forest"
  ) -> Self {
    Self(
      kind: .object,
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
      zIndex: zIndex,
      colorToken: color,
      object: object
    )
  }

  public static func qrCode(x: CGFloat, y: CGFloat, width: CGFloat, zIndex: Int, value: String) -> Self {
    Self(
      kind: .qrCode,
      x: x,
      y: y,
      width: width,
      height: width,
      zIndex: zIndex,
      colorToken: "paper",
      value: value
    )
  }

  public static func dateStamp(x: CGFloat, y: CGFloat, width: CGFloat, rotation: CGFloat = 0, zIndex: Int) -> Self {
    Self(
      kind: .dateStamp,
      x: x,
      y: y,
      width: width,
      height: 0.07,
      rotation: rotation,
      zIndex: zIndex,
      colorToken: "stamp",
      value: ISO8601DateFormatter().string(from: Date())
    )
  }
}

public enum MIRACaptroStudioTemplate: String, Codable, CaseIterable, Identifiable {
  case blankPaper
  case vintageBroadcast
  case musicPocket
  case yearbook
  case memoryBox
  case travelJournal
  case filmStrip
  case letter

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .blankPaper: return "Blank Paper"
    case .vintageBroadcast: return "Vintage Broadcast"
    case .musicPocket: return "Music Pocket"
    case .yearbook: return "Yearbook"
    case .memoryBox: return "Memory Box"
    case .travelJournal: return "Travel Journal"
    case .filmStrip: return "Film Strip"
    case .letter: return "Letter"
    }
  }

  public var subtitle: String {
    switch self {
    case .blankPaper: return "Start with a clean page"
    case .vintageBroadcast: return "A memory on an old screen"
    case .musicPocket: return "Song, QR, and keepsakes"
    case .yearbook: return "Faces, captions, and signatures"
    case .memoryBox: return "Layer small moments together"
    case .travelJournal: return "Photos, tickets, and stamps"
    case .filmStrip: return "A sequence of three frames"
    case .letter: return "Write something worth keeping"
    }
  }

  public var systemImage: String {
    switch self {
    case .blankPaper: return "doc"
    case .vintageBroadcast: return "tv"
    case .musicPocket: return "recordingtape"
    case .yearbook: return "person.3.sequence"
    case .memoryBox: return "shippingbox"
    case .travelJournal: return "airplane"
    case .filmStrip: return "film.stack"
    case .letter: return "envelope"
    }
  }

  public func makeDocument() -> MIRACaptroStudioDocument {
    var layers: [MIRACaptroStudioLayer] = [.paper(color: backgroundToken)]

    switch self {
    case .blankPaper:
      layers.append(.text("Make this page yours", x: 0.5, y: 0.47, width: 0.72, zIndex: 1, font: .editorial))

    case .vintageBroadcast:
      layers.append(.text("A MOMENT WORTH REPLAYING", x: 0.5, y: 0.15, width: 0.78, zIndex: 1, font: .typewriter))
      layers.append(.object(.television, x: 0.5, y: 0.49, width: 0.72, height: 0.42, rotation: -0.02, zIndex: 2, color: "charcoal"))
      layers.append(.photo(x: 0.5, y: 0.46, width: 0.55, height: 0.28, rotation: -0.02, zIndex: 3))
      layers.append(.object(.tape, x: 0.50, y: 0.72, width: 0.28, height: 0.05, rotation: 0.03, zIndex: 4, color: "tape"))

    case .musicPocket:
      layers.append(.text("PLAY THIS MEMORY", x: 0.5, y: 0.14, width: 0.72, zIndex: 1, font: .cutout))
      layers.append(.object(.cassette, x: 0.38, y: 0.48, width: 0.47, height: 0.27, rotation: -0.06, zIndex: 2, color: "lavender"))
      layers.append(.qrCode(x: 0.73, y: 0.57, width: 0.21, zIndex: 3, value: "https://captro.app"))
      layers.append(.object(.paperclip, x: 0.78, y: 0.24, width: 0.12, height: 0.16, rotation: 0.34, zIndex: 4, color: "metal"))

    case .yearbook:
      layers.append(.text("THE PEOPLE I WILL REMEMBER", x: 0.5, y: 0.11, width: 0.83, zIndex: 1, font: .editorial))
      layers.append(.photo(x: 0.30, y: 0.34, width: 0.32, height: 0.26, rotation: -0.035, zIndex: 2, mediaKey: "yearbook-1"))
      layers.append(.photo(x: 0.70, y: 0.34, width: 0.32, height: 0.26, rotation: 0.025, zIndex: 3, mediaKey: "yearbook-2"))
      layers.append(.photo(x: 0.30, y: 0.66, width: 0.32, height: 0.26, rotation: 0.02, zIndex: 4, mediaKey: "yearbook-3"))
      layers.append(.photo(x: 0.70, y: 0.66, width: 0.32, height: 0.26, rotation: -0.03, zIndex: 5, mediaKey: "yearbook-4"))
      layers.append(.object(.pressedFlower, x: 0.50, y: 0.50, width: 0.14, height: 0.14, zIndex: 6, color: "rose"))

    case .memoryBox:
      layers.append(.text("LITTLE THINGS I KEPT", x: 0.5, y: 0.12, width: 0.75, zIndex: 1, font: .handwritten))
      layers.append(.photo(x: 0.34, y: 0.42, width: 0.43, height: 0.34, rotation: -0.07, zIndex: 2, mediaKey: "memory-1"))
      layers.append(.photo(x: 0.68, y: 0.64, width: 0.38, height: 0.29, rotation: 0.065, zIndex: 3, mediaKey: "memory-2"))
      layers.append(.object(.ticket, x: 0.70, y: 0.31, width: 0.38, height: 0.13, rotation: 0.08, zIndex: 4, color: "butter"))
      layers.append(.object(.paperclip, x: 0.49, y: 0.20, width: 0.10, height: 0.15, rotation: -0.18, zIndex: 5, color: "metal"))

    case .travelJournal:
      layers.append(.text("PLACES THAT CHANGED ME", x: 0.5, y: 0.12, width: 0.80, zIndex: 1, font: .typewriter))
      layers.append(.photo(x: 0.5, y: 0.43, width: 0.70, height: 0.45, rotation: -0.025, zIndex: 2))
      layers.append(.object(.passportStamp, x: 0.73, y: 0.73, width: 0.22, height: 0.16, rotation: -0.11, zIndex: 3, color: "stamp"))
      layers.append(.object(.ticket, x: 0.31, y: 0.76, width: 0.42, height: 0.13, rotation: 0.07, zIndex: 4, color: "sky"))
      layers.append(.dateStamp(x: 0.30, y: 0.22, width: 0.30, rotation: -0.03, zIndex: 5))

    case .filmStrip:
      layers.append(.text("THREE FRAMES / ONE DAY", x: 0.5, y: 0.10, width: 0.78, zIndex: 1, font: .modern))
      layers.append(.photo(x: 0.5, y: 0.30, width: 0.72, height: 0.22, zIndex: 2, mediaKey: "film-1"))
      layers.append(.photo(x: 0.5, y: 0.54, width: 0.72, height: 0.22, zIndex: 3, mediaKey: "film-2"))
      layers.append(.photo(x: 0.5, y: 0.78, width: 0.72, height: 0.22, zIndex: 4, mediaKey: "film-3"))

    case .letter:
      layers.append(.text("DEAR FUTURE ME,", x: 0.29, y: 0.18, width: 0.43, zIndex: 1, font: .typewriter))
      layers.append(.text("Write something you want to remember.", x: 0.5, y: 0.46, width: 0.72, height: 0.30, zIndex: 2, font: .handwritten))
      layers.append(.object(.passportStamp, x: 0.75, y: 0.78, width: 0.20, height: 0.15, rotation: -0.08, zIndex: 3, color: "stamp"))
      layers.append(.object(.coffeeStain, x: 0.22, y: 0.77, width: 0.24, height: 0.20, zIndex: 4, color: "coffee"))
    }

    return MIRACaptroStudioDocument(template: self, backgroundToken: backgroundToken, layers: layers)
  }

  private var backgroundToken: String {
    switch self {
    case .blankPaper, .letter: return "warmPaper"
    case .vintageBroadcast: return "sagePaper"
    case .musicPocket: return "lilacPaper"
    case .yearbook: return "schoolPaper"
    case .memoryBox: return "kraftPaper"
    case .travelJournal: return "travelPaper"
    case .filmStrip: return "charcoalPaper"
    }
  }
}

public struct MIRACaptroStudioDocument: Identifiable, Codable, Hashable {
  public var id: String
  public var template: MIRACaptroStudioTemplate
  public var backgroundToken: String
  public var layers: [MIRACaptroStudioLayer]

  public init(
    id: String = UUID().uuidString,
    template: MIRACaptroStudioTemplate,
    backgroundToken: String,
    layers: [MIRACaptroStudioLayer]
  ) {
    self.id = id
    self.template = template
    self.backgroundToken = backgroundToken
    self.layers = layers
  }

  public var nextZIndex: Int {
    (layers.map(\.zIndex).max() ?? -1) + 1
  }

  public mutating func duplicateLayer(id: String) -> String? {
    guard let original = layers.first(where: { $0.id == id }), original.kind != .paper else { return nil }
    var copy = original
    copy.id = UUID().uuidString
    copy.x = min(0.94, copy.x + 0.045)
    copy.y = min(0.94, copy.y + 0.045)
    copy.zIndex = nextZIndex
    if copy.kind == .photo {
      copy.mediaKey = UUID().uuidString
    }
    layers.append(copy)
    return copy.id
  }

  public mutating func deleteLayer(id: String) {
    layers.removeAll { $0.id == id && $0.kind != .paper }
  }

  public mutating func moveLayer(id: String, by delta: Int) {
    guard let index = layers.firstIndex(where: { $0.id == id }), layers[index].kind != .paper else { return }
    layers[index].zIndex = max(1, layers[index].zIndex + delta)
    normalizeZIndexes()
  }

  public mutating func normalizeZIndexes() {
    let paperLayers = layers.filter { $0.kind == .paper }
    let contentLayers = layers.filter { $0.kind != .paper }.sorted {
      if $0.zIndex == $1.zIndex { return $0.id < $1.id }
      return $0.zIndex < $1.zIndex
    }
    var normalized = paperLayers.map { layer -> MIRACaptroStudioLayer in
      var value = layer
      value.zIndex = 0
      return value
    }
    normalized.append(contentsOf: contentLayers.enumerated().map { offset, layer in
      var value = layer
      value.zIndex = offset + 1
      return value
    })
    layers = normalized
  }

  public static func clampedPosition(_ value: CGFloat) -> CGFloat {
    min(max(value, 0.04), 0.96)
  }

  public static func snappedPosition(_ value: CGFloat, threshold: CGFloat = 0.018) -> (value: CGFloat, snapped: Bool) {
    let clamped = clampedPosition(value)
    if abs(clamped - 0.5) <= threshold {
      return (0.5, true)
    }
    return (clamped, false)
  }
}
