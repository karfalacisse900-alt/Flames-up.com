import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

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

    func storyCameraDidCapture(_ media: MIRAPickedMedia) {
      onCapture(media)
      dismiss()
    }
  }
}

protocol MIRAStoryCameraViewControllerDelegate: AnyObject {
  func storyCameraDidCancel()
  func storyCameraDidCapture(_ media: MIRAPickedMedia)
}

final class MIRAStoryCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, PHPickerViewControllerDelegate {
  weak var delegate: MIRAStoryCameraViewControllerDelegate?

  private enum CameraMode: String, CaseIterable {
    case photo = "Photo"
    case video15 = "15s"
    case video60 = "60s"
    case text = "Text"

    var maxDuration: TimeInterval? {
      switch self {
      case .video15: return 15
      case .video60: return 60
      default: return nil
      }
    }
  }

  private enum TimerSetting: CaseIterable {
    case off
    case three
    case ten

    var seconds: Int {
      switch self {
      case .off: return 0
      case .three: return 3
      case .ten: return 10
      }
    }

    var title: String {
      seconds == 0 ? "Timer off" : "\(seconds)s"
    }
  }

  private enum FlashSetting: CaseIterable {
    case off
    case on
    case automatic

    var systemImage: String {
      switch self {
      case .off: return "bolt.slash.fill"
      case .on: return "bolt.fill"
      case .automatic: return "bolt.circle.fill"
      }
    }

