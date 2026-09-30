import AVFoundation
import Foundation
import OSLog

private struct CaptroRealtimeCredentials: Decodable {
  let clientSecret: String
  let model: String
  let diagnosticId: String?
}

private struct CaptroRealtimeStart: Encodable {
  let hasCurrentRecording: Bool
  let currentRecordingId: String?
}

private struct CaptroVoiceDiagnostic: Encodable {
  let diagnosticId: String
  let stage: String
  let epoch: Int
  let frames: Int
  let bytes: Int
  let code: String?
  let httpStatus: Int?
}
private struct CaptroVoiceDiagnosticAck: Decodable { let accepted: Bool }
private struct CaptroMicrophoneChunk { let pcm: Data; let level: CGFloat }

struct CaptroRealtimeTurn: Encodable, Identifiable {
  let id = UUID()
  let role: String
  let text: String

  enum CodingKeys: String, CodingKey { case role, text }
}

private struct CaptroRealtimeIntent: Encodable {
  let utterance: String
  let history: [CaptroRealtimeTurn]
  let hasCurrentRecording: Bool
}

private struct CaptroRealtimeIntentReply: Decodable {
  let action: String
  let trimStartSeconds: Double?
  let trimDurationSeconds: Double?
}

@MainActor
final class CaptroRealtimeVoiceSession: ObservableObject {
  enum Phase: Equatable {
    case connecting, reconnecting, listening, userSpeaking, processing, captroSpeaking, error
  }

  @Published private(set) var phase: Phase = .connecting
  @Published private(set) var level: CGFloat = 0.08
  @Published private(set) var turns: [CaptroRealtimeTurn] = []
  @Published private(set) var muted = false
  @Published private(set) var failureMessage = "Captro AI is unavailable right now."
  @Published private(set) var failureTitle = "Couldn't connect"
  @Published private(set) var outputName = "Speaker"
  @Published private(set) var availableInputs: [AVAudioSessionPortDescription] = []
  @Published private(set) var suggestedAction: CaptroAssistantEditorDestination?
  @Published private(set) var suggestedEditPlan = CaptroAssistantEditPlan(trimStartSeconds: nil, trimDurationSeconds: nil)

  var status: String {
    switch phase {
    case .connecting: return "Connecting…"
    case .reconnecting: return "Reconnecting…"
    case .listening: return muted ? "Microphone muted" : "Listening…"
    case .userSpeaking: return "Listening…"
    case .processing: return "Thinking…"
    case .captroSpeaking: return "Captro is speaking…"
    case .error: return failureTitle
    }
  }

  private var socket: URLSessionWebSocketTask?
  private var transport: URLSession?
  private var receiveTask: Task<Void, Never>?
  private var sendTask: Task<Void, Never>?
  private var connectionTimeout: Task<Void, Never>?
  private var inputContinuation: AsyncStream<CaptroMicrophoneChunk>.Continuation?
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var responseDone = false
  private var queuedOutputBuffers = 0
  private var playbackGeneration = 0
  private var outputItemID: String?
  private var activeResponseID: String?
  private var interruptedResponses = Set<String>()
  private var outputSamplesScheduled = 0
  private var outputText = ""
  private var intentRevision = 0
  private var isClosed = true
  private var responseRequestedForItems = Set<String>()
  private var firstAudioSent = false
  private var micWatchdog: Task<Void, Never>?
  private var reconnectAttempts = 0
  private var sessionEpoch = 0
  private var diagnosticID = UUID().uuidString
  private var sentFrames = 0
  private var sentBytes = 0
  private var lastAudioLog = Date.distantPast
  private var lastAudioSent = Date()
  private var observedMicrophoneSignal = false
  private var heartbeatTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var audioInterrupted = false
  private var backgroundSuspended = false
  private var currentRecordingID: String?
  private var prefersSpeaker = true
  private let logger = Logger(subsystem: "com.captro.app", category: "RealtimeVoice")

