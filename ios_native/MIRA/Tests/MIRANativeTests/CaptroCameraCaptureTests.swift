import AVFoundation
import Combine
import UIKit
import XCTest
@testable import MIRANative

final class CaptroCameraCaptureTests: XCTestCase {
  func testExplicitCancelRejectsLateCapturedMediaAndRepeatedCancellation() {
    var delivery = CaptroCameraDeliveryGate()
    XCTAssertTrue(delivery.acceptsResult)
    XCTAssertTrue(delivery.cancel())
    XCTAssertFalse(delivery.acceptsResult)
    XCTAssertFalse(delivery.handOff())
    XCTAssertFalse(delivery.beginExport())
    XCTAssertFalse(delivery.cancel())
  }

  func testCancelDuringExportRejectsItsLateSuccessAndFailure() {
    var delivery = CaptroCameraDeliveryGate()
    XCTAssertTrue(delivery.beginExport())
    XCTAssertFalse(delivery.acceptsResult)
    XCTAssertTrue(delivery.cancel())
    XCTAssertFalse(delivery.finishExport())
    XCTAssertFalse(delivery.retryExport())
    XCTAssertFalse(delivery.acceptsResult)
  }

  func testSuccessfulHandoffCannotDeliverTwice() {
    var delivery = CaptroCameraDeliveryGate()
    XCTAssertTrue(delivery.handOff())
    XCTAssertFalse(delivery.handOff())
    XCTAssertFalse(delivery.acceptsResult)

    var exported = CaptroCameraDeliveryGate()
    XCTAssertTrue(exported.beginExport())
    XCTAssertFalse(exported.beginExport())
    XCTAssertTrue(exported.finishExport())
    XCTAssertFalse(exported.finishExport())
    XCTAssertFalse(exported.handOff())
  }

  func testFailedExportCanBeRetriedWithoutLosingEditableResult() {
    var delivery = CaptroCameraDeliveryGate()
    XCTAssertTrue(delivery.beginExport())
    XCTAssertTrue(delivery.retryExport())
    XCTAssertTrue(delivery.acceptsResult)
    XCTAssertTrue(delivery.beginExport())
    XCTAssertTrue(delivery.finishExport())
  }

  @MainActor
  func testPermissionCompletionReconcilesCurrentVideoAfterSuspendAndNewGeneration() async {
    let camera = CaptroCameraCaptureService()
    let installed = expectation(description: "Current video gets authorized microphone")
    await camera.preparePermissionTestContext(mode: .video, active: true, generation: 1, installAudio: { installed.fulfill() })
    camera.suspend() // The permission sheet made the scene inactive.
    await camera.preparePermissionTestContext(mode: .video, active: true, generation: 3, installAudio: { installed.fulfill() })
    let stillPending = await camera.finishPermissionForTesting(authorized: true)
    XCTAssertFalse(stillPending)
    await fulfillment(of: [installed], timeout: 1)
    XCTAssertFalse(camera.microphoneDenied)
  }

  @MainActor
  func testLatePermissionCompletionDoesNotInstallAudioAfterLeavingOrChoosingPhoto() async {
    let camera = CaptroCameraCaptureService()
    let notInstalled = expectation(description: "No obsolete audio install")
    notInstalled.isInverted = true
    await camera.preparePermissionTestContext(mode: .video, active: true, generation: 1, installAudio: { notInstalled.fulfill() })
    camera.suspend()
    let pendingAfterLeave = await camera.finishPermissionForTesting(authorized: true)
    XCTAssertFalse(pendingAfterLeave)
    await camera.preparePermissionTestContext(mode: .photo, active: true, generation: 3, installAudio: { notInstalled.fulfill() })
    _ = await camera.finishPermissionForTesting(authorized: true)
    await fulfillment(of: [notInstalled], timeout: 0.1)
  }

  @MainActor
  func testAuthorizedButUnavailableMicrophoneReportsSilentVideo() async {
    let camera = CaptroCameraCaptureService()
    let reported = expectation(description: "Silent recording notice published")
    let observation = camera.$notice.sink { message in
      if message == "Microphone unavailable. Video will be recorded without sound." { reported.fulfill() }
    }
    defer { observation.cancel() }
    await camera.preparePermissionTestContext(mode: .video, active: true, generation: 1, installAudio: {
      throw NSError(domain: "camera-test", code: 1)
    })
    _ = await camera.finishPermissionForTesting(authorized: true)
    await fulfillment(of: [reported], timeout: 1)
    XCTAssertEqual(camera.notice, "Microphone unavailable. Video will be recorded without sound.")
  }

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
