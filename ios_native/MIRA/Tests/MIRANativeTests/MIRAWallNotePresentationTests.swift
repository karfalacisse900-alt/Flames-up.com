import CoreGraphics
import Foundation
import XCTest
@testable import MIRANative

final class MIRAWallNotePresentationTests: XCTestCase {
  func testPresentationIsStableForTheSameNote() {
    let note = makeNote(id: "stable-note", style: "sticky_square")

    XCTAssertEqual(
      MIRAWallNotePresentationResolver.resolve(note),
      MIRAWallNotePresentationResolver.resolve(note)
    )
  }

  func testEveryExplicitStyleResolvesWithoutChangingIdentity() {
    for style in MIRAWallNoteVisualStyle.allCases {
      let media = style == .polaroid ? "https://media.captro.app/note.jpg" : nil
      let note = makeNote(id: "note-\(style.rawValue)", style: style.rawValue, mediaURL: media)
      let presentation = MIRAWallNotePresentationResolver.resolve(note)

      XCTAssertEqual(presentation.style, style)
      XCTAssertGreaterThanOrEqual(presentation.size.width, 96)
      XCTAssertLessThanOrEqual(presentation.size.width, 470)
      XCTAssertGreaterThanOrEqual(presentation.size.height, 96)
      XCTAssertLessThanOrEqual(presentation.size.height, 540)
    }
  }

  func testPolaroidRequiresRealMedia() {
    let withoutMedia = makeNote(id: "empty-polaroid", style: "polaroid")
    let withMedia = makeNote(
      id: "real-polaroid",
      style: "polaroid",
      mediaURL: "https://media.captro.app/notes/real-photo.jpg"
    )

    let fallback = MIRAWallNotePresentationResolver.resolve(withoutMedia)
    XCTAssertEqual(fallback.style, .postcard)
    XCTAssertGreaterThan(fallback.size.width, fallback.size.height)
    XCTAssertEqual(MIRAWallNotePresentationResolver.resolve(withMedia).style, .polaroid)
  }

  func testLocalComposerPhotoUsesPolaroidBeforeUploadCompletes() {
    let note = makeNote(id: "local-photo-preview", style: "polaroid")

    XCTAssertEqual(
      MIRAWallNotePresentationResolver.resolve(note, hasLocalMedia: true).style,
      .polaroid
    )
  }

  func testPhotoNotesUsePhotographicStockAndHeroScale() {
    let note = makeNote(
      id: "photo-material",
      style: "polaroid",
      mediaURL: "https://media.captro.app/notes/photo.jpg"
    )
    let presentation = MIRAWallNotePresentationResolver.resolve(note)

    XCTAssertEqual(presentation.material, .photographic)
    XCTAssertEqual(presentation.visualScale, .hero)
    XCTAssertGreaterThan(presentation.size.width, 224)
    XCTAssertGreaterThan(presentation.size.height, 272)
  }

  func testNotebookUsesRuledOrGraphPaperMaterial() {
    let presentation = MIRAWallNotePresentationResolver.resolve(
      makeNote(id: "notebook-material", style: "notebook")
    )

    XCTAssertTrue([MIRAWallPaperMaterial.notebook, .graph].contains(presentation.material))
  }

  func testPrimaryNotesAreApproximatelyTwentyFiveToThirtyFivePercentLarger() {
    let note = makeNote(id: "standard-scale", style: "sticky")
    let presentation = MIRAWallNotePresentationResolver.resolve(note)

    XCTAssertEqual(presentation.visualScale, .standard)
    XCTAssertEqual(presentation.size.width, 188 * 1.27, accuracy: 0.001)
    XCTAssertEqual(presentation.size.height, 184 * 1.27, accuracy: 0.001)
  }

  func testWallFrameExpandsAroundOriginalNoteCenter() {
    let note = makeNote(id: "expanded-frame", style: "sticky")
    let presentation = MIRAWallNotePresentationResolver.resolve(note)
    let frame = MIRAWallNotePresentationResolver.wallFrame(for: note)

    XCTAssertEqual(frame.midX, note.worldX + note.width * 0.5, accuracy: 0.001)
    XCTAssertEqual(frame.midY, note.worldY + note.height * 0.5, accuracy: 0.001)
    XCTAssertEqual(frame.width, presentation.size.width, accuracy: 0.001)
    XCTAssertEqual(frame.height, presentation.size.height, accuracy: 0.001)
  }

