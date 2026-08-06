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
