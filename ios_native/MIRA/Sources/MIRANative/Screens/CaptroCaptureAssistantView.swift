import AVFoundation
import SwiftUI

enum CaptroAssistantEditorDestination: Equatable { case story, post }
public struct CaptroAssistantEditPlan: Decodable {
  public let trimStartSeconds: Double?
  public let trimDurationSeconds: Double?
  public init(trimStartSeconds: Double?, trimDurationSeconds: Double?) {
    self.trimStartSeconds = trimStartSeconds; self.trimDurationSeconds = trimDurationSeconds
  }
}

struct CaptroCaptureAssistantView: View {
  let api: MIRAAPIClient
  let hasCurrentRecording: Bool
  var currentRecordingID: String? = nil
  let onClose: () -> Void
  let onOpenEditor: (CaptroAssistantEditorDestination, CaptroAssistantEditPlan) -> Void
  @StateObject private var session = CaptroRealtimeVoiceSession()
  @State private var showsTranscript = false
  @State private var showsDisclosure = false
  @AppStorage("captro.ai.liveVoice.disclosure.v1") private var acceptedDisclosure = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          HStack {
            Spacer()
            Menu {
              Button("Transcript", systemImage: "text.bubble") { showsTranscript = true }
              Menu("Audio output") {
                Text("Current: \(session.outputName)")
                Button("iPhone") { session.selectOutput(speaker: false) }
                Button("Speaker") { session.selectOutput(speaker: true) }
                ForEach(session.availableInputs.filter { $0.portType != .builtInMic }, id: \.uid) { input in
                  Button(input.portName) { session.selectOutput(speaker: false, input: input) }
                }
              }.disabled(session.connection != .ready)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Conversation options")
          }.foregroundStyle(MIRATheme.Color.textSecondary)
          Text(connectionLabel).font(.caption).foregroundStyle(MIRATheme.Color.textSecondary)
          Text("Captro AI").font(.title2.weight(.semibold)).foregroundStyle(MIRATheme.Color.textPrimary).padding(.top, 6)
          CaptroVoiceVisualStage(state: CaptroVoiceVisualState(session: session,
            active: scenePhase == .active, reduceMotion: reduceMotion))
            .frame(width: min(280, geometry.size.width - 72), height: min(280, geometry.size.width - 72))
            .padding(.top, 48).padding(.bottom, 38)
          TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsed(at: context.date)).font(.subheadline.monospacedDigit())
              .foregroundStyle(MIRATheme.Color.textSecondary).accessibilityLabel("Conversation duration")
          }
          Text(session.status).font(.body.weight(.medium)).foregroundStyle(MIRATheme.Color.textPrimary)
            .padding(.top, 10).accessibilityAddTraits(.updatesFrequently)
          if session.muted && session.phase == .captroSpeaking {
            Text("Microphone muted").font(.caption).foregroundStyle(.secondary).padding(.top, 5)
          }
          if session.connection == .failed {
            Text(session.failureMessage).font(.footnote).foregroundStyle(.secondary)
              .multilineTextAlignment(.center).padding(.top, 10)
            Button("Try Again") { start() }.tint(MIRATheme.Color.forest).frame(minHeight: 44).padding(.top, 8)
          } else if session.connection == .ended {
            Button("Start conversation") { start() }.tint(MIRATheme.Color.forest).frame(minHeight: 44)
          }
          if let notice = session.recoveryNotice, session.connection == .ready {
            Text(notice).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 8)
          }
          if let action = session.suggestedAction, hasCurrentRecording {
            Button(action == .story ? "Review Story" : "Review Post") {
              let plan = session.suggestedEditPlan; session.stop(); onOpenEditor(action, plan)
            }.tint(MIRATheme.Color.forest).frame(minHeight: 44).padding(.top, 10)
          }
          Spacer(minLength: 36)
          HStack(spacing: 46) {
            Button { session.toggleMute() } label: {
              Image(systemName: session.muted ? "mic.slash.fill" : "mic.fill").font(.title3)
                .frame(width: 64, height: 64).foregroundStyle(MIRATheme.Color.textPrimary)
                .background(session.muted ? MIRATheme.Color.forest.opacity(0.16) : MIRATheme.Color.surface, in: Circle())
            }
            .disabled(session.connection != .ready)
            .accessibilityLabel(session.muted ? "Unmute microphone" : "Mute microphone")
            .accessibilityValue(session.muted ? "Muted" : "On")
            Button { session.stop(); onClose() } label: {
              Image(systemName: "phone.down.fill").font(.title3).foregroundStyle(.white)
                .frame(width: 64, height: 64).background(Color(red: 0.7, green: 0.25, blue: 0.23), in: Circle())
            }.accessibilityLabel("End conversation")
          }.buttonStyle(.plain).padding(.bottom, 30)
        }.padding(.horizontal, 24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar, .tabBar)
    .sheet(isPresented: $showsTranscript) { transcript }
    .sheet(isPresented: $showsDisclosure) {
      NavigationStack {
        VStack(alignment: .leading, spacing: 18) {
          Text("Talk with Captro AI").font(.title3.weight(.semibold))
          Text("This is an AI voice. OpenAI processes your audio to respond. It is separate from private conversations with other people.")
          Text("The transcript is temporary in this screen. Provider retention follows the configured service terms; this is not end-to-end encryption against the AI provider.")
            .font(.footnote).foregroundStyle(.secondary)
          Button("Continue") { acceptedDisclosure = true; showsDisclosure = false; start() }
            .buttonStyle(.borderedProminent).tint(MIRATheme.Color.forest)
        }.padding(24)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsDisclosure = false; onClose() } } }
      }.presentationDetents([.medium, .large]).interactiveDismissDisabled()
    }
    .task { if acceptedDisclosure { start() } else { showsDisclosure = true } }
    .onDisappear { session.stop() }
    .onChange(of: scenePhase) { _, next in if next == .background { session.suspendForBackground() } }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { session.handleInterruption($0) }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { session.handleRouteChange($0) }
    .onReceive(NotificationCenter.default.publisher(for: .miraPlaybackShouldPause)) { note in
      if let reason = note.object as? String, reason.hasPrefix("account_") { session.stop(); onClose() }
    }
  }
  private func start() {
    Task { await session.connect(api: api, hasCurrentRecording: hasCurrentRecording, currentRecordingID: currentRecordingID) }
  }
  private var connectionLabel: String {
    switch session.connection {
    case .idle: return "AI voice conversation"
    case .requestingPermission: return "Microphone access"
    case .authorizing: return "Authorizing"
    case .connecting: return "Connecting"
    case .ready: return "Connected"
    case .reconnecting: return "Reconnecting"
    case .failed: return "Not connected"
    case .ending, .ended: return "Ended"
    }
  }
  private func elapsed(at date: Date) -> String {
    guard let start = session.startedAt else { return "00:00" }
    let seconds = max(0, Int((session.endedAt ?? date).timeIntervalSince(start)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
  private var transcript: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if session.turns.isEmpty { Text("No transcript yet.").foregroundStyle(.secondary) }
          ForEach(session.turns) { turn in
            VStack(alignment: .leading, spacing: 4) {
              Text(turn.role == "user" ? "You" : "Captro AI").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              Text(turn.text).textSelection(.enabled)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
      }.navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsTranscript = false } } }
    }.presentationDetents([.medium, .large])
  }
}
