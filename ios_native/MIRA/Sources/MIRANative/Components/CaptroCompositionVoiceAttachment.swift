import AVFoundation
import SwiftUI

struct CaptroCompositionVoiceAttachment: View {
  let recording: CaptroVoiceDraft
  let onReplace: () -> Void
  let onRemove: () -> Void
  @State private var player: AVAudioPlayer?
  @State private var playing = false
  @State private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 10) {
        Button { toggle() } label: {
          Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
        }.accessibilityLabel(playing ? "Pause recording" : "Play recording")
        Text(String(format: "%d:%02d", Int(recording.duration) / 60, Int(recording.duration) % 60))
          .font(.subheadline.monospacedDigit())
        Spacer()
        Menu {
          Button("Replace recording") { stop(); onReplace() }
          Button("Remove recording", role: .destructive) { stop(); onRemove() }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
          .accessibilityLabel("Voice attachment options")
      }
      if let error { Text(error).font(.footnote).foregroundStyle(.red) }
    }
    .buttonStyle(.plain).foregroundStyle(MIRATheme.Color.textSecondary)
    .onDisappear { stop() }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { note in
      if (note.object as? String) != "composition_voice_preview" { stop() }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
      // Changing to our own playback category is not a headphone disconnect.
      // Stop only when output disappears, so private audio never jumps to the speaker.
      if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { stop() }
    }
    .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
      if playing && player?.isPlaying == false { stop() }
    }
  }
  private func toggle() {
    if playing {
      player?.pause(); playing = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      return
    }
    do {
      MIRAPlaybackCoordinator.pauseAll(reason: "composition_voice_preview")
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try AVAudioSession.sharedInstance().setActive(true)
      let next: AVAudioPlayer
      if let current = player { next = current }
      else { next = try AVAudioPlayer(contentsOf: recording.fileURL) }
      guard next.play() else { throw MIRAAPIError.emptyResponse }
      player = next; playing = true; error = nil
    } catch {
      player = nil; playing = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      self.error = "Could not play this recording. You can replace it."
    }
  }
  private func stop() {
    guard player != nil else { return }
    player?.stop(); player = nil; playing = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

