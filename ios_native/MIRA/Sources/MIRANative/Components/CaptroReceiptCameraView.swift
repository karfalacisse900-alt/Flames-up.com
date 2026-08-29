import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision

struct CaptroReceiptCameraView: UIViewControllerRepresentable {
  let captureRequestID: Int
  let torchEnabled: Bool
  let onCapture: (Result<Data, Error>) -> Void
  let onStatusChange: (CaptroCameraDocumentStatus) -> Void
  let onAvailabilityChange: (Bool) -> Void

  func makeUIViewController(context: Context) -> CaptroReceiptCameraViewController {
    let controller = CaptroReceiptCameraViewController()
    controller.onCapture = onCapture
    controller.onStatusChange = onStatusChange
    controller.onAvailabilityChange = onAvailabilityChange
    return controller
  }

  func updateUIViewController(_ controller: CaptroReceiptCameraViewController, context: Context) {
    controller.onCapture = onCapture
    controller.onStatusChange = onStatusChange
    controller.onAvailabilityChange = onAvailabilityChange
    controller.setTorchEnabled(torchEnabled)
    controller.requestCapture(id: captureRequestID)
  }
}

enum CaptroCameraDocumentStatus: Equatable {
  case looking
  case receiptDetected
  case invoiceDetected
  case holdSteady
  case ready
  case capturing

  var title: String {
    switch self {
    case .looking: return "Looking for a document..."
    case .receiptDetected: return "Receipt detected"
    case .invoiceDetected: return "Invoice detected"
    case .holdSteady: return "Hold steady"
    case .ready: return "Ready"
    case .capturing: return "Capturing..."
    }
  }
}

private enum CaptroReceiptCameraError: Error, LocalizedError {
  case unavailable
  case permissionDenied
  case configurationFailed
  case captureFailed

  var errorDescription: String? {
    switch self {
    case .unavailable: return "Camera scanning is unavailable on this device."
    case .permissionDenied: return "Allow camera access in Settings to scan a document."
    case .configurationFailed: return "Captro could not start the document camera."
    case .captureFailed: return "Captro could not capture that document. Try again."
    }
  }
}

