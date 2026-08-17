import CoreGraphics
import XCTest
@testable import MIRANative

final class MIRACaptroStudioModelsTests: XCTestCase {
  func testEveryTemplateBuildsAStableLayerComposition() {
    for template in MIRACaptroStudioTemplate.allCases {
      let document = template.makeDocument()
      XCTAssertEqual(document.template, template)
      XCTAssertFalse(document.layers.isEmpty)
      XCTAssertEqual(document.layers.filter { $0.kind == .paper }.count, 1)
      XCTAssertEqual(Set(document.layers.map(\.id)).count, document.layers.count)
      XCTAssertEqual(document.layers.map(\.zIndex).min(), 0)
    }
  }

  func testTemplatePhotoSlotsUseDistinctMediaKeys() {
    for template in MIRACaptroStudioTemplate.allCases {
      let photoKeys = template.makeDocument().layers
        .filter { $0.kind == .photo }
        .compactMap(\.mediaKey)
      XCTAssertEqual(Set(photoKeys).count, photoKeys.count, "Duplicate media key in \(template.rawValue)")
    }
  }

  func testEveryTemplateMapsToNoteDocumentMetadata() {
    for template in MIRACaptroStudioTemplate.allCases {
      XCTAssertTrue(MIRANoteCanvasTemplate.allCases.contains(template.noteCanvasTemplate))
      XCTAssertTrue(MIRANoteCanvasFormat.allCases.contains(template.noteCanvasFormat))
      XCTAssertTrue(MIRANoteContentKind.allCases.contains(template.noteContentKind))
    }
  }

  func testPremiumTemplateFamiliesAreLayeredAndVisuallyDistinct() {
    let required: [MIRACaptroStudioTemplate] = [
      .stationeryNote,
      .landscapeQuote,
      .tornPaperMotivation,
      .photoHandwriting,
      .botanicalCollage,
      .editorialPortrait,
      .minimalTypography,
      .photoTornSection,
    ]

    for template in required {
      let layers = template.makeDocument().layers.filter { $0.kind != .paper }
      XCTAssertGreaterThanOrEqual(layers.count, 2, "\(template.rawValue) needs a composed visual hierarchy")
      XCTAssertTrue(layers.contains(where: { $0.kind == .text }))
    }

    let signatures = Set(required.map { template in
      template.makeDocument().layers
        .map { "\($0.kind.rawValue):\($0.object?.rawValue ?? $0.photoFrame?.rawValue ?? $0.fontStyle?.rawValue ?? "none")" }
        .joined(separator: "|")
    })
    XCTAssertEqual(signatures.count, required.count)
  }

  func testQuickNoteOffersEightLiveVisualTreatments() {
    let message = "Make room for the life you are building."
    XCTAssertEqual(MIRACaptroStudioTemplate.quickNoteTemplates.count, 8)

    for template in MIRACaptroStudioTemplate.quickNoteTemplates {
      let document = template.makeDocument(message: message)
      XCTAssertTrue(document.layers.contains(where: { $0.text == message }))
    }
  }

  func testTenDemoFixturesCoverEveryRequiredShowcase() {
    let documents = MIRACaptroStudioDemoFixtures.documents
    XCTAssertEqual(documents.count, 10)
    XCTAssertEqual(Set(documents.map(\.template)).count, 10)
    XCTAssertEqual(documents.first?.template, .stationeryNote)
    XCTAssertEqual(documents.last?.template, .importedDesign)
    XCTAssertTrue(documents.contains(where: { document in
      document.layers.contains(where: { $0.mediaKey == CaptroNoteAsset.mountainLake.rawValue })
    }))
    XCTAssertTrue(documents.contains(where: { document in
      document.layers.contains(where: { $0.object == .pressedFlower })
    }))
  }

  func testDuplicateCreatesIndependentLayerAboveOriginal() throws {
    var document = MIRACaptroStudioTemplate.travelJournal.makeDocument()
    let original = try XCTUnwrap(document.layers.first(where: { $0.kind == .photo }))
    let originalMaximum = document.layers.map(\.zIndex).max() ?? 0

    let duplicateID = try XCTUnwrap(document.duplicateLayer(id: original.id))
    let duplicate = try XCTUnwrap(document.layers.first(where: { $0.id == duplicateID }))

    XCTAssertNotEqual(duplicate.id, original.id)
    XCTAssertNotEqual(duplicate.mediaKey, original.mediaKey)
    XCTAssertEqual(duplicate.zIndex, originalMaximum + 1)
    XCTAssertGreaterThan(duplicate.x, original.x)
    XCTAssertGreaterThan(duplicate.y, original.y)
  }

  func testDuplicateKeepsBundledPhotoReferenceRenderable() throws {
    var document = MIRACaptroStudioTemplate.landscapeQuote.makeDocument()
    let original = try XCTUnwrap(document.layers.first(where: { $0.kind == .photo }))
    let duplicateID = try XCTUnwrap(document.duplicateLayer(id: original.id))
    let duplicate = try XCTUnwrap(document.layers.first(where: { $0.id == duplicateID }))

    XCTAssertEqual(original.mediaKey, CaptroNoteAsset.mountainLake.rawValue)
    XCTAssertEqual(duplicate.mediaKey, original.mediaKey)
  }

  func testPaperCannotBeDuplicatedOrDeleted() throws {
    var document = MIRACaptroStudioTemplate.blankPaper.makeDocument()
    let paper = try XCTUnwrap(document.layers.first(where: { $0.kind == .paper }))

    XCTAssertNil(document.duplicateLayer(id: paper.id))
    document.deleteLayer(id: paper.id)

    XCTAssertTrue(document.layers.contains(where: { $0.id == paper.id }))
  }

  func testSnapAndClampKeepLayersInsideCanvas() {
    XCTAssertEqual(MIRACaptroStudioDocument.clampedPosition(-4), 0.04, accuracy: 0.0001)
    XCTAssertEqual(MIRACaptroStudioDocument.clampedPosition(4), 0.96, accuracy: 0.0001)

    let center = MIRACaptroStudioDocument.snappedPosition(0.509)
    XCTAssertTrue(center.snapped)
    XCTAssertEqual(center.value, 0.5, accuracy: 0.0001)

    let free = MIRACaptroStudioDocument.snappedPosition(0.62)
    XCTAssertFalse(free.snapped)
    XCTAssertEqual(free.value, 0.62, accuracy: 0.0001)
  }

  func testLayerOrderingNormalizesWithoutMovingPaperAboveContent() throws {
    var document = MIRACaptroStudioTemplate.musicPocket.makeDocument()
    let target = try XCTUnwrap(document.layers.first(where: { $0.kind == .qrCode }))
    document.moveLayer(id: target.id, by: 50)

    XCTAssertEqual(document.layers.first(where: { $0.kind == .paper })?.zIndex, 0)
    let content = document.layers.filter { $0.kind != .paper }.sorted { $0.zIndex < $1.zIndex }
    XCTAssertEqual(content.map(\.zIndex), Array(1...content.count))
  }
}