  func connect(api: MIRAAPIClient, hasCurrentRecording: Bool, currentRecordingID: String? = nil) async {
    if isClosed { reconnectAttempts = 0 }
    sessionEpoch += 1
    let epoch = sessionEpoch
    stopTransport()
    isClosed = false
    intentAPI = api
    hasRecordingContext = hasCurrentRecording
    self.currentRecordingID = currentRecordingID
    responseRequestedForItems.removeAll()
    firstAudioSent = false
    phase = reconnectAttempts > 0 ? .reconnecting : .connecting
    level = 0.08
    sentFrames = 0
    sentBytes = 0
    lastAudioLog = .distantPast
    lastAudioSent = Date()
    observedMicrophoneSignal = false
    audioInterrupted = false
    backgroundSuspended = false
    failureMessage = "Captro AI is unavailable right now."
    failureTitle = "Couldn't connect"
    if reconnectAttempts == 0 { muted = false }

    let permission = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard permission, !isClosed, sessionEpoch == epoch else {
      if !permission { diagnostic("microphone_permission_denied") }
      if !isClosed && sessionEpoch == epoch {
        failureMessage = "Allow microphone access in iPhone Settings to talk to Captro."
        failureTitle = "Microphone access needed"
        fail()
      }
      return
    }
    diagnostic("microphone_permission_granted")

    do {
      let credentials: CaptroRealtimeCredentials = try await api.post(
        "/ai/realtime/session", body: CaptroRealtimeStart(hasCurrentRecording: hasCurrentRecording, currentRecordingId: currentRecordingID))
      guard !isClosed, sessionEpoch == epoch else { return }
      if let id = credentials.diagnosticId { diagnosticID = id }
      diagnostic("credential_created")
      guard credentials.model == "gpt-realtime-2.1",
            let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1") else { fail(); return }
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 15
      configuration.waitsForConnectivity = true
      let transport = URLSession(configuration: configuration)
      var request = URLRequest(url: url)
      request.setValue("Bearer \(credentials.clientSecret)", forHTTPHeaderField: "Authorization")
      let socket = transport.webSocketTask(with: request)
      self.transport = transport
      self.socket = socket
      socket.resume()
      diagnostic("transport_connecting")
      receiveTask = Task { [weak self] in
        guard let self else { return }
        await self.receiveEvents(epoch: epoch)
      }
      connectionTimeout = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        guard let self, !Task.isCancelled, self.sessionEpoch == epoch,
              self.phase == .connecting || self.phase == .reconnecting else { return }
        self.diagnostic("connection_timeout")
        self.recoverTransport()
      }
    } catch {
      diagnosticError("credential_failed", error)
      if !isClosed && sessionEpoch == epoch { recoverTransport() }
    }
  }

  func toggleMute() {
    guard firstAudioSent, !isClosed else { return }
    muted.toggle()
    level = 0
    diagnostic(muted ? "microphone_muted" : "microphone_unmuted")
    if muted {
      // Discard an unfinished utterance, never submit it as a turn.
      let epoch = sessionEpoch
      Task { [weak self] in
        guard let self, self.sessionEpoch == epoch else { return }
        try? await self.send(["type": "input_audio_buffer.clear"])
      }
      if phase == .userSpeaking { phase = .listening }
    }
  }

  func handleInterruption(_ notification: Notification) {
    guard !isClosed,
          let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
    if type == .began {
      diagnostic("audio_interrupted")
      audioInterrupted = true
      sessionEpoch += 1
      stopTransport()
      phase = .reconnecting
    } else if audioInterrupted {
      audioInterrupted = false
      recoverTransport()
    }
  }

  func handleRouteChange(_ notification: Notification) {
    guard !isClosed,
          let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: value) else { return }
    refreshAudioRoutes()
    guard engine != nil, reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
    if reason == .oldDeviceUnavailable { prefersSpeaker = false }
    diagnostic("audio_route_changed")
    recoverTransport()
  }

  func suspendForBackground() {
    guard !isClosed else { return }
    backgroundSuspended = true
    diagnostic("background_suspended")
    sessionEpoch += 1
    stopTransport()
    phase = .reconnecting
  }

  func resumeFromBackground() {
    guard backgroundSuspended, !isClosed else { return }
    backgroundSuspended = false
    recoverTransport()
  }

  func refreshAudioRoutes() {
    let audio = AVAudioSession.sharedInstance()
    availableInputs = audio.availableInputs ?? []
    outputName = audio.currentRoute.outputs.first?.portName ?? "iPhone"
  }

  func selectOutput(speaker: Bool, input: AVAudioSessionPortDescription? = nil) {
    guard !isClosed, engine != nil else { return }
    do {
      let audio = AVAudioSession.sharedInstance()
      prefersSpeaker = speaker
      try audio.setCategory(.playAndRecord, mode: .voiceChat,
        options: speaker ? [.defaultToSpeaker, .allowBluetoothHFP] : [.allowBluetoothHFP])
      try audio.setPreferredInput(input ?? audio.availableInputs?.first { $0.portType == .builtInMic })
      try audio.overrideOutputAudioPort(speaker ? .speaker : .none)
      refreshAudioRoutes()
      diagnostic("audio_output_selected")
    } catch { diagnosticError("audio_route_failed", error) }
  }

  func stop() {
    diagnostic("session_stopped")
    sessionEpoch += 1
    stopTransport()
    isClosed = true
  }

  private func stopTransport() {
    intentRevision += 1
    connectionTimeout?.cancel()
    connectionTimeout = nil
    heartbeatTask?.cancel()
    heartbeatTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    micWatchdog?.cancel()
    micWatchdog = nil
    receiveTask?.cancel()
    receiveTask = nil
    sendTask?.cancel()
    sendTask = nil
    inputContinuation?.finish()
    inputContinuation = nil
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      player?.removeTap(onBus: 0)
      player?.stop()
      engine.stop()
    }
    engine = nil
    player = nil
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    transport?.invalidateAndCancel()
    transport = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    queuedOutputBuffers = 0
    playbackGeneration += 1
    outputItemID = nil
    activeResponseID = nil
  }

  private func fail() {
    sessionEpoch += 1
    stopTransport()
    isClosed = true
    phase = .error
    level = 0
  }

  private func recoverTransport() {
    guard !isClosed, !audioInterrupted, !backgroundSuspended, reconnectTask == nil else { return }
    guard reconnectAttempts < 3, let intentAPI else { diagnostic("recovery_exhausted"); fail(); return }
    reconnectAttempts += 1
    let delay = UInt64(1 << (reconnectAttempts - 1)) * 1_000_000_000
    let recording = hasRecordingContext
    let recordingID = currentRecordingID
    sessionEpoch += 1
    let epoch = sessionEpoch
    stopTransport()
    phase = .reconnecting
    diagnostic("reconnect_scheduled", code: "attempt_\(reconnectAttempts)")
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: delay)
      guard let self, !Task.isCancelled, !self.isClosed, self.sessionEpoch == epoch else { return }
      self.reconnectTask = nil
      await self.connect(api: intentAPI, hasCurrentRecording: recording, currentRecordingID: recordingID)
    }
  }

  private func receiveEvents(epoch: Int) async {
    guard let socket else { return }
    do {
      while !Task.isCancelled {
        let message = try await socket.receive()
        guard sessionEpoch == epoch else { return }
        let bytes: Data
        switch message {
        case .string(let text): bytes = Data(text.utf8)
        case .data(let data): bytes = data
        @unknown default: continue
        }
        guard
              let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
        await handleEvent(event)
      }
    } catch {
      diagnosticError("transport_closed", error)
      if !isClosed && !Task.isCancelled && sessionEpoch == epoch { recoverTransport() }
    }
  }

  private func handleEvent(_ event: [String: Any]) async {
    guard !isClosed, let type = event["type"] as? String else { return }
    switch type {
    case "session.created":
      diagnostic("session_created")
      do {
        try await send(["type": "session.update", "session": [
          "type": "realtime",
          "audio": ["input": ["format": ["type": "audio/pcm", "rate": 24_000], "turn_detection": [
            "type": "semantic_vad", "eagerness": "medium",
            "create_response": false, "interrupt_response": true,
          ]], "output": ["format": ["type": "audio/pcm", "rate": 24_000]]],
        ]])
      } catch { logger.error("session update send failed"); recoverTransport() }
    case "session.updated":
      guard engine == nil else { return }
      let vad = ((event["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"] as? [String: Any]
      let turnDetection = vad?["turn_detection"] as? [String: Any]
      guard turnDetection?["type"] as? String == "semantic_vad",
            turnDetection?["create_response"] as? Bool == false,
            turnDetection?["interrupt_response"] as? Bool == true else {
        logger.error("realtime VAD configuration mismatch")
        fail()
        return
      }
      let audio = (event["session"] as? [String: Any])?["audio"] as? [String: Any]
      let inputFormat = vad?["format"] as? [String: Any]
      let outputFormat = (audio?["output"] as? [String: Any])?["format"] as? [String: Any]
      guard inputFormat?["type"] as? String == "audio/pcm", inputFormat?["rate"] as? Int == 24_000,
            outputFormat?["type"] as? String == "audio/pcm", outputFormat?["rate"] as? Int == 24_000 else {
        diagnostic("configuration_failed", code: "pcm_format_mismatch")
        fail()
        return
      }
      diagnostic("session_configured")
      // Listening requires a configured session AND the first actual PCM send.
      do {
        // A recovered transport restores only this session's bounded transcript;
        // the recording/draft stays local and is never uploaded implicitly.
        for turn in turns.suffix(8) {
          try await send(["type": "conversation.item.create", "item": [
            "type": "message", "role": turn.role,
            "content": [["type": turn.role == "user" ? "input_text" : "output_text", "text": turn.text]],
          ]])
        }
        try startAudio()
      }
      catch {
        diagnosticError("audio_engine_failed", error)
        recoverTransport()
      }
    case "input_audio_buffer.speech_started":
      diagnostic("speech_started")
      if activeResponseID != nil || queuedOutputBuffers > 0 { interruptOutput() }
      phase = .userSpeaking
      suggestedAction = nil
    case "input_audio_buffer.speech_stopped":
      diagnostic("speech_stopped")
      phase = .processing
    case "input_audio_buffer.committed":
      diagnostic("turn_committed")
      // This is OpenAI's completed Semantic VAD turn, not a local silence
      // timeout or a manual Send action. Request exactly one reply per item.
      guard let itemID = event["item_id"] as? String,
            responseRequestedForItems.insert(itemID).inserted else { return }
      if responseRequestedForItems.count > 80 { responseRequestedForItems = [itemID] }
      do { try await send(["type": "response.create"]); diagnostic("response_requested") }
      catch { logger.error("response.create send failed"); recoverTransport() }
    case "conversation.item.input_audio_transcription.completed":
      let text = (event["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { await handleTranscript(text) }
    case "response.created":
      diagnostic("response_created")
      activeResponseID = (event["response"] as? [String: Any])?["id"] as? String
      responseDone = false
      outputText = ""
      queuedOutputBuffers = 0
      playbackGeneration += 1
      outputItemID = nil
      outputSamplesScheduled = 0
      player?.stop()
      phase = .processing
    case "response.output_item.added":
      guard !isInterruptedEvent(event) else { return }
      outputItemID = (event["item"] as? [String: Any])?["id"] as? String
    case "response.output_audio.delta":
      guard !isInterruptedEvent(event), phase != .userSpeaking else { return }
      if let delta = event["delta"] as? String, let bytes = Data(base64Encoded: delta) { play(bytes) }
    case "response.output_audio_transcript.delta":
      guard !isInterruptedEvent(event) else { return }
      if let delta = event["delta"] as? String { outputText += delta }
    case "response.output_audio_transcript.done":
      guard !isInterruptedEvent(event) else { return }
      let final = (event["transcript"] as? String ?? outputText).trimmingCharacters(in: .whitespacesAndNewlines)
      if !final.isEmpty { appendTurn(role: "assistant", text: final) }
      outputText = ""
    case "response.done", "response.cancelled":
      let response = event["response"] as? [String: Any]
      let id = response?["id"] as? String ?? event["response_id"] as? String
      if let id, interruptedResponses.contains(id) || (activeResponseID != nil && activeResponseID != id) { return }
      if response?["status"] as? String == "failed" {
        let detail = response?["status_details"] as? [String: Any]
        let error = detail?["error"] as? [String: Any]
        diagnostic("response_failed", code: error?["code"] as? String ?? "unknown")
        recoverTransport()
        return
      }
      diagnostic("response_finished")
      responseDone = true
      activeResponseID = nil
      // Retry budget resets only after a successful turn, not every handshake.
      if response?["status"] as? String == "completed" { reconnectAttempts = 0 }
      if queuedOutputBuffers == 0 && phase != .userSpeaking { phase = .listening; level = 0.08 }
    case "conversation.item.input_audio_transcription.failed":
      diagnostic("transcription_failed", code: (event["error"] as? [String: Any])?["code"] as? String)
    case "error":
      let code = ((event["error"] as? [String: Any])?["code"] as? String ?? "unknown")
      diagnostic("api_error", code: code)
      // Cancellation/truncation races are not transport failures.
      if ["response_cancel_not_active", "conversation_already_has_active_response", "audio_end_ms_out_of_range"].contains(code) { return }
      recoverTransport()
    default:
      break
    }
  }

  private func handleTranscript(_ text: String) async {
    diagnostic("transcription_completed")
    appendTurn(role: "user", text: text)
    guard let intentAPI, hasRecordingContext else { return }
    intentRevision += 1
    let revision = intentRevision
    let history = Array(turns.dropLast().suffix(6))
    let body = CaptroRealtimeIntent(utterance: text, history: history, hasCurrentRecording: true)
    Task { [weak self] in
      guard let self else { return }
      guard let result: CaptroRealtimeIntentReply = try? await intentAPI.post("/ai/capture-assistant", body: body),
            revision == self.intentRevision, !self.isClosed else { return }
      switch result.action {
      case "open_story_editor": self.suggestedAction = .story
      case "open_post_editor": self.suggestedAction = .post
      default: self.suggestedAction = nil
      }
      self.suggestedEditPlan = CaptroAssistantEditPlan(
        trimStartSeconds: result.trimStartSeconds, trimDurationSeconds: result.trimDurationSeconds)
    }
  }

  private var intentAPI: MIRAAPIClient?
  private var hasRecordingContext = false

  private func appendTurn(role: String, text: String) {
    turns.append(CaptroRealtimeTurn(role: role, text: text))
    if turns.count > 80 { turns.removeFirst(turns.count - 80) }
  }

  private func isInterruptedEvent(_ event: [String: Any]) -> Bool {
    guard let id = event["response_id"] as? String else { return false }
    return interruptedResponses.contains(id) || (activeResponseID != nil && activeResponseID != id)
  }

  private func diagnostic(_ stage: String, code: String? = nil, httpStatus: Int? = nil) {
    // Only stages, counts and bounded error identifiers. No audio or transcripts.
    logger.info("stage=\(stage, privacy: .public) epoch=\(self.sessionEpoch, privacy: .public) frames=\(self.sentFrames, privacy: .public) bytes=\(self.sentBytes, privacy: .public) code=\(code ?? "none", privacy: .public) http=\(httpStatus ?? 0, privacy: .public)")
    guard let intentAPI else { return }
    let body = CaptroVoiceDiagnostic(diagnosticId: diagnosticID, stage: stage, epoch: sessionEpoch,
      frames: sentFrames, bytes: sentBytes, code: code, httpStatus: httpStatus)
    Task { let _: CaptroVoiceDiagnosticAck? = try? await intentAPI.post("/ai/realtime/diagnostics", body: body) }
  }

  private func diagnosticError(_ stage: String, _ error: Error) {
    let value = error as NSError
    let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
    logger.error("stage=\(stage, privacy: .public) error_domain=\(value.domain, privacy: .public) error_code=\(value.code, privacy: .public) underlying_domain=\(underlying?.domain ?? "none", privacy: .public) underlying_code=\(underlying?.code ?? 0, privacy: .public)")
    if case MIRAAPIError.server(let status, let code, _) = error {
      diagnostic(stage, code: code, httpStatus: status)
    } else if case MIRAAPIError.badStatus(let status) = error {
      diagnostic(stage, httpStatus: status)
    } else {
      diagnostic(stage, code: "\(value.domain).\(value.code)")
    }
  }

  private func startAudio() throws {
    MIRAPlaybackCoordinator.pauseAll(reason: "capture_realtime_voice")
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat,
      options: prefersSpeaker ? [.defaultToSpeaker, .allowBluetoothHFP] : [.allowBluetoothHFP])
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    let engine = AVAudioEngine()
    let input = engine.inputNode
    // Echo cancellation is required for speaker-mode barge-in. Don't silently
    // continue with an audio configuration that failed to activate.
    try input.setVoiceProcessingEnabled(true)
    let inputFormat = input.outputFormat(forBus: 0)
    logger.info("microphone format sampleRate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public)")
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
          inputFormat.commonFormat == .pcmFormatFloat32,
          let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
          let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: inputFormat, to: sendFormat) else { throw MIRAAPIError.emptyResponse }
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: playFormat)
    converter.primeMethod = .none
    let epoch = sessionEpoch
    var continuation: AsyncStream<CaptroMicrophoneChunk>.Continuation!
    // Bound latency; never deliver seconds-old microphone audio after congestion.
    let stream = AsyncStream<CaptroMicrophoneChunk>(bufferingPolicy: .bufferingNewest(6)) { continuation = $0 }
    inputContinuation = continuation
    let audioContinuation = continuation!
    var conversionFailureLogged = false
    input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
      guard let source = buffer.floatChannelData,
            let copy = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: buffer.frameLength),
            let destination = copy.floatChannelData else { return }
      copy.frameLength = buffer.frameLength
      let frameCount = Int(buffer.frameLength)
      for channel in 0..<Int(inputFormat.channelCount) {
        memcpy(destination[channel], source[channel], frameCount * MemoryLayout<Float>.size)
      }
      let capacity = AVAudioFrameCount(Double(frameCount) * 24_000 / inputFormat.sampleRate + 64)
      guard let converted = AVAudioPCMBuffer(pcmFormat: sendFormat, frameCapacity: capacity) else { return }
      var supplied = false
      var error: NSError?
      let conversionStatus = converter.convert(to: converted, error: &error) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true
        status.pointee = .haveData
        return copy
      }
      if (error != nil || conversionStatus == .error) && !conversionFailureLogged {
        conversionFailureLogged = true
        let failure = error ?? NSError(domain: "CaptroPCMConversion", code: -1)
        Task { @MainActor [weak self] in
          guard let self, self.sessionEpoch == epoch else { return }
          self.diagnosticError("microphone_conversion_failed", failure)
        }
      }
      guard error == nil, conversionStatus != .error, converted.frameLength > 0, let samples = converted.int16ChannelData else { return }
      let data = Data(bytes: samples[0], count: Int(converted.frameLength) * 2)
      var power: Float = 0
      for index in stride(from: 0, to: frameCount, by: 32) { power += source[0][index] * source[0][index] }
      let rms = sqrt(power / Float(max(1, (frameCount + 31) / 32)))
      audioContinuation.yield(CaptroMicrophoneChunk(pcm: data, level: CGFloat(min(1, rms * 5))))
    }
    player.installTap(onBus: 0, bufferSize: 1_024, format: playFormat) { [weak self] buffer, _ in
      guard let source = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
      var power: Float = 0
      let count = Int(buffer.frameLength)
      for index in stride(from: 0, to: count, by: 16) { power += source[index] * source[index] }
      let rms = sqrt(power / Float(max(1, (count + 15) / 16)))
      Task { @MainActor [weak self] in
        guard let self, self.sessionEpoch == epoch, self.queuedOutputBuffers > 0,
              self.phase != .userSpeaking, rms > 0.0001 else { return }
        if self.phase != .captroSpeaking { self.diagnostic("audio_playback_started") }
        self.phase = .captroSpeaking
        self.level = CGFloat(min(1, rms * 4))
      }
    }
    self.engine = engine
    self.player = player
    try engine.start()
    player.play()
    refreshAudioRoutes()
    diagnostic("audio_engine_started")
    micWatchdog = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard let self, !Task.isCancelled, !self.isClosed, self.sessionEpoch == epoch else { return }
        if Date().timeIntervalSince(self.lastAudioSent) > 5 {
          self.diagnostic("microphone_stream_stalled")
          self.recoverTransport()
          return
        }
      }
    }
    sendTask = Task { [weak self] in
      for await chunk in stream {
        guard let self, !Task.isCancelled, !self.isClosed, self.sessionEpoch == epoch else { return }
        // Continue transport/VAD timing with zero PCM when muted; no mic audio
        // is sent and unmuting does not release a buffered private utterance.
        let audio = self.muted ? Data(count: chunk.pcm.count) : chunk.pcm
        do {
          try await self.send(["type": "input_audio_buffer.append", "audio": audio.base64EncodedString()])
          guard self.sessionEpoch == epoch else { return }
          self.lastAudioSent = Date()
          self.sentFrames += audio.count / 2
          self.sentBytes += audio.count
          if !self.firstAudioSent {
            self.firstAudioSent = true
            self.diagnostic("first_pcm_sent")
            self.connectionTimeout?.cancel()
            self.connectionTimeout = nil
            self.phase = .listening
            self.startHeartbeat(epoch: epoch)
          }
          if !self.muted && chunk.level > 0.02 && !self.observedMicrophoneSignal {
            self.observedMicrophoneSignal = true
            self.diagnostic("microphone_signal_detected")
          }
          if Date().timeIntervalSince(self.lastAudioLog) >= 10 {
            self.lastAudioLog = Date()
            self.diagnostic("pcm_streaming")
          }
          if self.phase == .listening || self.phase == .userSpeaking {
            self.level = self.muted ? 0 : chunk.level
          }
        } catch {
          self.diagnosticError("pcm_send_failed", error)
          self.recoverTransport()
          return
        }
      }
    }
  }

  private func startHeartbeat(epoch: Int) {
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        guard let self, !Task.isCancelled, self.sessionEpoch == epoch, let socket = self.socket else { return }
        socket.sendPing { [weak self] error in
          guard let error else { return }
          Task { @MainActor [weak self] in
            guard let self, self.sessionEpoch == epoch else { return }
            self.diagnosticError("heartbeat_failed", error)
            self.recoverTransport()
          }
        }
      }
    }
  }

  private func play(_ bytes: Data) {
    guard let player, bytes.count >= 2,
          let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bytes.count / 2)),
          let samples = buffer.floatChannelData?[0] else { return }
    let count = bytes.count / 2
    buffer.frameLength = AVAudioFrameCount(count)
    bytes.withUnsafeBytes { raw in
      guard let source = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for index in 0..<count {
        let value = UInt16(source[index * 2]) | (UInt16(source[index * 2 + 1]) << 8)
        samples[index] = Float(Int16(bitPattern: value)) / 32_768
      }
    }
    queuedOutputBuffers += 1
    outputSamplesScheduled += count
    let generation = playbackGeneration
    responseDone = false
    if outputSamplesScheduled == count { diagnostic("audio_received") }
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.playbackGeneration == generation else { return }
        self.queuedOutputBuffers = max(0, self.queuedOutputBuffers - 1)
        if self.queuedOutputBuffers == 0 && self.responseDone && self.phase != .userSpeaking {
          self.diagnostic("audio_playback_finished")
          self.phase = .listening
          self.level = 0.08
        }
      }
    }
    if !player.isPlaying { player.play() }
  }

  private func interruptOutput() {
    guard let player else { return }
    diagnostic("barge_in")
    if let id = activeResponseID { interruptedResponses.insert(id) }
    if interruptedResponses.count > 80 { interruptedResponses = Set(interruptedResponses.suffix(40)) }
    let playedMs: Int
    if let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) {
      playedMs = min(outputSamplesScheduled / 24, max(0, Int(Double(time.sampleTime) / time.sampleRate * 1_000)))
    } else { playedMs = 0 }
    player.stop()
    queuedOutputBuffers = 0
    playbackGeneration += 1
    responseDone = true
    level = 0.08
    if let item = outputItemID {
      Task { try? await send(["type": "conversation.item.truncate", "item_id": item, "content_index": 0, "audio_end_ms": playedMs]) }
    }
  }

  private func send(_ event: [String: Any]) async throws {
    guard let socket else { throw MIRAAPIError.emptyResponse }
    let bytes = try JSONSerialization.data(withJSONObject: event)
    guard let text = String(data: bytes, encoding: .utf8) else { throw MIRAAPIError.decodingFailed }
    try await socket.send(.string(text))
  }
}
