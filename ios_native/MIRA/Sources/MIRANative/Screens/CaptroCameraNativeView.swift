import AVFoundation
import SwiftUI
import UIKit
import Photos
import PhotosUI

/// Propagates only the active camera's dark chrome preference. Presenting the
/// ordinary composer or leaving Capture restores the user's appearance setting.
struct CaptroCameraDarkChromePreferenceKey: PreferenceKey {
  static var defaultValue = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The Capture tab owns its result while a composer is presented. Nothing publishes here.
struct CaptroCameraNativeView: View {
  let api: MIRAAPIClient
  var isActive = true
  @StateObject private var camera = CaptroCameraCaptureService()
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var reviewMedia: MIRAPickedMedia?
  @State private var enhancedMedia: MIRAPickedMedia?
  @State private var showEnhanced = false
  @State private var enhancing = false
  @State private var enhancementTask: Task<Void, Never>?
  @State private var reviewError: String?
  @State private var showGrid = false
  @State private var showZoom = false
  @State private var showFullReview = false
  @State private var flash: CaptroCameraCaptureService.Flash = .off
  @State private var focused = false
  @State private var showSettings = false
  @State private var timerSeconds = 0
  @State private var countdown = 0
  @State private var countdownTask: Task<Void, Never>?
  @State private var showLibrary = false
  @State private var galleryItem: PhotosPickerItem?
  @State private var galleryThumbnail: UIImage?
  @State private var importing = false
  private let accent = Color(red: 0.90, green: 0.98, blue: 0.20)
  @State private var destination: Destination?
  @State private var showDestination = false
  private enum Destination: String, Identifiable {
    case post, story
    var id: String { rawValue }
  }

  init(api: MIRAAPIClient, isActive: Bool = true, initialReviewMedia: MIRAPickedMedia? = nil) {
    self.api = api; self.isActive = isActive
    _reviewMedia = State(initialValue: initialReviewMedia)
  }

