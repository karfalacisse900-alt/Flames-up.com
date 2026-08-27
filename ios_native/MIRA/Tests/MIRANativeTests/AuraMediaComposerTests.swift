import Foundation
import XCTest

final class AuraMediaComposerTests: XCTestCase {
  func testCommunityComposerAcceptsPhotoAndVideoAndPublishesTheRealMediaKind() throws {
    let source = try sourceText("Screens/Aura/AuraCreateCommunityPostView.swift")

    XCTAssertTrue(source.contains("matching: .any(of: [.images, .videos])"))
    XCTAssertTrue(source.contains("Add Photo or Video"))
    XCTAssertTrue(source.contains("selectedPhoto?.kind.rawValue"))
    XCTAssertTrue(source.contains("MIRAMediaUploadService(api: api, target: .feedPost)"))
    XCTAssertTrue(source.contains("mediaAssetIds: mediaAssetId.map { [$0] }"))
    XCTAssertTrue(source.contains("mediaKind: selectedPhoto?.kind.rawValue"))
    XCTAssertTrue(source.contains("MIRANativeMediaEditorRenderer.videoThumbnail"))
    XCTAssertFalse(source.contains("PHOTO_REQUIRED"))
  }

  private func sourceText(_ relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let sources = testFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MIRANative")
    return try String(contentsOf: sources.appendingPathComponent(relativePath), encoding: .utf8)
  }
}
