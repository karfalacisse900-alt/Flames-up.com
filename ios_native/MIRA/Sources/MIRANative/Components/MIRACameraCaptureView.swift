import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

enum MIRAStoryCameraEditTool {
  case text
  case filters
  case adjust
}

struct MIRAStoryLiveCameraView: UIViewControllerRepresentable {
  var editedMedia: MIRAPickedMedia?
  var dismissesOnCapture = true
  let onCapture: (MIRAPickedMedia) -> Void
  let onCancel: () -> Void
  let onEdit: (MIRAPickedMedia, MIRAStoryCameraEditTool) -> Void

  @Environment(\.dismiss) private var dismiss

  init(
    editedMedia: MIRAPickedMedia? = nil,
    dismissesOnCapture: Bool = true,
    onCapture: @escaping (MIRAPickedMedia) -> Void,
    onCancel: @escaping () -> Void = {},
    onEdit: @escaping (MIRAPickedMedia, MIRAStoryCameraEditTool) -> Void = { _, _ in }
  ) {
    self.editedMedia = editedMedia
    self.dismissesOnCapture = dismissesOnCapture
    self.onCapture = onCapture
    self.onCancel = onCancel
    self.onEdit = onEdit
  }

  func makeUIViewController(context: Context) -> MIRAStoryCameraViewController {
    let controller = MIRAStoryCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: MIRAStoryCameraViewController, context: Context) {
    if let editedMedia {
      uiViewController.applyEditedMedia(editedMedia)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel, onEdit: onEdit, dismissesOnCapture: dismissesOnCapture, dismiss: dismiss)
  }

  final class Coordinator: NSObject, MIRAStoryCameraViewControllerDelegate {
    private let onCapture: (MIRAPickedMedia) -> Void
    private let onCancel: () -> Void
    private let onEdit: (MIRAPickedMedia, MIRAStoryCameraEditTool) -> Void
    private let dismissesOnCapture: Bool
    private let dismiss: DismissAction

    init(
      onCapture: @escaping (MIRAPickedMedia) -> Void,
      onCancel: @escaping () -> Void,
      onEdit: @escaping (MIRAPickedMedia, MIRAStoryCameraEditTool) -> Void,
      dismissesOnCapture: Bool,
      dismiss: DismissAction
    ) {
      self.onCapture = onCapture
      self.onCancel = onCancel
      self.onEdit = onEdit
      self.dismissesOnCapture = dismissesOnCapture
      self.dismiss = dismiss
    }

    func storyCameraDidCancel() {
      onCancel()
      dismiss()
    }

    func storyCameraDidCapture(_ media: MIRAPickedMedia) {
      onCapture(media)
      if dismissesOnCapture {
        dismiss()
      }
    }

    func storyCameraDidRequestEdit(_ media: MIRAPickedMedia, tool: MIRAStoryCameraEditTool) {
      onEdit(media, tool)
    }
  }
}

protocol MIRAStoryCameraViewControllerDelegate: AnyObject {
  func storyCameraDidCancel()
  func storyCameraDidCapture(_ media: MIRAPickedMedia)
  func storyCameraDidRequestEdit(_ media: MIRAPickedMedia, tool: MIRAStoryCameraEditTool)
}

final class MIRAStoryCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, PHPickerViewControllerDelegate {
  weak var delegate: MIRAStoryCameraViewControllerDelegate?

  private enum CameraMode: String, CaseIterable {
    case photo = "Photo"
    case video15 = "15s"
    case video60 = "60s"

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
  private let textOverlayContainer = UIView()
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
  private let editRailButton = UIButton(type: .system)
  private let galleryButton = UIButton(type: .system)
  private let effectsButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .system)
  private let shutterFill = UIView()
  private let nextButton = UIButton(type: .system)
  private let modeStack = UIStackView()
  private let rightRail = UIStackView()
  private let inlineEditPanel = UIView()
  private let filterScrollView = UIScrollView()
  private let filterStack = UIStackView()
  private let adjustmentStack = UIStackView()
  private let brightnessSlider = UISlider()
  private let contrastSlider = UISlider()
  private let saturationSlider = UISlider()
  private let reviewToolsStack = UIStackView()
  private let reviewBar = UIStackView()
  private var modeButtons: [CameraMode: UIButton] = [:]
  private var lastAppliedEditedMediaSignature: String?
  private var inlineEditPanelHeightConstraint: NSLayoutConstraint?
  private var inlinePanelConstraints: [NSLayoutConstraint] = []
  private var capturedOriginalImage: UIImage?
  private var activeFilter: MIRANativeEditorFilter = .original
  private var activeBrightness: Double = 0
  private var activeContrast: Double = 1
  private var activeSaturation: Double = 1
  private var textLabels: [UILabel] = []

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

