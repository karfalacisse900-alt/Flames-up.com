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
    XCTAssertGreaterThanOrEqual(dense.scale, 0.38)
    XCTAssertLessThanOrEqual(dense.scale, 0.68)
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

  func testCollageLayoutIsDeterministicAndIgnoresStoredWorldCoordinates() {
    let first = makeNote(id: "first", x: -8_000, y: 11_000, z: 1)
    let second = makeNote(id: "second", x: 14_000, y: -9_000, z: 2)
    let relocatedFirst = makeNote(id: "first", x: 80_000, y: -61_000, z: 1)
    let relocatedSecond = makeNote(id: "second", x: -72_000, y: 49_000, z: 2)

    let firstPass = MIRAWallReadableLayout.frames(for: [first, second])
    let secondPass = MIRAWallReadableLayout.frames(for: [relocatedFirst, relocatedSecond])

    XCTAssertEqual(firstPass, secondPass)
  }

  func testCollageLayoutFormsCompactEditorialSpreadsWithControlledOverlap() {
    let notes = (0..<30).map { index in
      makeNote(
        id: "collage-\(index)",
        x: Double(index * 4_000),
        y: Double(index * -3_000),
        z: index
      )
    }
    let frames = MIRAWallReadableLayout.frames(for: notes)
    let bounds = frames.values.reduce(nil as CGRect?) { partial, frame in
      partial?.union(frame) ?? frame
    }

    XCTAssertEqual(frames.count, notes.count)
    XCTAssertLessThanOrEqual(bounds?.width ?? CGFloat.infinity, 820.1)
    XCTAssertGreaterThanOrEqual(bounds?.minX ?? -CGFloat.infinity, -410.1)
    XCTAssertLessThanOrEqual(bounds?.maxX ?? CGFloat.infinity, 410.1)

    let allFrames = Array(frames.values)
    var overlapCount = 0
    for left in allFrames.indices {
      for right in allFrames.indices where right > left {
        let intersection = allFrames[left].intersection(allFrames[right])
        guard !intersection.isEmpty else { continue }
        overlapCount += 1
        let smallerArea = min(
          allFrames[left].width * allFrames[left].height,
          allFrames[right].width * allFrames[right].height
        )
        XCTAssertLessThan(intersection.width * intersection.height / smallerArea, 0.30)
        XCTAssertFalse(allFrames[left].contains(CGPoint(x: allFrames[right].midX, y: allFrames[right].midY)))
        XCTAssertFalse(allFrames[right].contains(CGPoint(x: allFrames[left].midX, y: allFrames[left].midY)))
      }
    }
    XCTAssertGreaterThan(overlapCount, 0)
  }

  func testCollageLayoutFeaturesNewestArtworkAtTopCenter() {
    let older = makeNote(
      id: "older-landscape",
      x: 0,
      y: 0,
      z: 1,
      styleToken: "postcard",
      width: 300,
      height: 170,
      createdAt: "2026-07-11T00:00:00Z"
    )
    let newest = makeNote(
      id: "newest-landscape",
      x: 9_000,
      y: -9_000,
      z: 2,
      styleToken: "postcard",
      width: 300,
      height: 170,
      createdAt: "2026-07-12T00:00:00Z"
    )
    let frames = MIRAWallReadableLayout.frames(for: [older, newest])

    guard let newestFrame = frames[newest.id] else {
      return XCTFail("The newest artwork must be included in the collage")
    }
    XCTAssertEqual(newestFrame.minY, 0, accuracy: 0.001)
    XCTAssertEqual(newestFrame.width, 340, accuracy: 0.001)
    XCTAssertGreaterThan(newestFrame.midX, frames[older.id]?.midX ?? CGFloat.infinity)
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

  private func makeNote(
    id: String,
    x: Double,
    y: Double,
    z: Int,
    styleToken: String = "sticky_square",
    width: Double = 180,
    height: Double = 180,
    createdAt: String = "2026-07-11T00:00:00Z"
  ) -> MIRAWallNote {
    MIRAWallNote(
      id: id, wallId: "global", publishingIdentity: "ghost", body: "A real note",
      category: nil, colorToken: "butter", styleToken: styleToken,
      mediaUrl: nil, mediaThumbnailUrl: nil,
      worldX: x, worldY: y, width: width, height: height, rotation: 0, zIndex: z,
      approximateLocation: nil, createdAt: createdAt, updatedAt: nil,
      saveCount: 0, reactionCount: 0, replyCount: 0,
      reactedByViewer: false, savedByViewer: false, authorPreview: nil
    )
  }
}
