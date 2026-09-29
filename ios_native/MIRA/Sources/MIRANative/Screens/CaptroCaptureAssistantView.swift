import AVFoundation
import SwiftUI

enum CaptroAssistantEditorDestination: Equatable {
  case story
  case post
}

public struct CaptroAssistantEditPlan: Decodable {
  public let trimStartSeconds: Double?
  public let trimDurationSeconds: Double?

  public init(trimStartSeconds: Double?, trimDurationSeconds: Double?) {
    self.trimStartSeconds = trimStartSeconds
    self.trimDurationSeconds = trimDurationSeconds
  }
}

private struct CaptroAssistantTurn: Codable {
  let role: String
  let text: String
}

private struct CaptroAssistantReply: Decodable {
  let transcript: String?
  let reply: String
  let action: String
  let trimStartSeconds: Double?
  let trimDurationSeconds: Double?
}

struct CaptroCaptureAssistantView: View {
  let api: MIRAAPIClient
  let hasCurrentRecording: Bool
  let onClose: () -> Void
  let onOpenEditor: (CaptroAssistantEditorDestination, CaptroAssistantEditPlan) -> Void
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
            onOpenEditor(action, session.suggestedEditPlan)
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
          .frame(minHeight: 44)
        }
        if session.errorMessage != nil && hasCurrentRecording {
          Button("Use original", action: onClose)
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
        if session.errorMessage != nil && session.hasPendingTurn {
          Button("Record again") { Task { await session.startListening() } }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
        Button {
          if session.isListening || session.hasPendingTurn {
            Task { await session.sendTurn(api: api, hasCurrentRecording: hasCurrentRecording) }
          } else {
            Task { await session.startListening() }
          }
        } label: {
          Label(session.hasPendingTurn ? "Send to Captro" : "Speak to Captro",
                systemImage: session.hasPendingTurn ? "arrow.up.circle.fill" : "mic.fill")
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(MIRATheme.Color.forest)
        .disabled(session.isWaiting)

        Text("Your voice request is sent through Captro's backend to OpenAI for transcription and a response. The voice you hear is computer-generated. Nothing is posted automatically.")
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
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in session.stop() }
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
  @Published var suggestedEditPlan = CaptroAssistantEditPlan(trimStartSeconds: nil, trimDurationSeconds: nil)

  private let speaker = AVSpeechSynthesizer()
  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var recordingTimer: Timer?
  private var turns: [CaptroAssistantTurn] = []

  var hasPendingTurn: Bool { recordingURL != nil }

  override init() {
    super.init()
    speaker.delegate = self
  }

  func startListening() async {
    guard !isListening && !isWaiting else { return }
    speaker.stopSpeaking(at: .immediate)
    discardPendingTurn()
    errorMessage = nil
    suggestedAction = nil
    suggestedEditPlan = CaptroAssistantEditPlan(trimStartSeconds: nil, trimDurationSeconds: nil)
    transcript = nil

    let micPermission = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard micPermission else {
      status = "Microphone is off"
      errorMessage = "Enable Microphone access in iPhone Settings to talk to Captro."
      return
    }
    do {
      MIRAPlaybackCoordinator.pauseAll(reason: "capture_assistant_listening")
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audio.setActive(true, options: .notifyOthersOnDeactivation)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("captro-ai-\(UUID().uuidString).m4a")
      let next = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 24_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ])
      guard next.prepareToRecord(), next.record() else { throw MIRAAPIError.emptyResponse }
      recorder = next
      recordingURL = url
      isListening = true
      status = "Listening…"
      recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.isListening else { return }
          if (self.recorder?.currentTime ?? 0) >= 30 {
            self.stopRecording()
            self.status = "Ready to send"
          }
        }
      }
    } catch {
      stopRecording()
      discardPendingTurn()
      status = "Voice unavailable"
      errorMessage = "Captro could not start the microphone. Try again."
    }
  }

  func sendTurn(api: MIRAAPIClient, hasCurrentRecording: Bool) async {
    guard let url = recordingURL, !isWaiting else { return }
    let duration = recorder?.currentTime ?? 1
    stopRecording()
    guard duration >= 0.25, let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else {
      status = "I didn't hear anything"
      errorMessage = "Try speaking again."
      return
    }
    isWaiting = true
    status = "Captro is thinking…"
    answer = nil
    errorMessage = nil
    do {
      let history = try JSONEncoder().encode(Array(turns.suffix(6)))
      let reply: CaptroAssistantReply = try await api.uploadMultipart(
        "/ai/capture-assistant/audio", fileName: url.lastPathComponent,
        mimeType: "audio/mp4", data: data,
        fields: ["history": String(decoding: history, as: UTF8.self),
                 "has_current_recording": hasCurrentRecording ? "true" : "false"])
      let utterance = reply.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !utterance.isEmpty else { throw MIRAAPIError.emptyResponse }
      turns.append(CaptroAssistantTurn(role: "user", text: utterance))
      turns.append(CaptroAssistantTurn(role: "assistant", text: reply.reply))
      transcript = utterance
      answer = reply.reply
      discardPendingTurn()
      suggestedEditPlan = CaptroAssistantEditPlan(trimStartSeconds: reply.trimStartSeconds, trimDurationSeconds: reply.trimDurationSeconds)
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
      errorMessage = "Captro AI is temporarily unavailable. Try sending this request again. Your video is safe."
    }
  }

  private func stopRecording() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recorder?.stop()
    recorder = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func discardPendingTurn() {
    if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
    recordingURL = nil
  }

  func stop() {
    stopRecording()
    discardPendingTurn()
    speaker.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if !isWaiting && !isListening { status = "Tap to keep talking" }
    }
  }
}
