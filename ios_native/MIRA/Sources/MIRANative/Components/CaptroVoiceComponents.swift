import AVFoundation
import SwiftUI
import UIKit

public struct CaptroVoiceDraft: Hashable {
  public let fileURL: URL
  public let duration: TimeInterval
  public let levels: [Float]
  public let disclosureVersion: String
  public let disclosureAcceptedAt: Date
}

public struct CaptroVoiceSubmission: Decodable, Hashable {
  public let id: String
  public let durationMs: Int
  public let processingState: String
  public let moderationState: String
  public let publicationState: String
  public let transcript: String?
  public let decisionReason: String?
}

@MainActor
public final class CaptroVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  @Published public private(set) var isRecording = false
  @Published public private(set) var isPausedBySystem = false
  @Published public private(set) var duration: TimeInterval = 0
  @Published public private(set) var level: Float = 0
  @Published public private(set) var levels: [Float] = []
  @Published public private(set) var fileURL: URL?
  @Published public var errorMessage: String?

  private var recorder: AVAudioRecorder?
  private var timer: Timer?
  private let limit: TimeInterval
  private var observers: [NSObjectProtocol] = []

  public init(limit: TimeInterval) {
    self.limit = limit
    super.init()
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      Task { @MainActor in self?.handleInterruption(note) }
    })
    observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
      Task { @MainActor in self?.handleRouteChange(note) }
    })
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.stop(reason: "Recording stopped when Captro moved to the background.") }
    })
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  public func start() async {
    guard !isRecording else { return }
    errorMessage = nil
    let allowed = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard allowed else {
      errorMessage = "Microphone access is off. Enable it in Settings to record voice."
      return
    }
    do {
      MIRAPlaybackCoordinator.pauseAll(reason: "voice_recording_started")
      CaptroVoicePlaybackCenter.shared.stop()
      let session = AVAudioSession.sharedInstance()
      // spokenAudio is a playback mode (podcasts/audiobooks). Use the normal
      // recording mode so capture works consistently across input routes.
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      // The route can be empty briefly after activation, even though the
      // recorder can open the built-in microphone. Let AVAudioRecorder decide.
      guard let directory = postDraftMediaDirectory() else { throw MIRAAPIError.emptyResponse }
      let url = directory.appendingPathComponent("captro-voice-\(UUID().uuidString).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let next = try AVAudioRecorder(url: url, settings: settings)
      next.delegate = self
      next.isMeteringEnabled = true
      guard next.prepareToRecord() else { throw MIRAAPIError.emptyResponse }
      recorder = next
      fileURL = url
      duration = 0
      level = 0
      levels = []
      isPausedBySystem = false
      guard next.record() else { throw MIRAAPIError.emptyResponse }
      isRecording = true
      timer?.invalidate()
      timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.tick() }
      }
    } catch {
      let failedURL = fileURL
      recorder?.stop()
      recorder = nil
      timer?.invalidate()
      timer = nil
      isRecording = false
      fileURL = nil
      duration = 0
      if let failedURL { try? FileManager.default.removeItem(at: failedURL) }
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      errorMessage = "Captro could not start recording. Check the microphone and try again."
    }
  }

  public func stop(reason: String? = nil) {
    guard recorder != nil || isRecording else { return }
    let activeRecorder = recorder
    let finalDuration = activeRecorder?.currentTime ?? duration
    recorder = nil
    timer?.invalidate()
    timer = nil
    isRecording = false
    activeRecorder?.stop()
    duration = min(limit, max(duration, finalDuration))
    if let reason { errorMessage = reason }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  public var hasUsableRecording: Bool {
    guard !isRecording, duration >= 0.25, let fileURL,
          let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
          (values.fileSize ?? 0) > 0 else { return false }
    return true
  }

  public func reset() {
    stop()
    if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    fileURL = nil
    duration = 0
    level = 0
    levels = []
    errorMessage = nil
    isPausedBySystem = false
  }

  private func tick() {
    guard let recorder, recorder.isRecording else {
      if isRecording { stop() }
      return
    }
    recorder.updateMeters()
    duration = min(limit, recorder.currentTime)
    let normalized = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 35)))
    level = normalized
    if levels.count < 120 { levels.append(normalized) }
    else if Int(duration * 20) % 2 == 0 { levels[levels.count - 1] = normalized }
    if duration >= limit { stop() }
  }

  private func handleInterruption(_ note: Notification) {
    guard isRecording else { return }
    isPausedBySystem = true
    stop(reason: "Recording stopped because the audio session was interrupted.")
  }

  private func handleRouteChange(_ note: Notification) {
    guard isRecording,
          let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
    switch reason {
    case .oldDeviceUnavailable, .noSuitableRouteForCategory:
      stop(reason: "Recording stopped because the microphone route became unavailable.")
    default:
      // Session activation itself emits category/override route changes. Those must
      // not immediately stop a recording that has just started.
      break
    }
  }
}

