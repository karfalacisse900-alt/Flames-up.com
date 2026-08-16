import CoreGraphics
import Foundation

public enum NoteArtworkMode: String, Codable, Hashable, CaseIterable {
  case editableCanvas = "editable_canvas"
  case importedArtwork = "imported_artwork"
}

public enum NoteContentKind: String, Codable, Hashable, CaseIterable {
  case journal
  case collage
  case event
  case recipe
  case review
  case memory
  case link
  case poster
  case photo
  case artwork
}

public enum NoteVisibility: String, Codable, Hashable, CaseIterable {
  case everyone
  case friends
  case `private`
  case draft
}

public struct NoteDocument: Codable, Identifiable, Hashable {
  public var id: String
  public var schemaVersion: Int
  public var authorId: String
  public var canvas: NoteCanvas
  public var artworkMode: NoteArtworkMode
  public var contentKind: NoteContentKind?
  public var caption: String?
  public var detailBlocks: [NoteDetailBlock]
  public var visibility: NoteVisibility
  public var thumbnailReference: String?
  public var altText: String?
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    id: String = UUID().uuidString,
    schemaVersion: Int = 1,
    authorID: String = "",
    canvas: NoteCanvas,
    artworkMode: NoteArtworkMode = .editableCanvas,
    contentKind: NoteContentKind? = nil,
    caption: String? = nil,
    detailBlocks: [NoteDetailBlock] = [],
    visibility: NoteVisibility = .everyone,
    thumbnailReference: String? = nil,
    altText: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.authorId = authorID
    self.canvas = canvas
    self.artworkMode = artworkMode
    self.contentKind = contentKind
    self.caption = caption
    self.detailBlocks = detailBlocks
    self.visibility = visibility
    self.thumbnailReference = thumbnailReference
    self.altText = altText
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var canvasAspectRatio: CGFloat {
    guard canvas.designHeight > 0 else { return 1 }
    return canvas.designWidth / canvas.designHeight
  }
}

public struct NoteCanvas: Codable, Hashable {
  public var designWidth: CGFloat
  public var designHeight: CGFloat
  public var background: CanvasBackground
  public var elements: [CanvasElement]

  public init(
    designWidth: CGFloat = 1080,
    designHeight: CGFloat = 1350,
    background: CanvasBackground = .solid("#F8F5EE"),
    elements: [CanvasElement] = []
  ) {
    self.designWidth = designWidth
    self.designHeight = designHeight
    self.background = background
    self.elements = elements
  }
}

public enum NoteCanvasFormat: String, Codable, Hashable, CaseIterable, Identifiable {
  case square
  case portrait
  case posterStory
  case editorialPortrait
  case landscape
  case longPage

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .square: return "Square"
    case .portrait: return "Portrait"
    case .posterStory: return "Poster"
    case .editorialPortrait: return "Editorial"
    case .landscape: return "Landscape"
    case .longPage: return "Long Page"
    }
  }

  public var subtitle: String {
    switch self {
    case .square: return "1:1"
    case .portrait: return "4:5"
    case .posterStory: return "9:16"
    case .editorialPortrait: return "3:4"
    case .landscape: return "16:9"
    case .longPage: return "Journal"
    }
  }

  public var canvasSize: CGSize {
    switch self {
    case .square:
      return CGSize(width: 1080, height: 1080)
    case .portrait:
      return CGSize(width: 1080, height: 1350)
    case .posterStory:
      return CGSize(width: 1080, height: 1920)
    case .editorialPortrait:
      return CGSize(width: 1080, height: 1440)
    case .landscape:
      return CGSize(width: 1080, height: 608)
    case .longPage:
      return CGSize(width: 1080, height: 2400)
    }
  }

  public var aspectRatio: CGFloat {
    let size = canvasSize
    return size.width / size.height
  }

  public func blankCanvas(background: CanvasBackground = .material(.softNeutralPosterPaper)) -> NoteCanvas {
    let size = canvasSize
    return NoteCanvas(designWidth: size.width, designHeight: size.height, background: background, elements: [])
  }
}

public enum CanvasBackground: Codable, Hashable {
  case solid(String)
  case gradient([String])
  case image(String)
  case material(NoteMaterial)

  private enum CodingKeys: String, CodingKey {
    case type
    case value
    case colors
  }

