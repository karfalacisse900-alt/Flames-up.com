import AVFoundation
import Combine
import Foundation
import UIKit
import ImageIO

/// One capture foundation for Capture, Post and Story cameras. Session/device/file work
/// belongs exclusively to `queue`; observable values are delivered on the main queue.
final class CaptroCameraCaptureService: NSObject, ObservableObject {
  enum Mode: String, CaseIterable { case photo, video }
  enum State: Equatable {
    case permissionNeeded, starting, ready, capturing, recording, finalizing, interrupted, failed
    var isBusy: Bool { self == .starting || self == .capturing || self == .recording || self == .finalizing }
  }
  enum Flash: String, CaseIterable { case off, auto, on }

  let session = AVCaptureSession() // Attach to a preview layer; never configure from a view.
  @Published private(set) var state: State = .permissionNeeded
  @Published private(set) var mode: Mode = .photo
  @Published private(set) var result: MIRAPickedMedia?
  @Published private(set) var errorMessage: String?
  @Published private(set) var notice: String?
  @Published private(set) var zoom: CGFloat = 1
  @Published private(set) var zoomRange: ClosedRange<CGFloat> = 1...1
  @Published private(set) var lensZooms: [CGFloat] = [1]
  @Published private(set) var recordingSeconds: TimeInterval = 0
  @Published private(set) var videoQualityLabel = "Not configured"
  @Published private(set) var photoQualityLabel = "Not configured"
  @Published private(set) var isRecordingStarted = false
  @Published private(set) var isFrontCamera = false
  @Published private(set) var hasFlash = false
  @Published private(set) var hasTorch = false
  @Published private(set) var exposureBias: Float = 0
  @Published private(set) var previewAspectRatio: CGFloat = 3 / 4
  @Published private(set) var previewOrientation: AVCaptureVideoOrientation = .portrait
  @Published private(set) var microphoneDenied = false

  private let queue = DispatchQueue(label: "captro.camera.session", qos: .userInitiated)
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()
  private var input: AVCaptureDeviceInput?
  private var microphone: AVCaptureDeviceInput?
  private var configured = false
  private var wantsActive = false
  private var hasResult = false
  private var operation: State = .permissionNeeded
  private var captureMode: Mode = .photo
  private var flash: Flash = .off
  private var orientation: UIInterfaceOrientation = .portrait
  private var physicalOrientation: AVCaptureVideoOrientation?
  private var generation = 0
  private var captureID: Int64?
  private var pendingPhoto: Data?
  private var pendingPhotoError: Error?
  private var movieURL: URL?
  private var retainedMovieURL: URL?
  private var recordingTimer: DispatchSourceTimer?
  private var observations: [NSObjectProtocol] = []
  private var microphoneRequestPending = false
  // A dismissed camera must live until AVFoundation finishes its current file.
  private var captureRetention: CaptroCameraCaptureService?
  private var captureStartedAt: TimeInterval = 0
  // Main-queue owned. Protects only file finalization, never an offscreen camera.
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#if DEBUG
  private var testingAudioInstaller: (() throws -> Void)?
#endif

  override init() {
    super.init()
    observeLifecycle()
    DispatchQueue.main.async { [self] in
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      updateDeviceOrientation(UIDevice.current.orientation)
    }
  }