public struct CaptroVoiceRecorderSheet: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var recorder: CaptroVoiceRecorder
  @State private var disclosureAccepted = false
  @State private var previewPlayer: AVAudioPlayer?
  @State private var isPreviewing = false
  @State private var didUseRecording = false
  private let limit: TimeInterval
  private let onUse: (CaptroVoiceDraft) -> Void

  public init(limit: TimeInterval, onUse: @escaping (CaptroVoiceDraft) -> Void) {
    self.limit = limit
    self.onUse = onUse
    _recorder = StateObject(wrappedValue: CaptroVoiceRecorder(limit: limit))
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        VStack(spacing: 8) {
          Text("Record voice")
            .font(.title3.weight(.semibold))
          Text("\(time(recorder.duration)) / \(time(limit))")
            .font(.system(.body, design: .monospaced).weight(.medium))
            .foregroundStyle(.secondary)
        }

        HStack(alignment: .center, spacing: 3) {
          ForEach(0..<28, id: \.self) { index in
            Capsule()
              .fill(MIRATheme.Color.forest.opacity(0.78))
              .frame(width: 3, height: max(4, CGFloat(level(at: index)) * 34))
          }
        }
        .frame(height: 40)
        .accessibilityLabel("Microphone level")

        if recorder.fileURL == nil || recorder.isRecording {
          Button {
            if recorder.isRecording { recorder.stop() }
            else { Task { await recorder.start() } }
          } label: {
            Label(recorder.isRecording ? "Stop" : "Record", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
              .font(.body.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 48)
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
        } else {
          HStack(spacing: 12) {
            Button(isPreviewing ? "Pause" : "Play") { togglePreview() }
              .buttonStyle(.bordered)
            Button("Record again") {
              previewPlayer?.stop()
              isPreviewing = false
              recorder.reset()
            }
            .buttonStyle(.bordered)
          }

          Toggle(isOn: $disclosureAccepted) {
            Text("I understand this recording is securely sent to Captro’s configured AI provider for transcription and safety checks before publication.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .toggleStyle(.switch)

          Button("Use recording") {
            guard let fileURL = recorder.fileURL else { return }
            didUseRecording = true
            onUse(CaptroVoiceDraft(fileURL: fileURL, duration: recorder.duration, levels: recorder.levels,
              disclosureVersion: "voice-ai-processing-v1", disclosureAcceptedAt: Date()))
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
          .disabled(!disclosureAccepted || !recorder.hasUsableRecording)
          .frame(maxWidth: .infinity)
        }

        if let error = recorder.errorMessage {
          Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
        }
        Spacer()
      }
      .padding(20)
      .navigationTitle("Voice")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { recorder.reset(); dismiss() }
        }
      }
      .interactiveDismissDisabled(recorder.isRecording)
      .onDisappear {
        previewPlayer?.stop()
        previewPlayer = nil
        if didUseRecording { recorder.stop() }
        else { recorder.reset() }
      }
    }
  }

  private func togglePreview() {
    guard let url = recorder.fileURL else { return }
    if isPreviewing { previewPlayer?.pause(); isPreviewing = false; return }
    do {
      MIRAPlaybackCoordinator.pauseAll(reason: "voice_preview_started")
      let player = try AVAudioPlayer(contentsOf: url)
      player.play()
      previewPlayer = player
      isPreviewing = true
    } catch { recorder.errorMessage = "This recording could not be played." }
  }

  private func level(at index: Int) -> Float {
    let samples = Array(recorder.levels.suffix(28))
    guard !samples.isEmpty else { return recorder.isRecording && index == 27 ? max(0.12, recorder.level) : 0.08 }
    if recorder.isRecording, index == 27 { return max(0.12, recorder.level) }
    let source = min(samples.count - 1, index * samples.count / 28)
    return max(0.08, samples[source])
  }

  private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

public final class CaptroVoiceUploadService {
  private let api: MIRAAPIClient
  public init(api: MIRAAPIClient) { self.api = api }

  public func submit(
    _ draft: CaptroVoiceDraft,
    targetType: String,
    targetId: String? = nil,
    parentPostId: String? = nil,
    parentCommentId: String? = nil,
    caption: String,
    onUploadProgress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> CaptroVoiceSubmission {
    let data = try Data(contentsOf: draft.fileURL, options: .mappedIfSafe)
    var fields = [
      "target_type": targetType,
      "caption": caption,
      "disclosure_accepted": "true",
      "disclosure_version": draft.disclosureVersion,
      "disclosure_accepted_at": ISO8601DateFormatter().string(from: draft.disclosureAcceptedAt),
    ]
    if let targetId { fields["target_id"] = targetId }
    if let parentPostId { fields["parent_post_id"] = parentPostId }
    if let parentCommentId { fields["parent_comment_id"] = parentCommentId }
    do {
      return try await api.uploadMultipart(
        "/voice/submissions", fileName: draft.fileURL.lastPathComponent,
        mimeType: "audio/mp4", data: data, fields: fields,
        onProgress: onUploadProgress
      )
    } catch MIRAAPIError.badStatus(404) {
      throw CaptroVoiceUploadError.serviceUnavailable
    } catch MIRAAPIError.server(let status, _, _) where status == 404 {
      throw CaptroVoiceUploadError.serviceUnavailable
    }
  }
}

public enum CaptroVoiceUploadError: LocalizedError {
  case serviceUnavailable

  public var errorDescription: String? {
    switch self {
    case .serviceUnavailable:
      return "Voice uploads are not available on Captro’s server yet. Your recording is still here; please try again after the voice service is enabled."
    }
  }
}

@MainActor
public final class CaptroVoicePlaybackCenter: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
  public static let shared = CaptroVoicePlaybackCenter()
  @Published public private(set) var activeId: String?
  @Published public private(set) var isPlaying = false
  @Published public private(set) var progress: Double = 0
  @Published public private(set) var duration: Double = 0
  @Published public private(set) var errorMessage: String?
  private let session = MIRAKeychainSessionProvider()
  private var player: AVAudioPlayer?
  private var timer: Timer?

  public func toggle(id: String) async {
    if activeId == id, let player {
      if player.isPlaying {
        player.pause()
      } else {
        player.play()
      }
      isPlaying = player.isPlaying
      return
    }
    stop()
    do {
      var request = URLRequest(url: MIRAProductionBackend.apiURL("voice/\(id)/playback"))
      request.cachePolicy = .reloadIgnoringLocalCacheData
      if let token = await session.accessToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
      let (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MIRAAPIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0) }
      let next = try AVAudioPlayer(data: data)
      next.delegate = self
      next.prepareToPlay()
      player = next
      activeId = id
      duration = next.duration
      next.play()
      isPlaying = true
      timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.updateProgress() }
      }
    } catch {
      errorMessage = "This recording is unavailable."
      stop(keepError: true)
    }
  }

  public func seek(id: String, progress: Double) {
    guard activeId == id, let player else { return }
    player.currentTime = max(0, min(1, progress)) * player.duration
    updateProgress()
  }

  public func stop(keepError: Bool = false) {
    player?.stop()
    player = nil
    timer?.invalidate()
    timer = nil
    activeId = nil
    isPlaying = false
    progress = 0
    duration = 0
    if !keepError { errorMessage = nil }
  }

  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { stop() }
  private func updateProgress() {
    guard let player else { return }
    progress = player.duration > 0 ? player.currentTime / player.duration : 0
    isPlaying = player.isPlaying
  }
}

