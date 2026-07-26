import CoreGraphics
import XCTest
@testable import MIRANative

final class MIRAWallSpatialIndexTests: XCTestCase {
  func testCameraRoundTripPreservesWorldPoint() {
    let camera = MIRAWallCamera(center: CGPoint(x: 420, y: -180), scale: 0.73)
    let viewport = CGSize(width: 390, height: 844)
    let world = CGPoint(x: 812, y: 265)
    let screen = camera.screenPoint(forWorld: world, viewport: viewport)
    let roundTrip = camera.worldPoint(forScreen: screen, viewport: viewport)

    XCTAssertEqual(roundTrip.x, world.x, accuracy: 0.001)
    XCTAssertEqual(roundTrip.y, world.y, accuracy: 0.001)
  }

  func testFocalPointZoomKeepsWorldPositionUnderFinger() {
    let camera = MIRAWallCamera(center: CGPoint(x: 100, y: 240), scale: 0.6)
    let viewport = CGSize(width: 430, height: 932)
    let finger = CGPoint(x: 86, y: 214)
    let before = camera.worldPoint(forScreen: finger, viewport: viewport)
    let zoomed = camera.zoomed(to: 1.4, around: finger, viewport: viewport)
    let after = zoomed.worldPoint(forScreen: finger, viewport: viewport)

    XCTAssertEqual(after.x, before.x, accuracy: 0.001)
    XCTAssertEqual(after.y, before.y, accuracy: 0.001)
  }

  func testSpatialIndexCullsAndHitTests() {
    let first = makeNote(id: "first", x: 0, y: 0, z: 1)
    let second = makeNote(id: "second", x: 900, y: 900, z: 2)
    let index = MIRAWallSpatialIndex(notes: [first, second], cellSize: 256)

    XCTAssertEqual(index.notes(in: CGRect(x: -20, y: -20, width: 260, height: 260)).map(\.id), ["first"])
    XCTAssertEqual(index.note(at: CGPoint(x: 80, y: 80))?.id, "first")
    XCTAssertNil(index.note(at: CGPoint(x: 520, y: 520)))
  }

  func testSparseWallCameraFramesNotesAndStartSign() {
    let notes = CGRect(x: -220, y: -150, width: 540, height: 465)
    let sign = MIRAWallLayout.startSignRect(noteBounds: notes, noteCount: 3)
    let camera = MIRAWallLayout.initialCamera(
      noteBounds: notes,
      noteCount: 3,
      viewport: CGSize(width: 390, height: 844),
      includeStartSign: true
    )
    let visible = camera.worldBounds(viewport: CGSize(width: 390, height: 844))

    XCTAssertTrue(visible.intersects(notes))
    XCTAssertTrue(visible.intersects(sign))
    XCTAssertGreaterThanOrEqual(camera.scale, 0.62)
  }

  func testDenseWallStartsWiderThanSparseWall() {
    let bounds = CGRect(x: -900, y: -700, width: 1800, height: 1400)
    let sparse = MIRAWallLayout.initialCamera(
      noteBounds: bounds,
      noteCount: 3,
      viewport: CGSize(width: 430, height: 932),
      includeStartSign: false
    )
    let dense = MIRAWallLayout.initialCamera(
      noteBounds: bounds,
      noteCount: 40,
      viewport: CGSize(width: 430, height: 932),
      includeStartSign: false
    )

    XCTAssertLessThanOrEqual(dense.scale, sparse.scale)
    XCTAssertLessThanOrEqual(dense.scale, 0.58)
  }

  func testThousandNoteWallReturnsOnlyViewportCandidates() {
    let notes = (0..<1_000).map { index in
      makeNote(
        id: "bulk-\(index)",
        x: Double((index % 40) * 260),
        y: Double((index / 40) * 280),
        z: index
      )
    }
    let index = MIRAWallSpatialIndex(notes: notes, cellSize: 384)
    let visible = index.notes(in: CGRect(x: 0, y: 0, width: 620, height: 680))

    XCTAssertFalse(visible.isEmpty)
    XCTAssertLessThan(visible.count, 30)
    XCTAssertTrue(visible.allSatisfy { note in
      MIRAWallNotePresentationResolver.wallFrame(for: note)
        .intersects(CGRect(x: 0, y: 0, width: 620, height: 680))
    })
  }

  func testReadableLayoutSeparatesOverlappingTextAreasDeterministically() {
    let first = makeNote(id: "overlap-first", x: 0, y: 0, z: 1)
    let second = makeNote(id: "overlap-second", x: 0, y: 0, z: 2)
    let notes = [first, second]

    let firstPass = MIRAWallReadableLayout.frames(for: notes)
    let secondPass = MIRAWallReadableLayout.frames(for: notes)

    XCTAssertEqual(firstPass, secondPass)
    guard let firstFrame = firstPass[first.id], let secondFrame = firstPass[second.id] else {
      return XCTFail("Readable layout must return every note frame")
    }
    let firstReadable = firstFrame.insetBy(
      dx: max(10, firstFrame.width * 0.07),
      dy: max(12, firstFrame.height * 0.08)
    )
    let secondReadable = secondFrame.insetBy(
      dx: max(10, secondFrame.width * 0.07),
      dy: max(12, secondFrame.height * 0.08)
    )

    XCTAssertFalse(firstReadable.intersects(secondReadable))
  }

  func testSpatialIndexUsesReadableLayoutFramesForHitTesting() {
    let first = makeNote(id: "layout-hit-first", x: 0, y: 0, z: 1)
    let second = makeNote(id: "layout-hit-second", x: 0, y: 0, z: 2)
    let notes = [first, second]
    let frames = MIRAWallReadableLayout.frames(for: notes)
    var index = MIRAWallSpatialIndex()
    index.rebuild(with: notes, frameOverrides: frames)

    guard let secondFrame = frames[second.id] else {
      return XCTFail("Readable layout must return the moved note frame")
    }
    XCTAssertEqual(index.note(at: CGPoint(x: secondFrame.midX, y: secondFrame.midY))?.id, second.id)
  }

  func testReplacingInteractionStateDoesNotRebuildOrLoseSpatialMembership() {
    let original = makeNote(id: "stable-interaction", x: 120, y: 80, z: 4)
    var index = MIRAWallSpatialIndex(notes: [original], cellSize: 256)
    let updated = original.updating(reacted: true, reactionCount: 1, saved: true, saveCount: 1)

    XCTAssertTrue(index.replace(updated))
    let hit = index.note(at: CGPoint(x: 160, y: 120))
    XCTAssertEqual(hit?.id, original.id)
    XCTAssertEqual(hit?.reactionCount, 1)
    XCTAssertEqual(hit?.saveCount, 1)
    XCTAssertEqual(index.notes(in: CGRect(x: 0, y: 0, width: 400, height: 400)).count, 1)
  }

  private func makeNote(id: String, x: Double, y: Double, z: Int) -> MIRAWallNote {
    MIRAWallNote(
      id: id, wallId: "global", publishingIdentity: "ghost", body: "A real note",
      category: nil, colorToken: "butter", styleToken: "sticky_square",
      mediaUrl: nil, mediaThumbnailUrl: nil,
      worldX: x, worldY: y, width: 180, height: 180, rotation: 0, zIndex: z,
      approximateLocation: nil, createdAt: "2026-07-11T00:00:00Z", updatedAt: nil,
      saveCount: 0, reactionCount: 0, replyCount: 0,
      reactedByViewer: false, savedByViewer: false, authorPreview: nil
    )
  }
}