  deinit {
    observations.forEach(NotificationCenter.default.removeObserver)
    recordingTimer?.cancel()
    DispatchQueue.main.async { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
    let heldSession = session
    let heldOutput = movieOutput
    let file = retainedMovieURL
    queue.async {
      if heldOutput.isRecording { heldOutput.stopRecording() }
      if heldSession.isRunning { heldSession.stopRunning() }
      if let file { try? FileManager.default.removeItem(at: file) }
    }
  }

  func start() { resume() }

  func resume() {
    queue.async { [weak self] in
      guard let self else { return }
      self.wantsActive = true
      guard !self.hasResult, !self.operation.isBusy else { return }
      self.generation += 1
      let request = self.generation
      self.publish { $0.errorMessage = nil }
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        self.configureAndRun()
        if self.captureMode == .video { self.requestMicrophone() }
      case .notDetermined:
        self.transition(.permissionNeeded)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
          guard let self else { return }
          self.queue.async {
            guard self.wantsActive, self.generation == request else { return }
            if granted {
              self.configureAndRun()
              if self.captureMode == .video { self.requestMicrophone() }
            } else { self.fail("Allow camera access in Settings to take photos and videos.") }
          }
        }
      default: self.fail("Allow camera access in Settings to take photos and videos.")
      }
    }
  }

  /// Leaving the tab never tears down a file that is still being finalized.
  func suspend() {
    queue.async { [weak self] in
      guard let self else { return }
      self.wantsActive = false
      self.generation += 1
      self.applyTorch(false)
      if self.operation == .recording {
        self.finishRecording()
      } else if self.operation != .capturing && self.operation != .finalizing {
        self.stopSession()
      }
    }
  }

  func setMode(_ value: Mode) {
    queue.async { [weak self] in
      guard let self, !self.operation.isBusy, !self.hasResult, self.captureMode != value else { return }
      self.captureMode = value
      let orientation = self.physicalOrientation ?? CaptroCameraPolicy.captureOrientation(self.orientation)
      let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
      let ratio: CGFloat = value == .video ? 16 / 9 : 4 / 3
      let canConfigure = self.wantsActive && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
      self.publish {
        $0.mode = value; $0.notice = nil
        // A live session publishes its actual dimensions after reconfiguration.
        // Do not briefly stretch/crop the old format into the requested ratio.
        if !canConfigure { $0.previewAspectRatio = landscape ? ratio : 1 / ratio }
      }
      self.applyTorch(false)
      self.configured = false
      if canConfigure {
        self.configureAndRun()
        if self.operation == .failed {
          self.publish { $0.previewAspectRatio = landscape ? ratio : 1 / ratio }
        }
        if value == .video { self.requestMicrophone() }
      }
    }
  }

  func setOrientation(_ value: UIInterfaceOrientation) {
    guard value != .unknown else { return }
    queue.async { [weak self] in
      guard let self, self.orientation != value, self.operation != .recording, self.operation != .finalizing, self.operation != .capturing else { return }
      self.orientation = value
      self.applyOrientation()
      self.publishCapabilities()
    }
  }

  private func updateDeviceOrientation(_ value: UIDeviceOrientation) {
    guard let resolved = CaptroCameraPolicy.captureOrientation(value) else { return }
    queue.async { [weak self] in
      guard let self, self.physicalOrientation != resolved else { return }
      self.physicalOrientation = resolved
      guard !self.operation.isBusy, !self.hasResult else { return }
      self.applyOrientation()
      self.publishCapabilities()
    }
  }

  func shutter() {
    queue.async { [weak self] in
      guard let self else { return }
      if self.operation == .recording { self.finishRecording(); return }
      guard CaptroCameraPolicy.canBeginCapture(state: self.operation, wantsActive: self.wantsActive, running: self.session.isRunning, hasResult: self.hasResult) else { return }
      guard !self.microphoneRequestPending else { self.publish { $0.notice = "Choose microphone access before recording." }; return }
      guard self.hasCaptureSpace else { self.fail("Not enough storage. Free some space and try again."); return }
      if self.captureMode == .photo { self.capturePhoto() } else { self.captureVideo() }
    }
  }

  func flip() {
    queue.async { [weak self] in
      guard let self, self.wantsActive, self.session.isRunning, self.operation == .ready, !self.hasResult, let oldInput = self.input else { return }
      let next: AVCaptureDevice.Position = oldInput.device.position == .back ? .front : .back
      guard let device = self.device(position: next), let newInput = try? AVCaptureDeviceInput(device: device) else {
        self.publish { $0.notice = "This camera is unavailable." }; return
      }
      self.transition(.starting)
      self.session.stopRunning()
      self.session.beginConfiguration()
      self.session.removeInput(oldInput)
      if self.session.canAddInput(newInput) {
        self.session.addInput(newInput); self.input = newInput
      } else {
        self.session.addInput(oldInput)
      }
      self.session.commitConfiguration()
      self.configureAndRun(reconfigure: true)
    }
  }

  func setZoom(_ value: CGFloat) {
    queue.async { [weak self] in
      guard let self, let device = self.input?.device, self.operation == .ready || self.operation == .recording else { return }
      do {
        try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
        let range = Self.zoomBounds(device)
        device.videoZoomFactor = min(max(value, range.lowerBound), range.upperBound)
        let actual = device.videoZoomFactor
        self.publish { $0.zoom = actual }
      } catch { self.publish { $0.notice = "Zoom could not be adjusted." } }
    }
  }

  func focus(at point: CGPoint) {
    queue.async { [weak self] in
      guard let self, let device = self.input?.device, self.operation == .ready || self.operation == .recording else { return }
      do {
        try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
        let point = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
          device.focusPointOfInterest = point; device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
      } catch { self.publish { $0.notice = "Focus could not be adjusted." } }
    }
  }

  func setExposureBias(_ value: Float) {
    queue.async { [weak self] in
      guard let self, let device = self.input?.device, self.operation == .ready || self.operation == .recording else { return }
      do {
        try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
        let actual = min(max(value, max(device.minExposureTargetBias, -2)), min(device.maxExposureTargetBias, 2))
        device.setExposureTargetBias(actual)
        self.publish { $0.exposureBias = actual }
      } catch { self.publish { $0.notice = "Exposure could not be adjusted." } }
    }
  }

  func setFlash(_ value: Flash) {
    queue.async { [weak self] in
      guard let self, self.operation == .ready else { return }
      self.flash = value
      self.applyTorch(self.captureMode == .video && value == .on)
    }
  }

  func discardResult() {
    queue.async { [weak self] in
      guard let self, self.operation != .capturing, self.operation != .recording, self.operation != .finalizing else { return }
      self.hasResult = false
      if let file = self.retainedMovieURL { try? FileManager.default.removeItem(at: file) }
      self.retainedMovieURL = nil
      self.publish { $0.result = nil; $0.errorMessage = nil; $0.notice = nil }
      if self.wantsActive { self.configureAndRun() }
    }
  }

  private var hasCaptureSpace: Bool {
    let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return (values?.volumeAvailableCapacityForImportantUsage ?? Int64.max) > CaptroCameraPolicy.minimumFreeBytes
  }

  private func configureAndRun(reconfigure: Bool = false) {
    guard wantsActive, !hasResult else { return }
    transition(.starting)
    do {
      if !configured || reconfigure {
        configured = false
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        do {
          if input == nil {
            guard let device = device(position: .back) else { throw CaptureError.unavailable }
            let candidate = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(candidate) else { throw CaptureError.unavailable }
            session.addInput(candidate); input = candidate
          }
          if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw CaptureError.unavailable }
            session.addOutput(photoOutput)
          }
          if captureMode == .video {
            guard session.canSetSessionPreset(.hd1920x1080) else { throw CaptureError.videoFormat }
            session.sessionPreset = .hd1920x1080
            if !session.outputs.contains(movieOutput) {
              guard session.canAddOutput(movieOutput) else { throw CaptureError.unavailable }
              session.addOutput(movieOutput)
            }
          } else {
            if session.outputs.contains(movieOutput) { session.removeOutput(movieOutput) }
            if let microphone { session.removeInput(microphone); self.microphone = nil }
          }
          try configureFormat()
          if captureMode == .video && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            do { try installMicrophone() }
            catch { publish { $0.notice = "Microphone unavailable. Video will be recorded without sound." } }
          }
          session.commitConfiguration()
        } catch {
          session.commitConfiguration(); throw error
        }
        configured = true
      }
      // Permission prompts may background the scene. Reconcile the current OS
      // authorization when resuming even if the capture session already exists.
      if captureMode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, microphone == nil {
        session.beginConfiguration()
        do { try installMicrophone(); session.commitConfiguration() }
        catch {
          session.commitConfiguration()
          publish { $0.notice = "Microphone unavailable. Video will be recorded without sound." }
        }
      }
      applyOrientation()
      session.startRunning()
      guard session.isRunning else { throw CaptureError.unavailable }
      applyTorch(captureMode == .video && flash == .on)
      publishCapabilities()
      transition(.ready)
    } catch { fail(error.localizedDescription) }
  }

  private func configureFormat() throws {
    guard let device = input?.device else { throw CaptureError.unavailable }
    if captureMode == .photo {
      guard session.canSetSessionPreset(.photo) else { throw CaptureError.unavailable }
      session.sessionPreset = .photo
    } else {
      // The existing Stream delivery contract is 1080p. Do not advertise 4K until
      // that complete delivery pipeline has been verified and upgraded.
      guard let format = device.formats.first(where: {
        let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        return dimensions.width == 1920 && dimensions.height == 1080 &&
          $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
      }) else { throw CaptureError.videoFormat }
      session.sessionPreset = .inputPriority
      try device.lockForConfiguration()
      device.activeFormat = format
      device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
      device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
      // SDR is the proven existing upload/playback path; don't silently label HDR.
      device.automaticallyAdjustsVideoHDREnabled = false
      if device.activeFormat.isVideoHDRSupported { device.isVideoHDREnabled = false }
      device.unlockForConfiguration()
    }
    try device.lockForConfiguration()
    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
    device.isSubjectAreaChangeMonitoringEnabled = true
    device.unlockForConfiguration()
    guard let dimensions = CaptroCameraPolicy.largestPhotoDimensions(device.activeFormat.supportedMaxPhotoDimensions) else { throw CaptureError.unavailable }
    photoOutput.maxPhotoDimensions = dimensions
    photoOutput.maxPhotoQualityPrioritization = .quality
    movieOutput.maxRecordedDuration = CMTime(seconds: CaptroPostVideoLimits.maxDurationSeconds, preferredTimescale: 600)
    movieOutput.maxRecordedFileSize = Int64(CaptroPostVideoLimits.maxBytes)
    movieOutput.minFreeDiskSpaceLimit = CaptroCameraPolicy.minimumFreeBytes
    if let connection = movieOutput.connection(with: .video) {
      if connection.isVideoStabilizationSupported, device.activeFormat.isVideoStabilizationModeSupported(.standard) {
        connection.preferredVideoStabilizationMode = .standard
      }
      // H.264 is the verified capture→Stream→playback contract. HEVC capture can
      // be enabled only after that end-to-end path is verified on devices.
      guard movieOutput.availableVideoCodecTypes.contains(.h264) else { throw CaptureError.videoFormat }
      movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
    }
  }

  private func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    // Use the real wide camera. Zoom shortcuts below reflect its actual supported
    // range; never label a digital crop as a different physical lens.
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
  }

  private func requestMicrophone() {
    guard !microphoneRequestPending else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      microphoneRequestPending = true
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
        guard let self else { return }
        self.queue.async {
          self.completeMicrophonePermission(authorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        }
      }
    case .authorized: updateMicrophonePermission(true)
    default: updateMicrophonePermission(false)
    }
  }

  private func completeMicrophonePermission(authorized: Bool) {
    microphoneRequestPending = false
    // A permission sheet can change scene activity/generation. Its result is OS
    // authorization, not a stale session command. Reconcile the present context.
    guard wantsActive, captureMode == .video, !hasResult else { return }
    updateMicrophonePermission(authorized)
  }

  private func updateMicrophonePermission(_ granted: Bool) {
    publish { $0.microphoneDenied = !granted; $0.notice = granted ? nil : "Microphone is off. Video will be recorded without sound." }
    guard granted, configured, operation == .ready else { return }
#if DEBUG
    if let testingAudioInstaller {
      do { try testingAudioInstaller() }
      catch { publish { $0.notice = "Microphone unavailable. Video will be recorded without sound." } }
      return
    }
#endif
    session.beginConfiguration()
    do { try installMicrophone() } catch { publish { $0.notice = "Microphone unavailable. Video will be recorded without sound." } }
    session.commitConfiguration()
  }

  private func installMicrophone() throws {
    guard microphone == nil else { return }
    guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.microphoneUnavailable }
    let candidate = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(candidate) else { throw CaptureError.microphoneUnavailable }
    session.addInput(candidate); microphone = candidate
  }

  private func capturePhoto() {
    captureRetention = self
    beginFinalizationProtection()
    captureStartedAt = ProcessInfo.processInfo.systemUptime
    transition(.capturing)
    let codec: AVVideoCodecType = photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
    settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
    settings.photoQualityPrioritization = .quality
    let selectedFlash: AVCaptureDevice.FlashMode = flash == .on ? .on : flash == .auto ? .auto : .off
    if photoOutput.supportedFlashModes.contains(selectedFlash) { settings.flashMode = selectedFlash }
    pendingPhoto = nil; pendingPhotoError = nil; captureID = settings.uniqueID
    applyOrientation()
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func captureVideo() {
    guard ProcessInfo.processInfo.thermalState != .critical else { fail("iPhone needs to cool down before recording."); return }
    transition(.recording)
    publish { $0.isRecordingStarted = false }
    captureRetention = self
    beginFinalizationProtection()
    captureStartedAt = ProcessInfo.processInfo.systemUptime
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-capture-\(UUID().uuidString).mov")
    movieURL = url
    applyOrientation()
    movieOutput.startRecording(to: url, recordingDelegate: self)
    publish { $0.recordingSeconds = 0 }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(200))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let seconds = self.movieOutput.recordedDuration.seconds
      self.publish { $0.recordingSeconds = seconds.isFinite ? seconds : 0 }
    }
    recordingTimer = timer; timer.resume()
  }

  private func finishRecording() {
    guard operation == .recording else { return }
    transition(.finalizing)
    if movieOutput.isRecording { movieOutput.stopRecording() }
    // If stop precedes didStartRecording, that delegate will finish it.
    recordingTimer?.cancel(); recordingTimer = nil
    applyTorch(false)
  }

  private func applyOrientation() {
    let value = physicalOrientation ?? CaptroCameraPolicy.captureOrientation(orientation)
    for connection in [photoOutput.connection(with: .video), movieOutput.connection(with: .video)].compactMap({ $0 }) {
      if connection.isVideoOrientationSupported { connection.videoOrientation = value }
      if connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = input?.device.position == .front
      }
    }
  }

  private static func zoomBounds(_ device: AVCaptureDevice) -> ClosedRange<CGFloat> {
    max(1, device.minAvailableVideoZoomFactor)...max(1, min(device.maxAvailableVideoZoomFactor, 5))
  }

  private func publishCapabilities() {
    guard let device = input?.device else { return }
    let range = Self.zoomBounds(device)
    let dimensions = captureMode == .photo ? photoOutput.maxPhotoDimensions : CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    let landscapeRatio = CGFloat(dimensions.width) / max(CGFloat(dimensions.height), 1)
    let resolvedOrientation = physicalOrientation ?? CaptroCameraPolicy.captureOrientation(orientation)
    let ratio = resolvedOrientation == .landscapeLeft || resolvedOrientation == .landscapeRight ? landscapeRatio : 1 / landscapeRatio
    let zoom = device.videoZoomFactor
    let flash = device.hasFlash
    let torch = device.hasTorch
    let front = device.position == .front
    let exposure = device.exposureTargetBias
    let photoDimensions = photoOutput.maxPhotoDimensions
    let photoLabel = "\(photoDimensions.width) × \(photoDimensions.height)"
    let videoDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    let videoLabel = CaptroCameraPolicy.videoFormatLabel(dimensions: videoDimensions, frameDuration: device.activeVideoMinFrameDuration)
    let videoMode = captureMode == .video
    publish {
      $0.zoom = zoom; $0.zoomRange = range; $0.lensZooms = [1]
      $0.hasFlash = flash; $0.hasTorch = torch; $0.isFrontCamera = front
      $0.previewAspectRatio = ratio; $0.exposureBias = exposure
      $0.previewOrientation = resolvedOrientation
      $0.photoQualityLabel = photoLabel
      $0.videoQualityLabel = videoMode ? videoLabel : "Not configured"
    }
  }

  private func applyTorch(_ enabled: Bool) {
    guard let device = input?.device, device.hasTorch, device.isTorchAvailable else { return }
    do {
      try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
      if enabled { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) }
      else { device.torchMode = .off }
    } catch { publish { $0.notice = "The light is unavailable." } }
  }

  private func accept(_ media: MIRAPickedMedia) {
    hasResult = true
    applyTorch(false)
    stopSession()
    publish { $0.result = media; $0.errorMessage = nil }
    transition(.ready)
    endFinalizationProtection()
    captureRetention = nil
  }

  private func stopSession() { if session.isRunning { session.stopRunning() } }
  private func transition(_ value: State) { operation = value; publish { $0.state = value } }
  private func fail(_ message: String) {
    applyTorch(false); stopSession(); transition(.failed)
    publish { $0.errorMessage = message; $0.isRecordingStarted = false }
    endFinalizationProtection()
    captureRetention = nil
  }
  private func beginFinalizationProtection() {
    DispatchQueue.main.async { [self] in
      guard self.backgroundTask == .invalid else { return }
      self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish camera capture") { [weak self] in
        self?.suspend()
        self?.endFinalizationProtection()
      }
    }
  }
  private func endFinalizationProtection() {
    DispatchQueue.main.async { [self] in
      guard self.backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
  }
  private func publish(_ update: @escaping (CaptroCameraCaptureService) -> Void) {
    DispatchQueue.main.async { [weak self] in if let self { update(self) } }
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    observations.append(center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.updateDeviceOrientation(UIDevice.current.orientation)
    })
    observations.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in self?.suspend() })
    observations.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
      self?.queue.async { [weak self] in
        guard let self else { return }
        if self.operation == .recording { self.finishRecording() }
        else if self.operation != .capturing && self.operation != .finalizing { self.transition(.interrupted) }
        self.publish { $0.notice = "Camera interrupted. Your completed captures are safe." }
      }
    })
    observations.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
      self?.queue.async { [weak self] in
        guard let self, self.wantsActive, self.operation == .interrupted, !self.hasResult else { return }
        self.configureAndRun()
      }
    })
    observations.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
      let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
      self?.queue.async { [weak self] in
        guard let self else { return }
        if self.operation == .recording { self.finishRecording(); return }
        guard self.operation != .capturing && self.operation != .finalizing else { return }
        if error?.code == .mediaServicesWereReset, self.wantsActive, !self.hasResult { self.configureAndRun() }
        else { self.fail("Camera interrupted. Try again when it is available.") }
      }
    })
    observations.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
      self?.queue.async { [weak self] in
        guard let self, ProcessInfo.processInfo.thermalState == .critical else { return }
        if self.operation == .recording { self.finishRecording() }
        self.publish { $0.notice = "iPhone needs to cool down. Recording has been stopped safely." }
      }
    })
    observations.append(center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
      self?.queue.async { [weak self] in
        guard let self, let device = self.input?.device else { return }
        do {
          try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
          if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
          if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        } catch { self.publish { $0.notice = "Continuous focus could not be restored." } }
      }
    })
  }

  private enum CaptureError: LocalizedError {
    case unavailable, videoFormat, microphoneUnavailable
    var errorDescription: String? {
      self == .videoFormat ? "1080p at 30 FPS is unavailable on this camera. Try the other camera." : "Camera unavailable. Try again or check camera access in Settings."
    }
  }