    textOverlayContainer.translatesAutoresizingMaskIntoConstraints = false
    textOverlayContainer.backgroundColor = .clear
    textOverlayContainer.clipsToBounds = true
    textOverlayContainer.isHidden = true
    previewContainer.addSubview(textOverlayContainer)

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

      textOverlayContainer.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      textOverlayContainer.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      textOverlayContainer.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      textOverlayContainer.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

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
    configureCircleButton(editRailButton, systemImage: "pencil", action: #selector(editRailTapped))
    configureCircleButton(effectsButton, systemImage: "sparkles", action: #selector(filtersTapped))
    effectsButton.isHidden = true
    configureCircleButton(galleryButton, systemImage: "photo", action: #selector(openGallery))
    configureNextButton()

    rightRail.axis = .vertical
    rightRail.spacing = 12
    rightRail.alignment = .center
    rightRail.translatesAutoresizingMaskIntoConstraints = false
    [flipButton, flashButton, gridButton, editRailButton].forEach {
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

    reviewToolsStack.axis = .horizontal
    reviewToolsStack.spacing = 10
    reviewToolsStack.distribution = .fillEqually
    reviewToolsStack.translatesAutoresizingMaskIntoConstraints = false

    reviewBar.axis = .horizontal
    reviewBar.spacing = 12
    reviewBar.distribution = .fillEqually
    reviewBar.translatesAutoresizingMaskIntoConstraints = false

    inlineEditPanel.translatesAutoresizingMaskIntoConstraints = false
    inlineEditPanel.backgroundColor = UIColor.black.withAlphaComponent(0.58)
    inlineEditPanel.layer.cornerRadius = 24
    inlineEditPanel.layer.cornerCurve = .continuous
    inlineEditPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
    inlineEditPanel.layer.borderWidth = 1
    inlineEditPanel.clipsToBounds = true
    inlineEditPanel.isHidden = true

    filterScrollView.translatesAutoresizingMaskIntoConstraints = false
    filterScrollView.showsHorizontalScrollIndicator = false
    filterStack.axis = .horizontal
    filterStack.spacing = 10
    filterStack.alignment = .center
    filterStack.translatesAutoresizingMaskIntoConstraints = false
    filterScrollView.addSubview(filterStack)

    adjustmentStack.axis = .vertical
    adjustmentStack.spacing = 8
    adjustmentStack.translatesAutoresizingMaskIntoConstraints = false
    configureAdjustmentSlider(brightnessSlider, value: 0, minimum: -0.35, maximum: 0.35)
    configureAdjustmentSlider(contrastSlider, value: 1, minimum: 0.65, maximum: 1.45)
    configureAdjustmentSlider(saturationSlider, value: 1, minimum: 0, maximum: 1.8)
    [
      adjustmentRow(title: "Brightness", slider: brightnessSlider),
      adjustmentRow(title: "Contrast", slider: contrastSlider),
      adjustmentRow(title: "Saturation", slider: saturationSlider)
    ].forEach { adjustmentStack.addArrangedSubview($0) }

    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    countdownLabel.translatesAutoresizingMaskIntoConstraints = false

    [closeButton, rightRail, shutterButton, nextButton, galleryButton, effectsButton, modeStack, inlineEditPanel, reviewToolsStack, reviewBar, messageLabel, countdownLabel].forEach {
      view.addSubview($0)
    }
    inlineEditPanelHeightConstraint = inlineEditPanel.heightAnchor.constraint(equalToConstant: 58)
    inlineEditPanelHeightConstraint?.isActive = true

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

      nextButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 18),
      nextButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      nextButton.widthAnchor.constraint(equalToConstant: 86),
      nextButton.heightAnchor.constraint(equalToConstant: 52),

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

      reviewToolsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      reviewToolsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      reviewToolsStack.bottomAnchor.constraint(equalTo: reviewBar.topAnchor, constant: -12),
      reviewToolsStack.heightAnchor.constraint(equalToConstant: 46),

      inlineEditPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      inlineEditPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      inlineEditPanel.bottomAnchor.constraint(equalTo: reviewToolsStack.topAnchor, constant: -10),

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

  private func configureNextButton() {
    nextButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.setTitle("Next", for: .normal)
    nextButton.setTitleColor(.white, for: .normal)
    nextButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    nextButton.backgroundColor = UIColor(red: 0.09, green: 0.175, blue: 0.105, alpha: 1)
    nextButton.layer.cornerRadius = 26
    nextButton.layer.cornerCurve = .continuous
    nextButton.layer.shadowColor = UIColor.black.cgColor
    nextButton.layer.shadowOpacity = 0.16
    nextButton.layer.shadowRadius = 14
    nextButton.layer.shadowOffset = CGSize(width: 0, height: 8)
    nextButton.isHidden = true
    nextButton.accessibilityLabel = "Next"
    nextButton.accessibilityTraits.insert(.button)
    nextButton.addTarget(self, action: #selector(confirmCapturedMedia), for: .touchUpInside)
  }

  private func configureAdjustmentSlider(_ slider: UISlider, value: Float, minimum: Float, maximum: Float) {
    slider.minimumValue = minimum
    slider.maximumValue = maximum
    slider.value = value
    slider.minimumTrackTintColor = .white
    slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
    slider.thumbTintColor = .white
    slider.addTarget(self, action: #selector(adjustmentSliderChanged), for: .valueChanged)
  }

  private func adjustmentRow(title: String, slider: UISlider) -> UIView {
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = 10
    row.alignment = .center
    let label = UILabel()
    label.text = title
    label.textColor = .white
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.widthAnchor.constraint(equalToConstant: 82).isActive = true
    row.addArrangedSubview(label)
    row.addArrangedSubview(slider)
    return row
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
    textOverlayContainer.isHidden = !isReviewing
    capturedPlayIcon.isHidden = !isReviewing || capturedMedia?.kind != .video
    reviewToolsStack.isHidden = true
    reviewBar.isHidden = true
    if !isReviewing {
      inlineEditPanel.isHidden = true
    }
    rightRail.isHidden = false
    flipButton.isHidden = isReviewing
    flashButton.isHidden = isReviewing
    gridButton.isHidden = isReviewing
    editRailButton.isHidden = false
    editRailButton.alpha = capturedMedia == nil ? 0.62 : 1
    shutterButton.isHidden = false
    shutterFill.isHidden = false
    shutterFill.backgroundColor = isReviewing ? UIColor.white.withAlphaComponent(0.34) : UIColor.white.withAlphaComponent(0.82)
    shutterButton.accessibilityLabel = isReviewing ? "Retake" : "Capture"
    nextButton.isHidden = !isReviewing
    modeStack.isHidden = isReviewing
    galleryButton.isHidden = isReviewing
    effectsButton.isHidden = true
  }

  private func showFilterPanel() {
    guard capturedMedia?.kind == .image else {
      showTransientMessage("Video filters are coming soon.")
      return
    }
    clearInlinePanel()
    inlineEditPanelHeightConstraint?.constant = 58
    inlineEditPanel.addSubview(filterScrollView)
    inlinePanelConstraints = [
      filterScrollView.topAnchor.constraint(equalTo: inlineEditPanel.topAnchor),
      filterScrollView.leadingAnchor.constraint(equalTo: inlineEditPanel.leadingAnchor, constant: 10),
      filterScrollView.trailingAnchor.constraint(equalTo: inlineEditPanel.trailingAnchor, constant: -10),
      filterScrollView.bottomAnchor.constraint(equalTo: inlineEditPanel.bottomAnchor),
      filterStack.topAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.topAnchor),
      filterStack.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor),
      filterStack.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor),
      filterStack.bottomAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.bottomAnchor),
      filterStack.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor)
    ]
    NSLayoutConstraint.activate(inlinePanelConstraints)
    MIRANativeEditorFilter.allCases.forEach { filter in
      let button = inlinePillButton(title: filter.title, isSelected: filter == activeFilter)
      button.addAction(UIAction { [weak self] _ in
        self?.activeFilter = filter
        self?.showFilterPanel()
        self?.applyCurrentPhotoPreview()
      }, for: .touchUpInside)
      filterStack.addArrangedSubview(button)
    }
    showInlinePanel()
  }

