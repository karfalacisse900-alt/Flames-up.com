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

  private func makeNote(id: String, x: Double, y: Double, z: Int) -> MIRAWallNote {
    MIRAWallNote(
      id: id, wallId: "global", publishingIdentity: "ghost", body: "A real note",
      category: nil, colorToken: "butter", styleToken: "sticky_square",
      worldX: x, worldY: y, width: 180, height: 180, rotation: 0, zIndex: z,
      approximateLocation: nil, createdAt: "2026-07-11T00:00:00Z", updatedAt: nil,
      saveCount: 0, reactionCount: 0, replyCount: 0,
      reactedByViewer: false, savedByViewer: false, authorPreview: nil
    )
  }
}