final class CaptroReceiptCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
  var onCapture: ((Result<Data, Error>) -> Void)?
  var onStatusChange: ((CaptroCameraDocumentStatus) -> Void)?
  var onAvailabilityChange: ((Bool) -> Void)?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "captro.receipt.camera.session", qos: .userInitiated)
  private let detectionQueue = DispatchQueue(label: "captro.receipt.camera.detection", qos: .userInitiated)
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let edgeLayer = CAShapeLayer()

  private var cameraDevice: AVCaptureDevice?
  private var configured = false
  private var lastCaptureRequestID = 0
  private var lastDetectionTime: CFTimeInterval = 0
  private var detectionInFlight = false
  private var stableFrames = 0
  private var lastRectangle: VNRectangleObservation?
  private var requestedTorchEnabled = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(white: 0.08, alpha: 1)
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    edgeLayer.fillColor = UIColor.clear.cgColor
    edgeLayer.strokeColor = UIColor.white.withAlphaComponent(0.82).cgColor
    edgeLayer.lineWidth = 1.5
    edgeLayer.lineJoin = .round
    edgeLayer.shadowColor = UIColor.black.cgColor
    edgeLayer.shadowOpacity = 0.16
    edgeLayer.shadowRadius = 4
    view.layer.addSublayer(edgeLayer)

    prepareCamera()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startSessionIfReady()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
    edgeLayer.frame = view.bounds
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
  }

  func requestCapture(id: Int) {
    guard id > 0, id != lastCaptureRequestID else { return }
    lastCaptureRequestID = id
    sessionQueue.async { [weak self] in
      guard let self, self.configured, self.session.isRunning else {
        DispatchQueue.main.async { self?.onCapture?(.failure(CaptroReceiptCameraError.unavailable)) }
        return
      }
      DispatchQueue.main.async { self.onStatusChange?(.capturing) }
      let settings = AVCapturePhotoSettings()
      settings.photoQualityPrioritization = .quality
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  func setTorchEnabled(_ enabled: Bool) {
    requestedTorchEnabled = enabled
    sessionQueue.async { [weak self] in self?.applyTorchState() }
  }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        if granted {
          self.configureSession()
        } else {
          DispatchQueue.main.async {
            self.onAvailabilityChange?(false)
            self.onCapture?(.failure(CaptroReceiptCameraError.permissionDenied))
          }
        }
      }
    default:
      onAvailabilityChange?(false)
    }
  }

  private func configureSession() {
    sessionQueue.async { [weak self] in
      guard let self, !self.configured else { return }
      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device) else {
        DispatchQueue.main.async { self.onAvailabilityChange?(false) }
        return
      }

      self.session.beginConfiguration()
      self.session.sessionPreset = .photo
      guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.videoOutput) else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.onAvailabilityChange?(false) }
        return
      }

      self.session.addInput(input)
      self.session.addOutput(self.photoOutput)
      self.photoOutput.maxPhotoQualityPrioritization = .quality
      self.videoOutput.alwaysDiscardsLateVideoFrames = true
      self.videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ]
      self.videoOutput.setSampleBufferDelegate(self, queue: self.detectionQueue)
      self.session.addOutput(self.videoOutput)
      self.cameraDevice = device
      self.previewLayer.session = self.session
      self.configured = true
      self.session.commitConfiguration()
      self.applyTorchState()
      self.session.startRunning()

      DispatchQueue.main.async {
        self.onAvailabilityChange?(true)
        self.onStatusChange?(.looking)
      }
    }
  }

  private func startSessionIfReady() {
    sessionQueue.async { [weak self] in
      guard let self, self.configured, !self.session.isRunning else { return }
      self.session.startRunning()
      self.applyTorchState()
    }
  }

  private func applyTorchState() {
    guard let cameraDevice, cameraDevice.hasTorch else { return }
    do {
      try cameraDevice.lockForConfiguration()
      defer { cameraDevice.unlockForConfiguration() }
      if requestedTorchEnabled {
        try cameraDevice.setTorchModeOn(level: min(0.5, AVCaptureDevice.maxAvailableTorchLevel))
      } else {
        cameraDevice.torchMode = .off
      }
    } catch {}
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let now = CACurrentMediaTime()
    guard now - lastDetectionTime >= 0.28, !detectionInFlight,
          let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lastDetectionTime = now
    detectionInFlight = true

    let request = VNDetectRectanglesRequest { [weak self] request, _ in
      guard let self else { return }
      let rectangle = (request.results as? [VNRectangleObservation])?.first
      DispatchQueue.main.async {
        self.updateDetection(rectangle)
        self.detectionInFlight = false
      }
    }
    request.maximumObservations = 1
    request.minimumConfidence = 0.68
    request.minimumAspectRatio = 0.18
    request.maximumAspectRatio = 1.0
    request.quadratureTolerance = 22
    try? VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .right, options: [:]).perform([request])
  }

  private func updateDetection(_ rectangle: VNRectangleObservation?) {
    guard let rectangle else {
      stableFrames = 0
      lastRectangle = nil
      edgeLayer.path = nil
      onStatusChange?(.looking)
      return
    }

    if let previous = lastRectangle {
      let delta = abs(previous.boundingBox.midX - rectangle.boundingBox.midX)
        + abs(previous.boundingBox.midY - rectangle.boundingBox.midY)
        + abs(previous.boundingBox.width - rectangle.boundingBox.width)
        + abs(previous.boundingBox.height - rectangle.boundingBox.height)
      stableFrames = delta < 0.055 ? stableFrames + 1 : 0
    } else {
      stableFrames = 0
    }
    lastRectangle = rectangle
    edgeLayer.path = rectanglePath(rectangle).cgPath

    if stableFrames >= 5 {
      onStatusChange?(.ready)
    } else if stableFrames >= 2 {
      onStatusChange?(.holdSteady)
    } else {
      let ratio = rectangle.boundingBox.width / max(rectangle.boundingBox.height, 0.01)
      onStatusChange?(ratio < 0.62 ? .receiptDetected : .invoiceDetected)
    }
  }

  private func rectanglePath(_ rectangle: VNRectangleObservation) -> UIBezierPath {
    let convert: (CGPoint) -> CGPoint = { [previewLayer] point in
      previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y))
    }
    let path = UIBezierPath()
    path.move(to: convert(rectangle.topLeft))
    path.addLine(to: convert(rectangle.topRight))
    path.addLine(to: convert(rectangle.bottomRight))
    path.addLine(to: convert(rectangle.bottomLeft))
    path.close()
    return path
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    guard error == nil, let data = photo.fileDataRepresentation() else {
      DispatchQueue.main.async { self.onCapture?(.failure(error ?? CaptroReceiptCameraError.captureFailed)) }
      return
    }
    detectionQueue.async { [weak self] in
      let corrected = CaptroReceiptPerspectiveCorrector.correct(data) ?? data
      DispatchQueue.main.async {
        self?.onCapture?(.success(corrected))
      }
    }
  }
}

private enum CaptroReceiptPerspectiveCorrector {
  static func correct(_ data: Data) -> Data? {
    guard let image = UIImage(data: data), let ciImage = CIImage(image: image) else { return nil }
    let request = VNDetectRectanglesRequest()
    request.maximumObservations = 1
    request.minimumConfidence = 0.72
    request.minimumAspectRatio = 0.16
    request.quadratureTolerance = 24
    try? VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:]).perform([request])
    guard let rectangle = request.results?.first else { return image.jpegData(compressionQuality: 0.92) }

    let extent = ciImage.extent
    let point: (CGPoint) -> CIVector = { normalized in
      CIVector(x: extent.minX + normalized.x * extent.width, y: extent.minY + normalized.y * extent.height)
    }
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(point(rectangle.topLeft), forKey: "inputTopLeft")
    filter.setValue(point(rectangle.topRight), forKey: "inputTopRight")
    filter.setValue(point(rectangle.bottomLeft), forKey: "inputBottomLeft")
    filter.setValue(point(rectangle.bottomRight), forKey: "inputBottomRight")
    guard let output = filter.outputImage,
          let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
  }
}
