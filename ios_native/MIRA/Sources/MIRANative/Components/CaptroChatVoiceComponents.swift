import AVFoundation
import SwiftUI
import UIKit

/// Deliberate human voice messages. Never starts an AI session or transcription.
struct CaptroChatVoiceRecorderSheet: View {
  let onSend: (URL) -> Void
  @StateObject private var recorder = CaptroVoiceRecorder(limit: 60)
  @State private var startTask: Task<Void, Never>?
  @State private var keptRecording = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Text(clock(recorder.duration)).font(.title2.monospacedDigit())
        if recorder.isRecording {
          ProgressView(value: Double(recorder.level)).tint(MIRATheme.Color.forest)
            .accessibilityLabel("Microphone level")
          Button("Stop recording") { recorder.stop() }.frame(minHeight: 44)
        } else if let file = recorder.fileURL, recorder.hasUsableRecording {
          CaptroChatAudioMessage(url: file.absoluteString, identifier: file.lastPathComponent)
          Button("Retake") { recorder.reset() }.frame(minHeight: 44)
        } else {
          Button("Record voice message") {
            guard startTask == nil else { return }
            startTask = Task { await recorder.start(); startTask = nil }
          }.frame(minHeight: 44)
        }
        if let error = recorder.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
      }.padding(24).frame(maxWidth: .infinity)
      .navigationTitle("Voice message").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send") {
            guard recorder.hasUsableRecording, let file = recorder.fileURL else { return }
            keptRecording = true; onSend(file); dismiss()
          }.disabled(!recorder.hasUsableRecording).tint(MIRATheme.Color.forest)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .onDisappear {
      startTask?.cancel(); startTask = nil; recorder.stop()
      if !keptRecording { recorder.reset() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { note in
      if let reason = note.object as? String, reason.hasPrefix("account_") { dismiss() }
    }
  }
  private func clock(_ value: Double) -> String {
    let seconds = max(0, Int(value)); return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

struct CaptroChatAudioMessage: View {
  let url: String
  let identifier: String
  @StateObject private var playback = CaptroChatAudioPlayback()
  private var reason: String { "chat_voice_started:\(identifier)" }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Button { playback.toggle(url: url, reason: reason) } label: {
          Group {
            if playback.loading { ProgressView() }
            else { Image(systemName: playback.playing ? "pause.fill" : "play.fill") }
          }.frame(width: 44, height: 44)
        }.accessibilityLabel(playback.playing ? "Pause voice message" : "Play voice message")
        Text("Voice message").font(.subheadline)
        if playback.duration > 0 {
          Text(String(format: "%d:%02d", Int(playback.duration) / 60, Int(playback.duration) % 60))
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      if let error = playback.error { Text(error).font(.caption).foregroundStyle(.secondary) }
    }.buttonStyle(.plain).foregroundStyle(MIRATheme.Color.textPrimary)
    .onDisappear { playback.stop() }
    .onChange(of: url) { _, _ in playback.stop() }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { note in
      if (note.object as? String) != reason { playback.stop() }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in playback.stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
      if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { playback.stop() }
    }
  }
}

@MainActor private final class CaptroChatAudioPlayback: ObservableObject {
  @Published var playing = false
  @Published var loading = false
  @Published var duration: Double = 0
  @Published var error: String?
  private var player: AVPlayer?
  private var observation: NSKeyValueObservation?
  private var itemObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var generation = 0
  func toggle(url: String, reason: String) {
    if let player {
      if playing { player.pause() }
      else { MIRAPlaybackCoordinator.pauseAll(reason: reason); player.play() }
      return
    }
    guard let source = URL(string: url), source.isFileURL || source.scheme == "https" else {
      error = "This recording is unavailable."; return
    }
    stop(); error = nil
    do {
      MIRAPlaybackCoordinator.pauseAll(reason: reason)
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try AVAudioSession.sharedInstance().setActive(true)
      let current = generation
      let next = AVPlayer(url: source)
      player = next
      observation = next.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
        let status = player.timeControlStatus
        Task { @MainActor in
          guard self?.generation == current else { return }
          self?.playing = status == .playing
          self?.loading = status == .waitingToPlayAtSpecifiedRate
        }
      }
      itemObservation = next.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
        let status = item.status; let seconds = item.duration.seconds
        Task { @MainActor in
          guard self?.generation == current else { return }
          if status == .failed { self?.stop(); self?.error = "Couldn't play this recording. Try again." }
          else if seconds.isFinite { self?.duration = max(0, seconds) }
        }
      }
      endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
        object: next.currentItem, queue: .main) { [weak self] _ in
          Task { @MainActor in guard self?.generation == current else { return }; self?.stop() }
        }
      next.play()
    } catch { stop(); self.error = "Couldn't play this recording. Try again." }
  }
  func stop() {
    generation += 1
    observation?.invalidate(); observation = nil
    itemObservation?.invalidate(); itemObservation = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
    player?.pause(); player = nil; playing = false; loading = false
  }
}