  func testScaleClassesRemainDeterministicAndCompositionIncludesHierarchy() {
    let presentations = (0..<320).map { index in
      MIRAWallNotePresentationResolver.resolve(
        makeNote(id: "scale-class-\(index)", style: "sticky_square")
      )
    }
    let scales = Set(presentations.map(\.visualScale))

    XCTAssertTrue(scales.contains(.hero))
    XCTAssertTrue(scales.contains(.standard))
    XCTAssertTrue(scales.contains(.tiny))
    XCTAssertEqual(
      presentations,
      (0..<320).map { index in
        MIRAWallNotePresentationResolver.resolve(
          makeNote(id: "scale-class-\(index)", style: "sticky_square")
        )
      }
    )
  }

  func testLegacyNotesDistributeAcrossSeveralStableStyles() {
    let resolved = Set((0..<80).map { index in
      MIRAWallNotePresentationResolver.resolve(
        makeNote(id: "legacy-\(index)", style: "sticky_square")
      ).style
    })

    XCTAssertGreaterThanOrEqual(resolved.count, 7)
  }

  func testLongNotesReceiveMoreVerticalRoom() {
    let short = MIRAWallNotePresentationResolver.recommendedSize(
      styleToken: "notebook",
      text: "A short thought."
    )
    let long = MIRAWallNotePresentationResolver.recommendedSize(
      styleToken: "notebook",
      text: String(repeating: "A longer thought needs room to remain readable. ", count: 7)
    )

    XCTAssertGreaterThan(long.height, short.height)
  }

  func testPosterLineCompositionPreservesWords() {
    let source = "never let anyone stop you from making the thing"
    let lines = MIRAWallTextComposition.lines(for: source, preferredCharacters: 12)

    XCTAssertEqual(lines.joined(separator: " "), source)
    XCTAssertFalse(lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }))
  }

  func testPosterLineCompositionPreservesEmojiAndLineBreakWords() {
    let sparkle = "\u{2728}"
    let source = "little reminder: keep going \(sparkle) even on difficult days"
    let lines = MIRAWallTextComposition.lines(for: source, preferredCharacters: 13)

    XCTAssertEqual(lines.joined(separator: " "), source)
    XCTAssertTrue(lines.joined().contains(sparkle))
  }

  func testPosterLineCompositionAvoidsOrphanedSingleCharacters() {
    let source = "I will make it even when I feel uncertain"
    let lines = MIRAWallTextComposition.lines(for: source, preferredCharacters: 8)

    XCTAssertEqual(lines.joined(separator: " "), source)
    XCTAssertFalse(lines.contains(where: { $0.count == 1 }))
  }

  func testRenderDetailReducesDecorationWithoutChangingNotePresentation() {
    XCTAssertEqual(MIRAWallNotePresentationResolver.renderDetail(forWallScale: 0.24), .distant)
    XCTAssertEqual(MIRAWallNotePresentationResolver.renderDetail(forWallScale: 0.54), .compact)
    XCTAssertEqual(MIRAWallNotePresentationResolver.renderDetail(forWallScale: 0.92), .full)
    XCTAssertEqual(MIRAWallNotePresentationResolver.renderDetail(forWallScale: 0.24, isFocused: true), .full)
  }

  private func makeNote(
    id: String,
    style: String,
    mediaURL: String? = nil,
    body: String = "A real note from the wall"
  ) -> MIRAWallNote {
    MIRAWallNote(
      id: id,
      wallId: "global",
      publishingIdentity: "ghost",
      body: body,
      category: nil,
      colorToken: "butter",
      styleToken: style,
      mediaUrl: mediaURL,
      mediaThumbnailUrl: mediaURL,
      worldX: 0,
      worldY: 0,
      width: 188,
      height: 184,
      rotation: 0,
      zIndex: 1,
      approximateLocation: nil,
      createdAt: "2026-07-24T00:00:00Z",
      updatedAt: nil,
      saveCount: 0,
      reactionCount: 0,
      replyCount: 0,
      reactedByViewer: false,
      savedByViewer: false,
      authorPreview: nil
    )
  }
}
