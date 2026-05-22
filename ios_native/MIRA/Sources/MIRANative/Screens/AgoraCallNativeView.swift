import AgoraRtcKit
import AVFoundation
import SwiftUI
import UIKit

enum MIRAAgoraCallMode: String, Hashable {
  case video = "call"
  case voice
  case live

  var needsVideo: Bool {
    self != .voice
  }

  var title: String {
    switch self {
    case .video: return "Video call"
    case .voice: return "Voice call"
    case .live: return "Live"
    }
  }
}

enum MIRAAgoraCallRole: String, Hashable {
  case host
  case audience
}

struct MIRAAgoraCallPresentation: Identifiable, Hashable {
  let peerId: String
  let peerName: String
  let peerAvatar: String?
  let channel: String
  let mode: MIRAAgoraCallMode
  let role: MIRAAgoraCallRole

  var id: String {
    "\(channel)-\(mode.rawValue)-\(role.rawValue)"
  }

  static func direct(
    currentUserId: String,
    peerId: String,
    peerName: String,
    peerAvatar: String?,
    mode: MIRAAgoraCallMode = .video
  ) -> MIRAAgoraCallPresentation {
    MIRAAgoraCallPresentation(
      peerId: peerId,
      peerName: peerName.isEmpty ? mode.title : peerName,
      peerAvatar: peerAvatar,
      channel: buildDirectChannel(currentUserId: currentUserId, peerId: peerId),
      mode: mode,
      role: .host
    )
  }

  private static func buildDirectChannel(currentUserId: String, peerId: String) -> String {
    let ids = [cleanChannelPart(currentUserId), cleanChannelPart(peerId)]
      .filter { !$0.isEmpty }
      .sorted()
    let base = ids.count == 2 ? ids.joined(separator: "_") : (ids.first ?? "preview")
    return String("flames_\(base)".prefix(63))
  }

  private static func cleanChannelPart(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_ -"))
    var output = ""
    var previousWasSpace = false

    for scalar in trimmed.unicodeScalars {
      if CharacterSet.whitespacesAndNewlines.contains(scalar) {
        if !previousWasSpace {
          output.append("_")
          previousWasSpace = true
        }
      } else if allowed.contains(scalar) {
        output.unicodeScalars.append(scalar)
        previousWasSpace = false
      } else {
        output.append("_")
        previousWasSpace = false
      }
      if output.count >= 28 { break }
    }

    return String(output.prefix(28))
  }
}

final class MIRAAgoraCallModel: NSObject, ObservableObject, AgoraRtcEngineDelegate {
  @Published var localUid: UInt?
  @Published var remoteUid: UInt?
  @Published var isJoining = true
  @Published var isJoined = false
  @Published var micMuted = false
  @Published var cameraOff = false
  @Published var usingFrontCamera = true
  @Published var elapsed = 0
  @Published var statusText = "Connecting..."
  @Published var errorText: String?

  let presentation: MIRAAgoraCallPresentation
  let api: MIRAAPIClient

  private(set) var engine: AgoraRtcEngineKit?
  private var tokenData: MIRAAgoraTokenResponse?
  private var startTask: Task<Void, Never>?
  private var timerTask: Task<Void, Never>?
  private var didCleanup = false

  init(presentation: MIRAAgoraCallPresentation, api: MIRAAPIClient) {
    self.presentation = presentation
    self.api = api
  }

  @MainActor
  func start() {
    guard startTask == nil else { return }
    didCleanup = false
    startTask = Task { [weak self] in
      await self?.joinCall()
    }
  }

  @MainActor
  func end() {
    cleanup()
  }