  private enum Kind: String, Codable {
    case solid
    case gradient
    case image
    case material
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = (try? container.decode(Kind.self, forKey: .type)) ?? .solid
    switch type {
    case .solid:
      self = .solid((try? container.decode(String.self, forKey: .value)) ?? "#F8F5EE")
    case .gradient:
      self = .gradient((try? container.decode([String].self, forKey: .colors)) ?? ["#F8F5EE", "#ECE6D8"])
    case .image:
      self = .image((try? container.decode(String.self, forKey: .value)) ?? "")
    case .material:
      self = .material((try? container.decode(NoteMaterial.self, forKey: .value)) ?? .softNeutralPosterPaper)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .solid(let value):
      try container.encode(Kind.solid, forKey: .type)
      try container.encode(value, forKey: .value)
    case .gradient(let colors):
      try container.encode(Kind.gradient, forKey: .type)
      try container.encode(colors, forKey: .colors)
    case .image(let value):
      try container.encode(Kind.image, forKey: .type)
      try container.encode(value, forKey: .value)
    case .material(let material):
      try container.encode(Kind.material, forKey: .type)
      try container.encode(material, forKey: .value)
    }
  }
}

public enum NoteMaterial: String, Codable, Hashable, CaseIterable {
  case creamPaper = "cream_paper"
  case whiteCottonPaper = "white_cotton_paper"
  case agedPaper = "aged_paper"
  case linen
  case notebookPaper = "notebook_paper"
  case blackLeather = "black_leather"
  case darkCardstock = "dark_cardstock"
  case watercolorPaper = "watercolor_paper"
  case softNeutralPosterPaper = "soft_neutral_poster_paper"
}

public enum CanvasElementKind: String, Codable, Hashable, CaseIterable {
  case photo
  case text
  case paper
  case tape
  case sticker
  case drawing
  case shape
  case group
}

public struct CanvasElement: Codable, Identifiable, Hashable {
  public var id: String
  public var kind: CanvasElementKind
  public var transform: ElementTransform
  public var photo: PhotoElement?
  public var text: TextElement?
  public var shape: ShapeElement?
  public var material: NoteMaterial?
  public var preset: VisualPreset?
  public var isLocked: Bool
  public var isHidden: Bool
  public var accessibilityLabel: String?

  public init(
    id: String = UUID().uuidString,
    kind: CanvasElementKind,
    transform: ElementTransform,
    photo: PhotoElement? = nil,
    text: TextElement? = nil,
    shape: ShapeElement? = nil,
    material: NoteMaterial? = nil,
    preset: VisualPreset? = nil,
    isLocked: Bool = false,
    isHidden: Bool = false,
    accessibilityLabel: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.transform = transform
    self.photo = photo
    self.text = text
    self.shape = shape
    self.material = material
    self.preset = preset
    self.isLocked = isLocked
    self.isHidden = isHidden
    self.accessibilityLabel = accessibilityLabel
  }
}

public struct ElementTransform: Codable, Hashable {
  public var x: CGFloat
  public var y: CGFloat
  public var width: CGFloat
  public var height: CGFloat
  public var rotation: Double
  public var scaleX: CGFloat
  public var scaleY: CGFloat
  public var opacity: Double
  public var zIndex: Int

  public init(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    rotation: Double = 0,
    scaleX: CGFloat = 1,
    scaleY: CGFloat = 1,
    opacity: Double = 1,
    zIndex: Int = 0
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.rotation = rotation
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.opacity = opacity
    self.zIndex = zIndex
  }
}

public struct PhotoElement: Codable, Hashable {
  public var assetId: String
  public var url: String
  public var originalUrl: String?
  public var presentation: PhotoPresentationStyle
  public var crop: UnitRect

  public init(
    assetID: String = UUID().uuidString,
    url: String,
    originalURL: String? = nil,
    presentation: PhotoPresentationStyle = .borderless,
    crop: UnitRect = .full
  ) {
    self.assetId = assetID
    self.url = url
    self.originalUrl = originalURL
    self.presentation = presentation
    self.crop = crop
  }
}

public enum PhotoPresentationStyle: String, Codable, Hashable, CaseIterable {
  case borderless
  case printed
  case polaroid
  case tornEdge = "torn_edge"
  case rounded
  case circle
  case arch
  case fullBleed = "full_bleed"
  case cutout
}

public struct UnitRect: Codable, Hashable {
  public var x: CGFloat
  public var y: CGFloat
  public var width: CGFloat
  public var height: CGFloat

  public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)
}

