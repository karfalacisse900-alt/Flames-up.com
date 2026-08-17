import Foundation
import XCTest
@testable import MIRANative

final class MIRANoteCanvasTests: XCTestCase {
  func testDocumentRoundTripPreservesAuthoredComposition() throws {
    let photoStyle = MIRANoteCanvasElementStyle(
      material: "polaroid",
      colorHex: "#F7F1E6",
      fontName: "Noteworthy",
      fontSize: 48,
      fontWeight: "medium",
      textAlignment: .leading,
      cornerRadius: 3,
      borderWidth: 2,
      borderColorHex: "#E7DDCC",
      shadowLevel: 4,
      stickerName: "pressed_flower",
      drawingName: "hand_drawn_arrow",
      shapeName: "organic_blob",
      blendMode: "multiply"
    )
    let canvas = MIRANoteCanvas(
      version: 3,
      template: .travelDiary,
      designWidth: 1080,
      designHeight: 2160,
      background: MIRANoteCanvasBackground(
        material: "cotton_paper",
        colorHex: "#F3EFE5",
        textureAsset: "captro-archival-paper"
      ),
      elements: [
        MIRANoteCanvasElement(
          id: "photo-1",
          kind: .polaroid,
          x: 0.72,
          y: 0.27,
          width: 0.43,
          height: 0.38,
          rotation: -4.5,
          zIndex: 12,
          opacity: 0.94,
          isLocked: true,
          text: "Rain in London",
          mediaAssetId: "asset-1",
          mediaUrl: "https://media.captro.app/photo-1",
          thumbnailUrl: "https://media.captro.app/photo-1/thumb",
          cropX: 0.31,
          cropY: 0.67,
          cropScale: 1.8,
          style: photoStyle
        ),
        MIRANoteCanvasElement(
          id: "caption-1",
          kind: .handwrittenCaption,
          x: 0.30,
          y: 0.22,
          width: 0.44,
          height: 0.20,
          rotation: 1.75,
          zIndex: 18,
          text: "Five days still were not enough.",
          style: MIRANoteCanvasElementStyle(
            colorHex: "#17130E",
            fontName: "Noteworthy",
            fontSize: 58,
            fontWeight: "regular",
            textAlignment: .leading
          )
        ),
        MIRANoteCanvasElement(
          id: "tape-1",
          kind: .tape,
          x: 0.69,
          y: 0.075,
          width: 0.23,
          height: 0.055,
          rotation: 2.5,
          zIndex: 30,
          opacity: 0.76,
          style: MIRANoteCanvasElementStyle(colorHex: "#D8C39A", shadowLevel: 1)
        )
      ]
    )

    let encoded = try JSONEncoder().encode(canvas)
    let decoded = try JSONDecoder().decode(MIRANoteCanvas.self, from: encoded)

    XCTAssertEqual(decoded, canvas)
    XCTAssertEqual(decoded.orderedElements.map(\.id), ["photo-1", "caption-1", "tape-1"])
  }

