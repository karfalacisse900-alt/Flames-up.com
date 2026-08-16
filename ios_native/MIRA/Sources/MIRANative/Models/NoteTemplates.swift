import Foundation

public struct NoteTemplate: Identifiable, Hashable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let contentKind: NoteContentKind
  public let document: NoteDocument
}

public enum NoteTemplateLibrary {
  public static let templates: [NoteTemplate] = [
    darkPolaroidAlbum,
    recipePoster,
    bookReview,
    eventPoster,
    minimalMotivation,
    dailyNote,
    travelCollage,
    personalJournal,
    partyInvitation,
    minimalPhoto,
  ]

  public static func blank(format: NoteCanvasFormat = .portrait, authorID: String = "") -> NoteDocument {
    NoteDocument(
      authorID: authorID,
      canvas: format.blankCanvas(),
      artworkMode: .editableCanvas,
      contentKind: .artwork,
      visibility: .everyone
    )
  }

  public static func importedArtwork(mediaURL: String, caption: String? = nil, authorID: String = "", format: NoteCanvasFormat = .portrait) -> NoteDocument {
    var canvas = format.blankCanvas(background: .solid("#111111"))
    let size = format.canvasSize
    canvas.elements = [
      CanvasElement(
        kind: .photo,
        transform: ElementTransform(x: 0, y: 0, width: size.width, height: size.height, zIndex: 0),
        photo: PhotoElement(url: mediaURL, originalURL: mediaURL, presentation: .fullBleed),
        accessibilityLabel: caption ?? "Imported finished artwork"
      )
    ]
    return NoteDocument(
      authorID: authorID,
      canvas: canvas,
      artworkMode: .importedArtwork,
      contentKind: .poster,
      caption: caption,
      visibility: .everyone,
      thumbnailReference: mediaURL,
      altText: caption ?? "Imported poster or artwork"
    )
  }

