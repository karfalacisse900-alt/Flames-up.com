import SwiftUI

/// A sibling overlay of the media tap surface, never a gesture on the pager.
/// Home keeps playback state row-local; Details retains its existing ownership.
struct CaptroVideoControls: View {
  @Binding var isPaused: Bool
  @Binding var isMuted: Bool
  let surface: String

  var body: some View {
    HStack(spacing: 0) {
      control(icon: isPaused ? "play.fill" : "pause.fill",
        label: isPaused ? "Play video" : "Pause video", id: "play") { isPaused.toggle() }
      control(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
        label: isMuted ? "Unmute video" : "Mute video", id: "mute") { isMuted.toggle() }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("\(surface).video.controls")
  }

  private func control(icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white).frame(width: 30, height: 30)
        .background(.black.opacity(0.65), in: Circle())
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label).accessibilityIdentifier("\(surface).video.\(id)")
  }
}
