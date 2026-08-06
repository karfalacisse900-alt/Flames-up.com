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

  func testPhotoCanKeepEveryExplicitPaperStyle() {
    for style in MIRAWallNoteVisualStyle.allCases {
      let note = makeNote(
        id: "photo-style-\(style.rawValue)",
        style: style.rawValue,
        mediaURL: "https://media.captro.app/notes/photo.jpg"
      )

      XCTAssertEqual(MIRAWallNotePresentationResolver.resolve(note).style, style)
    }
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

  func testDistantInkLegibilityScalesContinuouslyWithoutChangingFocusedNotes() {
    XCTAssertEqual(MIRAWallNotePresentationResolver.wallLegibilityScale(forWallScale: 0.72), 1, accuracy: 0.001)
    XCTAssertEqual(MIRAWallNotePresentationResolver.wallLegibilityScale(forWallScale: 0.48), 1.11, accuracy: 0.001)
    XCTAssertEqual(MIRAWallNotePresentationResolver.wallLegibilityScale(forWallScale: 0.24), 1.22, accuracy: 0.001)
    XCTAssertEqual(
      MIRAWallNotePresentationResolver.wallLegibilityScale(forWallScale: 0.24, isFocused: true),
      1,
      accuracy: 0.001
    )
  }

  func testCombinedLivingNoteCapabilitiesRemainIndependent() {
    var note = makeNote(id: "living-note", style: "cassette")
    note.noteType = "voice"
    note.voice = MIRAWallVoiceMetadata(
      mediaId: "voice-1",
      url: "https://media.captro.app/voice/voice-1.m4a",
      durationSeconds: 12,
      waveform: [0.2, 0.8, 0.4]
    )
    note.backBody = "The thought on the back"
    note.hasBackSide = true
    note.allowContributions = true
    note.viewerIsAuthor = false
    note.location = MIRAWallLocationPreview(
      label: "Found near Brooklyn",
      city: "Brooklyn",
      country: "United States",
      distanceKm: 0.6
    )

    XCTAssertEqual(
      note.capabilities,
      MIRAWallNoteCapabilities(
        canSign: true,
        canCollaborate: true,
        canManageCollaboration: false,
        hasLocation: true,
        hasBackSide: true,
        hasVoice: true
      )
    )
  }

  func testAuthorManagesCollaborationButCannotSignOwnNote() {
    var note = makeNote(id: "author-note", style: "notebook")
    note.viewerIsAuthor = true
    note.allowContributions = true

    XCTAssertFalse(note.capabilities.canSign)
    XCTAssertTrue(note.capabilities.canCollaborate)
    XCTAssertTrue(note.capabilities.canManageCollaboration)
  }

  func testLegacyBackSideRemainsFlippableWhenCapabilityFlagIsMissing() {
    var note = makeNote(id: "legacy-two-sided", style: "notebook")
    note.backBody = "A preserved thought on the back"
    note.hasBackSide = nil

    XCTAssertTrue(note.canFlip)
    XCTAssertTrue(note.capabilities.hasBackSide)
  }

  func testExplicitlyDisabledBackSideCannotFlip() {
    var note = makeNote(id: "disabled-two-sided", style: "notebook")
    note.backBody = "A stale cached back side"
    note.hasBackSide = false

    XCTAssertFalse(note.canFlip)
    XCTAssertFalse(note.capabilities.hasBackSide)
  }

  func testBackSidePreservesSocialAndLocationStateWithoutFrontMedia() {
    var note = makeNote(
      id: "two-sided-photo",
      style: "polaroid",
      mediaURL: "https://media.captro.app/notes/front.jpg"
    )
    note.backBody = "Only the back-side thought"
    note.backColorToken = "rose"
    note.backStyleToken = "notebook"
    note.hasBackSide = true
    note.allowContributions = true
    note.signatureCount = 17
    note.contributionCount = 4
    note.signedByViewer = true
    note.viewerIsAuthor = false
    note.location = MIRAWallLocationPreview(
      label: "Found nearby",
      city: nil,
      country: nil,
      distanceKm: 1.2
    )
    note.voice = MIRAWallVoiceMetadata(
      mediaId: "front-voice",
      url: "https://media.captro.app/voice/front.m4a",
      durationSeconds: 8,
      waveform: [0.4, 0.6]
    )

    let back = note.displayingBackSide()

    XCTAssertEqual(back.body, "Only the back-side thought")
    XCTAssertEqual(back.colorToken, "rose")
    XCTAssertEqual(back.styleToken, "notebook")
    XCTAssertNil(back.mediaUrl)
    XCTAssertNil(back.mediaThumbnailUrl)
    XCTAssertNil(back.voice)
    XCTAssertFalse(back.canFlip)
    XCTAssertEqual(back.signatureCount, 17)
    XCTAssertEqual(back.contributionCount, 4)
    XCTAssertEqual(back.signedByViewer, true)
    XCTAssertEqual(back.allowContributions, true)
    XCTAssertEqual(back.location?.distanceKm, 1.2)
    XCTAssertTrue(back.capabilities.canSign)
    XCTAssertTrue(back.capabilities.canCollaborate)
    XCTAssertTrue(back.capabilities.hasLocation)
  }

  func testOptimisticSocialUpdatesPreserveLivingNoteMetadata() {
    var note = makeNote(id: "optimistic-note", style: "cassette")
    note.noteType = "voice"
    note.voice = MIRAWallVoiceMetadata(
      mediaId: "voice-optimistic",
      url: nil,
      durationSeconds: 9,
      waveform: [0.3, 0.7]
    )
    note.backBody = "Back"
    note.hasBackSide = true
    note.allowContributions = true
    note.signatureCount = 2
    note.contributionCount = 3
    note.location = MIRAWallLocationPreview(
      label: "Found near Queens",
      city: "Queens",
      country: "United States",
      distanceKm: nil
    )

    let updated = note.updating(
      reacted: true,
      reactionCount: 5,
      saved: true,
      saveCount: 4,
      signed: true,
      signatureCount: 3,
      contributionCount: 4
    )

    XCTAssertTrue(updated.reactedByViewer)
    XCTAssertEqual(updated.reactionCount, 5)
    XCTAssertTrue(updated.savedByViewer)
    XCTAssertEqual(updated.saveCount, 4)
    XCTAssertEqual(updated.signedByViewer, true)
    XCTAssertEqual(updated.signatureCount, 3)
    XCTAssertEqual(updated.contributionCount, 4)
    XCTAssertEqual(updated.voice, note.voice)
    XCTAssertEqual(updated.backBody, note.backBody)
    XCTAssertEqual(updated.location, note.location)
    XCTAssertEqual(updated.allowContributions, true)
  }

  func testDrawnSignatureCountsPointsAcrossStrokes() {
    let drawing = MIRAWallSignatureDrawing(strokes: [
      MIRAWallSignatureStroke(points: [
        MIRAWallSignaturePoint(x: 0.1, y: 0.2),
        MIRAWallSignaturePoint(x: 0.2, y: 0.3),
      ]),
      MIRAWallSignatureStroke(points: [
        MIRAWallSignaturePoint(x: 0.4, y: 0.5),
        MIRAWallSignaturePoint(x: 0.6, y: 0.7),
        MIRAWallSignaturePoint(x: 0.8, y: 0.9),
      ]),
    ])

    XCTAssertEqual(drawing.version, 1)
    XCTAssertEqual(drawing.pointCount, 5)
    XCTAssertFalse(drawing.isEmpty)
  }

  func testDrawnSignatureNeedsAtLeastTwoPoints() {
    let empty = MIRAWallSignatureDrawing(strokes: [])
    let dot = MIRAWallSignatureDrawing(strokes: [
      MIRAWallSignatureStroke(points: [MIRAWallSignaturePoint(x: 0.5, y: 0.5)]),
    ])

    XCTAssertTrue(empty.isEmpty)
    XCTAssertTrue(dot.isEmpty)
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