  private var selectedMedia: MIRAPickedMedia? {
    showEnhanced ? (enhancedMedia ?? reviewMedia) : reviewMedia
  }
  private var busy: Bool { camera.state == .capturing || camera.state == .finalizing || camera.state == .starting }
  private var recording: Bool { camera.state == .recording || camera.state == .finalizing }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        header
        ZStack {
          Color(white: 0.035)
          if let media = selectedMedia {
            CaptroCameraResultView(media: media, isActive: isActive && scenePhase == .active && destination == nil && !showFullReview)
              .accessibilityIdentifier("capture.review.media")
          } else {
            CaptroLiveCameraPreview(session: camera.session, mirrored: camera.isFrontCamera,
              captureOrientation: camera.previewOrientation, onFocus: { point in
              guard camera.state == .ready || camera.state == .recording else { return }
              camera.focus(at: point); focused = true
            }, onOrientation: camera.setOrientation, zoom: camera.zoom,
              onZoom: camera.setZoom, interactionEnabled: camera.state == .ready || camera.state == .recording)
              .aspectRatio(camera.previewAspectRatio, contentMode: .fit)
              .overlay { if showGrid { cameraGrid.allowsHitTesting(false) } }
              .accessibilityLabel("Live camera preview")
            cameraStatus
            if countdown > 0 {
              Text("\(countdown)").font(.largeTitle.bold()).monospacedDigit()
                .padding(20).background(.black.opacity(0.6), in: Circle())
                .accessibilityLabel("Photo in \(countdown) seconds")
                .accessibilityIdentifier("capture.countdown")
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
          if reviewMedia == nil && (camera.state == .ready || camera.state == .recording) {
            VStack(spacing: 8) {
              if focused {
                HStack {
                  Image(systemName: "sun.min")
                  Slider(value: Binding(get: { Double(camera.exposureBias) },
                    set: { camera.setExposureBias(Float($0)) }), in: -2...2)
                    .accessibilityLabel("Exposure adjustment")
                  Image(systemName: "sun.max")
                }.padding(10).background(.black.opacity(0.55), in: Capsule())
                  .frame(maxWidth: 230)
              }
              HStack(spacing: 8) {
                ForEach(camera.lensZooms, id: \.self) { factor in
                  Button { camera.setZoom(factor) } label: {
                    Text(String(format: "%g×", Double(factor))).font(.caption.weight(.semibold).monospacedDigit())
                      .frame(minWidth: 44, minHeight: 44)
                      .foregroundStyle(abs(camera.zoom - factor) < 0.05 ? Color.black : Color.white)
                      .background(abs(camera.zoom - factor) < 0.05 ? accent : .black.opacity(0.55), in: Circle())
                  }.accessibilityLabel("Zoom \(factor.formatted()) times")
                    .accessibilityAddTraits(abs(camera.zoom - factor) < 0.05 ? .isSelected : [])
                }
                if camera.zoomRange.upperBound > camera.zoomRange.lowerBound {
                Button { showZoom.toggle() } label: {
                  Text(abs(camera.zoom - 1) < 0.05 ? "+" : String(format: "%.1f×", camera.zoom)).font(.caption.monospacedDigit())
                    .frame(minWidth: 44, minHeight: 44).background(.black.opacity(0.6), in: Capsule())
                }.accessibilityLabel("Current zoom \(camera.zoom.formatted()) times")
                  .popover(isPresented: $showZoom) {
                    VStack(spacing: 12) {
                      Text(String(format: "Zoom %.1f×", camera.zoom)).font(.headline.monospacedDigit())
                      Text("Digital zoom").font(.caption).foregroundStyle(.secondary)
                      Slider(value: Binding(get: { Double(camera.zoom) }, set: { camera.setZoom(CGFloat($0)) }),
                        in: Double(camera.zoomRange.lowerBound)...max(Double(camera.zoomRange.upperBound), Double(camera.zoomRange.lowerBound) + 0.01))
                        .accessibilityLabel("Camera zoom")
                    }.padding(20).frame(width: 240).presentationCompactAdaptation(.popover)
                  }
                }
              }
            }.padding(.bottom, 12)
          }
        }
        if let media = reviewMedia { reviewControls(media) } else { captureControls }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .background(Color(white: 0.035))
      .foregroundStyle(.white)
    }
    .background(Color(white: 0.035).ignoresSafeArea())
    .preference(key: CaptroCameraDarkChromePreferenceKey.self, value: isActive && destination == nil)
    .onAppear { updateActivity() }
    .onDisappear { cancelCountdown(); camera.suspend() }
    .onChange(of: isActive) { _, _ in updateActivity() }
    .onChange(of: scenePhase) { _, _ in updateActivity() }
    .onChange(of: destination) { _, _ in updateActivity() }
    .onChange(of: showLibrary) { _, _ in updateActivity() }
    .onChange(of: camera.state) { _, state in if state != .ready { cancelCountdown() } }
    .onChange(of: camera.isRecordingStarted) { _, started in
      if started { UIAccessibility.post(notification: .announcement, argument: "Recording started") }
    }
    .onReceive(camera.$result) { result in
      guard let result, result.localID != reviewMedia?.localID else { return }
      reviewMedia = result; enhancedMedia = nil; showEnhanced = false
      UIAccessibility.post(notification: .announcement, argument: result.kind == .image ? "Photo captured" : "Video saved")
      camera.suspend()
    }
    .sheet(isPresented: $showSettings) { settingsSheet }
    .photosPicker(isPresented: $showLibrary, selection: $galleryItem, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
    .task(id: galleryItem) {
      guard let item = galleryItem else { return }
      importing = true; camera.suspend()
      defer { importing = false; updateActivity() }
      do {
        let media = try await CaptroPostMediaPicker.load(item)
        guard !Task.isCancelled, galleryItem == item else { return }
        reviewMedia = media; enhancedMedia = nil; showEnhanced = false
      } catch { if !Task.isCancelled { reviewError = "That item could not be opened. Your existing capture is unchanged." } }
    }
    .task(id: isActive) {
      guard isActive else { return }
      let image = await Self.permittedGalleryThumbnail()
      guard !Task.isCancelled else { return }; galleryThumbnail = image
    }
    .confirmationDialog("Use capture", isPresented: $showDestination, titleVisibility: .visible) {
      Button("Create post") { destination = .post }
      Button("Create Story") { destination = .story }
      Button("Cancel", role: .cancel) {}
    }
    .fullScreenCover(item: $destination, onDismiss: updateActivity) { route in
      if let media = selectedMedia {
        switch route {
        case .post: CreatePostNativeView(api: api, initialMedia: media, onClose: { destination = nil })
        case .story: CreateStoryNativeView(api: api, initialMedia: media, onClose: { destination = nil })
        }
      }
    }
    .fullScreenCover(isPresented: $showFullReview) {
      if let media = selectedMedia {
        ZStack(alignment: .topTrailing) {
          Color.black.ignoresSafeArea()
          CaptroCameraResultView(media: media, isActive: scenePhase == .active)
          Button { showFullReview = false } label: {
            Image(systemName: "xmark").foregroundStyle(.white).frame(width: 44, height: 44)
              .background(.black.opacity(0.6), in: Circle())
          }.accessibilityLabel("Close captured result").padding(16)
        }
      }
    }
    .alert("Capture unchanged", isPresented: Binding(get: { reviewError != nil }, set: { if !$0 { reviewError = nil } })) {
      Button("OK", role: .cancel) { reviewError = nil }
    } message: { Text(reviewError ?? "") }
  }

  private var header: some View {
    HStack {
      if reviewMedia != nil {
        Text("Review").font(.headline).accessibilityIdentifier("capture.review.title")
      } else {
        Menu {
          Picker(camera.mode == .photo ? "Flash" : "Torch", selection: $flash) {
            Text("Off").tag(CaptroCameraCaptureService.Flash.off)
            if camera.mode == .photo { Text("Auto").tag(CaptroCameraCaptureService.Flash.auto) }
            Text("On").tag(CaptroCameraCaptureService.Flash.on)
          }
        } label: {
          Image(systemName: flash == .off ? "bolt.slash" : flash == .auto ? "bolt.badge.a" : "bolt.fill")
            .font(.title3).frame(width: 44, height: 44)
        }.disabled(camera.state != .ready || countdown > 0 || !(camera.mode == .photo ? camera.hasFlash : camera.hasTorch))
          .opacity((camera.mode == .photo ? camera.hasFlash : camera.hasTorch) ? 1 : 0.4)
          .accessibilityLabel(camera.mode == .photo ? "Photo flash" : "Video torch")
          .accessibilityValue((camera.mode == .photo ? camera.hasFlash : camera.hasTorch) ? flash.rawValue : "Unavailable")
          .accessibilityIdentifier("capture.flash")
      }
      Spacer()
      if recording {
        HStack(spacing: 6) {
          if camera.isRecordingStarted { Circle().fill(.red).frame(width: 8, height: 8) }
          Text(camera.state == .finalizing ? "Saving…" : camera.isRecordingStarted ? "REC \(recordingTime)" : "Starting…")
        }.font(.caption.monospacedDigit()).accessibilityIdentifier("capture.recording.status")
      } else {
        CaptroBrandLogo(onDark: true).frame(width: 86, height: 23).accessibilityHidden(true)
      }
      Spacer()
      if reviewMedia == nil {
        Button { showSettings = true } label: {
          Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 44, height: 44)
        }.disabled(busy || recording || countdown > 0)
          .accessibilityLabel("Camera options").accessibilityIdentifier("capture.options")
      } else {
        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
    .onChange(of: flash) { _, value in camera.setFlash(value) }
  }

  private func modeButton(_ mode: CaptroCameraCaptureService.Mode, title: String) -> some View {
    Button {
      guard camera.mode != mode else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      focused = false; flash = .off; camera.setMode(mode)
    } label: {
      Text(title.uppercased()).font(.subheadline.weight(camera.mode == mode ? .semibold : .regular)).tracking(1)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .foregroundStyle(camera.mode == mode ? accent : .white.opacity(0.8))
    }.disabled(busy || recording || countdown > 0 || importing)
      .buttonStyle(CaptroCameraPressStyle())
      .accessibilityAddTraits(camera.mode == mode ? .isSelected : [])
      .accessibilityIdentifier("capture.mode." + title.lowercased())
  }

  @ViewBuilder private var cameraStatus: some View {
    if importing {
      ProgressView("Opening selected media").tint(.white).padding(16).background(.black.opacity(0.55))
    } else if camera.state == .permissionNeeded || camera.state == .failed || camera.state == .interrupted {
      VStack(spacing: 12) {
        Image(systemName: "camera").font(.largeTitle)
        Text(camera.errorMessage ?? (camera.state == .interrupted
          ? (camera.notice ?? "Camera interrupted. Try again when it is available.")
          : "Camera access is needed to take photos and videos."))
          .font(.body).multilineTextAlignment(.center)
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied || AVCaptureDevice.authorizationStatus(for: .video) == .restricted {
          Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            .frame(minHeight: 44)
        } else {
          Button("Try again") { camera.start() }.frame(minHeight: 44)
        }
      }.padding(24).background(.black.opacity(0.75)).padding(20)
        .accessibilityIdentifier("capture.unavailable")
    } else if busy {
      ProgressView(camera.state == .capturing ? "Capturing photo" : camera.state == .finalizing ? "Saving video" : "Starting camera")
        .tint(.white).padding(16).background(.black.opacity(0.55), in: Capsule())
    }
  }

  private var captureControls: some View {
    VStack(spacing: 8) {
      HStack(spacing: 20) {
        modeButton(.photo, title: "Photo")
        modeButton(.video, title: "Video")
      }
      if let notice = camera.notice { Text(notice).font(.caption).multilineTextAlignment(.center) }
      if camera.mode == .video && camera.microphoneDenied {
        Button("Microphone off · Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
          .font(.caption).frame(minHeight: 44)
      }
      HStack {
        Button { galleryItem = nil; showLibrary = true } label: {
          Group {
            if let galleryThumbnail { Image(uiImage: galleryThumbnail).resizable().scaledToFill() }
            else { Image(systemName: "photo.on.rectangle").font(.title3).foregroundStyle(.white.opacity(0.8)) }
          }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
        }.disabled(busy || recording || countdown > 0 || importing)
          .accessibilityLabel("Choose from Photos").accessibilityIdentifier("capture.library")
        Spacer()
        Button {
          takeCapture()
        } label: {
          ZStack {
            Circle().stroke(.white, lineWidth: 3).frame(width: 76, height: 76)
            if recording {
              RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 30, height: 30)
            } else {
              Circle().fill(camera.mode == .photo ? .white : .red).frame(width: 62, height: 62)
            }
          }.frame(width: 88, height: 88)
        }.disabled((camera.state != .ready && camera.state != .recording) || countdown > 0 || importing)
          .buttonStyle(CaptroCameraPressStyle())
          .accessibilityLabel(recording ? "Stop recording" : camera.mode == .photo ? "Take photo" : "Record video")
          .accessibilityIdentifier("capture.shutter")
        Spacer()
        Button { focused = false; camera.flip() } label: {
          Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title3)
            .frame(width: 52, height: 52).background(.white.opacity(0.1), in: Circle())
        }.disabled(camera.state != .ready || countdown > 0 || importing).accessibilityLabel("Flip camera")
          .accessibilityIdentifier("capture.flip")
      }
      if camera.mode == .video { Text(camera.videoQualityLabel + " · Up to 60 seconds").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
    }.padding(.horizontal, 26).padding(.vertical, 12)
  }

  private func reviewControls(_ media: MIRAPickedMedia) -> some View {
    VStack(spacing: 10) {
      if media.kind == .image {
        HStack {
          Button { enhance() } label: {
            if enhancing { ProgressView().tint(.white) }
            else { Label(showEnhanced ? "Enhanced" : "Enhance", systemImage: "wand.and.stars") }
          }.disabled(enhancing).frame(minHeight: 44).accessibilityIdentifier("capture.enhance")
          if enhancedMedia != nil {
            Button(showEnhanced ? "Show original" : "Show enhanced") { showEnhanced.toggle() }
              .frame(minHeight: 44).accessibilityIdentifier("capture.compare")
          }
        }.font(.subheadline)
      }
      HStack {
        Button { showFullReview = true } label: {
          CaptroCaptureThumbnail(media: selectedMedia ?? media).frame(width: 44, height: 44).clipped()
        }.accessibilityLabel("Open current captured result")
        Button("Retake") {
          enhancementTask?.cancel(); enhancementTask = nil; enhancing = false
          reviewMedia = nil; enhancedMedia = nil; showEnhanced = false
          camera.discardResult(); updateActivity()
        }.frame(minWidth: 70, minHeight: 48).accessibilityIdentifier("capture.retake")
        Spacer()
        Button(media.kind == .image ? "Use photo" : "Use video") { showDestination = true }
          .font(.headline).foregroundStyle(.black).padding(.horizontal, 24)
          .padding(.vertical, 12).frame(minHeight: 48)
          .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
          .disabled(enhancing).accessibilityIdentifier("capture.use")
      }
    }.padding(.horizontal, 20).padding(.vertical, 12)
  }

  private var recordingTime: String {
    let seconds = Int(camera.recordingSeconds)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
  private var settingsSheet: some View {
    NavigationStack {
      Form {
        Section("Composition") {
          Toggle("Grid", isOn: $showGrid).accessibilityIdentifier("capture.grid")
          if camera.mode == .photo {
            Picker("Photo timer", selection: $timerSeconds) {
              Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10)
            }.accessibilityIdentifier("capture.timer")
          }
        }
        Section("Capture quality") {
          if camera.mode == .video {
            LabeledContent("Active format", value: camera.videoQualityLabel)
            Text("Up to 60 seconds · 200 MB. H.264 / SDR delivery.").font(.caption).foregroundStyle(.secondary)
          } else {
            LabeledContent("Active resolution", value: camera.photoQualityLabel)
            Text("Full photo output with quality prioritization. Originals are kept for review.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }.navigationTitle("Camera settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
    }.preferredColorScheme(.dark).tint(.white)
      .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }

  private func takeCapture() {
    guard countdownTask == nil, !importing else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    focused = false
    guard camera.mode == .photo, timerSeconds > 0, camera.state == .ready else { camera.shutter(); return }
    countdown = timerSeconds
    countdownTask = Task { @MainActor in
      for remaining in stride(from: timerSeconds, through: 1, by: -1) {
        guard !Task.isCancelled else { return }
        countdown = remaining
        UIAccessibility.post(notification: .announcement, argument: "\(remaining)")
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
      }
      guard !Task.isCancelled, isActive, scenePhase == .active, camera.state == .ready else { return }
      countdown = 0; countdownTask = nil; camera.shutter()
    }
  }
  private func cancelCountdown() {
    countdownTask?.cancel(); countdownTask = nil; countdown = 0
  }

  private static func permittedGalleryThumbnail() async -> UIImage? {
    // Never request/expand Photos permission merely to decorate this control.
    await Task.detached(priority: .utility) { () -> UIImage? in
      let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      guard authorization == .authorized || authorization == .limited else { return nil }
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = 1
      guard let asset = PHAsset.fetchAssets(with: options).firstObject else { return nil }
      let request = PHImageRequestOptions()
      request.isSynchronous = true; request.isNetworkAccessAllowed = false
      request.deliveryMode = .fastFormat; request.resizeMode = .fast
      var thumbnail: UIImage?
      PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 144, height: 144),
        contentMode: .aspectFill, options: request) { image, _ in thumbnail = image }
      return thumbnail
    }.value
  }
  private var cameraGrid: some View {
    GeometryReader { geometry in
      Path { path in
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
          path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
          path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
          path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
          path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
        }
      }.stroke(.white.opacity(0.25), lineWidth: 0.5)
    }
  }
  private func updateActivity() {
    if isActive && scenePhase == .active && destination == nil && reviewMedia == nil && !showLibrary && !importing {
      MIRAPlaybackCoordinator.pauseAll(reason: "camera")
      camera.start()
    } else { cancelCountdown(); camera.suspend() }
  }
  private func enhance() {
    guard let original = reviewMedia else { return }
    if enhancedMedia != nil { showEnhanced.toggle(); return }
    enhancing = true
    enhancementTask = Task { @MainActor in
      defer { if reviewMedia?.localID == original.localID { enhancing = false } }
      do {
        let enhanced = try await CaptroCaptureReview.enhanced(original)
        guard !Task.isCancelled, reviewMedia?.localID == original.localID else { return }
        enhancedMedia = enhanced; showEnhanced = true
      } catch is CancellationError { }
      catch {
        if !Task.isCancelled, reviewMedia?.localID == original.localID { reviewError = error.localizedDescription }
      }
    }
  }
}

private struct CaptroLiveCameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  let mirrored: Bool
  let captureOrientation: AVCaptureVideoOrientation
  let onFocus: (CGPoint) -> Void
  let onOrientation: (UIInterfaceOrientation) -> Void
  let zoom: CGFloat
  let onZoom: (CGFloat) -> Void
  let interactionEnabled: Bool
  func makeUIView(context: Context) -> Preview {
    let view = Preview(); view.preview.session = session
    view.mirrored = mirrored
    view.captureOrientation = captureOrientation
    view.onFocus = onFocus; view.onOrientation = onOrientation
    view.zoom = zoom; view.onZoom = onZoom; view.interactionEnabled = interactionEnabled
    return view
  }
  func updateUIView(_ uiView: Preview, context: Context) {
    uiView.onFocus = onFocus; uiView.onOrientation = onOrientation
    uiView.mirrored = mirrored
    uiView.captureOrientation = captureOrientation
    uiView.zoom = zoom; uiView.onZoom = onZoom; uiView.interactionEnabled = interactionEnabled
    uiView.setNeedsLayout()
  }
  static func dismantleUIView(_ uiView: Preview, coordinator: ()) {
    uiView.focusDismissal?.cancel(); uiView.preview.session = nil
  }
  final class Preview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    var onOrientation: ((UIInterfaceOrientation) -> Void)?
    var mirrored = false
    var zoom: CGFloat = 1
    var onZoom: ((CGFloat) -> Void)?
    var interactionEnabled = false
    private var initialZoom: CGFloat = 1
    private let focusIndicator = CAShapeLayer()
    var focusDismissal: DispatchWorkItem?
    var captureOrientation: AVCaptureVideoOrientation = .portrait
    private var orientation: UIInterfaceOrientation?
    override init(frame: CGRect) {
      super.init(frame: frame); preview.videoGravity = .resizeAspect
      addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
      addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
      focusIndicator.fillColor = UIColor.clear.cgColor
      focusIndicator.strokeColor = UIColor(red: 0.90, green: 0.98, blue: 0.20, alpha: 1).cgColor
      focusIndicator.lineWidth = 2; focusIndicator.isHidden = true
      layer.addSublayer(focusIndicator)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
      super.layoutSubviews()
      if let connection = preview.connection, connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = mirrored
      }
      guard let value = window?.windowScene?.interfaceOrientation else { return }
      if value != orientation { orientation = value; onOrientation?(value) }
      if let connection = preview.connection, connection.isVideoOrientationSupported {
        connection.videoOrientation = captureOrientation
      }
    }
    @objc private func focus(_ tap: UITapGestureRecognizer) {
      guard interactionEnabled, tap.state == .ended else { return }
      let point = tap.location(in: self)
      onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point))
      focusDismissal?.cancel()
      CATransaction.begin(); CATransaction.setDisableActions(true)
      focusIndicator.path = UIBezierPath(rect: CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56)).cgPath
      focusIndicator.isHidden = false
      CATransaction.commit()
      let dismissal = DispatchWorkItem { [weak self] in self?.focusIndicator.isHidden = true }
      focusDismissal = dismissal
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: dismissal)
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
      guard interactionEnabled else { return }
      if gesture.state == .began { initialZoom = zoom }
      if gesture.state == .began || gesture.state == .changed { onZoom?(initialZoom * gesture.scale) }
    }
  }
}

