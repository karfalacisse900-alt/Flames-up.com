import XCTest
import UIKit
import UniformTypeIdentifiers
import ImageIO
@testable import MIRANative

final class CaptroPostMediaTests: XCTestCase {
  func testFutureOverlayDoesNotBreakPostDecoding() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let post = try decoder.decode(MIRAPost.self, from: Data("""
      {"id":"future","editor_overlays":[{"type":"media_writing","media_index":0,"writing":{"schema_version":99}}]}
      """.utf8))
    XCTAssertNil(post.mediaWriting(at: 0))
  }
  func testRotatedPhotoMetadataUsesDisplayedOrientationWithoutReencoding() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
      UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    }
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let media = MIRAPickedMedia(data: bytes as Data, kind: .image, fileName: "rotated.jpg", mimeType: "image/jpeg")
    let dimension = await media.mediaDimension()
    XCTAssertEqual(dimension.originalWidth, 20)
    XCTAssertEqual(dimension.originalHeight, 40)
    XCTAssertEqual(media.data, bytes as Data)
  }
  func testMediaWritingRoundTripPreservesOriginalBytesAndMetadata() throws {
    var writing = CaptroMediaWriting()
    writing.text = "FRIDAY NIGHT\nNYC"
    writing.sourceAspectRatio = 0.75
    let bytes = Data([1, 2, 3])
    var media = MIRAPickedMedia(data: bytes, kind: .image, fileName: "original.jpg", mimeType: "image/jpeg")
    media.mediaWriting = writing
    XCTAssertEqual(media.data, bytes)
    let saved = try JSONEncoder().encode(writing)
    XCTAssertEqual(try JSONDecoder().decode(CaptroMediaWriting.self, from: saved), writing)
    media.mediaWriting = nil
    XCTAssertEqual(media.data, bytes)
  }
  func testMediaWritingCropAndFitUseSameSourceCoordinateTransform() {
    var writing = CaptroMediaWriting()
    writing.sourceAspectRatio = 0.5
    writing.text = "NYC"
    for width: CGFloat in [320, 390, 440] {
      let canvas = CGSize(width: width, height: width * 1.25)
      let crop = writing.sourceRect(in: canvas, fill: true)
      XCTAssertEqual(crop.width, width, accuracy: 0.01)
      XCTAssertEqual(crop.height, width * 2, accuracy: 0.01)
      let text = writing.textRect(in: canvas, fill: true)
      XCTAssertEqual(text.midY, crop.minY + crop.height * writing.y, accuracy: 0.01)
      let fit = writing.sourceRect(in: canvas, fill: false)
      XCTAssertEqual(fit.height, canvas.height, accuracy: 0.01)
      XCTAssertLessThan(fit.width, canvas.width)
    }
  }
  func testMediaWritingValidatesMeasuredLinesWithoutRewriting() {
    var writing = CaptroMediaWriting()
    writing.text = "FRIDAY NIGHT\nNYC"
    XCTAssertNil(writing.validationMessage)
    writing.text = String(repeating: "WORDS ", count: 13)
    writing.size = "large"
    XCTAssertNotNil(writing.validationMessage)
    XCTAssertEqual(writing.text.count, 78)
    writing.text = String(repeating: "a", count: 81)
    XCTAssertNotNil(writing.validationMessage)
  }
  func testHomeHeightUsesResolvedMetadataNotDeviceHeight() throws {
    for width: CGFloat in [320, 390, 440] {
      for format in MIRASupportedPostAspectRatio.allCases {
        let json: [String: Any] = ["format": format.rawValue,
          "original_width": 100, "original_height": 100]
        let dimensions = try JSONDecoder().decode(MIRAMediaDimension.self,
          from: JSONSerialization.data(withJSONObject: json))
        let ratio = try XCTUnwrap(dimensions.heightToWidthRatio)
        XCTAssertEqual(ratio, format.heightToWidthRatio, accuracy: 0.001)
        for screenHeight: CGFloat in [568, 852, 956] {
          XCTAssertEqual(MIRAMediaSizing.mainFeedHeight(for: [], aspectRatios: [ratio],
            width: width, screenHeight: screenHeight), width * MIRAMediaSizing.homeDisplayRatio(ratio), accuracy: 0.001)
        }
      }
    }
  }
  func testVoiceWatchdogStartsAtAudioActivationNotAuthorization() {
    let health = CaptroVoicePipelineHealth(now: 100)
    XCTAssertNil(health.stall(now: 103))
    XCTAssertEqual(health.stall(now: 106), .capture)
    health.captured(now: 106)
    XCTAssertEqual(health.stall(now: 106), .conversion)
    health.converted(now: 106)
    XCTAssertEqual(health.stall(now: 106), .transport)
    health.sent(now: 106)
    XCTAssertNil(health.stall(now: 106))
  }

  func testVoiceWatchdogDoesNotTreatQuietOrMutedPCMAsMissingCapture() {
    let health = CaptroVoicePipelineHealth(now: 0)
    for second in 1...30 {
      health.captured(now: Double(second))
      health.converted(now: Double(second))
      health.sent(now: Double(second))
      XCTAssertNil(health.stall(now: Double(second)))
    }
  }

  @MainActor func testAudioOwnershipCannotBeReleasedByStaleVoiceSession() {
    let owner = UUID(), stale = UUID()
    XCTAssertTrue(MIRAPlaybackCoordinator.acquireLiveVoice(owner))
    defer { MIRAPlaybackCoordinator.releaseLiveVoice(owner) }
    XCTAssertFalse(MIRAPlaybackCoordinator.acquireLiveVoice(stale))
    MIRAPlaybackCoordinator.releaseLiveVoice(stale)
    XCTAssertTrue(MIRAPlaybackCoordinator.isLiveVoiceActive)
    MIRAPlaybackCoordinator.releaseLiveVoice(owner)
    XCTAssertFalse(MIRAPlaybackCoordinator.isLiveVoiceActive)
  }
  func testSupportedRatiosIncludeWideLandscapeAndPreserveLegacyFormats() {
    XCTAssertEqual(MIRASupportedPostAspectRatio.allCases.map(\.rawValue), ["16:9", "4:3", "0.65:1", "4:5", "3:4", "1:1"])
    for ratio in MIRASupportedPostAspectRatio.allCases {
      XCTAssertEqual(MIRASupportedPostAspectRatio.nearest(width: ratio.feedWidth, height: ratio.feedHeight), ratio)
    }
  }

  func testHEICIsNotMistakenForVideoBecauseOfItsContainerHeader() {
    let heicHeader = Data([0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99])
    XCTAssertEqual(pickedMediaKind(from: [.heic], fallbackData: heicHeader).0, .image)
    XCTAssertEqual(pickedMediaKind(from: [.movie], fallbackData: Data()).0, .video)
  }

  func testVideoReferencesDoNotIncludePosterImagesOrOrdinaryImageNames() {
    XCTAssertTrue("cfstream:abc123xyz".isVideoURL)
    XCTAssertTrue("https://videodelivery.net/abc123xyz/manifest/video.m3u8".isVideoURL)
    XCTAssertTrue("https://example.com/upload.MOV?token=test".isVideoURL)
    XCTAssertFalse("https://videodelivery.net/abc123xyz/thumbnails/thumbnail.jpg".isVideoURL)
    XCTAssertFalse("https://example.com/stream-in-the-woods.jpg".isVideoURL)
  }

  func testVideoLimitsRejectInvalidFilesBeforeNetworkUpload() {
    XCTAssertNoThrow(try CaptroPostVideoLimits.validate(byteCount: 1_000, duration: 60))
    XCTAssertThrowsError(try CaptroPostVideoLimits.validate(byteCount: 200_000_001, duration: 10))
    for duration in [0, -1, 61, Double.nan, Double.infinity] {
      XCTAssertThrowsError(try CaptroPostVideoLimits.validate(byteCount: 1_000, duration: duration))
    }
  }

  func testFeedUploadKeepsPhotographAspectRatioWithoutCenterCrop() async throws {
    let size = CGSize(width: 2400, height: 1200)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { _ in
      UIColor.red.setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
      UIColor.blue.setFill()
      UIRectFill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
    }
    let source = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
    let uploader = MIRAMediaUploadService(api: MIRAAPIClient(), target: .feedPost)
    let preparedData = await uploader.prepareFeedImage(source)
    let prepared = try XCTUnwrap(preparedData)
    let output = try XCTUnwrap(UIImage(data: prepared))
    XCTAssertEqual(output.size.width, 2400, accuracy: 1)
    XCTAssertEqual(output.size.height, 1200, accuracy: 1)
    XCTAssertLessThan(prepared.count, 10_000_000)
  }

  func testPublishedImageMetadataRequestsAspectPreservation() async throws {
    let size = CGSize(width: 1920, height: 1080)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: size))
    }
    let media = MIRAPickedMedia(
      data: try XCTUnwrap(image.jpegData(compressionQuality: 0.8)),
      kind: .image,
      fileName: "landscape.jpg",
      mimeType: "image/jpeg"
    )
    let dimension = await media.postMediaDimension()
    XCTAssertEqual(dimension.cropMode, "preserve_aspect")
    XCTAssertEqual(dimension.format, "16:9")
  }

  func testTusVideoUploadSendsAlignedChunksAndChecksProviderOffset() async throws {
    TusUploadURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TusUploadURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let api = MIRAAPIClient(directUploadSession: session)
    let bytes = Data(repeating: 0x41, count: 5 * 1024 * 1024 + 16)
    let uploadURL = try XCTUnwrap(URL(string: "https://upload.videodelivery.net/test-tus"))

    try await api.uploadTusVideo(to: uploadURL, data: bytes)

    XCTAssertEqual(TusUploadURLProtocol.patchOffsets, [0, 5 * 1024 * 1024])
    XCTAssertEqual(TusUploadURLProtocol.headRequests, 1)
  }
}

private final class TusUploadURLProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var offsets: [Int] = []
  private static var heads = 0

  static var patchOffsets: [Int] { lock.lock(); defer { lock.unlock() }; return offsets }
  static var headRequests: Int { lock.lock(); defer { lock.unlock() }; return heads }
  static func reset() { lock.lock(); defer { lock.unlock() }; offsets = []; heads = 0 }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "upload.videodelivery.net"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let headers: [String: String]
    if request.httpMethod == "HEAD" {
      Self.lock.lock()
      Self.heads += 1
      Self.lock.unlock()
      headers = ["Upload-Offset": "0", "Upload-Length": "5242896"]
    } else {
      let offset = Int(request.value(forHTTPHeaderField: "Upload-Offset") ?? "") ?? -1
      Self.lock.lock()
      Self.offsets.append(offset)
      Self.lock.unlock()
      let next = offset == 0 ? 5 * 1024 * 1024 : 5 * 1024 * 1024 + 16
      headers = ["Upload-Offset": String(next)]
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: request.httpMethod == "HEAD" ? 200 : 204,
      httpVersion: "HTTP/1.1", headerFields: headers
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
