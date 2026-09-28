import AVFoundation
import Speech
import SwiftUI

enum CaptroAssistantEditorDestination: Equatable {
  case story
  case post
}

private struct CaptroAssistantTurn: Codable {
  let role: String
  let text: String
}

private struct CaptroAssistantRequest: Encodable {
  let utterance: String
  let history: [CaptroAssistantTurn]
  let hasCurrentRecording: Bool
}

private struct CaptroAssistantReply: Decodable {
  let reply: String
  let action: String
}

struct CaptroCaptureAssistantView: View {
  let api: MIRAAPIClient
  let hasCurrentRecording: Bool
  let onClose: () -> Void
  let onOpenEditor: (CaptroAssistantEditorDestination) -> Void
  @StateObject private var session = CaptroCaptureAssistantSession()

  var body: some View {
    NavigationStack {
      VStack(spacing: 22) {
        Spacer(minLength: 24)
        Image(systemName: session.isListening ? "waveform" : "waveform.circle")
          .font(.system(size: 72, weight: .ultraLight))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 120, height: 120)
          .accessibilityHidden(true)

        Text(session.status)
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .multilineTextAlignment(.center)

        if let transcript = session.transcript, !transcript.isEmpty {
          Text("You: \(transcript)")
            .font(.system(size: 15))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
        }
        if let answer = session.answer {
          Text("Captro: \(answer)")
            .font(.system(size: 16))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
        }
        if let error = session.errorMessage {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        }

        Spacer(minLength: 24)

        if let action = session.suggestedAction {
          Button(action == .story ? "Review Story" : "Review Post") {
            session.stop()
            onOpenEditor(action)
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
          .frame(minHeight: 44)
        }
        Button {
          if session.isListening {
            Task { await session.sendTurn(api: api, hasCurrentRecording: hasCurrentRecording) }
          } else {
            Task { await session.startListening() }
          }
        } label: {
          Label(session.isListening ? "Send what I said" : "Speak to Captro",
                systemImage: session.isListening ? "arrow.up.circle.fill" : "mic.fill")
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(MIRATheme.Color.forest)
        .disabled(session.isWaiting)

        Text("Captro uses on-device speech recognition when available. Your words are sent to Captro's AI to answer. The voice you hear is computer-generated. Nothing is posted automatically.")
          .font(.footnote)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(20)
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Voice")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { session.stop(); onClose() } } }
      .task { await session.startListening() }
      .onDisappear { session.stop() }
    }
  }
}

@MainActor
private final class CaptroCaptureAssistantSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  @Published var status = "Preparing microphone…"
  @Published var transcript: String?
  @Published var answer: String?
  @Published var errorMessage: String?
  @Published var isListening = false
  @Published var isWaiting = false
  @Published var suggestedAction: CaptroAssistantEditorDestination?

  private let engine = AVAudioEngine()
  private let speaker = AVSpeechSynthesizer()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var turns: [CaptroAssistantTurn] = []

  override init() {
    super.init()
    speaker.delegate = self
  }

  func startListening() async {
    guard !isListening && !isWaiting else { return }
    speaker.stopSpeaking(at: .immediate)
    errorMessage = nil
    suggestedAction = nil
    transcript = nil

    let speechPermission = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speechPermission == .authorized else {
      status = "Speech recognition is off"
      errorMessage = "Enable Speech Recognition in iPhone Settings to talk to Captro."
      return
    }
    let micPermission = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard micPermission else {
      status = "Microphone is off"
      errorMessage = "Enable Microphone access in iPhone Settings to talk to Captro."
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
          recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
      status = "Voice unavailable"
      errorMessage = "On-device speech recognition is unavailable for this language or device."
      return
    }

    do {
      MIRAPlaybackCoordinator.pauseAll(reason: "capture_assistant_listening")
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audio.setActive(true, options: .notifyOthersOnDeactivation)
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      self.request = request
      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          guard let self, self.isListening else { return }
          if let result { self.transcript = result.bestTranscription.formattedString }
          if error != nil {
            self.errorMessage = "Could not understand that. Try speaking again."
            self.stopRecording()
          }
        }
      }
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
      engine.prepare()
      try engine.start()
      isListening = true
      status = "Listening…"
    } catch {
      stopRecording()
      status = "Voice unavailable"
      errorMessage = "Captro could not start the microphone. Try again."
    }
  }

  func sendTurn(api: MIRAAPIClient, hasCurrentRecording: Bool) async {
    guard isListening else { return }
    let utterance = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    stopRecording()
    guard !utterance.isEmpty else {
      status = "I didn't hear anything"
      errorMessage = "Try speaking again."
      return
    }
    isWaiting = true
    status = "Captro is thinking…"
    answer = nil
    errorMessage = nil
    do {
      let reply: CaptroAssistantReply = try await api.post("/ai/capture-assistant",
        body: CaptroAssistantRequest(utterance: utterance, history: Array(turns.suffix(6)), hasCurrentRecording: hasCurrentRecording))
      turns.append(CaptroAssistantTurn(role: "user", text: utterance))
      turns.append(CaptroAssistantTurn(role: "assistant", text: reply.reply))
      answer = reply.reply
      if hasCurrentRecording {
        switch reply.action {
        case "open_story_editor": suggestedAction = .story
        case "open_post_editor": suggestedAction = .post
        default: suggestedAction = nil
        }
      }
      status = "Captro"
      isWaiting = false
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      speaker.speak(AVSpeechUtterance(string: reply.reply))
    } catch {
      isWaiting = false
      status = "Couldn't connect"
      errorMessage = "Captro Voice couldn't respond. Your recording is safe; try speaking again."
    }
  }

  private func stopRecording() {
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    request = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func stop() {
    stopRecording()
    speaker.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if !isWaiting && !isListening { status = "Tap to keep talking" }
    }
  }
}