  private static var darkPolaroidAlbum: NoteTemplate {
    NoteTemplate(
      id: "dark-polaroid-album",
      title: "Dark Polaroid Album",
      subtitle: "Coffee-table collage",
      contentKind: .collage,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.blackLeather),
          elements: [
            text("AFTER HOURS", x: 86, y: 92, width: 520, height: 80, size: 36, role: .label, weight: .semibold, color: "#F7F1E2", uppercase: true, z: 5),
            text("captured by you", x: 84, y: 1185, width: 360, height: 50, size: 24, role: .credit, color: "#E6DCCC", uppercase: true, z: 5),
            photoPlaceholder(x: 130, y: 255, width: 390, height: 500, style: .polaroid, rotation: -7, z: 2),
            photoPlaceholder(x: 485, y: 345, width: 420, height: 520, style: .polaroid, rotation: 5, z: 3),
            photoPlaceholder(x: 260, y: 690, width: 360, height: 470, style: .polaroid, rotation: -2, z: 4),
            tape(x: 235, y: 230, width: 210, height: 54, rotation: -10, z: 9),
            tape(x: 650, y: 338, width: 190, height: 52, rotation: 7, z: 9),
          ]
        ),
        artworkMode: .editableCanvas,
        contentKind: .collage
      )
    )
  }

  private static var recipePoster: NoteTemplate {
    NoteTemplate(
      id: "recipe-poster",
      title: "Recipe Poster",
      subtitle: "Clean cover with detail block",
      contentKind: .recipe,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.creamPaper),
          elements: [
            text("Sunday Citrus Cake", x: 155, y: 310, width: 770, height: 250, size: 86, role: .title, weight: .semibold, alignment: .center, color: "#162018", z: 5),
            text("a small kitchen note", x: 282, y: 575, width: 520, height: 72, size: 32, role: .subtitle, alignment: .center, color: "#68705F", z: 5),
            shape(x: 104, y: 158, width: 210, height: 148, fill: "#F6B35D", shape: .ellipse, z: 1),
            shape(x: 782, y: 185, width: 160, height: 210, fill: "#80A35A", shape: .ellipse, z: 1),
            shape(x: 126, y: 940, width: 240, height: 190, fill: "#D9674F", shape: .ellipse, z: 1),
            shape(x: 740, y: 970, width: 210, height: 165, fill: "#F2D46F", shape: .ellipse, z: 1),
          ]
        ),
        contentKind: .recipe,
        detailBlocks: [
          .recipe(NoteRecipeDetailBlock(title: "Sunday Citrus Cake", prepTime: "20 min", cookTime: "45 min", servings: "8", ingredients: ["Citrus", "Flour", "Butter", "Sugar"], steps: ["Mix the batter.", "Bake until golden.", "Finish with glaze."], sourceUrl: nil))
        ]
      )
    )
  }

  private static var bookReview: NoteTemplate {
    NoteTemplate(
      id: "book-review",
      title: "Book Review",
      subtitle: "Notebook and torn-paper notes",
      contentKind: .review,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.notebookPaper),
          elements: [
            text("BOOK NOTES", x: 90, y: 100, width: 480, height: 78, size: 44, role: .label, weight: .bold, color: "#202018", uppercase: true, z: 4),
            photoPlaceholder(x: 86, y: 245, width: 375, height: 460, style: .printed, rotation: -3, z: 2),
            paper(x: 522, y: 245, width: 420, height: 285, material: .agedPaper, rotation: 2, z: 2),
            text("favorite line lives here", x: 562, y: 300, width: 338, height: 138, size: 38, role: .handwriting, color: "#332B20", z: 4),
            paper(x: 140, y: 825, width: 760, height: 285, material: .whiteCottonPaper, rotation: -1, z: 2),
            text("Review fragment: what stayed with me after the last page.", x: 190, y: 875, width: 660, height: 150, size: 39, role: .body, color: "#141411", z: 5),
          ]
        ),
        contentKind: .review,
        detailBlocks: [
          .bookReview(NoteBookReviewDetailBlock(title: "Book Title", author: "Author", rating: 4.5, review: "Add your review after publishing.", favoriteQuote: nil, link: nil))
        ]
      )
    )
  }

  private static var eventPoster: NoteTemplate {
    NoteTemplate(
      id: "event-poster",
      title: "Event Poster",
      subtitle: "Bold flyer structure",
      contentKind: .event,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .gradient(["#111417", "#3C2438", "#F6B352"]),
          elements: [
            text("FRIDAY NIGHT", x: 92, y: 135, width: 895, height: 98, size: 62, role: .label, weight: .heavy, color: "#FFFFFF", uppercase: true, z: 4),
            text("COMEDY ROOM", x: 88, y: 265, width: 900, height: 250, size: 116, role: .title, weight: .heavy, color: "#FFFFFF", uppercase: true, z: 4),
            shape(x: 126, y: 610, width: 820, height: 6, fill: "#FFFFFF", z: 3),
            text("8 PM  /  144 MAIN ST", x: 100, y: 655, width: 860, height: 80, size: 45, role: .date, weight: .bold, alignment: .center, color: "#FFFFFF", z: 4),
            photoPlaceholder(x: 230, y: 795, width: 620, height: 390, style: .cutout, z: 2),
          ]
        ),
        contentKind: .event,
        detailBlocks: [
          .event(NoteEventDetailBlock(title: "Comedy Room", date: "Friday", startTime: "8:00 PM", endTime: nil, venue: "Venue name", address: nil, ticketUrl: nil, organizer: nil, ageRestriction: nil))
        ]
      )
    )
  }

  private static var minimalMotivation: NoteTemplate {
    NoteTemplate(
      id: "minimal-motivation",
      title: "Minimal Motivation",
      subtitle: "Type and negative space",
      contentKind: .poster,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .solid("#F7F4EC"),
          elements: [
            paper(x: 185, y: 388, width: 710, height: 350, material: .whiteCottonPaper, rotation: -2, z: 1),
            text("make it\nquietly beautiful", x: 230, y: 438, width: 620, height: 245, size: 76, role: .title, weight: .semibold, alignment: .center, color: "#171713", z: 4),
            text("CAPTRO NOTE", x: 365, y: 1045, width: 360, height: 48, size: 27, role: .credit, alignment: .center, color: "#747064", uppercase: true, z: 3),
          ]
        ),
        contentKind: .poster
      )
    )
  }

  private static var dailyNote: NoteTemplate {
    NoteTemplate(
      id: "daily-note",
      title: "Daily Note",
      subtitle: "Simple journal page",
      contentKind: .journal,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.whiteCottonPaper),
          elements: [
            text("Today", x: 92, y: 110, width: 440, height: 110, size: 80, role: .title, weight: .semibold, color: "#141411", z: 4),
            text("1. Notice the good light\n2. Send the message\n3. Make dinner slowly", x: 115, y: 310, width: 820, height: 360, size: 54, role: .body, color: "#1F221C", z: 4),
            shape(x: 96, y: 985, width: 720, height: 5, fill: "#151515", z: 2),
            text("signature", x: 100, y: 1018, width: 430, height: 74, size: 44, role: .handwriting, color: "#151515", z: 4),
          ]
        ),
        contentKind: .journal
      )
    )
  }

  private static var travelCollage: NoteTemplate {
    NoteTemplate(
      id: "travel-collage",
      title: "Travel Collage",
      subtitle: "Photos, ticket, location",
      contentKind: .memory,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.linen),
          elements: [
            text("Lisbon", x: 84, y: 102, width: 520, height: 130, size: 98, role: .title, weight: .semibold, color: "#172016", z: 5),
            photoPlaceholder(x: 92, y: 265, width: 440, height: 520, style: .printed, rotation: -3, z: 2),
            photoPlaceholder(x: 520, y: 350, width: 420, height: 470, style: .borderless, rotation: 2, z: 3),
            paper(x: 220, y: 850, width: 620, height: 170, material: .agedPaper, rotation: 1.5, z: 1),
            text("three days of bright tiles and late walks", x: 250, y: 890, width: 560, height: 90, size: 35, role: .caption, alignment: .center, color: "#221A12", z: 4),
          ]
        ),
        contentKind: .memory
      )
    )
  }

  private static var personalJournal: NoteTemplate {
    NoteTemplate(
      id: "personal-journal",
      title: "Personal Journal",
      subtitle: "Photo plus writing",
      contentKind: .journal,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .material(.watercolorPaper),
          elements: [
            text("June 12", x: 88, y: 96, width: 300, height: 58, size: 36, role: .date, color: "#5A675A", z: 4),
            photoPlaceholder(x: 88, y: 210, width: 570, height: 620, style: .rounded, z: 2),
            photoPlaceholder(x: 620, y: 710, width: 330, height: 330, style: .printed, rotation: 4, z: 3),
            text("A page for the part I want to remember.", x: 116, y: 900, width: 440, height: 210, size: 43, role: .body, color: "#1C211B", z: 5),
          ]
        ),
        contentKind: .journal
      )
    )
  }

  private static var partyInvitation: NoteTemplate {
    NoteTemplate(
      id: "party-invitation",
      title: "Party Invitation",
      subtitle: "Structured RSVP details",
      contentKind: .event,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .gradient(["#F8E16C", "#EF6B61", "#25476A"]),
          elements: [
            text("ROOFTOP", x: 96, y: 182, width: 880, height: 120, size: 84, role: .title, weight: .heavy, alignment: .center, color: "#FFFFFF", uppercase: true, z: 4),
            text("birthday party", x: 160, y: 315, width: 760, height: 122, size: 70, role: .subtitle, weight: .semibold, alignment: .center, color: "#FFFFFF", z: 4),
            text("SAT 9 PM", x: 250, y: 720, width: 580, height: 90, size: 58, role: .date, weight: .bold, alignment: .center, color: "#FFFFFF", z: 4),
            shape(x: 245, y: 845, width: 590, height: 78, fill: "#FFFFFF", cornerRadius: 39, z: 2),
            text("RSVP LINK BELOW", x: 302, y: 865, width: 480, height: 44, size: 28, role: .label, weight: .bold, alignment: .center, color: "#1D2A2E", uppercase: true, z: 5),
          ]
        ),
        contentKind: .event,
        detailBlocks: [
          .event(NoteEventDetailBlock(title: "Rooftop Birthday Party", date: "Saturday", startTime: "9:00 PM", endTime: nil, venue: "Rooftop", address: nil, ticketUrl: nil, organizer: nil, ageRestriction: nil))
        ]
      )
    )
  }

  private static var minimalPhoto: NoteTemplate {
    NoteTemplate(
      id: "minimal-photo",
      title: "Minimal Photo",
      subtitle: "One image, tiny caption",
      contentKind: .photo,
      document: NoteDocument(
        canvas: NoteCanvas(
          background: .solid("#F8F8F4"),
          elements: [
            photoPlaceholder(x: 0, y: 0, width: 1080, height: 1350, style: .fullBleed, z: 1),
            text("small caption", x: 72, y: 1220, width: 420, height: 52, size: 31, role: .caption, color: "#FFFFFF", z: 2),
          ]
        ),
        contentKind: .photo
      )
    )
  }

  private static func photoPlaceholder(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, style: PhotoPresentationStyle, rotation: Double = 0, z: Int) -> CanvasElement {
    CanvasElement(
      kind: .photo,
      transform: ElementTransform(x: x, y: y, width: width, height: height, rotation: rotation, zIndex: z),
      photo: PhotoElement(url: "", presentation: style),
      accessibilityLabel: "Photo placeholder"
    )
  }

  private static func text(
    _ value: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    role: TextRole,
    weight: TextWeight = .regular,
    alignment: TextAlignmentValue = .leading,
    color: String,
    uppercase: Bool = false,
    z: Int
  ) -> CanvasElement {
    CanvasElement(
      kind: .text,
      transform: ElementTransform(x: x, y: y, width: width, height: height, zIndex: z),
      text: TextElement(text: value, role: role, size: size, weight: weight, alignment: alignment, color: color, uppercase: uppercase),
      accessibilityLabel: value
    )
  }

  private static func paper(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, material: NoteMaterial, rotation: Double = 0, z: Int) -> CanvasElement {
    CanvasElement(kind: .paper, transform: ElementTransform(x: x, y: y, width: width, height: height, rotation: rotation, zIndex: z), material: material)
  }

  private static func tape(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotation: Double, z: Int) -> CanvasElement {
    CanvasElement(kind: .tape, transform: ElementTransform(x: x, y: y, width: width, height: height, rotation: rotation, opacity: 0.76, zIndex: z), accessibilityLabel: "Tape")
  }

  private static func shape(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fill: String, shape: ShapeKind = .rectangle, cornerRadius: CGFloat = 0, z: Int) -> CanvasElement {
    CanvasElement(kind: .shape, transform: ElementTransform(x: x, y: y, width: width, height: height, zIndex: z), shape: ShapeElement(shape: shape, fill: fill, cornerRadius: cornerRadius))
  }
}