  func testDecoderClampsUnsafeGeometryAndCapsLayerCount() throws {
    let rawElements: [[String: Any]] = (0..<86).map { index in
      [
        "id": "layer-\(index)",
        "kind": "photo",
        "x": 9.0,
        "y": -9.0,
        "width": -4.0,
        "height": 8.0,
        "rotation": 9_999.0,
        "zIndex": 9_999,
        "opacity": -3.0,
        "cropX": 5.0,
        "cropY": -5.0,
        "cropScale": 12.0,
        "style": [
          "fontSize": 900.0,
          "cornerRadius": 900.0,
          "borderWidth": 900.0,
          "shadowLevel": 99
        ]
      ]
    }
    let payload: [String: Any] = [
      "version": 1,
      "template": "scrapbook",
      "designWidth": 99_999.0,
      "designHeight": 99_999.0,
      "background": ["material": "aged_paper", "colorHex": "#EFE4CF"],
      "elements": rawElements
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let decoded = try JSONDecoder().decode(MIRANoteCanvas.self, from: data)

    XCTAssertEqual(decoded.designWidth, 4_096)
    XCTAssertEqual(decoded.designHeight, 8_192)
    XCTAssertEqual(decoded.elements.count, 80)

    let element = try XCTUnwrap(decoded.elements.first)
    XCTAssertEqual(element.x, 1.25)
    XCTAssertEqual(element.y, -0.25)
    XCTAssertEqual(element.width, 0.02)
    XCTAssertEqual(element.height, 1.5)
    XCTAssertEqual(element.rotation, 1_080)
    XCTAssertEqual(element.zIndex, 1_000)
    XCTAssertEqual(element.opacity, 0)
    XCTAssertEqual(element.cropX, 1)
    XCTAssertEqual(element.cropY, 0)
    XCTAssertEqual(element.cropScale, 4)
    XCTAssertEqual(element.style.fontSize, 360)
    XCTAssertEqual(element.style.cornerRadius, 240)
    XCTAssertEqual(element.style.borderWidth, 80)
    XCTAssertEqual(element.style.shadowLevel, 8)
  }

  func testEqualZIndexUsesStableLayerIdentityOrdering() {
    let canvas = MIRANoteCanvas(elements: [
      MIRANoteCanvasElement(id: "z-layer", kind: .shape, x: 0.5, y: 0.5, width: 0.2, height: 0.2, zIndex: 4),
      MIRANoteCanvasElement(id: "a-layer", kind: .text, x: 0.5, y: 0.5, width: 0.2, height: 0.2, zIndex: 4),
      MIRANoteCanvasElement(id: "underlay", kind: .tornPaper, x: 0.5, y: 0.5, width: 0.2, height: 0.2, zIndex: -2)
    ])

    XCTAssertEqual(canvas.orderedElements.map(\.id), ["underlay", "a-layer", "z-layer"])
  }

  func testReplacingMediaChangesOnlyTheRequestedLayer() {
    let untouched = MIRANoteCanvasElement(
      id: "photo-2",
      kind: .photo,
      x: 0.75,
      y: 0.75,
      width: 0.3,
      height: 0.3,
      mediaAssetId: "keep"
    )
    let canvas = MIRANoteCanvas(elements: [
      MIRANoteCanvasElement(id: "photo-1", kind: .photo, x: 0.25, y: 0.25, width: 0.3, height: 0.3),
      untouched
    ])

    let replaced = canvas.replacingMedia(
      elementID: "photo-1",
      assetID: "new-asset",
      url: "https://media.captro.app/new",
      thumbnailURL: "https://media.captro.app/new/thumb"
    )

    XCTAssertEqual(replaced.elements[0].mediaAssetId, "new-asset")
    XCTAssertEqual(replaced.elements[0].mediaUrl, "https://media.captro.app/new")
    XCTAssertEqual(replaced.elements[0].thumbnailUrl, "https://media.captro.app/new/thumb")
    XCTAssertEqual(replaced.elements[1], untouched)
  }

  func testNoteDocumentRoundTripPreservesProductMetadata() throws {
    let canvas = MIRANoteCanvas(
      template: .eventPoster,
      format: .poster9x16,
      designWidth: 1080,
      designHeight: 1920,
      elements: [
        MIRANoteCanvasElement(
          id: "poster-art",
          kind: .photo,
          x: 0.5,
          y: 0.5,
          width: 1,
          height: 1,
          mediaAssetId: "asset-poster"
        )
      ]
    )
    let document = MIRANoteDocument(
      id: "note-doc-1",
      artworkMode: .importedArtwork,
      contentKind: .eventPoster,
      visibility: .publicWall,
      title: "Saturday Night",
      subtitle: "Comedy room",
      altText: "A black event poster.",
      thumbnailUrl: "https://media.captro.app/poster/thumb",
      canvas: canvas,
      detailBlocks: [
        MIRANoteDetailBlock(
          id: "event-details",
          kind: .event,
          title: "Showtime",
          body: "Doors at 8.",
          dateText: "Saturday"
        )
      ]
    )

    let encoded = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(MIRANoteDocument.self, from: encoded)

    XCTAssertEqual(decoded, document)
    XCTAssertEqual(decoded.canvas.format, .poster9x16)
    XCTAssertEqual(decoded.detailBlocks.first?.kind, .event)
  }
}