public struct TextElement: Codable, Hashable {
  public var text: String
  public var role: TextRole
  public var fontName: String?
  public var size: CGFloat
  public var weight: TextWeight
  public var alignment: TextAlignmentValue
  public var lineSpacing: CGFloat
  public var letterSpacing: CGFloat
  public var color: String
  public var backgroundColor: String?
  public var uppercase: Bool

  public init(
    text: String,
    role: TextRole = .body,
    fontName: String? = nil,
    size: CGFloat = 44,
    weight: TextWeight = .regular,
    alignment: TextAlignmentValue = .leading,
    lineSpacing: CGFloat = 1,
    letterSpacing: CGFloat = 0,
    color: String = "#111111",
    backgroundColor: String? = nil,
    uppercase: Bool = false
  ) {
    self.text = text
    self.role = role
    self.fontName = fontName
    self.size = size
    self.weight = weight
    self.alignment = alignment
    self.lineSpacing = lineSpacing
    self.letterSpacing = letterSpacing
    self.color = color
    self.backgroundColor = backgroundColor
    self.uppercase = uppercase
  }
}

public enum TextRole: String, Codable, Hashable, CaseIterable {
  case title
  case subtitle
  case body
  case caption
  case handwriting
  case label
  case date
  case location
  case credit
}

public enum TextWeight: String, Codable, Hashable, CaseIterable {
  case regular
  case medium
  case semibold
  case bold
  case heavy
}

public enum TextAlignmentValue: String, Codable, Hashable, CaseIterable {
  case leading
  case center
  case trailing
}

public struct ShapeElement: Codable, Hashable {
  public var shape: ShapeKind
  public var fill: String
  public var stroke: String?
  public var strokeWidth: CGFloat
  public var cornerRadius: CGFloat

  public init(shape: ShapeKind = .rectangle, fill: String = "#FFFFFF", stroke: String? = nil, strokeWidth: CGFloat = 0, cornerRadius: CGFloat = 0) {
    self.shape = shape
    self.fill = fill
    self.stroke = stroke
    self.strokeWidth = strokeWidth
    self.cornerRadius = cornerRadius
  }
}

public enum ShapeKind: String, Codable, Hashable, CaseIterable {
  case rectangle
  case ellipse
  case line
}

public enum VisualPreset: String, Codable, Hashable, CaseIterable {
  case polaroid
  case printedPhotograph = "printed_photograph"
  case tornPhotograph = "torn_photograph"
  case tornPaper = "torn_paper"
  case crumpledPaper = "crumpled_paper"
  case notebookPaper = "notebook_paper"
  case receipt
  case paperclip
  case pushpin
  case driedFlower = "dried_flower"
  case leaf
  case handwrittenArrow = "handwritten_arrow"
  case highlightStrip = "highlight_strip"
  case paintStroke = "paint_stroke"
  case label
  case dateCard = "date_card"
}

public enum NoteDetailBlock: Codable, Identifiable, Hashable {
  case text(NoteTextDetailBlock)
  case event(NoteEventDetailBlock)
  case recipe(NoteRecipeDetailBlock)
  case bookReview(NoteBookReviewDetailBlock)
  case location(NoteLocationDetailBlock)
  case link(NoteLinkDetailBlock)
  case credits(NoteCreditsDetailBlock)