#if DEBUG
  /// Unit-test seam at the hardware boundary. Tests run the real queued permission
  /// completion and suspend paths, without pretending a simulator has a camera.
  func preparePermissionTestContext(mode: Mode, active: Bool, generation: Int,
                                    installAudio: @escaping () throws -> Void) async {
    await withCheckedContinuation { continuation in
      queue.async {
        self.captureMode = mode; self.wantsActive = active; self.generation = generation
        self.configured = true; self.operation = .ready; self.microphoneRequestPending = true
        self.testingAudioInstaller = installAudio
        continuation.resume()
      }
    }
  }
  func finishPermissionForTesting(authorized: Bool) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        self.completeMicrophonePermission(authorized: authorized)
        continuation.resume(returning: self.microphoneRequestPending)
      }
    }
  }
#endif
}

extension CaptroCameraCaptureService: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    queue.async { [weak self] in
      guard let self, self.captureID == photo.resolvedSettings.uniqueID else { return }
      self.pendingPhoto = photo.fileDataRepresentation()
      self.pendingPhotoError = error
    }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
    queue.async { [weak self] in
      guard let self, self.captureID == resolvedSettings.uniqueID else { return }
      self.captureID = nil
      defer { self.pendingPhoto = nil; self.pendingPhotoError = nil }
      guard error == nil, self.pendingPhotoError == nil, let data = self.pendingPhoto, !data.isEmpty else {
        self.fail("That photo could not be captured. Try again."); return
      }
      let jpeg = data.starts(with: [0xff, 0xd8, 0xff])
#if DEBUG
      if let source = CGImageSourceCreateWithData(data as CFData, nil),
         let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        print("CaptroCamera photo_complete width=\(width) height=\(height) bytes=\(data.count) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - self.captureStartedAt) * 1000)) main=\(Thread.isMainThread)")
      }
