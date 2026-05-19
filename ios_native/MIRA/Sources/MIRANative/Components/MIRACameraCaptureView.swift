import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

public struct MIRACameraCaptureView: UIViewControllerRepresentable {
  public typealias UIViewControllerType = UIImagePickerController

  let allowsVideo: Bool
  let onCapture: (MIRAPickedMedia) -> Void

  @Environment(\.dismiss) private var dismiss

  public init(allowsVideo: Bool = true, onCapture: @escaping (MIRAPickedMedia) -> Void) {
    self.allowsVideo = allowsVideo
    self.onCapture = onCapture
  }

  public func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.mediaTypes = allowsVideo ? [UTType.image.identifier, UTType.movie.identifier] : [UTType.image.identifier]
    picker.videoQuality = .typeHigh
    picker.delegate = context.coordinator
    return picker
  }

  public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    private let parent: MIRACameraCaptureView

    init(parent: MIRACameraCaptureView) {
      self.parent = parent
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }

    public func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer { parent.dismiss() }

      if let videoURL = info[.mediaURL] as? URL,
         let data = try? Data(contentsOf: videoURL) {
        parent.onCapture(MIRAPickedMedia(data: data, kind: .video, fileName: "\(UUID().uuidString).mov", mimeType: "video/quicktime"))
        return
      }

      if let image = info[.originalImage] as? UIImage,
         let data = image.jpegData(compressionQuality: 0.9) {
        parent.onCapture(MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpeg"))
      }
    }
  }
}

struct MIRAStoryLiveCameraView: UIViewControllerRepresentable {
  let onCapture: (MIRAPickedMedia) -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss

  init(onCapture: @escaping (MIRAPickedMedia) -> Void, onCancel: @escaping () -> Void = {}) {
    self.onCapture = onCapture
    self.onCancel = onCancel
  }

  func makeUIViewController(context: Context) -> MIRAStoryCameraViewController {
    let controller = MIRAStoryCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: MIRAStoryCameraViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel, dismiss: dismiss)
  }

  final class Coordinator: NSObject, MIRAStoryCameraViewControllerDelegate {
    private let onCapture: (MIRAPickedMedia) -> Void
    private let onCancel: () -> Void
    private let dismiss: DismissAction

    init(onCapture: @escaping (MIRAPickedMedia) -> Void, onCancel: @escaping () -> Void, dismiss: DismissAction) {
      self.onCapture = onCapture
      self.onCancel = onCancel
      self.dismiss = dismiss
    }

    func storyCameraDidCancel() {
      onCancel()
      dismiss()
    }

    func storyCameraDidCapturePhoto(_ data: Data) {
      onCapture(MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpeg"))
      dismiss()
    }

    func storyCameraDidCaptureVideo(_ data: Data) {
      onCapture(MIRAPickedMedia(data: data, kind: .video, fileName: "\(UUID().uuidString).mov", mimeType: "video/quicktime"))
      dismiss()
    }
  }
}

protocol MIRAStoryCameraViewControllerDelegate: AnyObject {
  func storyCameraDidCancel()
  func storyCameraDidCapturePhoto(_ data: Data)
  func storyCameraDidCaptureVideo(_ data: Data)
}

