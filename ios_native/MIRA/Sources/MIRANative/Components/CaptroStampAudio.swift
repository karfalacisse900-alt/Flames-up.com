import AVFoundation
import SwiftUI
import UIKit

/// Real attachments, inside the Stamp surface; never inside its navigation Button.
struct CaptroStampAudio: View {
  let post: MIRAPost
  let api: MIRAAPIClient
  var isActive = true
  @State private var transcript = false
  @StateObject private var music = CaptroStampMusicPlayback()
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let voice = post.detail?.voice {
        CaptroCompactVoicePlayer(voiceId: voice.id, durationMs: voice.durationMs, waveform: voice.waveform) { transcript = true }
          .accessibilityIdentifier("stamp.voice")
      }
      if post.hasAudio {
        HStack(spacing: 8) {
          Button { Task { await music.toggle(post: post, api: api) } } label: {
            Group {
              if music.loading { ProgressView() }
              else { Image(systemName: music.playing ? "pause.fill" : "play.fill") }
            }.frame(width: 44, height: 44)
          }.disabled(music.loading)
            .accessibilityLabel(music.playing ? "Pause attached music" : "Play attached music")
          VStack(alignment: .leading, spacing: 2) {
            Text(post.audioDisplayTitle ?? "Music").font(.subheadline).lineLimit(2)
            Text(post.audioDisplayArtist ?? "Audius").font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }.accessibilityIdentifier("stamp.music")
        if let error = music.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
      }
    }
    .buttonStyle(.plain).foregroundStyle(MIRATheme.Color.textPrimary)
    .sheet(isPresented: $transcript) {
      if let voice = post.detail?.voice { CaptroVoiceTranscriptSheet(voiceId: voice.id) }
    }
    .onDisappear { stopOwnedPlayback() }
    .onChange(of: isActive) { _, active in if !active { stopOwnedPlayback() } }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { note in
      if (note.object as? String) != "stamp_music_started:\(post.id)" { music.stop() }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in music.stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in music.stop() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
      if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { music.stop() }
    }
  }
  private func stopOwnedPlayback() {
    music.stop()
    if let voice = post.detail?.voice, CaptroVoicePlaybackCenter.shared.activeId == voice.id {
      CaptroVoicePlaybackCenter.shared.stop()
    }
  }
}

@MainActor private final class CaptroStampMusicPlayback: ObservableObject {
  @Published var playing = false
  @Published var loading = false
  @Published var error: String?
  private var player: AVPlayer?
  private var observation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var generation = 0
  func toggle(post: MIRAPost, api: MIRAAPIClient) async {
    guard !MIRAPlaybackCoordinator.isLiveVoiceActive else { return }
    if let player {
      if playing { player.pause(); playing = false }
      else { MIRAPlaybackCoordinator.pauseAll(reason: "stamp_music_started:\(post.id)"); player.play() }
      return
    }
    loading = true; error = nil
    let current = generation
    do {
      var stream = post.audioStreamUrl
      if stream?.isEmpty != false, let trackID = post.audioTrackId?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
        let track: MIRAAudiusTrack = try await api.get("/music/audius/stream/\(trackID)")
        stream = track.streamUrl
      }
      guard current == generation, !Task.isCancelled else { return }
      guard !MIRAPlaybackCoordinator.isLiveVoiceActive else { stop(); return }
      guard let stream, let url = URL(string: stream), url.scheme == "https" else { throw MIRAAPIError.emptyResponse }
      MIRAPlaybackCoordinator.pauseAll(reason: "stamp_music_started:\(post.id)")
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      let next = AVPlayer(url: url)
      player = next
      statusObservation = next.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .failed else { return }
        Task { @MainActor in
          guard self?.generation == current else { return }
          self?.stop(); self?.error = "Music couldn’t play. Try again."
        }
      }
      observation = next.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
        let state = player.timeControlStatus
        Task { @MainActor in
          guard self?.generation == current else { return }
          self?.playing = state == .playing
          self?.loading = state == .waitingToPlayAtSpecifiedRate
        }
      }
      if let start = post.audioStartTime, start > 0 {
        await next.seek(to: CMTime(seconds: Double(start), preferredTimescale: 600))
        guard current == generation, !Task.isCancelled,
              !MIRAPlaybackCoordinator.isLiveVoiceActive else { return }
      }
      if let duration = post.audioDuration, duration > 0 {
        next.currentItem?.forwardPlaybackEndTime = CMTime(seconds: Double((post.audioStartTime ?? 0) + duration), preferredTimescale: 600)
      }
      next.play(); loading = false
    } catch {
      guard current == generation else { return }
      stop(); self.error = "Music couldn’t play. Try again."
    }
  }
  func stop() {
    generation += 1
    observation?.invalidate(); observation = nil
    statusObservation?.invalidate(); statusObservation = nil
    player?.pause(); player = nil; playing = false; loading = false
  }
}