  @MainActor
  func toggleMic() {
    let next = !micMuted
    micMuted = next
    engine?.muteLocalAudioStream(next)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @MainActor
  func toggleCamera() {
    guard presentation.mode.needsVideo else { return }
    let next = !cameraOff
    cameraOff = next
    engine?.muteLocalVideoStream(next)
    if next {
      engine?.stopPreview()
    } else {
      engine?.startPreview()
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @MainActor
  func switchCamera() {
    guard presentation.mode.needsVideo, !cameraOff else { return }
    engine?.switchCamera()
    usingFrontCamera.toggle()
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func joinCall() async {
    let permissions = await requestPermissions(needsVideo: presentation.mode.needsVideo)
    guard permissions.microphone, permissions.camera else {
      await MainActor.run {
        isJoining = false
        statusText = presentation.mode.needsVideo ? "Camera and microphone needed" : "Microphone needed"
        errorText = presentation.mode.needsVideo
          ? "Allow camera and microphone access to start this call."
          : "Allow microphone access to start this call."
      }
      return
    }

    do {
      let token: MIRAAgoraTokenResponse = try await api.post(
        "/calls/agora/token",
        body: MIRAAgoraTokenRequest(
          channel: presentation.channel,
          role: presentation.role.rawValue,
          mode: presentation.mode.rawValue
        )
      )
      await MainActor.run {
        configureEngine(with: token)
      }
    } catch {
      await MainActor.run {
        isJoining = false
        statusText = "Call unavailable"
        errorText = callErrorMessage(for: error)
      }
    }
  }

  @MainActor
  private func configureEngine(with token: MIRAAgoraTokenResponse) {
    tokenData = token
    let appId = token.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !appId.isEmpty else {
      isJoining = false
      statusText = "Call unavailable"
      errorText = "Agora is not configured for this build."
      return
    }

    UIApplication.shared.isIdleTimerDisabled = true

    let config = AgoraRtcEngineConfig()
    config.appId = appId
    let rtcEngine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
    engine = rtcEngine
    rtcEngine.setDefaultAudioRouteToSpeakerphone(true)

    if presentation.mode.needsVideo {
      rtcEngine.enableVideo()
      if presentation.role == .host {
        rtcEngine.startPreview()
      }
    }

    let mediaOptions = AgoraRtcChannelMediaOptions()
    let profile: AgoraChannelProfile = presentation.mode == .live ? .liveBroadcasting : .communication
    let clientRole: AgoraClientRole = presentation.role == .audience ? .audience : .broadcaster
    mediaOptions.channelProfile = profile
    mediaOptions.clientRoleType = clientRole

    let result = rtcEngine.joinChannel(
      byToken: token.token,
      channelId: token.channel,
      uid: token.uid,
      mediaOptions: mediaOptions
    )

    if result != 0 {
      isJoining = false
      statusText = "Could not join"
      errorText = "Agora join failed with code \(result)."
    }
  }

  private func requestPermissions(needsVideo: Bool) async -> (microphone: Bool, camera: Bool) {
    let microphone = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { allowed in
        continuation.resume(returning: allowed)
      }
    }

    guard needsVideo else { return (microphone, true) }

    let camera = await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .video) { allowed in
        continuation.resume(returning: allowed)
      }
    }

    return (microphone, camera)
  }

  private func renewToken() async {
    guard !didCleanup else { return }
    do {
      let renewed: MIRAAgoraTokenResponse = try await api.post(
        "/calls/agora/token",
        body: MIRAAgoraTokenRequest(
          channel: presentation.channel,
          role: presentation.role.rawValue,
          mode: presentation.mode.rawValue
        )
      )
      await MainActor.run {
        tokenData = renewed
        engine?.renewToken(renewed.token)
      }
    } catch {
      await MainActor.run {
        errorText = "The call token could not be refreshed."
      }
    }
  }

  @MainActor
  private func startTimerIfNeeded() {
    guard timerTask == nil else { return }
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
          self?.elapsed += 1
        }
      }
    }
  }

  @MainActor
  private func cleanup() {
    guard !didCleanup else { return }
    didCleanup = true
    startTask?.cancel()
    startTask = nil
    timerTask?.cancel()
    timerTask = nil
    engine?.leaveChannel(nil)
    engine?.stopPreview()
    AgoraRtcEngineKit.destroy()
    engine = nil
    UIApplication.shared.isIdleTimerDisabled = false
  }

  private func callErrorMessage(for error: Error) -> String {
    if let apiError = error as? MIRAAPIError {
      switch apiError {
      case .badStatus(503): return "Agora calling is not configured yet."
      case .badStatus(400): return "This call channel is not valid."
      case .badStatus(401), .badStatus(403): return "Verify your account before starting calls."
      default: return apiError.localizedDescription
      }
    }
    return error.localizedDescription.isEmpty ? "Could not start the call." : error.localizedDescription
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      localUid = uid
      isJoined = true
      isJoining = false
      statusText = remoteUid == nil ? "Waiting for them..." : "Connected"
      errorText = nil
      startTimerIfNeeded()
    }
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      remoteUid = uid
      statusText = "Connected"
      errorText = nil
      startTimerIfNeeded()
    }
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      if remoteUid == uid {
        remoteUid = nil
      }
      statusText = "They left the call"
    }
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      isJoining = false
      statusText = "Call error"
      errorText = "Agora error \(errorCode)."
    }
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
    Task { [weak self] in
      await self?.renewToken()
    }
  }
}

