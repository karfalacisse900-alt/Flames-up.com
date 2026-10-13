import AVFoundation
import UIKit
import XCTest
@testable import MIRANative

final class CaptroCameraCaptureTests: XCTestCase {
  func testOnlyReadyVisibleSessionAcceptsShutter() {
    XCTAssertTrue(CaptroCameraPolicy.canBeginCapture(state: .ready, wantsActive: true, running: true, hasResult: false))
    let blocked: [CaptroCameraCaptureService.State] = [.permissionNeeded, .starting, .capturing, .recording, .finalizing, .interrupted, .failed]
    for state in blocked {
      XCTAssertFalse(CaptroCameraPolicy.canBeginCapture(state: state, wantsActive: true, running: true, hasResult: false))
    }
  }

  func testLeavingCameraOrKeepingReviewBlocksNewCapture() {
    XCTAssertFalse(CaptroCameraPolicy.canBeginCapture(state: .ready, wantsActive: false, running: true, hasResult: false))
    XCTAssertFalse(CaptroCameraPolicy.canBeginCapture(state: .ready, wantsActive: true, running: false, hasResult: false))
    XCTAssertFalse(CaptroCameraPolicy.canBeginCapture(state: .ready, wantsActive: true, running: true, hasResult: true))
  }

  func testPhotoDimensionsComeFromSupportedFormatAndUsePixelArea() {
    let small = CMVideoDimensions(width: 1920, height: 1080)
    let larger = CMVideoDimensions(width: 4032, height: 3024)
    let panoramic = CMVideoDimensions(width: 6000, height: 1000)
    let result = CaptroCameraPolicy.largestPhotoDimensions([panoramic, larger, small])
    XCTAssertEqual(result?.width, larger.width)
    XCTAssertEqual(result?.height, larger.height)
    XCTAssertNil(CaptroCameraPolicy.largestPhotoDimensions([]))
    XCTAssertNil(CaptroCameraPolicy.largestPhotoDimensions([CMVideoDimensions(width: 0, height: 1)]))
  }

  func testSuccessfulNativeDurationLimitFinalizationIsNotDiscarded() {
    let limit = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.maximumDurationReached.rawValue,
                        userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true])
    XCTAssertTrue(CaptroCameraPolicy.recordingSucceeded(limit))
    XCTAssertTrue(CaptroCameraPolicy.recordingSucceeded(nil))
  }

  func testFailedVideoFinalizationNeverCreatesResult() {
    XCTAssertFalse(CaptroCameraPolicy.recordingSucceeded(NSError(domain: AVFoundationErrorDomain, code: AVError.Code.diskFull.rawValue)))
    XCTAssertFalse(CaptroCameraPolicy.recordingSucceeded(NSError(domain: AVFoundationErrorDomain, code: -1,
                          userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false])))
  }

  func testCaptureOrientationFollowsInterfaceAndIsNotAlwaysPortrait() {
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIInterfaceOrientation.portrait), .portrait)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIInterfaceOrientation.portraitUpsideDown), .portraitUpsideDown)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIInterfaceOrientation.landscapeLeft), .landscapeLeft)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIInterfaceOrientation.landscapeRight), .landscapeRight)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIInterfaceOrientation.unknown), .portrait)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIDeviceOrientation.landscapeLeft), .landscapeRight)
    XCTAssertEqual(CaptroCameraPolicy.captureOrientation(UIDeviceOrientation.landscapeRight), .landscapeLeft)
    XCTAssertNil(CaptroCameraPolicy.captureOrientation(UIDeviceOrientation.faceUp))
  }

  func testNativeCameraAndUploadShareExistingLimits() {
    XCTAssertEqual(CaptroPostVideoLimits.maxBytes, 200_000_000)
    XCTAssertEqual(CaptroPostVideoLimits.maxDurationSeconds, 60)
    XCTAssertGreaterThan(CaptroCameraPolicy.minimumFreeBytes, 0)
  }
}
