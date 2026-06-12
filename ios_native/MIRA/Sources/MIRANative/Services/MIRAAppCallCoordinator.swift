import CallKit
import Foundation
import PushKit
import SwiftUI
import UIKit

@MainActor
final class MIRAAppCallCoordinator: NSObject, ObservableObject {
  static let shared = MIRAAppCallCoordinator()

  @Published var incomingCall: MIRACallSession?
  @Published var outgoingCall: MIRACallSession?
  @Published var activeCall: MIRAAgoraCallPresentation?
  @Published var statusText: String?

  private var api: MIRAAPIClient?
  private var currentUserId = ""
  private var pushRegistry: PKPushRegistry?
  private var provider: CXProvider?
  private var callUUIDByCallId: [String: UUID] = [:]
  private var callIdByUUID: [UUID: String] = [:]
  private var sessionsByCallId: [String: MIRACallSession] = [:]
  private var incomingPollTask: Task<Void, Never>?
  private var outgoingPollTask: Task<Void, Never>?

  private override init() {
    super.init()
    configureCallKit()
  }

  func configure(api: MIRAAPIClient, currentUserId: String?) {
    self.api = api
    self.currentUserId = currentUserId ?? ""
    guard !self.currentUserId.isEmpty else {
      resetForSignedOutUser()
      return
    }
    registerForVoIPPushesIfNeeded()
    startIncomingPolling()
  }

  func startVideoCall(peerId: String, peerName: String, peerAvatar: String?) async {
    guard !peerId.isEmpty, peerId != currentUserId else { return }
    guard activeCall == nil, outgoingCall == nil else {
      statusText = "You are already in a call."
      return
    }
    guard let api else {
      statusText = "Calling is not ready yet."
      return
    }

    statusText = "Creating video call..."
    CaptroHaptics.medium()

    do {
      let session: MIRACallSession = try await api.post(
        "/calls",
        body: MIRACallStartBody(calleeUserId: peerId, callType: "video")
      )
      sessionsByCallId[session.resolvedId] = session
      outgoingCall = session
      statusText = "Ringing \(peerName.isEmpty ? "them" : peerName)..."
      startOutgoingPolling(for: session)
    } catch {
      statusText = callErrorText(for: error)
      CaptroHaptics.error()
    }
  }

  func acceptIncomingCall(_ call: MIRACallSession) async {
    guard let api else { return }
    do {
      let updated: MIRACallSession = try await api.post("/calls/\(call.resolvedId)/accept", body: EmptyBody())
      sessionsByCallId[updated.resolvedId] = updated
      incomingCall = nil
      activeCall = updated.agoraPresentation(currentUserId: currentUserId)
      statusText = nil
      CaptroHaptics.success()
    } catch {
      statusText = callErrorText(for: error)
      CaptroHaptics.error()
    }
  }

  func declineIncomingCall(_ call: MIRACallSession) async {
    guard let api else {
      incomingCall = nil
      return
    }
    let _: MIRACallSession? = try? await api.post("/calls/\(call.resolvedId)/decline", body: EmptyBody())
    endReportedCallKitCall(for: call, reason: .declinedElsewhere)
    incomingCall = nil
    statusText = nil
    CaptroHaptics.light()
  }

  func cancelOutgoingCall() async {
    guard let call = outgoingCall else { return }
    if let api {
      let _: MIRACallSession? = try? await api.post("/calls/\(call.resolvedId)/cancel", body: EmptyBody())
    }
    outgoingPollTask?.cancel()
    outgoingPollTask = nil
    outgoingCall = nil
    statusText = nil
    CaptroHaptics.light()
  }

  func endActiveCall() async {
    guard let callId = activeCall?.callId else {
      activeCall = nil
      return
    }
    if let api {
      let _: MIRACallSession? = try? await api.post("/calls/\(callId)/end", body: EmptyBody())
    }
    if let session = sessionsByCallId[callId] {
      endReportedCallKitCall(for: session, reason: .remoteEnded)
    }
    activeCall = nil
    statusText = nil
  }

  private func resetForSignedOutUser() {
    incomingPollTask?.cancel()
    outgoingPollTask?.cancel()
    incomingPollTask = nil
    outgoingPollTask = nil
    incomingCall = nil
    outgoingCall = nil
    activeCall = nil
    statusText = nil
  }

