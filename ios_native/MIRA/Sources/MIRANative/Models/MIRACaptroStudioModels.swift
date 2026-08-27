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

public enum MIRACaptroStudioPhotoFrame: String, Codable, CaseIterable, Identifiable {
  case print
  case polaroid
  case fullBleed
  case rounded
  case circle
  case arch
  case torn
  case cutout

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .print: return "Photo"
    case .polaroid: return "Polaroid"
    case .fullBleed: return "Full bleed"
    case .rounded: return "Rounded"
    case .circle: return "Circle"
    case .arch: return "Arch"
    case .torn: return "Torn"
    case .cutout: return "Cutout"
    }
  }
}

public enum MIRACaptroStudioObject: String, Codable, CaseIterable, Identifiable {
  case tornPaper
  case texturedPaper
  case decklePaper
  case gridPaper
  case newsprintPaper
  case blushPaper
  case midnightPaper
  case textilePaper
  case handDrawnArrow
  case organicShape
  case tape
  case coolTape
  case pen
  case paperclip
  case pushPin
  case ticket
  case cassette
  case television
  case polaroidFrame
  case passportStamp
  case pressedFlower
  case vintageRose
  case carnationBouquet
  case pinkRose
  case purpleBud
  case tapedBotanicals
  case pressedScatter
  case tapedYellowSprig
  case tapedEucalyptus
  case tapedBrownBloom
  case tapedBillyButton
  case tapedDryBranch
  case ivoryHydrangea
  case ivoryDaisy
  case ivoryPompom
  case ivoryAirySprig
  case driedSprig
  case pinkBabysBreath
  case whiteGerbera
  case magentaDaisy
  case tangerineDaisy
  case sunshineDaisy
  case limeDaisy
  case cyanDaisy
  case violetDaisy
  case impastoBlossom
  case peachRibbonRose
  case berryRibbonRose
  case sparkleCluster
  case starburstFrame
  case postageLabel
  case wavyUnderline
  case archiveStamp
  case quoteMarks
  case keepGoingBadge
  case makeItCountBadge
  case mainCharacterBadge
  case plotTwistSticker
  case noContextSticker
  case hahaSticker
  case moodSticker
  case beSeriousSticker
  case wovenSun
  case wovenBird
  case diamondTotem
  case textileRibbon
  case coffeeStain

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .tornPaper: return "Torn paper"
    case .texturedPaper: return "Paper scrap"
    case .decklePaper: return "Deckle paper"
    case .gridPaper: return "Grid paper"
    case .newsprintPaper: return "Newsprint"
    case .blushPaper: return "Blush paper"
    case .midnightPaper: return "Midnight paper"
    case .textilePaper: return "Woven paper"
    case .handDrawnArrow: return "Drawing"
    case .organicShape: return "Shape"
    case .tape: return "Tape"
    case .coolTape: return "Cool tape"
    case .pen: return "Pen"
    case .paperclip: return "Paperclip"
    case .pushPin: return "Push pin"
    case .ticket: return "Ticket"
    case .cassette: return "Cassette"
    case .television: return "Vintage TV"
    case .polaroidFrame: return "Photo frame"
    case .passportStamp: return "Passport stamp"
    case .pressedFlower: return "Pressed flower"
    case .vintageRose: return "Vintage rose"
    case .carnationBouquet: return "Carnations"
    case .pinkRose: return "Pink rose"
    case .purpleBud: return "Purple bud"
    case .tapedBotanicals: return "Taped botanicals"
    case .pressedScatter: return "Pressed scatter"
    case .tapedYellowSprig: return "Yellow sprig"
    case .tapedEucalyptus: return "Eucalyptus"
    case .tapedBrownBloom: return "Dried bloom"
    case .tapedBillyButton: return "Billy button"
    case .tapedDryBranch: return "Dried branch"
    case .ivoryHydrangea: return "Pressed hydrangea"
    case .ivoryDaisy: return "Pressed daisy"
    case .ivoryPompom: return "Pressed pom-pom"
    case .ivoryAirySprig: return "Airy sprig"
    case .driedSprig: return "Dried sprig"
    case .pinkBabysBreath: return "Pink bouquet"
    case .whiteGerbera: return "White gerbera"
    case .magentaDaisy: return "Magenta daisy"
    case .tangerineDaisy: return "Orange daisy"
    case .sunshineDaisy: return "Yellow daisy"
    case .limeDaisy: return "Lime daisy"
    case .cyanDaisy: return "Blue daisy"
    case .violetDaisy: return "Violet daisy"
    case .impastoBlossom: return "Painted blossom"
    case .peachRibbonRose: return "Peach ribbon rose"
    case .berryRibbonRose: return "Berry ribbon rose"
    case .sparkleCluster: return "Sparkles"
    case .starburstFrame: return "Starburst"
    case .postageLabel: return "Postage label"
    case .wavyUnderline: return "Wavy underline"
    case .archiveStamp: return "Archive stamp"
    case .quoteMarks: return "Quote marks"
    case .keepGoingBadge: return "Keep going"
    case .makeItCountBadge: return "Make it count"
    case .mainCharacterBadge: return "Main character"
    case .plotTwistSticker: return "Plot twist"
    case .noContextSticker: return "No context"
    case .hahaSticker: return "Ha ha"
    case .moodSticker: return "Mood"
    case .beSeriousSticker: return "Be serious"
    case .wovenSun: return "Woven sun"
    case .wovenBird: return "Woven bird"
    case .diamondTotem: return "Diamond motif"
    case .textileRibbon: return "Textile ribbon"
    case .coffeeStain: return "Coffee stain"
    }
  }

  public var systemImage: String {
    switch self {
    case .tornPaper: return "doc.text.image"
    case .texturedPaper: return "rectangle.on.rectangle"
    case .decklePaper, .gridPaper, .newsprintPaper, .blushPaper,
         .midnightPaper, .textilePaper:
      return "doc.text.image"
    case .handDrawnArrow: return "scribble.variable"
    case .organicShape: return "seal"
    case .tape: return "rectangle.fill"
    case .coolTape: return "rectangle.fill"
    case .pen: return "pencil"
    case .paperclip: return "paperclip"
    case .pushPin: return "pin.fill"
    case .ticket: return "ticket.fill"
    case .cassette: return "recordingtape"
    case .television: return "tv"
    case .polaroidFrame: return "photo"
    case .passportStamp: return "seal"
    case .pressedFlower, .vintageRose, .carnationBouquet, .pinkRose,
         .purpleBud, .tapedBotanicals, .pressedScatter,
         .tapedYellowSprig, .tapedEucalyptus, .tapedBrownBloom,
         .tapedBillyButton, .tapedDryBranch, .ivoryHydrangea,
         .ivoryDaisy, .ivoryPompom, .ivoryAirySprig, .driedSprig,
         .pinkBabysBreath, .whiteGerbera, .magentaDaisy,
         .tangerineDaisy, .sunshineDaisy, .limeDaisy, .cyanDaisy,
         .violetDaisy, .impastoBlossom, .peachRibbonRose,
         .berryRibbonRose:
      return "camera.macro"
    case .sparkleCluster, .starburstFrame, .postageLabel,
         .wavyUnderline, .archiveStamp:
      return "sparkles"
    case .quoteMarks, .keepGoingBadge, .makeItCountBadge,
         .mainCharacterBadge:
      return "quote.opening"
    case .plotTwistSticker, .noContextSticker, .hahaSticker,
         .moodSticker, .beSeriousSticker:
      return "face.smiling"
    case .wovenSun, .wovenBird, .diamondTotem, .textileRibbon:
      return "square.grid.3x3.fill"
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
  public var photoFrame: MIRACaptroStudioPhotoFrame?
  public var mediaKey: String?
  public var value: String?
  public var opacity: CGFloat
  public var isLocked: Bool?
  public var cropX: CGFloat?
  public var cropY: CGFloat?
  public var cropScale: CGFloat?
  public var fontSize: CGFloat?
  public var textAlignment: MIRANoteCanvasTextAlignment?
  public var letterSpacing: CGFloat?
  public var lineSpacing: CGFloat?

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
    photoFrame: MIRACaptroStudioPhotoFrame? = nil,
    mediaKey: String? = nil,
    value: String? = nil,
    opacity: CGFloat = 1,
    isLocked: Bool? = false,
    cropX: CGFloat? = nil,
    cropY: CGFloat? = nil,
    cropScale: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    textAlignment: MIRANoteCanvasTextAlignment? = nil,
    letterSpacing: CGFloat? = nil,
    lineSpacing: CGFloat? = nil
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
    self.photoFrame = photoFrame
    self.mediaKey = mediaKey
    self.value = value
    self.opacity = opacity
    self.isLocked = isLocked
    self.cropX = cropX
    self.cropY = cropY
    self.cropScale = cropScale
    self.fontSize = fontSize
    self.textAlignment = textAlignment
    self.letterSpacing = letterSpacing
    self.lineSpacing = lineSpacing
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
    frame: MIRACaptroStudioPhotoFrame = .polaroid,
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
      photoFrame: frame,
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
    color: String = "ink",
    fontSize: CGFloat? = nil,
    alignment: MIRANoteCanvasTextAlignment = .center,
    letterSpacing: CGFloat? = nil,
    lineSpacing: CGFloat? = nil
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
      colorToken: color,
      fontSize: fontSize,
      textAlignment: alignment,
      letterSpacing: letterSpacing,
      lineSpacing: lineSpacing
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
  case stationeryNote
  case landscapeQuote
  case tornPaperMotivation
  case photoHandwriting
  case botanicalCollage
  case editorialPortrait
  case minimalTypography
  case photoTornSection
  case photoOnly
  case blankPaper
  case vintageBroadcast
  case musicPocket
  case yearbook
  case memoryBox
  case travelJournal
  case filmStrip
  case letter
  case recipeBook
  case bookReview
  case eventPoster
  case partyInvitation
  case dailyNote
  case quotePoster
  case minimalPhoto
  case importedDesign

  public static var creationTemplates: [Self] {
    [
      .stationeryNote,
      .landscapeQuote,
      .tornPaperMotivation,
      .photoHandwriting,
      .botanicalCollage,
      .editorialPortrait,
      .minimalTypography,
      .photoTornSection,
      .photoOnly,
      .eventPoster,
      .partyInvitation,
      .bookReview,
      .recipeBook,
      .blankPaper,
      .importedDesign
    ]
  }

  public static var quickNoteTemplates: [Self] {
    [
      .stationeryNote,
      .tornPaperMotivation,
      .minimalTypography,
      .botanicalCollage,
      .landscapeQuote,
      .dailyNote,
      .letter,
      .quotePoster,
    ]
  }

  public static var demoTemplates: [Self] {
    [
      .stationeryNote,
      .landscapeQuote,
      .tornPaperMotivation,
      .photoHandwriting,
      .botanicalCollage,
      .editorialPortrait,
      .minimalTypography,
      .photoTornSection,
      .photoOnly,
      .importedDesign,
    ]
  }

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .stationeryNote: return "Notebook + Pen"
    case .landscapeQuote: return "Landscape Quote"
    case .tornPaperMotivation: return "Torn Paper"
    case .photoHandwriting: return "Photo + Handwriting"
    case .botanicalCollage: return "Botanical Collage"
    case .editorialPortrait: return "Editorial Portrait"
    case .minimalTypography: return "Minimal Type"
    case .photoTornSection: return "Photo + Torn Section"
    case .photoOnly: return "Photo Only"
    case .blankPaper: return "Minimal"
    case .vintageBroadcast: return "Vintage Broadcast"
    case .musicPocket: return "Music Pocket"
    case .yearbook: return "Journal"
    case .memoryBox: return "Scrapbook"
    case .travelJournal: return "Travel Diary"
    case .filmStrip: return "Dark Album"
    case .letter: return "Notebook"
    case .recipeBook: return "Recipe Book"
    case .bookReview: return "Book Review"
    case .eventPoster: return "Event Poster"
    case .partyInvitation: return "Invitation"
    case .dailyNote: return "Daily Note"
    case .quotePoster: return "Quote Poster"
    case .minimalPhoto: return "Minimal Photo"
    case .importedDesign: return "Finished Design"
    }
  }

  public var subtitle: String {
    switch self {
    case .stationeryNote: return "Lined paper, a real pen, and room to think"
    case .landscapeQuote: return "A photograph with layered paper and type"
    case .tornPaperMotivation: return "Deckled fibers, tape, and generous space"
    case .photoHandwriting: return "One strong photograph with a personal line"
    case .botanicalCollage: return "Pressed flowers, tickets, and paper scraps"
    case .editorialPortrait: return "Portraiture, bold type, and a color field"
    case .minimalTypography: return "One thought, one focal object, no clutter"
    case .photoTornSection: return "A custom photo mask with a tactile transition"
    case .photoOnly: return "Let a single photograph be the whole Note"
    case .blankPaper: return "Start with a clean page"
    case .vintageBroadcast: return "A memory on an old screen"
    case .musicPocket: return "Song, QR, and keepsakes"
    case .yearbook: return "Faces, captions, and signatures"
    case .memoryBox: return "Layer small moments together"
    case .travelJournal: return "Photos, tickets, and stamps"
    case .filmStrip: return "A sequence of three frames"
    case .letter: return "Write something worth keeping"
    case .recipeBook: return "Recipes, photos, and kitchen notes"
    case .bookReview: return "A visual review with room for notes"
    case .eventPoster: return "Flyers, shows, launches, and pop-ups"
    case .partyInvitation: return "A polished invite with date and place"
    case .dailyNote: return "A quiet page for the day"
    case .quotePoster: return "Large type and one clear idea"
    case .minimalPhoto: return "One image, carefully framed"
    case .importedDesign: return "Upload artwork from another app"
    }
  }

  public var systemImage: String {
    switch self {
    case .stationeryNote: return "pencil.and.list.clipboard"
    case .landscapeQuote: return "photo.on.rectangle.angled"
    case .tornPaperMotivation: return "doc.richtext"
    case .photoHandwriting: return "signature"
    case .botanicalCollage: return "camera.macro"
    case .editorialPortrait: return "person.crop.rectangle"
    case .minimalTypography: return "textformat"
    case .photoTornSection: return "rectangle.split.2x1"
    case .photoOnly: return "photo.fill"
    case .blankPaper: return "doc"
    case .vintageBroadcast: return "tv"
    case .musicPocket: return "recordingtape"
    case .yearbook: return "person.3.sequence"
    case .memoryBox: return "shippingbox"
    case .travelJournal: return "airplane"
    case .filmStrip: return "film.stack"
    case .letter: return "envelope"
    case .recipeBook: return "fork.knife"
    case .bookReview: return "book.closed"
    case .eventPoster: return "megaphone"
    case .partyInvitation: return "sparkles"
    case .dailyNote: return "calendar"
    case .quotePoster: return "quote.opening"
    case .minimalPhoto: return "photo"
    case .importedDesign: return "square.and.arrow.down.on.square"
    }
  }

  /// The document height is part of the authored composition. Journal-style
  /// templates intentionally use a taller page so the Wall preview and detail
  /// view render the exact same geometry without reflowing text or photos.
  public var canvasDesignHeight: Double {
    switch self {
    case .landscapeQuote:
      return 810
    case .tornPaperMotivation, .photoHandwriting, .editorialPortrait,
         .photoTornSection, .photoOnly, .blankPaper, .vintageBroadcast,
         .musicPocket, .filmStrip, .minimalPhoto:
      return 1_350
    case .eventPoster, .partyInvitation, .quotePoster, .importedDesign:
      return 1_920
    case .stationeryNote, .botanicalCollage, .minimalTypography,
         .yearbook, .memoryBox, .travelJournal, .letter, .recipeBook:
      return 1_620
    case .bookReview, .dailyNote:
      return 1_620
    }
  }

  public func makeDocument(message: String? = nil) -> MIRACaptroStudioDocument {
    var layers: [MIRACaptroStudioLayer] = [.paper(color: backgroundToken)]

    switch self {
    case .stationeryNote:
      layers.append(.object(.texturedPaper, x: 0.50, y: 0.51, width: 0.72, height: 0.70, rotation: -0.018, zIndex: 1, color: "schoolPaper"))
      layers.append(.text("THREE THINGS I WANT TO REMEMBER", x: 0.49, y: 0.21, width: 0.57, height: 0.12, zIndex: 2, font: .handwritten, color: "coffee", fontSize: 54, alignment: .leading, lineSpacing: 6))
      layers.append(.text("01  Give yourself room to begin.\n\n02  Keep the part that feels honest.\n\n03  Make the next small thing.", x: 0.47, y: 0.49, width: 0.54, height: 0.32, zIndex: 3, font: .typewriter, fontSize: 34, alignment: .leading, letterSpacing: 0.8, lineSpacing: 12))
      layers.append(.text("FOR THE DAYS THAT MOVE TOO FAST", x: 0.49, y: 0.76, width: 0.48, height: 0.06, zIndex: 4, font: .typewriter, color: "stamp", fontSize: 24, alignment: .leading, letterSpacing: 2))
      layers.append(.object(.pen, x: 0.76, y: 0.69, width: 0.12, height: 0.33, rotation: 0.28, zIndex: 5, color: "lavender"))

    case .landscapeQuote:
      layers.append(.photo(x: 0.50, y: 0.50, width: 1.0, height: 1.0, zIndex: 1, frame: .fullBleed, mediaKey: CaptroNoteAsset.mountainLake.rawValue))
      layers.append(.object(.texturedPaper, x: 0.38, y: 0.73, width: 0.50, height: 0.34, rotation: -0.018, zIndex: 2, color: "kraftPaper"))
      layers.append(.object(.tornPaper, x: 0.40, y: 0.69, width: 0.52, height: 0.34, rotation: 0.012, zIndex: 3, color: "paper"))
      layers.append(.object(.tape, x: 0.28, y: 0.52, width: 0.23, height: 0.09, rotation: -0.16, zIndex: 4, color: "tape"))
      layers.append(.text("FIELD NOTE / 06:42", x: 0.28, y: 0.61, width: 0.30, height: 0.05, zIndex: 5, font: .modern, color: "stamp", fontSize: 22, alignment: .leading, letterSpacing: 2.4))
      layers.append(.text("The quiet parts can carry you farther than the noise.", x: 0.41, y: 0.72, width: 0.42, height: 0.18, zIndex: 6, font: .typewriter, fontSize: 34, alignment: .leading, lineSpacing: 9))

    case .tornPaperMotivation:
      layers.append(.object(.texturedPaper, x: 0.52, y: 0.52, width: 0.72, height: 0.52, rotation: 0.035, zIndex: 1, color: "kraftPaper"))
      layers.append(.object(.tornPaper, x: 0.50, y: 0.48, width: 0.74, height: 0.52, rotation: -0.012, zIndex: 2, color: "paper"))
      layers.append(.object(.coolTape, x: 0.36, y: 0.22, width: 0.25, height: 0.09, rotation: -0.13, zIndex: 3, color: "metal"))
      layers.append(.text("DAILY NOTE", x: 0.50, y: 0.34, width: 0.48, height: 0.06, zIndex: 4, font: .script, color: "coffee", fontSize: 48))
      layers.append(.text("Pause. Take the breath. Give yourself another honest try.", x: 0.50, y: 0.52, width: 0.56, height: 0.20, zIndex: 5, font: .editorial, fontSize: 52, lineSpacing: 10))
      layers.append(.object(.handDrawnArrow, x: 0.50, y: 0.68, width: 0.18, height: 0.06, zIndex: 6, color: "coffee"))

    case .photoHandwriting:
      layers.append(.photo(x: 0.50, y: 0.50, width: 1.0, height: 1.0, zIndex: 1, frame: .fullBleed, mediaKey: CaptroNoteAsset.editorialPortrait.rawValue))
      layers.append(.text("STAY CLOSE TO\nWHAT FEELS TRUE", x: 0.09, y: 0.13, width: 0.70, height: 0.15, zIndex: 2, font: .modern, color: "white", fontSize: 32, alignment: .leading, letterSpacing: 3))
      layers.append(.text("good things grow quietly", x: 0.53, y: 0.86, width: 0.76, height: 0.11, rotation: -0.035, zIndex: 3, font: .script, color: "white", fontSize: 66))

    case .botanicalCollage:
      layers.append(.object(.texturedPaper, x: 0.39, y: 0.39, width: 0.46, height: 0.36, rotation: -0.055, zIndex: 1, color: "kraftPaper"))
      layers.append(.object(.tornPaper, x: 0.57, y: 0.46, width: 0.60, height: 0.43, rotation: 0.025, zIndex: 2, color: "paper"))
      layers.append(.object(.ticket, x: 0.33, y: 0.70, width: 0.36, height: 0.13, rotation: -0.08, zIndex: 3, color: "butter"))
      layers.append(.object(.pressedFlower, x: 0.72, y: 0.58, width: 0.32, height: 0.48, rotation: 0.11, zIndex: 4, color: "rose"))
      layers.append(.object(.paperclip, x: 0.32, y: 0.23, width: 0.08, height: 0.15, rotation: -0.22, zIndex: 5, color: "metal"))
      layers.append(.text("FOUND / KEPT / LOVED", x: 0.48, y: 0.31, width: 0.46, height: 0.08, zIndex: 6, font: .typewriter, color: "stamp", fontSize: 28, alignment: .leading, letterSpacing: 1.5))
      layers.append(.text("Collect the small evidence that life was beautiful here.", x: 0.47, y: 0.48, width: 0.44, height: 0.20, zIndex: 7, font: .handwritten, color: "coffee", fontSize: 48, alignment: .leading, lineSpacing: 7))

    case .editorialPortrait:
      layers.append(.text("BECOME", x: 0.08, y: 0.12, width: 0.62, height: 0.12, zIndex: 1, font: .cutout, color: "white", fontSize: 96, alignment: .leading, letterSpacing: 1.5))
      layers.append(.text("MORE\nYOURSELF", x: 0.08, y: 0.28, width: 0.78, height: 0.22, zIndex: 2, font: .editorial, color: "white", fontSize: 78, alignment: .leading, lineSpacing: 2))
      layers.append(.photo(x: 0.54, y: 0.66, width: 0.68, height: 0.58, zIndex: 3, frame: .arch, mediaKey: CaptroNoteAsset.editorialPortrait.rawValue))
      layers.append(.object(.pressedFlower, x: 0.76, y: 0.48, width: 0.25, height: 0.36, rotation: 0.13, zIndex: 4, color: "rose"))
      layers.append(.text("PORTRAIT STUDY / CAPTRO", x: 0.10, y: 0.92, width: 0.60, height: 0.05, zIndex: 5, font: .modern, color: "white", fontSize: 21, alignment: .leading, letterSpacing: 2.6))

    case .minimalTypography:
      layers.append(.text("MAKE ROOM\nFOR JOY.", x: 0.50, y: 0.27, width: 0.72, height: 0.22, zIndex: 1, font: .editorial, color: "ink", fontSize: 76, alignment: .leading, lineSpacing: 1))
      layers.append(.text("A SMALL REMINDER FOR TODAY", x: 0.50, y: 0.43, width: 0.72, height: 0.05, zIndex: 2, font: .modern, color: "stamp", fontSize: 22, alignment: .leading, letterSpacing: 3))
      layers.append(.photo(x: 0.55, y: 0.72, width: 0.48, height: 0.38, rotation: -0.018, zIndex: 3, frame: .rounded, mediaKey: CaptroNoteAsset.creamFlower.rawValue))

    case .photoTornSection:
      layers.append(.photo(x: 0.50, y: 0.38, width: 0.84, height: 0.58, rotation: -0.018, zIndex: 1, frame: .cutout, mediaKey: CaptroNoteAsset.editorialPortrait.rawValue))
      layers.append(.object(.tornPaper, x: 0.50, y: 0.75, width: 0.84, height: 0.38, rotation: 0.014, zIndex: 2, color: "paper"))
      layers.append(.object(.tape, x: 0.70, y: 0.51, width: 0.23, height: 0.08, rotation: 0.14, zIndex: 3, color: "tape"))
      layers.append(.text("CALL YOURSELF BACK", x: 0.50, y: 0.67, width: 0.66, height: 0.08, zIndex: 4, font: .typewriter, color: "stamp", fontSize: 30, alignment: .leading, letterSpacing: 1.5))
      layers.append(.text("You are allowed to begin again from exactly where you are.", x: 0.50, y: 0.78, width: 0.66, height: 0.15, zIndex: 5, font: .handwritten, color: "ink", fontSize: 48, alignment: .leading, lineSpacing: 7))
      layers.append(.object(.handDrawnArrow, x: 0.76, y: 0.90, width: 0.18, height: 0.07, rotation: -0.08, zIndex: 6, color: "stamp"))

    case .photoOnly:
      layers.append(.photo(x: 0.50, y: 0.50, width: 1.0, height: 1.0, zIndex: 1, frame: .fullBleed, mediaKey: CaptroNoteAsset.oceanShore.rawValue))

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

    case .recipeBook:
      layers.append(.text("MY RECIPE BOOK", x: 0.5, y: 0.12, width: 0.78, zIndex: 1, font: .editorial, color: "rust"))
      layers.append(.photo(x: 0.34, y: 0.43, width: 0.46, height: 0.34, rotation: -0.045, zIndex: 2, mediaKey: "recipe-1"))
      layers.append(.photo(x: 0.70, y: 0.67, width: 0.40, height: 0.30, rotation: 0.045, zIndex: 3, mediaKey: "recipe-2"))
      layers.append(.text("Ingredients, memories, and the little details worth making again.", x: 0.67, y: 0.37, width: 0.43, height: 0.24, zIndex: 4, font: .handwritten))
      layers.append(.object(.pressedFlower, x: 0.20, y: 0.78, width: 0.17, height: 0.17, rotation: -0.12, zIndex: 5, color: "sage"))

    case .bookReview:
      layers.append(.text("BOOK NOTES", x: 0.5, y: 0.11, width: 0.70, zIndex: 1, font: .editorial))
      layers.append(.photo(x: 0.34, y: 0.42, width: 0.42, height: 0.48, rotation: -0.025, zIndex: 2, mediaKey: "book-cover"))
      layers.append(.text("Title / author", x: 0.70, y: 0.32, width: 0.36, height: 0.12, zIndex: 3, font: .typewriter))
      layers.append(.text("A few lines about what stayed with you.", x: 0.67, y: 0.56, width: 0.40, height: 0.24, zIndex: 4, font: .handwritten))
      layers.append(.object(.tornPaper, x: 0.66, y: 0.73, width: 0.42, height: 0.16, rotation: 0.03, zIndex: 5, color: "paper"))

    case .eventPoster:
      layers.append(.text("SATURDAY NIGHT", x: 0.5, y: 0.16, width: 0.78, height: 0.15, zIndex: 1, font: .cutout, color: "white"))
      layers.append(.photo(x: 0.5, y: 0.48, width: 0.78, height: 0.42, zIndex: 2, frame: .print))
      layers.append(.text("COMEDY / MUSIC / POP-UP", x: 0.5, y: 0.73, width: 0.76, height: 0.08, zIndex: 3, font: .modern, color: "white"))
      layers.append(.text("8PM  -  123 MAIN", x: 0.5, y: 0.84, width: 0.62, height: 0.06, zIndex: 4, font: .typewriter, color: "white"))

    case .partyInvitation:
      layers.append(.text("YOU'RE INVITED", x: 0.5, y: 0.17, width: 0.76, height: 0.12, zIndex: 1, font: .script, color: "rose"))
      layers.append(.photo(x: 0.5, y: 0.45, width: 0.66, height: 0.36, rotation: 0.015, zIndex: 2, frame: .print))
      layers.append(.text("FRIDAY / 7PM", x: 0.5, y: 0.72, width: 0.56, height: 0.08, zIndex: 3, font: .editorial))
      layers.append(.object(.pressedFlower, x: 0.25, y: 0.78, width: 0.16, height: 0.16, rotation: -0.12, zIndex: 4, color: "rose"))

    case .dailyNote:
      layers.append(.dateStamp(x: 0.28, y: 0.12, width: 0.34, rotation: -0.02, zIndex: 1))
      layers.append(.text("TODAY FELT LIKE", x: 0.5, y: 0.24, width: 0.70, height: 0.10, zIndex: 2, font: .typewriter))
      layers.append(.text("Write the sentence you want to keep.", x: 0.5, y: 0.48, width: 0.72, height: 0.30, zIndex: 3, font: .handwritten))
      layers.append(.object(.coffeeStain, x: 0.72, y: 0.76, width: 0.24, height: 0.18, zIndex: 4, color: "coffee"))

    case .quotePoster:
      layers.append(.text("MAKE IT\nMEAN\nSOMETHING", x: 0.5, y: 0.43, width: 0.78, height: 0.36, zIndex: 1, font: .cutout, color: "white"))
      layers.append(.text("- CAPTRO", x: 0.5, y: 0.74, width: 0.38, height: 0.05, zIndex: 2, font: .typewriter, color: "white"))

    case .minimalPhoto:
      layers.append(.photo(x: 0.5, y: 0.45, width: 0.90, height: 0.70, zIndex: 1, frame: .print))
      layers.append(.text("small caption", x: 0.5, y: 0.86, width: 0.62, height: 0.07, zIndex: 2, font: .modern))

    case .importedDesign:
      layers.append(.photo(x: 0.5, y: 0.5, width: 1.0, height: 1.0, zIndex: 1, frame: .fullBleed, mediaKey: CaptroNoteAsset.venueNight.rawValue))
      layers.append(.text("NIGHT SHIFT", x: 0.10, y: 0.15, width: 0.72, height: 0.11, zIndex: 2, font: .cutout, color: "white", fontSize: 82, alignment: .leading, letterSpacing: 1.2))
      layers.append(.text("ONE NIGHT / ONE ROOM / NO REWIND", x: 0.10, y: 0.88, width: 0.72, height: 0.06, zIndex: 3, font: .modern, color: "white", fontSize: 22, alignment: .leading, letterSpacing: 2.2))
    }

    let cleanMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cleanMessage.isEmpty,
       let index = layers.indices
         .filter({ layers[$0].kind == .text })
         .max(by: { layers[$0].width * layers[$0].height < layers[$1].width * layers[$1].height }) {
      layers[index].text = String(cleanMessage.prefix(1_000))
    }

    return MIRACaptroStudioDocument(template: self, backgroundToken: backgroundToken, layers: layers)
  }

  private var backgroundToken: String {
    switch self {
    case .stationeryNote: return "sunlitPaper"
    case .landscapeQuote: return "bluePaper"
    case .tornPaperMotivation: return "bluePaper"
    case .photoHandwriting: return "charcoalPaper"
    case .botanicalCollage: return "cottonPaper"
    case .editorialPortrait: return "burgundy"
    case .minimalTypography: return "cottonPaper"
    case .photoTornSection: return "bluePaper"
    case .photoOnly: return "charcoalPaper"
    case .blankPaper, .letter: return "warmPaper"
    case .vintageBroadcast: return "sagePaper"
    case .musicPocket: return "lilacPaper"
    case .yearbook: return "schoolPaper"
    case .memoryBox: return "kraftPaper"
    case .travelJournal: return "travelPaper"
    case .filmStrip: return "charcoalPaper"
    case .recipeBook: return "recipePaper"
    case .bookReview, .dailyNote, .minimalPhoto: return "warmPaper"
    case .eventPoster, .quotePoster: return "charcoalPaper"
    case .partyInvitation: return "lilacPaper"
    case .importedDesign: return "white"
    }
  }

  public var noteCanvasTemplate: MIRANoteCanvasTemplate {
    switch self {
    case .stationeryNote: return .notebook
    case .landscapeQuote: return .travelDiary
    case .tornPaperMotivation: return .minimalMotivation
    case .photoHandwriting, .photoOnly: return .minimalPhoto
    case .botanicalCollage, .photoTornSection: return .scrapbook
    case .editorialPortrait: return .eventPoster
    case .minimalTypography: return .minimal
    case .yearbook: return .journal
    case .travelJournal: return .travelDiary
    case .memoryBox, .vintageBroadcast, .musicPocket: return .scrapbook
    case .letter: return .notebook
    case .blankPaper: return .minimal
    case .filmStrip: return .darkAlbum
    case .recipeBook: return .recipeBook
    case .bookReview: return .scrapbook
    case .eventPoster, .partyInvitation, .quotePoster: return .minimal
    case .dailyNote: return .journal
    case .minimalPhoto: return .minimal
    case .importedDesign: return .importedArtwork
    }
  }

  public var noteCanvasFormat: MIRANoteCanvasFormat {
    switch self {
    case .landscapeQuote:
      return .landscape4x3
    case .tornPaperMotivation, .photoHandwriting, .editorialPortrait,
         .photoTornSection, .photoOnly, .blankPaper, .vintageBroadcast,
         .musicPocket, .filmStrip, .minimalPhoto:
      return .portrait4x5
    case .eventPoster, .partyInvitation, .quotePoster, .importedDesign:
      return .poster9x16
    case .stationeryNote, .botanicalCollage, .minimalTypography,
         .yearbook, .memoryBox, .travelJournal, .letter, .recipeBook,
         .bookReview, .dailyNote:
      return .portrait2x3
    }
  }

  public var noteContentKind: MIRANoteContentKind {
    switch self {
    case .stationeryNote, .tornPaperMotivation, .minimalTypography: return .journal
    case .landscapeQuote: return .travelRecap
    case .photoHandwriting, .photoOnly: return .minimalPhoto
    case .botanicalCollage, .photoTornSection: return .scrapbook
    case .editorialPortrait: return .artwork
    case .blankPaper, .letter, .dailyNote: return .journal
    case .vintageBroadcast, .memoryBox, .yearbook: return .scrapbook
    case .musicPocket, .filmStrip: return .photoCollage
    case .travelJournal: return .travelRecap
    case .recipeBook: return .recipe
    case .bookReview: return .bookReview
    case .eventPoster: return .eventPoster
    case .partyInvitation: return .partyInvitation
    case .quotePoster: return .quote
    case .minimalPhoto: return .minimalPhoto
    case .importedDesign: return .importedDesign
    }
  }
}

public enum MIRACaptroStudioDemoFixtures {
  /// Ten deliberately different documents used by previews and regression
  /// tests to verify that the Wall can display a varied body of visual work.
  public static var documents: [MIRACaptroStudioDocument] {
    MIRACaptroStudioTemplate.demoTemplates.map { $0.makeDocument() }
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
    if copy.kind == .photo,
       let mediaKey = copy.mediaKey,
       CaptroNoteAsset.resolve(mediaKey) == nil {
      copy.mediaKey = UUID().uuidString
    }
    copy.x = min(0.94, copy.x + 0.045)
    copy.y = min(0.94, copy.y + 0.045)
    copy.zIndex = nextZIndex
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