final class MIRAStoryCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
  weak var delegate: MIRAStoryCameraViewControllerDelegate?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "mira.story.camera.session")
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private var currentInput: AVCaptureDeviceInput?
  private var cameraPosition: AVCaptureDevice.Position = .back
  private var flashMode: AVCaptureDevice.FlashMode = .off
  private var isConfigured = false

  private let messageLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.isHidden = true
    return label
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    installPreview()
    installControls()
    prepareCamera()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [session] in
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func installPreview() {
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.backgroundColor = UIColor.black.cgColor
    view.layer.addSublayer(previewLayer)
  }

  private func installControls() {
    let closeButton = iconButton(systemName: "xmark", action: #selector(cancelTapped))
    let flashButton = iconButton(systemName: "bolt.slash", action: #selector(toggleFlash))
    let flipButton = iconButton(systemName: "arrow.triangle.2.circlepath.camera", action: #selector(flipCamera))
    let textButton = textOverlayButton("Aa")
    let loopButton = iconButton(systemName: "infinity", action: #selector(noop))
    let layoutButton = iconButton(systemName: "square.split.2x1", action: #selector(noop))
    let effectsButton = iconButton(systemName: "face.smiling", action: #selector(noop))
    let confirmButton = iconButton(systemName: "checkmark", action: #selector(noop))

    let topRow = UIStackView(arrangedSubviews: [closeButton, UIView(), flashButton, UIView(), flipButton])
    topRow.axis = .horizontal
    topRow.alignment = .center
    topRow.translatesAutoresizingMaskIntoConstraints = false

    let toolColumn = UIStackView(arrangedSubviews: [textButton, loopButton, layoutButton, effectsButton, confirmButton])
    toolColumn.axis = .vertical
    toolColumn.alignment = .leading
    toolColumn.spacing = 22
    toolColumn.translatesAutoresizingMaskIntoConstraints = false

    let shutterButton = UIButton(type: .system)
    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.80)
    shutterButton.layer.cornerRadius = 42
    shutterButton.layer.borderWidth = 4
    shutterButton.layer.borderColor = UIColor.white.cgColor
    shutterButton.layer.shadowColor = UIColor.black.cgColor
    shutterButton.layer.shadowOpacity = 0.18
    shutterButton.layer.shadowRadius = 16
    shutterButton.layer.shadowOffset = CGSize(width: 0, height: 8)
    shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleShutterLongPress(_:)))
    longPress.minimumPressDuration = 0.22
    shutterButton.addGestureRecognizer(longPress)

    messageLabel.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(topRow)
    view.addSubview(toolColumn)
    view.addSubview(shutterButton)
    view.addSubview(messageLabel)

    NSLayoutConstraint.activate([
      topRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
      topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      closeButton.widthAnchor.constraint(equalToConstant: 52),
      closeButton.heightAnchor.constraint(equalToConstant: 52),
      flashButton.widthAnchor.constraint(equalToConstant: 52),
      flashButton.heightAnchor.constraint(equalToConstant: 52),
      flipButton.widthAnchor.constraint(equalToConstant: 52),
      flipButton.heightAnchor.constraint(equalToConstant: 52),

      toolColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
      toolColumn.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40),

      shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -38),
      shutterButton.widthAnchor.constraint(equalToConstant: 84),
      shutterButton.heightAnchor.constraint(equalToConstant: 84),

      messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
      messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),
      messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }

  private func iconButton(systemName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .white
    button.setImage(UIImage(systemName: systemName), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.backgroundColor = UIColor.black.withAlphaComponent(0.16)
    button.layer.cornerRadius = 26
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func textOverlayButton(_ title: String) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 34, weight: .regular)
    button.widthAnchor.constraint(equalToConstant: 58).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    button.addTarget(self, action: #selector(noop), for: .touchUpInside)
    return button
  }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          granted ? self?.configureSession() : self?.showCameraUnavailableMessage()
        }
      }
    default:
      showCameraUnavailableMessage()
    }
  }

  private func configureSession() {
    guard !isConfigured else { return }
    isConfigured = true

    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.session.beginConfiguration()
      self.session.sessionPreset = .high

      if let input = self.makeCameraInput(position: self.cameraPosition), self.session.canAddInput(input) {
        self.session.addInput(input)
        self.currentInput = input
      }

      if self.session.canAddOutput(self.photoOutput) {
        self.session.addOutput(self.photoOutput)
      }

      if self.session.canAddOutput(self.movieOutput) {
        self.session.addOutput(self.movieOutput)
        self.movieOutput.movieFragmentInterval = .invalid
      }

      self.session.commitConfiguration()

      DispatchQueue.main.async {
        self.previewLayer.session = self.session
      }

      self.session.startRunning()
    }
  }

  private func makeCameraInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
      return nil
    }
    return try? AVCaptureDeviceInput(device: device)
  }

  private func showCameraUnavailableMessage() {
    messageLabel.text = "Camera access is needed to create a story. Turn it on in Settings, then try again."
    messageLabel.isHidden = false
  }

  @objc private func cancelTapped() {
    delegate?.storyCameraDidCancel()
  }

  @objc private func capturePhoto() {
    guard session.isRunning, !movieOutput.isRecording else { return }
    let settings = AVCapturePhotoSettings()
    if photoOutput.supportedFlashModes.contains(flashMode) {
      settings.flashMode = flashMode
    }
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  @objc private func handleShutterLongPress(_ recognizer: UILongPressGestureRecognizer) {
    switch recognizer.state {
    case .began:
      startRecordingVideo()
      UIView.animate(withDuration: 0.12) {
        recognizer.view?.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        recognizer.view?.backgroundColor = UIColor.white.withAlphaComponent(0.64)
      }
    case .ended, .cancelled, .failed:
      if movieOutput.isRecording {
        movieOutput.stopRecording()
      }
      UIView.animate(withDuration: 0.12) {
        recognizer.view?.transform = .identity
        recognizer.view?.backgroundColor = UIColor.white.withAlphaComponent(0.80)
      }
    default:
      break
    }
  }

  private func startRecordingVideo() {
    guard session.isRunning, !movieOutput.isRecording else { return }
    if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    movieOutput.startRecording(to: url, recordingDelegate: self)
  }

  @objc private func toggleFlash(_ sender: UIButton) {
    flashMode = flashMode == .off ? .auto : .off
    let imageName = flashMode == .off ? "bolt.slash" : "bolt.badge.a"
    sender.setImage(UIImage(systemName: imageName), for: .normal)
  }

  @objc private func flipCamera() {
    cameraPosition = cameraPosition == .back ? .front : .back
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.session.beginConfiguration()
      if let currentInput = self.currentInput {
        self.session.removeInput(currentInput)
      }
      if let input = self.makeCameraInput(position: self.cameraPosition), self.session.canAddInput(input) {
        self.session.addInput(input)
        self.currentInput = input
      }
      self.session.commitConfiguration()
    }
  }

  @objc private func noop() {}

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard error == nil, let data = photo.fileDataRepresentation() else {
      messageLabel.text = "That photo could not be captured. Try again."
      messageLabel.isHidden = false
      return
    }
    delegate?.storyCameraDidCapturePhoto(data)
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    defer { try? FileManager.default.removeItem(at: outputFileURL) }
    guard error == nil, let data = try? Data(contentsOf: outputFileURL), !data.isEmpty else {
      messageLabel.text = "That video could not be captured. Try again."
      messageLabel.isHidden = false
      return
    }
    delegate?.storyCameraDidCaptureVideo(data)
  }
}