  private func startIncomingPolling() {
    guard incomingPollTask == nil else { return }
    incomingPollTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refreshIncomingCall()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
    }
  }

  private func refreshIncomingCall() async {
    guard activeCall == nil, outgoingCall == nil, let api else { return }
    do {
      let envelope: MIRAIncomingCallEnvelope = try await api.get("/calls/incoming")
      if let call = envelope.call {
        sessionsByCallId[call.resolvedId] = call
        if incomingCall?.resolvedId != call.resolvedId {
          incomingCall = call
        }
      } else if incomingCall != nil {
        incomingCall = nil
      }
    } catch {
      // Foreground polling should stay quiet. PushKit/CallKit still handles real incoming calls.
    }
  }

  private func startOutgoingPolling(for session: MIRACallSession) {
    outgoingPollTask?.cancel()
    outgoingPollTask = Task { [weak self] in
      guard let self else { return }
      let callId = session.resolvedId
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard self.outgoingCall?.resolvedId == callId, let api = self.api else { return }
        do {
          let updated: MIRACallSession = try await api.get("/calls/\(callId)")
          self.sessionsByCallId[updated.resolvedId] = updated
          self.outgoingCall = updated
          switch updated.status {
          case .accepted, .connecting, .active:
            self.outgoingCall = nil
            self.statusText = nil
            self.activeCall = updated.agoraPresentation(currentUserId: self.currentUserId)
            CaptroHaptics.success()
            return
          case .declined:
            self.statusText = "Call declined."
            CaptroHaptics.warning()
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.outgoingCall = nil
            return
          case .missed:
            self.statusText = "No answer."
            CaptroHaptics.warning()
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.outgoingCall = nil
            return
          case .cancelled, .ended, .failed:
            self.outgoingCall = nil
            return
          default:
            break
          }
        } catch {
          self.statusText = "Call connection failed."
          self.outgoingCall = nil
          return
        }
      }
    }
  }

  private func configureCallKit() {
    let configuration = CXProviderConfiguration(localizedName: "Captro")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.iconTemplateImageData = UIImage(systemName: "video.fill")?.pngData()
    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: nil)
    self.provider = provider
  }

  private func registerForVoIPPushesIfNeeded() {
    guard pushRegistry == nil else { return }
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    pushRegistry = registry
  }

  private func registerVoIPToken(_ token: Data) async {
    guard let api else { return }
    let tokenString = token.map { String(format: "%02x", $0) }.joined()
    let body = MIRAVoIPTokenBody(
      token: tokenString,
      deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UIDevice.current.name,
      bundleId: Bundle.main.bundleIdentifier ?? "com.captro.app",
      environment: isDebugBuild ? "development" : "production"
    )
    let _: EmptyResponse? = try? await api.post("/calls/voip-token", body: body)
  }

  private var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
  }

  private func handleIncomingPushPayload(_ payload: [AnyHashable: Any]) async {
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    if let call = try? decoder.decode(MIRACallSession.self, from: data) {
      sessionsByCallId[call.resolvedId] = call
      guard call.status == .ringing else {
        if incomingCall?.resolvedId == call.resolvedId {
          incomingCall = nil
        }
        endReportedCallKitCall(for: call, reason: .remoteEnded)
        return
      }
      incomingCall = call
      reportIncomingCallToCallKit(call)
    } else {
      await refreshIncomingCall()
    }
  }

  private func reportIncomingCallToCallKit(_ call: MIRACallSession) {
    guard provider != nil else { return }
    let uuid = uuidForCall(call)
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: call.callerName ?? "Captro")
    update.localizedCallerName = call.callerName ?? "Captro Video Call"
    update.hasVideo = true
    provider?.reportNewIncomingCall(with: uuid, update: update) { _ in }
  }

  private func uuidForCall(_ call: MIRACallSession) -> UUID {
    if let existing = callUUIDByCallId[call.resolvedId] { return existing }
    let uuid = UUID()
    callUUIDByCallId[call.resolvedId] = uuid
    callIdByUUID[uuid] = call.resolvedId
    return uuid
  }

  private func endReportedCallKitCall(for call: MIRACallSession, reason: CXCallEndedReason) {
    guard let uuid = callUUIDByCallId[call.resolvedId] else { return }
    provider?.reportCall(with: uuid, endedAt: Date(), reason: reason)
    callUUIDByCallId[call.resolvedId] = nil
    callIdByUUID[uuid] = nil
  }

  private func callErrorText(for error: Error) -> String {
    if let apiError = error as? MIRAAPIError {
      switch apiError {
      case .badStatus(403): return "This call is not available for that profile."
      case .badStatus(409): return "One of you is already in another call."
      case .badStatus(503): return "Video calling is not configured yet."
      default: return apiError.localizedDescription
      }
    }
    return error.localizedDescription.isEmpty ? "Could not start the call." : error.localizedDescription
  }
}

