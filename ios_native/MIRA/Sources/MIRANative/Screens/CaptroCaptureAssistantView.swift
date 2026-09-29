import AVFoundation
import AVKit
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

struct CaptroCaptureAssistantView: View {
  let api: MIRAAPIClient
  let hasCurrentRecording: Bool
  let onClose: () -> Void
  let onOpenEditor: (CaptroAssistantEditorDestination, CaptroAssistantEditPlan) -> Void
  @StateObject private var session = CaptroRealtimeVoiceSession()
  @State private var showsTranscript = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Spacer(minLength: 40)

        ZStack {
          Circle()
            .stroke(MIRATheme.Color.forest.opacity(0.14), lineWidth: 1)
            .frame(width: 168, height: 168)
          Circle()
            .fill(MIRATheme.Color.forest.opacity(session.phase == .error ? 0.07 : 0.12))
            .frame(width: orbSize, height: orbSize)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: orbSize)
          Image(systemName: session.phase == .error ? "waveform.slash" : "waveform")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(MIRATheme.Color.forest)
            .accessibilityHidden(true)
        }
        .frame(height: 180)
        .accessibilityLabel(session.status)

        Text(session.status)
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .padding(.top, 20)

        if session.phase == .error {
          Text("Captro AI is unavailable right now.")
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .padding(.top, 9)
          Button("Try Again") {
            Task { await session.connect(api: api, hasCurrentRecording: hasCurrentRecording) }
          }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
          .frame(minHeight: 44)
          .padding(.top, 22)
        }

        if showsTranscript && !session.turns.isEmpty {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(session.turns.suffix(8)) { turn in
                  VStack(alignment: .leading, spacing: 3) {
                    Text(turn.role == "user" ? "You" : "Captro")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(MIRATheme.Color.textSecondary)
                    Text(turn.text)
                      .font(.subheadline)
                      .foregroundStyle(MIRATheme.Color.textPrimary)
                      .textSelection(.enabled)
                  }
                  .id(turn.id)
                }
              }
              .padding(.vertical, 12)
            }
            .onChange(of: session.turns.count) { _, _ in
              if let last = session.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
          }
          .frame(maxHeight: 170)
          .padding(.top, 20)
          .accessibilityLabel("Conversation transcript")
        }

        Spacer(minLength: 32)

        if let action = session.suggestedAction, hasCurrentRecording {
          Button(action == .story ? "Review Story" : "Review Post") {
            let plan = session.suggestedEditPlan
            session.stop()
            onOpenEditor(action, plan)
          }
          .buttonStyle(.bordered)
          .tint(MIRATheme.Color.forest)
          .frame(minHeight: 44)
          .padding(.bottom, 20)
        }

        HStack(spacing: 28) {
          Button { session.toggleMute() } label: {
            Image(systemName: session.muted ? "mic.slash" : "mic")
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel(session.muted ? "Unmute microphone" : "Mute microphone")
          .disabled(session.phase == .connecting || session.phase == .reconnecting || session.phase == .error)

          Button { showsTranscript.toggle() } label: {
            Image(systemName: showsTranscript ? "text.bubble.fill" : "text.bubble")
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel(showsTranscript ? "Hide transcript" : "Show transcript")

          CaptroVoiceRoutePicker()
            .frame(width: 44, height: 44)
            .accessibilityLabel("Audio output")
        }
        .foregroundStyle(MIRATheme.Color.forest)
        .padding(.bottom, 24)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 20)
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Voice")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { session.stop(); onClose() }
            .foregroundStyle(MIRATheme.Color.forest)
        }
      }
      .task { await session.connect(api: api, hasCurrentRecording: hasCurrentRecording) }
      .onDisappear { session.stop() }
      .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { session.handleInterruption($0) }
      .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { session.handleRouteChange($0) }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in session.stop() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
        if session.phase != .connecting { Task { await session.connect(api: api, hasCurrentRecording: hasCurrentRecording) } }
      }
    }
  }

  private var orbSize: CGFloat {
    switch session.phase {
    case .userSpeaking, .captroSpeaking: return 108 + session.level * 42
    case .processing: return 114
    case .connecting, .reconnecting, .listening, .error: return 108
    }
  }
}

private struct CaptroVoiceRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.prioritizesVideoDevices = false
    view.tintColor = UIColor(MIRATheme.Color.forest)
    view.activeTintColor = UIColor(MIRATheme.Color.forest)
    return view
  }

  func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