private struct CaptroCameraPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct CaptroCaptureThumbnail: View {
  let media: MIRAPickedMedia
  @State private var image: UIImage?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Group {
      if let image { Image(uiImage: image).resizable().scaledToFill() }
      else { Image(systemName: media.kind == .video ? "play.rectangle" : "photo").font(.title2) }
    }
    .scaleEffect(image == nil && !reduceMotion ? 0.94 : 1)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: image != nil)
    .task(id: media.localID) {
      image = nil
      let loaded = await CaptroCaptureReview.thumbnail(media, maxPixelSize: 128)
      guard !Task.isCancelled else { return }; image = loaded
    }
  }
}

private struct CaptroCameraResultView: View {
  let media: MIRAPickedMedia
  let isActive: Bool
  @State private var image: UIImage?
  @State private var player: AVPlayer?
  @State private var file: URL?
  @State private var playing = false
  @State private var error: String?
  @State private var audioNotice: String?
  @State private var loadGeneration = UUID()
  @State private var endObserver: NSObjectProtocol?
  var body: some View {
    ZStack {
      if let image { Image(uiImage: image).resizable().scaledToFit() }
      else if let player {
        CaptroCameraReviewPlayer(player: player)
        Button {
          guard isActive else { return }
          if playing { player.pause() }
          else {
            if let duration = player.currentItem?.duration.seconds, duration.isFinite,
               player.currentTime().seconds >= duration - 0.05 { player.seek(to: .zero) }
            MIRAPlaybackCoordinator.activateVideo(player, id: media.localID.uuidString)
            do {
              // Capture configures a recording session. Review intentionally
              // switches back to playback only after capture has finalized.
              let session = AVAudioSession.sharedInstance()
              try session.setCategory(.playback, mode: .moviePlayback)
              try session.setActive(true)
              audioNotice = nil
            } catch {
              audioNotice = "Sound is temporarily unavailable. You can still review the video."
            }
            player.isMuted = false; player.play()
          }
          playing.toggle()
        } label: {
          Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2)
            .frame(width: 56, height: 56).background(.black.opacity(0.6), in: Circle())
        }.accessibilityLabel(playing ? "Pause captured video" : "Play captured video")
      } else if let error { Text(error).padding() }
      else { ProgressView().tint(.white) }
    }
    .overlay(alignment: .bottom) {
      if let audioNotice {
        Text(audioNotice).font(.caption).padding(10)
          .background(.black.opacity(0.65)).padding(12)
      }
    }
    .task(id: media.localID) {
      cleanup(); image = nil; error = nil
      let generation = loadGeneration
      if media.kind == .image {
        let thumbnail = await CaptroCaptureReview.thumbnail(media)
        guard !Task.isCancelled, loadGeneration == generation else { return }
        image = thumbnail
        if thumbnail == nil { error = "Preview unavailable. Your original photo is still kept." }
      }
      else {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-review-\(UUID().uuidString).mov")
        do {
          try await Task.detached(priority: .userInitiated) {
            try media.data.write(to: url, options: [.atomic, .completeFileProtection])
          }.value
          guard !Task.isCancelled, loadGeneration == generation else { removeFile(url); return }
          let reviewPlayer = AVPlayer(url: url)
          reviewPlayer.actionAtItemEnd = .pause
          reviewPlayer.isMuted = true
          file = url; player = reviewPlayer
          endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: reviewPlayer.currentItem, queue: .main
          ) { _ in
            Task { @MainActor in
              guard loadGeneration == generation, player === reviewPlayer else { return }
              MIRAPlaybackCoordinator.releaseVideo(reviewPlayer)
              playing = false
            }
          }
        } catch {
          removeFile(url)
          guard !Task.isCancelled, loadGeneration == generation else { return }
          self.error = "Preview unavailable. Your captured video is still kept."
        }
      }
    }
    .onChange(of: isActive) { _, active in if !active { player?.pause(); playing = false } }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { _ in player?.pause(); playing = false }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
      player?.pause(); playing = false // Resume only after a deliberate tap.
    }
    .onDisappear { cleanup() }
  }
  private func cleanup() {
    loadGeneration = UUID()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    if let player { MIRAPlaybackCoordinator.releaseVideo(player); player.replaceCurrentItem(with: nil) }
    player = nil; playing = false
    if let file { removeFile(file) }
    file = nil
  }
  private func removeFile(_ url: URL) {
    Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
  }
}

private struct CaptroCameraReviewPlayer: UIViewRepresentable {
  let player: AVPlayer
  func makeUIView(context: Context) -> Surface { Surface() }
  func updateUIView(_ uiView: Surface, context: Context) { uiView.playerLayer.player = player }
  static func dismantleUIView(_ uiView: Surface, coordinator: ()) { uiView.playerLayer.player = nil }
  final class Surface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) { super.init(frame: frame); playerLayer.videoGravity = .resizeAspect }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  }
}