extension MIRAAppCallCoordinator: PKPushRegistryDelegate {
  nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let token = pushCredentials.token
    Task { @MainActor in
      await self.registerVoIPToken(token)
    }
  }

  nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
  }

  nonisolated func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let dictionary = payload.dictionaryPayload
    Task { @MainActor in
      await self.handleIncomingPushPayload(dictionary)
      completion()
    }
  }
}

extension MIRAAppCallCoordinator: CXProviderDelegate {
  nonisolated func providerDidReset(_ provider: CXProvider) {
    Task { @MainActor in
      self.incomingCall = nil
      self.outgoingCall = nil
      self.activeCall = nil
    }
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    Task { @MainActor in
      if let callId = self.callIdByUUID[action.callUUID], let call = self.sessionsByCallId[callId] {
        await self.acceptIncomingCall(call)
      }
      action.fulfill()
    }
  }

  nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    Task { @MainActor in
      if let callId = self.callIdByUUID[action.callUUID], let call = self.sessionsByCallId[callId] {
        if self.incomingCall?.resolvedId == callId {
          await self.declineIncomingCall(call)
        } else if self.activeCall?.callId == callId {
          await self.endActiveCall()
        }
      }
      action.fulfill()
    }
  }
}

struct MIRACallOverlays: View {
  @ObservedObject var coordinator: MIRAAppCallCoordinator

  var body: some View {
    ZStack {
      if let incoming = coordinator.incomingCall {
        MIRAIncomingCallOverlay(call: incoming) {
          Task { await coordinator.declineIncomingCall(incoming) }
        } onAccept: {
          Task { await coordinator.acceptIncomingCall(incoming) }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(20)
      }

      if let outgoing = coordinator.outgoingCall {
        MIRAOutgoingCallOverlay(call: outgoing, statusText: coordinator.statusText) {
          Task { await coordinator.cancelOutgoingCall() }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(19)
      }
    }
    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: coordinator.incomingCall)
    .animation(.easeInOut(duration: 0.22), value: coordinator.outgoingCall)
  }
}

private struct MIRAIncomingCallOverlay: View {
  let call: MIRACallSession
  let onDecline: () -> Void
  let onAccept: () -> Void

  var body: some View {
    VStack {
      HStack(spacing: MIRATheme.Space.md) {
        RemoteAvatar(url: call.callerAvatar, size: 54)
        VStack(alignment: .leading, spacing: 3) {
          Text(call.callerName ?? "Captro")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text("Captro Video Call")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.72))
        }
        Spacer()
        Button(action: onDecline) {
          Image(systemName: "phone.down.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.red)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        Button(action: onAccept) {
          Image(systemName: "video.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.green)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
      }
      .padding(14)
      .background(.black.opacity(0.88))
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(Color.white.opacity(0.14), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.md)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(true)
  }
}

private struct MIRAOutgoingCallOverlay: View {
  let call: MIRACallSession
  let statusText: String?
  let onCancel: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.92).ignoresSafeArea()
      VStack(spacing: MIRATheme.Space.lg) {
        RemoteAvatar(url: call.calleeAvatar, size: 116)
          .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        VStack(spacing: 6) {
          Text(call.calleeName ?? "Video call")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
          Text(statusText ?? "Ringing...")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.68))
        }
        CaptroCallPulse()
          .padding(.top, 4)
        Button(action: onCancel) {
          Image(systemName: "phone.down.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 70, height: 58)
            .background(Color.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.miraPress)
        .padding(.top, MIRATheme.Space.xl)
      }
      .padding(.horizontal, MIRATheme.Space.xl)
    }
  }
}

private struct CaptroCallPulse: View {
  var body: some View {
    TimelineView(.animation) { timeline in
      let value = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 7) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.white.opacity(0.26 + 0.46 * abs(sin(value * 2.1 + Double(index) * 0.8))))
            .frame(width: 7, height: 7)
        }
      }
    }
    .frame(height: 12)
  }
}
