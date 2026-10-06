import SwiftUI

/// Renderer-independent signals for the reference artwork, once supplied.
/// Playback amplitude comes only from the actual native output tap. Expressions
/// are optional hooks, not inferred emotional claims about the user or model.
struct CaptroVoiceVisualState: Equatable {
  enum Expression: Equatable { case neutral, attentive, thinking, happy, joking, error }
  let expression: Expression
  let microphoneAmplitude: CGFloat
  let playbackAmplitude: CGFloat
  let isSpeaking: Bool
  let isMuted: Bool
  let permitsIdleMotion: Bool
  let permitsBlinking: Bool

  @MainActor init(session: CaptroRealtimeVoiceSession, active: Bool, reduceMotion: Bool,
    expressionOverride: Expression? = nil) {
    isMuted = session.muted
    isSpeaking = session.activity == .assistantSpeaking
    microphoneAmplitude = session.muted || session.connection != .ready ? 0 : session.microphoneLevel
    playbackAmplitude = isSpeaking ? session.playbackLevel : 0
    permitsIdleMotion = active && session.connection == .ready && !reduceMotion
    permitsBlinking = permitsIdleMotion
    if session.connection == .failed { expression = .error }
    else if session.activity == .waitingForResponse { expression = .thinking }
    else if session.connection == .ready { expression = expressionOverride ?? .attentive }
    else { expression = .neutral }
  }
}

/// Reference-based artwork is replaceable without changing audio ownership.
struct CaptroVoiceVisualStage: View {
  let state: CaptroVoiceVisualState
  var body: some View { CaptroVoiceCharacterView(state: state).accessibilityHidden(true) }
}