public struct CaptroCompactVoicePlayer: View {
  @ObservedObject private var center = CaptroVoicePlaybackCenter.shared
  public let voiceId: String
  public let durationMs: Int
  public let waveform: [Float]?
  public let onTranscript: () -> Void

  public init(voiceId: String, durationMs: Int, waveform: [Float]? = nil, onTranscript: @escaping () -> Void) {
    self.voiceId = voiceId; self.durationMs = durationMs; self.waveform = waveform; self.onTranscript = onTranscript
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button { Task { await center.toggle(id: voiceId) } } label: {
          Image(systemName: center.activeId == voiceId && center.isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 44, height: 44)
            .background(MIRATheme.Color.surfaceSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(center.activeId == voiceId && center.isPlaying ? "Pause recording" : "Play recording")
        Slider(value: Binding(get: { center.activeId == voiceId ? center.progress : 0 }, set: { center.seek(id: voiceId, progress: $0) }))
          .tint(MIRATheme.Color.forest)
          .accessibilityLabel("Recording progress")
        Text(time(center.activeId == voiceId ? center.duration : Double(durationMs) / 1000))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Button("Read transcript", action: onTranscript)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.forest)
    }
  }

  private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

public struct CaptroVoiceTranscriptSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var transcript: String?
  @State private var errorMessage: String?
  private let voiceId: String
  private let session = MIRAKeychainSessionProvider()

  public init(voiceId: String) { self.voiceId = voiceId }

  public var body: some View {
    NavigationStack {
      Group {
        if let transcript {
          ScrollView { Text(transcript).frame(maxWidth: .infinity, alignment: .leading).padding(20).textSelection(.enabled) }
        } else if let errorMessage {
          ContentUnavailableView("Transcript unavailable", systemImage: "text.bubble", description: Text(errorMessage))
        } else {
          ProgressView("Loading transcript…")
        }
      }
      .navigationTitle("Transcript")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
  }

  private func load() async {
    do {
      var request = URLRequest(url: MIRAProductionBackend.apiURL("voice/\(voiceId)/transcript"))
      if let token = await session.accessToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
      let (data, response) = try await MIRAAPIClient.productionSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MIRAAPIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0) }
      struct Payload: Decodable { let transcript: String? }
      let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
      transcript = try decoder.decode(Payload.self, from: data).transcript
      if transcript?.isEmpty != false { errorMessage = "No approved transcript is available." }
    } catch { errorMessage = "Captro could not load this transcript." }
  }
}