    var photoMode: AVCaptureDevice.FlashMode {
      switch self {
      case .off: return .off
      case .on: return .on
      case .automatic: return .auto
      }
    }
  }

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "mira.camera.session")
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let imageManager = PHCachingImageManager()

  private var currentInput: AVCaptureDeviceInput?
  private var audioInput: AVCaptureDeviceInput?
  private var cameraPosition: AVCaptureDevice.Position = .back
  private var isConfigured = false
  private var selectedMode: CameraMode = .photo
  private var timerSetting: TimerSetting = .off
  private var flashSetting: FlashSetting = .off
  private var countdownTimer: Timer?
  private var countdownValue = 0
  private var pendingStopWorkItem: DispatchWorkItem?
  private var initialZoomFactor: CGFloat = 1
  private var longPressDidRecord = false
  private var capturedMedia: MIRAPickedMedia?

  private let previewContainer = UIView()
  private let gridOverlay = MIRACameraGridOverlayView()
  private let capturedImageView = UIImageView()
  private let capturedPlayIcon = UIImageView(image: UIImage(systemName: "play.fill"))
  private let focusRing = UIView()
  private let loadingIndicator = UIActivityIndicatorView(style: .large)

  private let closeButton = UIButton(type: .system)
  private let flipButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)
  private let timerButton = UIButton(type: .system)
  private let gridButton = UIButton(type: .system)
  private let galleryRailButton = UIButton(type: .system)
  private let filtersButton = UIButton(type: .system)
  private let galleryButton = UIButton(type: .system)
  private let effectsButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .system)
  private let shutterFill = UIView()
  private let modeStack = UIStackView()
  private let rightRail = UIStackView()
  private let reviewBar = UIStackView()
  private var modeButtons: [CameraMode: UIButton] = [:]

  private let messageLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.backgroundColor = UIColor.black.withAlphaComponent(0.32)
    label.layer.cornerRadius = 16
    label.clipsToBounds = true
    label.isHidden = true
    return label
  }()

  private let countdownLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 86, weight: .bold)
    label.layer.shadowColor = UIColor.black.cgColor
    label.layer.shadowOpacity = 0.24
    label.layer.shadowRadius = 18
    label.layer.shadowOffset = CGSize(width: 0, height: 8)
    label.isHidden = true
    return label
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.025, green: 0.029, blue: 0.032, alpha: 1)
    installPreview()
    installControls()
    installGestures()
    updateModeSelection()
    updateTimerButton()
    updateFlashButton()
    setReviewMode(false)
    prepareCamera()
    loadRecentGalleryThumbnailIfAllowed()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = previewContainer.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    countdownTimer?.invalidate()
    pendingStopWorkItem?.cancel()
    if movieOutput.isRecording {
      movieOutput.stopRecording()
    }
    sessionQueue.async { [session] in
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func installPreview() {
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.backgroundColor = .black
    previewContainer.clipsToBounds = true
    previewContainer.layer.cornerRadius = 30
    previewContainer.layer.cornerCurve = .continuous
    previewContainer.layer.shadowColor = UIColor.black.cgColor
    previewContainer.layer.shadowOpacity = 0.22
    previewContainer.layer.shadowRadius = 28
    previewContainer.layer.shadowOffset = CGSize(width: 0, height: 14)

    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.backgroundColor = UIColor.black.cgColor
    previewContainer.layer.addSublayer(previewLayer)

    gridOverlay.translatesAutoresizingMaskIntoConstraints = false
    gridOverlay.isHidden = true
    previewContainer.addSubview(gridOverlay)

    capturedImageView.translatesAutoresizingMaskIntoConstraints = false
    capturedImageView.contentMode = .scaleAspectFill
    capturedImageView.clipsToBounds = true
    capturedImageView.isHidden = true
    previewContainer.addSubview(capturedImageView)

    capturedPlayIcon.translatesAutoresizingMaskIntoConstraints = false
    capturedPlayIcon.tintColor = .white
    capturedPlayIcon.contentMode = .scaleAspectFit
    capturedPlayIcon.isHidden = true
    previewContainer.addSubview(capturedPlayIcon)

    focusRing.frame = CGRect(x: 0, y: 0, width: 82, height: 82)
    focusRing.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
    focusRing.layer.borderWidth = 1.6
    focusRing.layer.cornerRadius = 41
    focusRing.alpha = 0
    previewContainer.addSubview(focusRing)

    loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    loadingIndicator.color = .white
    loadingIndicator.startAnimating()
    previewContainer.addSubview(loadingIndicator)

    view.addSubview(previewContainer)

    NSLayoutConstraint.activate([
      gridOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      gridOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      gridOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      gridOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

      capturedImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      capturedImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      capturedImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      capturedImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

      capturedPlayIcon.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
      capturedPlayIcon.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
      capturedPlayIcon.widthAnchor.constraint(equalToConstant: 76),
      capturedPlayIcon.heightAnchor.constraint(equalToConstant: 76),

      loadingIndicator.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
      loadingIndicator.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor)
    ])
  }

  private func installControls() {
    configureCircleButton(closeButton, systemImage: "xmark", action: #selector(cancelTapped))
    configureCircleButton(flipButton, systemImage: "arrow.triangle.2.circlepath.camera", action: #selector(flipCamera))
    configureCircleButton(flashButton, systemImage: flashSetting.systemImage, action: #selector(cycleFlash))
    configureCircleButton(timerButton, systemImage: "timer", action: #selector(cycleTimer))
    configureCircleButton(gridButton, systemImage: "square.grid.3x3", action: #selector(toggleGrid))
    configureCircleButton(galleryRailButton, systemImage: "photo.on.rectangle", action: #selector(openGallery))
    configureCircleButton(filtersButton, systemImage: "wand.and.stars", action: #selector(filtersTapped))
    configureCircleButton(effectsButton, systemImage: "sparkles", action: #selector(filtersTapped))
    configureCircleButton(galleryButton, systemImage: "photo", action: #selector(openGallery))

    rightRail.axis = .vertical
    rightRail.spacing = 12
    rightRail.alignment = .center
    rightRail.translatesAutoresizingMaskIntoConstraints = false
    [flipButton, flashButton, timerButton, gridButton, galleryRailButton, filtersButton].forEach {
      rightRail.addArrangedSubview($0)
      $0.widthAnchor.constraint(equalToConstant: 48).isActive = true
      $0.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.backgroundColor = .clear
    shutterButton.layer.cornerRadius = 42
    shutterButton.layer.borderWidth = 4
    shutterButton.layer.borderColor = UIColor.white.cgColor
    shutterButton.layer.shadowColor = UIColor.black.cgColor
    shutterButton.layer.shadowOpacity = 0.22
    shutterButton.layer.shadowRadius = 18
    shutterButton.layer.shadowOffset = CGSize(width: 0, height: 10)
    shutterButton.addTarget(self, action: #selector(capturePressed), for: .touchUpInside)
    shutterButton.addTarget(self, action: #selector(captureTouchDown), for: .touchDown)
    shutterButton.addTarget(self, action: #selector(captureTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

    shutterFill.translatesAutoresizingMaskIntoConstraints = false
    shutterFill.backgroundColor = UIColor.white.withAlphaComponent(0.82)
    shutterFill.layer.cornerRadius = 31
    shutterFill.isUserInteractionEnabled = false
    shutterButton.addSubview(shutterFill)

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleShutterLongPress(_:)))
    longPress.minimumPressDuration = 0.22
    shutterButton.addGestureRecognizer(longPress)

    modeStack.axis = .horizontal
    modeStack.alignment = .center
    modeStack.spacing = 8
    modeStack.translatesAutoresizingMaskIntoConstraints = false
    CameraMode.allCases.forEach { mode in
      let button = UIButton(type: .system)
      button.setTitle(mode.rawValue, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
      button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
      button.layer.cornerRadius = 17
      button.layer.cornerCurve = .continuous
      button.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
      button.accessibilityLabel = "\(mode.rawValue) mode"
      modeButtons[mode] = button
      modeStack.addArrangedSubview(button)
    }

    let retakeButton = reviewButton(title: "Retake", foreground: .white, background: UIColor.white.withAlphaComponent(0.14), action: #selector(retakeCapturedMedia))
    let galleryReviewButton = reviewButton(title: "Gallery", foreground: .white, background: UIColor.white.withAlphaComponent(0.14), action: #selector(openGallery))
    let nextButton = reviewButton(title: "Next", foreground: .black, background: .white, action: #selector(confirmCapturedMedia))
    reviewBar.axis = .horizontal
    reviewBar.spacing = 12
    reviewBar.distribution = .fillEqually
    reviewBar.translatesAutoresizingMaskIntoConstraints = false
    reviewBar.addArrangedSubview(retakeButton)
    reviewBar.addArrangedSubview(galleryReviewButton)
    reviewBar.addArrangedSubview(nextButton)

    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    countdownLabel.translatesAutoresizingMaskIntoConstraints = false

    [closeButton, rightRail, shutterButton, galleryButton, effectsButton, modeStack, reviewBar, messageLabel, countdownLabel].forEach {
      view.addSubview($0)
    }

    NSLayoutConstraint.activate([
      previewContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewContainer.bottomAnchor.constraint(equalTo: modeStack.topAnchor, constant: -18),

      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
      closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      closeButton.widthAnchor.constraint(equalToConstant: 54),
      closeButton.heightAnchor.constraint(equalToConstant: 54),

      rightRail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
      rightRail.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),

      modeStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      modeStack.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16),

      shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      shutterButton.widthAnchor.constraint(equalToConstant: 84),
      shutterButton.heightAnchor.constraint(equalToConstant: 84),

      shutterFill.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
      shutterFill.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      shutterFill.widthAnchor.constraint(equalToConstant: 62),
      shutterFill.heightAnchor.constraint(equalToConstant: 62),

      galleryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      galleryButton.widthAnchor.constraint(equalToConstant: 56),
      galleryButton.heightAnchor.constraint(equalToConstant: 56),

      effectsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      effectsButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      effectsButton.widthAnchor.constraint(equalToConstant: 56),
      effectsButton.heightAnchor.constraint(equalToConstant: 56),

      reviewBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      reviewBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      reviewBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      reviewBar.heightAnchor.constraint(equalToConstant: 56),

      messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
      messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),
      messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      countdownLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
      countdownLabel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor)
    ])
  }

  private func installGestures() {
    let tap = UITapGestureRecognizer(target: self, action: #selector(focusAndExpose(_:)))
    previewContainer.addGestureRecognizer(tap)

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchToZoom(_:)))
    previewContainer.addGestureRecognizer(pinch)
  }

  private func configureCircleButton(_ button: UIButton, systemImage: String, action: Selector) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .white
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.backgroundColor = UIColor.black.withAlphaComponent(0.30)
    button.layer.cornerRadius = 26
    button.layer.cornerCurve = .continuous
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
    button.clipsToBounds = true
    button.addTarget(self, action: action, for: .touchUpInside)
    button.accessibilityTraits.insert(.button)
  }

  private func reviewButton(title: String, foreground: UIColor, background: UIColor, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    button.setTitleColor(foreground, for: .normal)
    button.backgroundColor = background
    button.layer.cornerRadius = 22
    button.layer.cornerCurve = .continuous
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      requestMicrophoneThenConfigure()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          granted ? self?.requestMicrophoneThenConfigure() : self?.showCameraUnavailableMessage()
        }
      }
    default:
      showCameraUnavailableMessage()
    }
  }

  private func requestMicrophoneThenConfigure() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
        DispatchQueue.main.async { self?.configureSession() }
      }
    default:
      configureSession()
    }
  }

  private func configureSession() {
    guard !isConfigured else { return }
    isConfigured = true

    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.session.beginConfiguration()
      if self.session.canSetSessionPreset(.high) {
        self.session.sessionPreset = .high
      }

      if let input = self.makeCameraInput(position: self.cameraPosition), self.session.canAddInput(input) {
        self.session.addInput(input)
        self.currentInput = input
      }

      if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
         let audioDevice = AVCaptureDevice.default(for: .audio),
         let input = try? AVCaptureDeviceInput(device: audioDevice),
         self.session.canAddInput(input) {
        self.session.addInput(input)
        self.audioInput = input
      }

      if self.session.canAddOutput(self.photoOutput) {
        self.session.addOutput(self.photoOutput)
        self.photoOutput.isHighResolutionCaptureEnabled = true
      }

      if self.session.canAddOutput(self.movieOutput) {
        self.session.addOutput(self.movieOutput)
        self.movieOutput.movieFragmentInterval = .invalid
      }

      self.session.commitConfiguration()

      DispatchQueue.main.async {
        self.previewLayer.session = self.session
        self.updateFlashAvailability()
      }

      self.session.startRunning()

      DispatchQueue.main.async {
        self.loadingIndicator.stopAnimating()
        self.messageLabel.isHidden = true
      }
    }
  }

  private func makeCameraInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
      return nil
    }
    configureDeviceDefaults(device)
    return try? AVCaptureDeviceInput(device: device)
  }

  private func configureDeviceDefaults(_ device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
        device.whiteBalanceMode = .continuousAutoWhiteBalance
      }
      device.unlockForConfiguration()
    } catch {}
  }

  private func showCameraUnavailableMessage() {
    loadingIndicator.stopAnimating()
    messageLabel.text = "Camera access is needed to create. Turn it on in Settings, then try again."
    messageLabel.isHidden = false
  }

  private func showTransientMessage(_ text: String) {
    messageLabel.text = text
    messageLabel.alpha = 0
    messageLabel.isHidden = false
    UIView.animate(withDuration: 0.18) {
      self.messageLabel.alpha = 1
    } completion: { _ in
      UIView.animate(withDuration: 0.22, delay: 1.45, options: []) {
        self.messageLabel.alpha = 0
      } completion: { _ in
        self.messageLabel.isHidden = true
        self.messageLabel.alpha = 1
      }
    }
  }

  private func updateModeSelection() {
    modeButtons.forEach { mode, button in
      let isSelected = mode == selectedMode
      button.backgroundColor = isSelected ? .white : UIColor.black.withAlphaComponent(0.26)
      button.setTitleColor(isSelected ? .black : UIColor.white.withAlphaComponent(0.82), for: .normal)
    }
  }

  private func updateTimerButton() {
    let title = timerSetting == .off ? nil : "\(timerSetting.seconds)"
    timerButton.setTitle(title, for: .normal)
    timerButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
    timerButton.tintColor = .white
    timerButton.backgroundColor = timerSetting == .off ? UIColor.black.withAlphaComponent(0.30) : UIColor.white.withAlphaComponent(0.24)
    timerButton.accessibilityLabel = timerSetting.title
  }

  private func updateFlashButton() {
    flashButton.setImage(UIImage(systemName: flashSetting.systemImage), for: .normal)
    flashButton.accessibilityLabel = "Flash \(flashSetting)"
  }

  private func updateFlashAvailability() {
    let device = currentInput?.device
    let isAvailable = (device?.hasFlash == true) || (device?.hasTorch == true)
    flashButton.isEnabled = isAvailable
    flashButton.alpha = isAvailable ? 1 : 0.38
  }

  private func setReviewMode(_ isReviewing: Bool) {
    capturedImageView.isHidden = !isReviewing
    capturedPlayIcon.isHidden = !isReviewing || capturedMedia?.kind != .video
    reviewBar.isHidden = !isReviewing
    rightRail.isHidden = isReviewing
    shutterButton.isHidden = isReviewing
    shutterFill.isHidden = isReviewing
    modeStack.isHidden = isReviewing
    galleryButton.isHidden = isReviewing
    effectsButton.isHidden = isReviewing
  }

  private func setRecordingState(_ isRecording: Bool) {
    UIView.animate(withDuration: 0.16) {
      self.shutterFill.backgroundColor = isRecording ? UIColor.systemRed.withAlphaComponent(0.92) : UIColor.white.withAlphaComponent(0.82)
      self.shutterFill.transform = isRecording ? CGAffineTransform(scaleX: 0.72, y: 0.72) : .identity
      self.shutterFill.layer.cornerRadius = isRecording ? 12 : 31
    }
  }

  @objc private func cancelTapped() {
    delegate?.storyCameraDidCancel()
  }

  @objc private func modeTapped(_ sender: UIButton) {
    guard let mode = modeButtons.first(where: { $0.value === sender })?.key else { return }
    selectedMode = mode
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    UIView.animate(withDuration: 0.18) {
      self.updateModeSelection()
      self.modeStack.layoutIfNeeded()
    }
  }

  @objc private func cycleTimer() {
    let values = TimerSetting.allCases
    let nextIndex = (values.firstIndex(of: timerSetting) ?? 0) + 1
    timerSetting = values[nextIndex % values.count]
    updateTimerButton()
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func cycleFlash() {
    let values = FlashSetting.allCases
    let nextIndex = (values.firstIndex(of: flashSetting) ?? 0) + 1
    flashSetting = values[nextIndex % values.count]
    updateFlashButton()
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func toggleGrid() {
    gridOverlay.isHidden.toggle()
    gridButton.backgroundColor = gridOverlay.isHidden ? UIColor.black.withAlphaComponent(0.30) : UIColor.white.withAlphaComponent(0.24)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func filtersTapped() {
    showTransientMessage("Filters are available after capture.")
  }

  @objc private func openGallery() {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .any(of: [.images, .videos])
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    present(picker, animated: true)
  }

  @objc private func captureTouchDown() {
    UIView.animate(withDuration: 0.10) {
      self.shutterButton.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
    }
  }

  @objc private func captureTouchUp() {
    UIView.animate(withDuration: 0.12) {
      self.shutterButton.transform = .identity
    }
  }

  @objc private func capturePressed() {
    if longPressDidRecord {
      longPressDidRecord = false
      return
    }
    guard session.isRunning else { return }
    if selectedMode == .text {
      showTransientMessage("Text posts continue on the next page.")
      return
    }
    if movieOutput.isRecording {
      stopRecordingVideo()
      return
    }
    if timerSetting.seconds > 0 {
      startCountdown(seconds: timerSetting.seconds) { [weak self] in
        self?.performCaptureAction()
      }
    } else {
      performCaptureAction()
    }
  }

  private func performCaptureAction() {
    switch selectedMode {
    case .photo:
      capturePhoto()
    case .video15, .video60:
      startRecordingVideo(maxDuration: selectedMode.maxDuration)
    case .text:
      showTransientMessage("Text posts continue on the next page.")
    }
  }

  private func startCountdown(seconds: Int, completion: @escaping () -> Void) {
    countdownTimer?.invalidate()
    countdownValue = seconds
    countdownLabel.text = "\(seconds)"
    countdownLabel.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
    countdownLabel.alpha = 0
    countdownLabel.isHidden = false
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    UIView.animate(withDuration: 0.18) {
      self.countdownLabel.alpha = 1
      self.countdownLabel.transform = .identity
    }

    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard let self else { return }
      self.countdownValue -= 1
      if self.countdownValue <= 0 {
        timer.invalidate()
        self.countdownLabel.isHidden = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        completion()
      } else {
        self.countdownLabel.text = "\(self.countdownValue)"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
    }
  }

  private func capturePhoto() {
    guard session.isRunning, !movieOutput.isRecording else { return }
    let settings = AVCapturePhotoSettings()
    if currentInput?.device.hasFlash == true {
      settings.flashMode = flashSetting.photoMode
    } else {
      settings.flashMode = .off
    }
    settings.isHighResolutionPhotoEnabled = true
    if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
      if cameraPosition == .front, connection.isVideoMirroringSupported {
        connection.isVideoMirrored = true
      }
    }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  @objc private func handleShutterLongPress(_ recognizer: UILongPressGestureRecognizer) {
    switch recognizer.state {
    case .began:
      guard selectedMode == .photo, session.isRunning, !movieOutput.isRecording else { return }
      longPressDidRecord = true
      startRecordingVideo(maxDuration: 60)
    case .ended, .cancelled, .failed:
      if movieOutput.isRecording {
        stopRecordingVideo()
      }
    default:
      break
    }
  }

  private func startRecordingVideo(maxDuration: TimeInterval?) {
    guard session.isRunning, !movieOutput.isRecording else { return }
    if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
      if cameraPosition == .front, connection.isVideoMirroringSupported {
        connection.isVideoMirrored = true
      }
    }
    setTorch(active: flashSetting == .on)
    setRecordingState(true)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    movieOutput.startRecording(to: url, recordingDelegate: self)

    pendingStopWorkItem?.cancel()
    if let maxDuration {
      let workItem = DispatchWorkItem { [weak self] in
        guard let self, self.movieOutput.isRecording else { return }
        self.stopRecordingVideo()
      }
      pendingStopWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration, execute: workItem)
    }
  }

  private func stopRecordingVideo() {
    pendingStopWorkItem?.cancel()
    if movieOutput.isRecording {
      movieOutput.stopRecording()
    }
    setTorch(active: false)
    setRecordingState(false)
  }

  private func setTorch(active: Bool) {
    guard let device = currentInput?.device, device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = active ? .on : .off
      device.unlockForConfiguration()
    } catch {}
  }

  @objc private func flipCamera() {
    cameraPosition = cameraPosition == .back ? .front : .back
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    UIView.animate(withDuration: 0.22) {
      self.flipButton.transform = self.flipButton.transform.rotated(by: .pi)
    }
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
      DispatchQueue.main.async {
        self.updateFlashAvailability()
        UIView.transition(with: self.previewContainer, duration: 0.18, options: .transitionCrossDissolve) {}
      }
    }
  }

  @objc private func focusAndExpose(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: previewContainer)
    showFocusRing(at: point)
    let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
    guard let device = currentInput?.device else { return }
    do {
      try device.lockForConfiguration()
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = devicePoint
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = devicePoint
        device.exposureMode = .autoExpose
      }
      device.unlockForConfiguration()
    } catch {}
  }

  private func showFocusRing(at point: CGPoint) {
    focusRing.center = point
    focusRing.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
    focusRing.alpha = 1
    UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
      self.focusRing.transform = .identity
    } completion: { _ in
      UIView.animate(withDuration: 0.24, delay: 0.42) {
        self.focusRing.alpha = 0
      }
    }
  }

  @objc private func pinchToZoom(_ recognizer: UIPinchGestureRecognizer) {
    guard let device = currentInput?.device else { return }
    switch recognizer.state {
    case .began:
      initialZoomFactor = device.videoZoomFactor
    case .changed:
      let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
      let zoom = min(max(initialZoomFactor * recognizer.scale, 1), maxZoom)
      do {
        try device.lockForConfiguration()
        device.videoZoomFactor = zoom
        device.unlockForConfiguration()
      } catch {}
    default:
      break
    }
  }

  @objc private func retakeCapturedMedia() {
    capturedMedia = nil
    capturedImageView.image = nil
    setReviewMode(false)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func confirmCapturedMedia() {
    guard let capturedMedia else { return }
    delegate?.storyCameraDidCapture(capturedMedia)
  }

  private func showCapturedMedia(_ media: MIRAPickedMedia, thumbnail: UIImage? = nil) {
    capturedMedia = media
    if media.kind == .image {
      capturedImageView.image = UIImage(data: media.data)
      capturedPlayIcon.isHidden = true
      setReviewMode(true)
    } else if let thumbnail {
      capturedImageView.image = thumbnail
      setReviewMode(true)
    } else {
      capturedImageView.image = nil
      capturedImageView.backgroundColor = UIColor.black.withAlphaComponent(0.92)
      setReviewMode(true)
      makeVideoThumbnail(from: media.data) { [weak self] image in
        guard let self, self.capturedMedia?.fileName == media.fileName else { return }
        self.capturedImageView.image = image
      }
    }
  }

  private func makeVideoThumbnail(from data: Data, completion: @escaping (UIImage?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
      try? data.write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      let asset = AVAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil)
      let image = cgImage.map { UIImage(cgImage: $0) }
      DispatchQueue.main.async {
        completion(image)
      }
    }
  }

  private func loadRecentGalleryThumbnailIfAllowed() {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else { return }
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = 1
    let assets = PHAsset.fetchAssets(with: options)
    guard let asset = assets.firstObject else { return }
    let requestOptions = PHImageRequestOptions()
    requestOptions.deliveryMode = .opportunistic
    requestOptions.resizeMode = .fast
    imageManager.requestImage(
      for: asset,
      targetSize: CGSize(width: 120, height: 120),
      contentMode: .aspectFill,
      options: requestOptions
    ) { [weak self] image, _ in
      guard let self, let image else { return }
      self.galleryButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
      self.galleryButton.imageView?.contentMode = .scaleAspectFill
      self.galleryButton.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else { return }
    let videoTypes = [UTType.movie.identifier, UTType.mpeg4Movie.identifier, UTType.quickTimeMovie.identifier]
    if let type = videoTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
      provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
        guard let self, let url, let data = try? Data(contentsOf: url) else { return }
        DispatchQueue.main.async {
          let media = MIRAPickedMedia(data: data, kind: .video, fileName: "\(UUID().uuidString).mov", mimeType: "video/quicktime")
          self.showCapturedMedia(media)
        }
      }
      return
    }

    let imageType = provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ? UTType.png.identifier : UTType.image.identifier
    guard provider.hasItemConformingToTypeIdentifier(imageType) else { return }
    provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, _ in
      guard let self, let data else { return }
      DispatchQueue.main.async {
        let mimeType = imageType == UTType.png.identifier ? "image/png" : "image/jpeg"
        let extensionName = imageType == UTType.png.identifier ? "png" : "jpg"
        let media = MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).\(extensionName)", mimeType: mimeType)
        self.showCapturedMedia(media)
      }
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard error == nil, let data = photo.fileDataRepresentation() else {
      DispatchQueue.main.async {
        self.showTransientMessage("That photo could not be captured. Try again.")
      }
      return
    }
    let media = MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpeg")
    DispatchQueue.main.async {
      self.showCapturedMedia(media)
    }
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    DispatchQueue.main.async {
      self.setRecordingState(false)
      self.setTorch(active: false)
    }
    defer { try? FileManager.default.removeItem(at: outputFileURL) }
    guard error == nil, let data = try? Data(contentsOf: outputFileURL), !data.isEmpty else {
      DispatchQueue.main.async {
        self.showTransientMessage("That video could not be captured. Try again.")
      }
      return
    }
    let media = MIRAPickedMedia(data: data, kind: .video, fileName: "\(UUID().uuidString).mov", mimeType: "video/quicktime")
    DispatchQueue.main.async {
      self.showCapturedMedia(media)
    }
  }
}

private final class MIRACameraGridOverlayView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor)
    context.setLineWidth(0.8)

    for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
      let x = rect.width * fraction
      context.move(to: CGPoint(x: x, y: 0))
      context.addLine(to: CGPoint(x: x, y: rect.height))

      let y = rect.height * fraction
      context.move(to: CGPoint(x: 0, y: y))
      context.addLine(to: CGPoint(x: rect.width, y: y))
    }

    context.strokePath()
  }
}
