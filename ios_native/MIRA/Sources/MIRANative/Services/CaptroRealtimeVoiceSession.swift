import AVFoundation
import Foundation
import OSLog

private struct CaptroRealtimeCredentials: Decodable {
  let clientSecret: String
  let model: String
}

private struct CaptroRealtimeStart: Encodable {
  let hasCurrentRecording: Bool
}

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
  @Published private(set) var suggestedAction: CaptroAssistantEditorDestination?
  @Published private(set) var suggestedEditPlan = CaptroAssistantEditPlan(trimStartSeconds: nil, trimDurationSeconds: nil)

  var status: String {
    switch phase {
    case .connecting: return "Connecting…"
    case .reconnecting: return "Reconnecting…"
    case .listening: return muted ? "Microphone muted" : "Listening…"
    case .userSpeaking: return "Listening…"
    case .processing: return "Understanding…"
    case .captroSpeaking: return "Captro is speaking…"
    case .error: return "Couldn't connect"
    }
  }

  private var socket: URLSessionWebSocketTask?
  private var transport: URLSession?
  private var receiveTask: Task<Void, Never>?
  private var sendTask: Task<Void, Never>?
  private var connectionTimeout: Task<Void, Never>?
  private var inputContinuation: AsyncStream<Data>.Continuation?
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var responseDone = false
  private var queuedOutputBuffers = 0
  private var playbackGeneration = 0
  private var outputItemID: String?
  private var outputText = ""
  private var intentRevision = 0
  private var isClosed = true
  private var responseRequestedForItems = Set<String>()
  private var firstAudioSent = false
  private var micWatchdog: Task<Void, Never>?
  private var reconnectAttempts = 0
  private var sessionEpoch = 0
  private let logger = Logger(subsystem: "com.captro.app", category: "RealtimeVoice")

  func connect(api: MIRAAPIClient, hasCurrentRecording: Bool) async {
    if isClosed { reconnectAttempts = 0 }
    sessionEpoch += 1
    let epoch = sessionEpoch
    stopTransport()
    isClosed = false
    intentAPI = api
    hasRecordingContext = hasCurrentRecording
    responseRequestedForItems.removeAll()
    firstAudioSent = false
    phase = reconnectAttempts > 0 ? .reconnecting : .connecting
    level = 0.08
    muted = false

    let permission = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard permission, !isClosed, sessionEpoch == epoch else {
      if !permission { logger.error("microphone permission denied") }
      if !isClosed { fail() }
      return
    }
    logger.info("microphone permission granted")

    do {
      let credentials: CaptroRealtimeCredentials = try await api.post(
        "/ai/realtime/session", body: CaptroRealtimeStart(hasCurrentRecording: hasCurrentRecording))
      guard !isClosed, sessionEpoch == epoch else { return }
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
      logger.info("websocket connection started")
      receiveTask = Task { [weak self] in
        guard let self else { return }
        await self.receiveEvents(epoch: epoch)
      }
      connectionTimeout = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        guard let self, !Task.isCancelled, self.sessionEpoch == epoch,
              self.phase == .connecting || self.phase == .reconnecting else { return }
        self.logger.error("realtime session configuration timed out")
        self.recoverTransport()
      }
    } catch {
      logger.error("realtime credential request failed: \(String(describing: type(of: error)), privacy: .public)")
      if !isClosed && sessionEpoch == epoch { recoverTransport() }
    }
  }

  func toggleMute() {
    guard phase != .error && phase != .connecting else { return }
    muted.toggle()
  }

  func handleInterruption(_ notification: Notification) {
    guard !isClosed,
          let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
    logger.info("audio session interrupted")
    fail()
  }

  func handleRouteChange(_ notification: Notification) {
    guard !isClosed,
          let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
    // Never continue private AI speech unexpectedly on the loudspeaker.
    logger.info("audio route unavailable")
    fail()
  }

  func stop() {
    logger.info("realtime voice stopped")
    sessionEpoch += 1
    stopTransport()
    isClosed = true
  }

  private func stopTransport() {
    connectionTimeout?.cancel()
    connectionTimeout = nil
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
  }

  private func fail() {
    sessionEpoch += 1
    stopTransport()
    isClosed = true
    phase = .error
    level = 0
  }

  private func recoverTransport() {
    guard !isClosed else { return }
    guard reconnectAttempts < 3, let intentAPI else { fail(); return }
    reconnectAttempts += 1
    let delay = UInt64(1 << (reconnectAttempts - 1)) * 1_000_000_000
    let recording = hasRecordingContext
    sessionEpoch += 1
    let epoch = sessionEpoch
    stopTransport()
    phase = .reconnecting
    logger.info("realtime reconnect scheduled attempt=\(self.reconnectAttempts, privacy: .public)")
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: delay)
      guard let self, !Task.isCancelled, !self.isClosed, self.sessionEpoch == epoch else { return }
      await self.connect(api: intentAPI, hasCurrentRecording: recording)
    }
  }

  private func receiveEvents(epoch: Int) async {
    guard let socket else { return }
    do {
      while !Task.isCancelled {
        let message = try await socket.receive()
        guard sessionEpoch == epoch else { return }
        guard case .string(let text) = message,
              let bytes = text.data(using: .utf8),
              let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
        await handleEvent(event)
      }
    } catch {
      logger.error("websocket closed: \(String(describing: type(of: error)), privacy: .public)")
      if !isClosed && !Task.isCancelled && sessionEpoch == epoch { recoverTransport() }
    }
  }

  private func handleEvent(_ event: [String: Any]) async {
    guard !isClosed, let type = event["type"] as? String else { return }
    switch type {
    case "session.created":
      logger.info("realtime session created")
      do {
        try await send(["type": "session.update", "session": [
          "type": "realtime",
          "audio": ["input": ["turn_detection": [
            "type": "semantic_vad", "eagerness": "medium",
            "create_response": false, "interrupt_response": true,
          ]]],
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
      logger.info("realtime semantic VAD configured; client response on committed turn")
      reconnectAttempts = 0
      connectionTimeout?.cancel()
      connectionTimeout = nil
      do { try startAudio(); phase = .listening }
      catch {
        logger.error("microphone engine failed: \(String(describing: type(of: error)), privacy: .public)")
        fail()
      }
    case "input_audio_buffer.speech_started":
      logger.info("speech_started")
      if phase == .captroSpeaking { interruptOutput() }
      phase = .userSpeaking
      suggestedAction = nil
    case "input_audio_buffer.speech_stopped":
      logger.info("speech_stopped")
      phase = .processing
    case "input_audio_buffer.committed":
      logger.info("input_audio_buffer.committed")
      // This is OpenAI's completed Semantic VAD turn, not a local silence
      // timeout or a manual Send action. Request exactly one reply per item.
      guard let itemID = event["item_id"] as? String,
            responseRequestedForItems.insert(itemID).inserted else { return }
      if responseRequestedForItems.count > 80 { responseRequestedForItems = [itemID] }
      do { try await send(["type": "response.create"]); logger.info("response.create sent") }
      catch { logger.error("response.create send failed"); recoverTransport() }
    case "conversation.item.input_audio_transcription.completed":
      let text = (event["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { await handleTranscript(text) }
    case "response.created":
      logger.info("response.created")
      responseDone = false
      outputText = ""
      queuedOutputBuffers = 0
      playbackGeneration += 1
      outputItemID = nil
      player?.stop()
      phase = .processing
    case "response.output_item.added":
      outputItemID = (event["item"] as? [String: Any])?["id"] as? String
    case "response.output_audio.delta":
      if let delta = event["delta"] as? String, let bytes = Data(base64Encoded: delta) { play(bytes) }
    case "response.output_audio_transcript.delta":
      if let delta = event["delta"] as? String { outputText += delta }
    case "response.output_audio_transcript.done":
      let final = (event["transcript"] as? String ?? outputText).trimmingCharacters(in: .whitespacesAndNewlines)
      if !final.isEmpty { turns.append(CaptroRealtimeTurn(role: "assistant", text: final)) }
      outputText = ""
    case "response.done", "response.cancelled":
      logger.info("response finished")
      responseDone = true
      if queuedOutputBuffers == 0 { phase = .listening; level = 0.08 }
    case "error":
      let code = ((event["error"] as? [String: Any])?["code"] as? String ?? "unknown")
      logger.error("realtime API error code: \(code, privacy: .public)")
      fail()
    default:
      break
    }
  }

  private func handleTranscript(_ text: String) async {
    turns.append(CaptroRealtimeTurn(role: "user", text: text))
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

  private func startAudio() throws {
    MIRAPlaybackCoordinator.pauseAll(reason: "capture_realtime_voice")
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    let engine = AVAudioEngine()
    let input = engine.inputNode
    try? input.setVoiceProcessingEnabled(true)
    let inputFormat = input.outputFormat(forBus: 0)
    logger.info("microphone format sampleRate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public)")
    guard inputFormat.commonFormat == .pcmFormatFloat32,
          let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
          let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: inputFormat, to: sendFormat) else { throw MIRAAPIError.emptyResponse }
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: playFormat)
    var continuation: AsyncStream<Data>.Continuation!
    let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(60)) { continuation = $0 }
    inputContinuation = continuation
    let audioContinuation = continuation!
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
      converter.convert(to: converted, error: &error) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true
        status.pointee = .haveData
        return copy
      }
      guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData else { return }
      let data = Data(bytes: samples[0], count: Int(converted.frameLength) * 2)
      audioContinuation.yield(data)
      var power: Float = 0
      for index in stride(from: 0, to: frameCount, by: 32) { power += source[0][index] * source[0][index] }
      let rms = sqrt(power / Float(max(1, (frameCount + 31) / 32)))
      Task { @MainActor [weak self] in
        guard let self, self.phase == .listening || self.phase == .userSpeaking else { return }
        self.level = CGFloat(min(1, max(0.08, rms * 5)))
      }
    }
    try engine.start()
    player.play()
    self.engine = engine
    self.player = player
    logger.info("microphone audio engine started")
    micWatchdog = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard let self, !Task.isCancelled, !self.isClosed, !self.firstAudioSent else { return }
      self.logger.error("microphone stream produced no sendable PCM audio")
      self.fail()
    }
    sendTask = Task { [weak self] in
      for await audio in stream {
        guard let self, !Task.isCancelled, !self.isClosed else { return }
        if self.muted { continue }
        do {
          try await self.send(["type": "input_audio_buffer.append", "audio": audio.base64EncodedString()])
          if !self.firstAudioSent {
            self.firstAudioSent = true
            self.logger.info("first microphone PCM chunk sent")
          }
        } catch {
          self.logger.error("microphone chunk send failed: \(String(describing: type(of: error)), privacy: .public)")
          self.recoverTransport()
          return
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
    let generation = playbackGeneration
    responseDone = false
    phase = .captroSpeaking
    if queuedOutputBuffers == 1 { logger.info("response audio playback started") }
    let previewCount = min(count, 1_200)
    var power: Float = 0
    for index in stride(from: 0, to: previewCount, by: 32) { power += samples[index] * samples[index] }
    level = CGFloat(min(1, max(0.12, sqrt(power / Float(max(1, previewCount / 32))) * 4)))
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.playbackGeneration == generation else { return }
        self.queuedOutputBuffers = max(0, self.queuedOutputBuffers - 1)
        if self.queuedOutputBuffers == 0 && self.responseDone { self.phase = .listening; self.level = 0.08 }
      }
    }
    if !player.isPlaying { player.play() }
  }

  private func interruptOutput() {
    guard let player else { return }
    logger.info("assistant playback interrupted by user speech")
    let playedMs: Int
    if let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) {
      playedMs = max(0, Int(Double(time.sampleTime) / time.sampleRate * 1_000))
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