  private func showAdjustPanel() {
    guard capturedMedia?.kind == .image else {
      showTransientMessage("Video adjustments are coming soon.")
      return
    }
    clearInlinePanel()
    inlineEditPanelHeightConstraint?.constant = 132
    inlineEditPanel.addSubview(adjustmentStack)
    inlinePanelConstraints = [
      adjustmentStack.topAnchor.constraint(equalTo: inlineEditPanel.topAnchor, constant: 12),
      adjustmentStack.leadingAnchor.constraint(equalTo: inlineEditPanel.leadingAnchor, constant: 16),
      adjustmentStack.trailingAnchor.constraint(equalTo: inlineEditPanel.trailingAnchor, constant: -16),
      adjustmentStack.bottomAnchor.constraint(equalTo: inlineEditPanel.bottomAnchor, constant: -12)
    ]
    NSLayoutConstraint.activate(inlinePanelConstraints)
    showInlinePanel()
  }

  private func showInlinePanel() {
    inlineEditPanel.isHidden = false
    UIView.animate(withDuration: 0.16) {
      self.view.layoutIfNeeded()
    }
  }

  private func clearInlinePanel() {
    NSLayoutConstraint.deactivate(inlinePanelConstraints)
    inlinePanelConstraints = []
    inlineEditPanel.subviews.forEach { $0.removeFromSuperview() }
    filterStack.arrangedSubviews.forEach { view in
      filterStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }

  private func inlinePillButton(title: String, isSelected: Bool) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setTitleColor(isSelected ? .black : .white, for: .normal)
    button.backgroundColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.16)
    button.layer.cornerRadius = 18
    button.layer.cornerCurve = .continuous
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    return button
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
    guard capturedMedia != nil else {
      showTransientMessage("Filters are available after capture.")
      return
    }
    showFilterPanel()
  }

  @objc private func editRailTapped() {
    guard capturedMedia != nil else {
      showTransientMessage("Capture a photo or video first, then tap Edit.")
      return
    }
    editCapturedMedia()
  }

  @objc private func editTextTapped() {
    guard capturedMedia != nil else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    presentTextEditor()
  }

  @objc private func editFiltersTapped() {
    guard capturedMedia != nil else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    showFilterPanel()
  }

  @objc private func editAdjustTapped() {
    guard capturedMedia != nil else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    showAdjustPanel()
  }

  private func presentTextEditor(for label: UILabel? = nil) {
    let alert = UIAlertController(title: label == nil ? "Add text" : "Edit text", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "Text"
      textField.text = label?.text == "Text" ? "" : label?.text
      textField.autocapitalizationType = .sentences
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let label {
      alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self, weak label] _ in
        guard let self, let label else { return }
        self.textLabels.removeAll { $0 === label }
        label.removeFromSuperview()
      })
    }
    alert.addAction(UIAlertAction(title: label == nil ? "Add" : "Save", style: .default) { [weak self, weak label] _ in
      guard let self else { return }
      let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !text.isEmpty else { return }
      if let label {
        label.text = text
        label.sizeToFit()
        label.bounds = CGRect(
          x: 0,
          y: 0,
          width: min(max(label.bounds.width + 28, 96), self.textOverlayContainer.bounds.width - 36),
          height: label.bounds.height + 12
        )
      } else {
        self.addTextLabel(text)
      }
    })
    present(alert, animated: true)
  }

  private func addTextLabel(_ text: String) {
    let label = UILabel()
    label.text = text
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 34, weight: .semibold)
    label.layer.shadowColor = UIColor.black.cgColor
    label.layer.shadowOpacity = 0.36
    label.layer.shadowRadius = 10
    label.layer.shadowOffset = CGSize(width: 0, height: 4)
    label.isUserInteractionEnabled = true
    label.accessibilityLabel = "Text overlay"
    label.sizeToFit()
    let width = min(max(label.bounds.width + 34, 120), textOverlayContainer.bounds.width - 44)
    label.bounds = CGRect(x: 0, y: 0, width: width, height: max(label.bounds.height + 16, 52))
    label.center = CGPoint(x: textOverlayContainer.bounds.midX, y: textOverlayContainer.bounds.midY)
    label.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(textOverlayPanned(_:))))
    label.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(textOverlayPinched(_:))))
    label.addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(textOverlayRotated(_:))))
    label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(textOverlayTapped(_:))))
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(textOverlayLongPressed(_:)))
    longPress.minimumPressDuration = 0.35
    label.addGestureRecognizer(longPress)
    textOverlayContainer.addSubview(label)
    textLabels.append(label)
  }

  @objc private func textOverlayPanned(_ recognizer: UIPanGestureRecognizer) {
    guard let label = recognizer.view else { return }
    let translation = recognizer.translation(in: textOverlayContainer)
    let proposed = CGPoint(x: label.center.x + translation.x, y: label.center.y + translation.y)
    label.center = CGPoint(
      x: min(max(proposed.x, 34), textOverlayContainer.bounds.width - 34),
      y: min(max(proposed.y, 34), textOverlayContainer.bounds.height - 34)
    )
    recognizer.setTranslation(.zero, in: textOverlayContainer)
  }

  @objc private func textOverlayPinched(_ recognizer: UIPinchGestureRecognizer) {
    guard let label = recognizer.view else { return }
    label.transform = label.transform.scaledBy(x: recognizer.scale, y: recognizer.scale)
    recognizer.scale = 1
  }

  @objc private func textOverlayRotated(_ recognizer: UIRotationGestureRecognizer) {
    guard let label = recognizer.view else { return }
    label.transform = label.transform.rotated(by: recognizer.rotation)
    recognizer.rotation = 0
  }

  @objc private func textOverlayTapped(_ recognizer: UITapGestureRecognizer) {
    guard let label = recognizer.view as? UILabel else { return }
    presentTextEditor(for: label)
  }

  @objc private func textOverlayLongPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let label = recognizer.view as? UILabel else { return }
    textLabels.removeAll { $0 === label }
    UIView.animate(withDuration: 0.14, animations: {
      label.alpha = 0
      label.transform = label.transform.scaledBy(x: 0.82, y: 0.82)
    }, completion: { _ in
      label.removeFromSuperview()
    })
  }

  @objc private func adjustmentSliderChanged() {
    activeBrightness = Double(brightnessSlider.value)
    activeContrast = Double(contrastSlider.value)
    activeSaturation = Double(saturationSlider.value)
    applyCurrentPhotoPreview()
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
    if capturedMedia != nil {
      retakeCapturedMedia()
      return
    }
    if longPressDidRecord {
      longPressDidRecord = false
      return
    }
    guard session.isRunning else { return }
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
    lastAppliedEditedMediaSignature = nil
    resetInlineEdits()
    capturedImageView.image = nil
    setReviewMode(false)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func editCapturedMedia() {
    guard let capturedMedia else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    delegate?.storyCameraDidRequestEdit(capturedMedia, tool: .text)
  }

  @objc private func confirmCapturedMedia() {
    guard let capturedMedia else { return }
    let recipe = currentEditRecipe(for: capturedMedia)
    guard recipe.hasEdits else {
      delegate?.storyCameraDidCapture(capturedMedia)
      return
    }
    showExportState(true)
    Task { @MainActor in
      do {
        let finalMedia = try await exportInlineEditedMedia(from: capturedMedia, recipe: recipe)
        showExportState(false)
        delegate?.storyCameraDidCapture(finalMedia)
      } catch {
        showExportState(false)
        showTransientMessage("Edits could not be applied. Try again.")
      }
    }
  }

  private func showCapturedMedia(_ media: MIRAPickedMedia, thumbnail: UIImage? = nil) {
    capturedMedia = media
    lastAppliedEditedMediaSignature = editedMediaSignature(media)
    resetInlineEdits(keepMedia: true)
    if media.kind == .image {
      let image = UIImage(data: media.data)
      capturedOriginalImage = image
      capturedImageView.image = image
      capturedPlayIcon.isHidden = true
      setReviewMode(true)
    } else if let thumbnail {
      capturedOriginalImage = nil
      capturedImageView.image = thumbnail
      setReviewMode(true)
    } else {
      capturedOriginalImage = nil
      capturedImageView.image = nil
      capturedImageView.backgroundColor = UIColor.black.withAlphaComponent(0.92)
      setReviewMode(true)
      makeVideoThumbnail(from: media.data) { [weak self] image in
        guard let self, self.capturedMedia?.fileName == media.fileName else { return }
        self.capturedImageView.image = image
      }
    }
  }

  private func resetInlineEdits(keepMedia: Bool = false) {
    activeFilter = .original
    activeBrightness = 0
    activeContrast = 1
    activeSaturation = 1
    brightnessSlider.value = 0
    contrastSlider.value = 1
    saturationSlider.value = 1
    inlineEditPanel.isHidden = true
    clearInlinePanel()
    textLabels.forEach { $0.removeFromSuperview() }
    textLabels.removeAll()
    if !keepMedia {
      capturedOriginalImage = nil
    }
  }

  private func currentEditRecipe(for media: MIRAPickedMedia) -> MIRANativeEditRecipe {
    MIRANativeEditRecipe(
      mediaId: media.fileName,
      mediaType: media.kind == .image ? .photo : .video,
      selectedFilter: activeFilter,
      brightness: activeBrightness,
      contrast: activeContrast,
      saturation: activeSaturation,
      textLayers: currentTextLayers()
    )
  }

  private func currentTextLayers() -> [MIRANativeTextLayer] {
    let bounds = textOverlayContainer.bounds
    guard bounds.width > 0, bounds.height > 0 else { return [] }
    return textLabels.enumerated().compactMap { index, label in
      guard let text = label.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
      let transform = label.transform
      let scale = max(0.5, min(3.2, sqrt(transform.a * transform.a + transform.c * transform.c)))
      let rotation = atan2(transform.b, transform.a)
      return MIRANativeTextLayer(
        text: text,
        x: label.center.x / bounds.width,
        y: label.center.y / bounds.height,
        scale: scale,
        rotation: rotation,
        colorHex: "#FFFFFF",
        fontSize: 34,
        alignment: "center",
        zIndex: index
      )
    }
  }

  private func applyCurrentPhotoPreview() {
    guard let capturedMedia, capturedMedia.kind == .image, let original = capturedOriginalImage else { return }
    let recipe = currentEditRecipe(for: capturedMedia)
    DispatchQueue.global(qos: .userInitiated).async {
      let preview = MIRANativeMediaEditorRenderer.applyPhotoFilter(to: original, recipe: recipe)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.capturedMedia?.fileName == capturedMedia.fileName else { return }
        self.capturedImageView.image = preview
      }
    }
  }

  private func exportInlineEditedMedia(from media: MIRAPickedMedia, recipe: MIRANativeEditRecipe) async throws -> MIRAPickedMedia {
    switch media.kind {
    case .image:
      return try await MIRANativeMediaEditorExporter.exportPhoto(media: media, recipe: recipe)
    case .video:
      return try await MIRANativeMediaEditorExporter.exportVideo(media: media, recipe: recipe)
    }
  }

  private func showExportState(_ isExporting: Bool) {
    reviewBar.isUserInteractionEnabled = !isExporting
    reviewToolsStack.isUserInteractionEnabled = !isExporting
    if isExporting {
      loadingIndicator.startAnimating()
      loadingIndicator.isHidden = false
    } else {
      loadingIndicator.stopAnimating()
      loadingIndicator.isHidden = true
    }
  }

  func applyEditedMedia(_ media: MIRAPickedMedia) {
    let signature = editedMediaSignature(media)
    guard signature != lastAppliedEditedMediaSignature else { return }
    showCapturedMedia(media)
  }

  private func editedMediaSignature(_ media: MIRAPickedMedia) -> String {
    "\(media.fileName)-\(media.data.count)-\(media.editorMetadata?.appliedFilter ?? "none")-\(media.editorMetadata?.hasTextOverlay == true)"
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