#endif
      self.accept(MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).\(jpeg ? "jpg" : "heic")", mimeType: jpeg ? "image/jpeg" : "image/heic"))
    }
  }

  func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    queue.async { [weak self] in
      guard let self, self.movieURL == fileURL else { return }
      self.publish { $0.isRecordingStarted = true }
#if DEBUG
      print("CaptroCamera video_started elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - self.captureStartedAt) * 1000)) main=\(Thread.isMainThread)")
#endif
      if !self.wantsActive || self.operation == .finalizing { self.movieOutput.stopRecording() }
    }
  }

  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    queue.async { [weak self] in
      guard let self, self.movieURL == fileURL else { return }
      self.publish { $0.isRecordingStarted = false }
      self.recordingTimer?.cancel(); self.recordingTimer = nil
      self.movieURL = nil
      self.transition(.finalizing)
      self.applyTorch(false)
      guard CaptroCameraPolicy.recordingSucceeded(error) else {
        try? FileManager.default.removeItem(at: fileURL)
        self.fail("That video could not be completed. Please try again."); return
      }
      do {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let count = values.fileSize, count > 0, count <= CaptroPostVideoLimits.maxBytes else { throw CaptureError.unavailable }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
#if DEBUG
        print("CaptroCamera video_finalized bytes=\(count) codec=h264 format=1080p30 main=\(Thread.isMainThread)")
#endif
        self.retainedMovieURL = fileURL
        self.accept(MIRAPickedMedia(data: data, kind: .video, fileName: fileURL.lastPathComponent, mimeType: "video/quicktime"))
      } catch {
        try? FileManager.default.removeItem(at: fileURL)
        self.fail("The video could not be saved. Check available storage and try again.")
      }
    }
  }
}

enum CaptroCameraPolicy {
  static func videoFormatLabel(dimensions: CMVideoDimensions, frameDuration: CMTime) -> String {
    let seconds = frameDuration.seconds
    guard dimensions.width > 0, dimensions.height > 0, seconds.isFinite, seconds > 0,
          (1...240).contains(1 / seconds) else { return "Not configured" }
    return "\(min(dimensions.width, dimensions.height))p · \(Int((1 / seconds).rounded())) FPS"
  }
  static let minimumFreeBytes: Int64 = 50_000_000
  static func canBeginCapture(state: CaptroCameraCaptureService.State, wantsActive: Bool, running: Bool, hasResult: Bool) -> Bool {
    state == .ready && wantsActive && running && !hasResult
  }
  static func largestPhotoDimensions(_ supported: [CMVideoDimensions]) -> CMVideoDimensions? {
    supported.filter { $0.width > 0 && $0.height > 0 }.max {
      Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
    }
  }
  static func recordingSucceeded(_ error: Error?) -> Bool {
    guard let error = error as NSError? else { return true }
    return (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
  }
  static func captureOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
    switch orientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
  static func captureOrientation(_ orientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
    switch orientation {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    default: return nil // Flat/unknown must not unexpectedly rotate the composition.
    }
  }
}