struct MIRAAgoraCallView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var model: MIRAAgoraCallModel
  @State private var isVisible = false

  private let presentation: MIRAAgoraCallPresentation

  init(presentation: MIRAAgoraCallPresentation, api: MIRAAPIClient) {
    self.presentation = presentation
    _model = StateObject(wrappedValue: MIRAAgoraCallModel(presentation: presentation, api: api))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      callContent
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.985)
    }
    .preferredColorScheme(.dark)
    .onAppear {
      withAnimation(.easeOut(duration: reduceMotion ? 0.05 : 0.24)) {
        isVisible = true
      }
      model.start()
    }
    .onDisappear {
      model.end()
    }
  }

  private var callContent: some View {
    ZStack {
      remoteLayer
      VStack(spacing: 0) {
        topBar
        Spacer()
        callControls
      }
      .padding(.horizontal, MIRATheme.Space.lg)
      .padding(.bottom, MIRATheme.Space.lg)

      if presentation.mode.needsVideo, !model.cameraOff, presentation.role == .host {
        localPreview
          .padding(.trailing, MIRATheme.Space.lg)
          .padding(.bottom, 116)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
    }
  }

  @ViewBuilder
  private var remoteLayer: some View {
    if presentation.mode.needsVideo, let remoteUid = model.remoteUid, let engine = model.engine {
      MIRAAgoraVideoSurface(engine: engine, uid: remoteUid, isLocal: false)
        .ignoresSafeArea()
        .overlay(callGradient)
    } else {
      waitingLayer
        .overlay(callGradient)
    }
  }

  private var waitingLayer: some View {
    VStack(spacing: MIRATheme.Space.md) {
      RemoteAvatar(url: presentation.peerAvatar, size: 108)
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
      Text(presentation.peerName)
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.75)
      Text(model.errorText ?? model.statusText)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.72))
        .multilineTextAlignment(.center)
        .padding(.horizontal, MIRATheme.Space.xl)
      if model.isJoining {
        ProgressView()
          .tint(.white)
          .padding(.top, MIRATheme.Space.xs)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.070, green: 0.080, blue: 0.075),
          Color(red: 0.015, green: 0.018, blue: 0.016)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var callGradient: some View {
    LinearGradient(
      colors: [
        Color.black.opacity(0.42),
        Color.black.opacity(0.08),
        Color.black.opacity(0.64)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }

  private var topBar: some View {
    HStack(alignment: .center, spacing: MIRATheme.Space.md) {
      Button {
        close()
      } label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Color.white.opacity(0.14))
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)

      VStack(alignment: .leading, spacing: 3) {
        Text(presentation.mode.title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.72))
        Text(durationLabel)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }

      Spacer()
    }
    .padding(.top, MIRATheme.Space.md)
  }

  private var localPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.black.opacity(0.62))
      if let engine = model.engine {
        MIRAAgoraVideoSurface(engine: engine, uid: 0, isLocal: true)
      }
    }
    .frame(width: 116, height: 164)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Color.white.opacity(0.16), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
  }

  private var callControls: some View {
    HStack(spacing: MIRATheme.Space.md) {
      CallControlButton(systemImage: model.micMuted ? "mic.slash.fill" : "mic.fill", isActive: model.micMuted) {
        model.toggleMic()
      }

      if presentation.mode.needsVideo {
        CallControlButton(systemImage: model.cameraOff ? "video.slash.fill" : "video.fill", isActive: model.cameraOff) {
          model.toggleCamera()
        }

        CallControlButton(systemImage: "camera.rotate.fill", isActive: false, isDisabled: model.cameraOff) {
          model.switchCamera()
        }
      }

      Button {
        close()
      } label: {
        Image(systemName: "phone.down.fill")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 66, height: 58)
          .background(Color.red)
          .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
  }

  private var durationLabel: String {
    let minutes = model.elapsed / 60
    let seconds = model.elapsed % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }

  private func close() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    model.end()
    withAnimation(.easeInOut(duration: reduceMotion ? 0.05 : 0.22)) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.22)) {
      dismiss()
    }
  }
}

private struct MIRAAgoraVideoSurface: UIViewRepresentable {
  let engine: AgoraRtcEngineKit
  let uid: UInt
  let isLocal: Bool

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .black
    view.isOpaque = true
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    let canvas = AgoraRtcVideoCanvas()
    canvas.uid = uid
    canvas.renderMode = .hidden
    canvas.view = view
    if isLocal {
      engine.setupLocalVideo(canvas)
    } else {
      engine.setupRemoteVideo(canvas)
    }
  }
}

private struct CallControlButton: View {
  let systemImage: String
  let isActive: Bool
  var isDisabled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
        .clipShape(Circle())
    }
    .buttonStyle(.miraPress)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.42 : 1)
  }
}
