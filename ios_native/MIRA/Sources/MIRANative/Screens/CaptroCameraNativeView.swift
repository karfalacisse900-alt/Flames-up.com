import AVFoundation
import SwiftUI
import UIKit

/// The Capture tab owns its result while a composer is presented. Nothing publishes here.
struct CaptroCameraNativeView: View {
  let api: MIRAAPIClient
  var isActive = true
  @StateObject private var camera = CaptroCameraCaptureService()
  @Environment(\.scenePhase) private var scenePhase
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
              camera.focus(at: point); focused = true
            }, onOrientation: camera.setOrientation)
              .aspectRatio(camera.previewAspectRatio, contentMode: .fit)
              .overlay { if showGrid { cameraGrid.allowsHitTesting(false) } }
              .accessibilityLabel("Live camera preview")
            cameraStatus
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
          if reviewMedia == nil && camera.state == .ready {
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
                    Text(String(format: "%.1f×", factor)).font(.caption.monospacedDigit())
                      .frame(minWidth: 44, minHeight: 44)
                      .background(.black.opacity(abs(camera.zoom - factor) < 0.05 ? 0.8 : 0.5), in: Circle())
                  }.accessibilityLabel("Zoom \(factor.formatted()) times")
                }
                Button { showZoom.toggle() } label: {
                  Text(String(format: "%.1f×", camera.zoom)).font(.caption.monospacedDigit())
                    .frame(minWidth: 44, minHeight: 44).background(.black.opacity(0.6), in: Capsule())
                }.accessibilityLabel("Current zoom \(camera.zoom.formatted()) times")
                  .popover(isPresented: $showZoom) {
                    VStack(spacing: 12) {
                      Text(String(format: "Zoom %.1f×", camera.zoom)).font(.headline.monospacedDigit())
                      Slider(value: Binding(get: { Double(camera.zoom) }, set: { camera.setZoom(CGFloat($0)) }),
                        in: Double(camera.zoomRange.lowerBound)...max(Double(camera.zoomRange.upperBound), Double(camera.zoomRange.lowerBound) + 0.01))
                        .accessibilityLabel("Camera zoom")
                    }.padding(20).frame(width: 240).presentationCompactAdaptation(.popover)
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
    .onAppear { updateActivity() }
    .onDisappear { camera.suspend() }
    .onChange(of: isActive) { _, _ in updateActivity() }
    .onChange(of: scenePhase) { _, _ in updateActivity() }
    .onChange(of: destination) { _, _ in updateActivity() }
    .onReceive(camera.$result) { result in
      guard let result, result.localID != reviewMedia?.localID else { return }
      reviewMedia = result; enhancedMedia = nil; showEnhanced = false
      camera.suspend()
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
    .alert("Photo unchanged", isPresented: Binding(get: { reviewError != nil }, set: { if !$0 { reviewError = nil } })) {
      Button("OK", role: .cancel) { reviewError = nil }
    } message: { Text(reviewError ?? "") }
  }

  private var header: some View {
    HStack(spacing: 10) {
      if reviewMedia != nil {
        Text("Review").font(.headline).accessibilityIdentifier("capture.review.title")
      } else {
        HStack(spacing: 0) {
          modeButton(.photo, title: "Photo")
          modeButton(.video, title: "Video")
        }.background(.white.opacity(0.10), in: Capsule())
      }
      Spacer(minLength: 8)
      if recording {
        Label(camera.state == .finalizing ? "Saving…" : recordingTime, systemImage: "record.circle")
          .font(.caption.monospacedDigit()).accessibilityLabel("Recording \(recordingTime)")
      } else if reviewMedia == nil {
        Menu {
          Toggle("Grid", isOn: $showGrid)
          if camera.hasFlash || camera.hasTorch {
            Picker(camera.mode == .photo ? "Flash" : "Torch", selection: $flash) {
              Text("Off").tag(CaptroCameraCaptureService.Flash.off)
              if camera.mode == .photo { Text("Auto").tag(CaptroCameraCaptureService.Flash.auto) }
              Text("On").tag(CaptroCameraCaptureService.Flash.on)
            }
          }
          if camera.mode == .video {
            Text(camera.videoQualityLabel)
            Text("Up to 60 seconds · 200 MB")
            Text("Delivery supports up to 1080p")
          }
        } label: {
          Image(systemName: "ellipsis").frame(width: 44, height: 44)
            .background(.white.opacity(0.1), in: Circle())
        }.accessibilityLabel("Camera options").accessibilityIdentifier("capture.options")
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
    .onChange(of: flash) { _, value in camera.setFlash(value) }
  }

  private func modeButton(_ mode: CaptroCameraCaptureService.Mode, title: String) -> some View {
    Button { focused = false; flash = .off; camera.setMode(mode) } label: {
      Text(title).font(.subheadline.weight(camera.mode == mode ? .semibold : .regular))
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(camera.mode == mode ? .white.opacity(0.20) : .clear, in: Capsule())
    }.disabled(busy || recording)
      .accessibilityAddTraits(camera.mode == mode ? .isSelected : [])
      .accessibilityIdentifier("capture.mode." + title.lowercased())
  }

  @ViewBuilder private var cameraStatus: some View {
    if camera.state == .permissionNeeded || camera.state == .failed || camera.state == .interrupted {
      VStack(spacing: 12) {
        Image(systemName: "camera").font(.largeTitle)
        Text(camera.errorMessage ?? "Camera access is needed to take photos and videos.")
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
      if let notice = camera.notice { Text(notice).font(.caption).multilineTextAlignment(.center) }
      if camera.microphoneDenied {
        Button("Microphone off · Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
          .font(.caption).frame(minHeight: 44)
      }
      HStack {
        Image(systemName: "photo").foregroundStyle(.white.opacity(0.35))
          .frame(width: 52, height: 52).accessibilityLabel("No captured photo or video yet")
        Spacer()
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          focused = false; camera.shutter()
        } label: {
          ZStack {
            Circle().stroke(.white, lineWidth: 3).frame(width: 76, height: 76)
            if recording {
              RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 30, height: 30)
            } else {
              Circle().fill(camera.mode == .photo ? .white : .red).frame(width: 62, height: 62)
            }
          }.frame(width: 88, height: 88)
        }.disabled(camera.state != .ready && camera.state != .recording)
          .accessibilityLabel(recording ? "Stop recording" : camera.mode == .photo ? "Take photo" : "Record video")
          .accessibilityIdentifier("capture.shutter")
        Spacer()
        Button { focused = false; camera.flip() } label: {
          Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title3)
            .frame(width: 52, height: 52).background(.white.opacity(0.1), in: Circle())
        }.disabled(camera.state != .ready).accessibilityLabel("Flip camera")
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
          .font(.headline).foregroundStyle(.black).padding(.horizontal, 24).frame(minHeight: 48)
          .background(Color(red: 0.96, green: 0.94, blue: 0.89), in: Capsule())
          .disabled(enhancing).accessibilityIdentifier("capture.use")
      }
    }.padding(.horizontal, 20).padding(.vertical, 12)
  }

  private var recordingTime: String {
    let seconds = Int(camera.recordingSeconds)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
    if isActive && scenePhase == .active && destination == nil && reviewMedia == nil {
      MIRAPlaybackCoordinator.pauseAll(reason: "camera")
      camera.start()
    } else { camera.suspend() }
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
  func makeUIView(context: Context) -> Preview {
    let view = Preview(); view.preview.session = session
    view.mirrored = mirrored
    view.captureOrientation = captureOrientation
    view.onFocus = onFocus; view.onOrientation = onOrientation
    return view
  }
  func updateUIView(_ uiView: Preview, context: Context) {
    uiView.onFocus = onFocus; uiView.onOrientation = onOrientation
    uiView.mirrored = mirrored
    uiView.captureOrientation = captureOrientation
    uiView.setNeedsLayout()
  }
  final class Preview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    var onOrientation: ((UIInterfaceOrientation) -> Void)?
    var mirrored = false
    var captureOrientation: AVCaptureVideoOrientation = .portrait
    private var orientation: UIInterfaceOrientation?
    override init(frame: CGRect) {
      super.init(frame: frame); preview.videoGravity = .resizeAspect
      addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
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
      onFocus?(preview.captureDevicePointConverted(fromLayerPoint: tap.location(in: self)))
    }
  }
}

private struct CaptroCaptureThumbnail: View {
  let media: MIRAPickedMedia
  @State private var image: UIImage?
  var body: some View {
    Group {
      if let image { Image(uiImage: image).resizable().scaledToFill() }
      else { Image(systemName: media.kind == .video ? "play.rectangle" : "photo").font(.title2) }
    }.task(id: media.localID) {
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