  public var id: String {
    switch self {
    case .text(let block): return block.id
    case .event(let block): return block.id
    case .recipe(let block): return block.id
    case .bookReview(let block): return block.id
    case .location(let block): return block.id
    case .link(let block): return block.id
    case .credits(let block): return block.id
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case payload
  }

  private enum Kind: String, Codable {
    case text
    case event
    case recipe
    case bookReview = "book_review"
    case location
    case link
    case credits
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = (try? container.decode(Kind.self, forKey: .type)) ?? .text
    switch type {
    case .text:
      self = .text(try container.decode(NoteTextDetailBlock.self, forKey: .payload))
    case .event:
      self = .event(try container.decode(NoteEventDetailBlock.self, forKey: .payload))
    case .recipe:
      self = .recipe(try container.decode(NoteRecipeDetailBlock.self, forKey: .payload))
    case .bookReview:
      self = .bookReview(try container.decode(NoteBookReviewDetailBlock.self, forKey: .payload))
    case .location:
      self = .location(try container.decode(NoteLocationDetailBlock.self, forKey: .payload))
    case .link:
      self = .link(try container.decode(NoteLinkDetailBlock.self, forKey: .payload))
    case .credits:
      self = .credits(try container.decode(NoteCreditsDetailBlock.self, forKey: .payload))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let payload):
      try container.encode(Kind.text, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .event(let payload):
      try container.encode(Kind.event, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .recipe(let payload):
      try container.encode(Kind.recipe, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .bookReview(let payload):
      try container.encode(Kind.bookReview, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .location(let payload):
      try container.encode(Kind.location, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .link(let payload):
      try container.encode(Kind.link, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case .credits(let payload):
      try container.encode(Kind.credits, forKey: .type)
      try container.encode(payload, forKey: .payload)
    }
  }
}

public struct NoteTextDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var heading: String
  public var body: String
  public var link: String?
}

public struct NoteEventDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var title: String
  public var date: String
  public var startTime: String?
  public var endTime: String?
  public var venue: String?
  public var address: String?
  public var ticketUrl: String?
  public var organizer: String?
  public var ageRestriction: String?
}

public struct NoteRecipeDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var title: String
  public var prepTime: String?
  public var cookTime: String?
  public var servings: String?
  public var ingredients: [String]
  public var steps: [String]
  public var sourceUrl: String?
}

public struct NoteBookReviewDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var title: String
  public var author: String?
  public var rating: Double?
  public var review: String
  public var favoriteQuote: String?
  public var link: String?
}

public struct NoteLocationDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var placeName: String
  public var city: String?
  public var mapUrl: String?
}

public struct NoteLinkDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var title: String
  public var description: String?
  public var url: String
}

public struct NoteCreditsDetailBlock: Codable, Identifiable, Hashable {
  public var id = UUID().uuidString
  public var photographer: String?
  public var designer: String?
  public var artist: String?
  public var source: String?
  public var collaborators: [String]
}

public enum NoteLegacyConverter {
  public static func document(from note: MIRANote) -> NoteDocument {
    let caption = note.body?.trimmingCharacters(in: .whitespacesAndNewlines)
    let media = note.mediaUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let kind: NoteContentKind = media.isEmpty ? .journal : .photo
    let canvas = media.isEmpty
      ? legacyTextCanvas(text: caption ?? "Note", color: note.color)
      : legacyPhotoCanvas(mediaURL: media, caption: caption)

    return NoteDocument(
      id: note.id,
      schemaVersion: 1,
      authorID: note.user?.id ?? "",
      canvas: canvas,
      artworkMode: media.isEmpty ? .editableCanvas : .importedArtwork,
      contentKind: kind,
      caption: caption?.isEmpty == false ? caption : nil,
      detailBlocks: note.detailBlocks ?? [],
      visibility: note.visibility ?? .everyone,
      thumbnailReference: note.thumbnailReference ?? media,
      altText: note.altText,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt
    )
  }

  private static func legacyPhotoCanvas(mediaURL: String, caption: String?) -> NoteCanvas {
    var elements: [CanvasElement] = [
      CanvasElement(
        kind: .photo,
        transform: ElementTransform(x: 0, y: 0, width: 1080, height: 1350, zIndex: 0),
        photo: PhotoElement(url: mediaURL, originalURL: mediaURL, presentation: .fullBleed),
        accessibilityLabel: "Imported note artwork"
      )
    ]

    if let caption, !caption.isEmpty {
      elements.append(
        CanvasElement(
          kind: .text,
          transform: ElementTransform(x: 84, y: 1130, width: 912, height: 128, zIndex: 2),
          text: TextElement(text: caption, role: .caption, size: 42, weight: .semibold, color: "#FFFFFF", backgroundColor: "#00000099"),
          accessibilityLabel: caption
        )
      )
    }

    return NoteCanvas(designWidth: 1080, designHeight: 1350, background: .solid("#111111"), elements: elements)
  }

  private static func legacyTextCanvas(text: String, color: String?) -> NoteCanvas {
    NoteCanvas(
      designWidth: 1080,
      designHeight: 1350,
      background: .solid(color?.isEmpty == false ? color! : "#F6E7D7"),
      elements: [
        CanvasElement(
          kind: .text,
          transform: ElementTransform(x: 112, y: 210, width: 856, height: 720, zIndex: 1),
          text: TextElement(text: text, role: .body, size: 68, weight: .semibold, alignment: .center, lineSpacing: 1.12, color: "#141411"),
          accessibilityLabel: text
        )
      ]
    )
  }
}
