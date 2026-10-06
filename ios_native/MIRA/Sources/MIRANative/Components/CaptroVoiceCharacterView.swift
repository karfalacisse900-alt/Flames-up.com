import SwiftUI

/// Native layers reconstructed from the supplied Captro PNG/SVG, not a screenshot.
/// Only idle motion/blinking use a clock. Speech mouth movement uses rendered audio.
struct CaptroVoiceCharacterView: View {
  let state: CaptroVoiceVisualState
  @State private var blink = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 760, geometry.size.height / 820)
      TimelineView(.animation(minimumInterval: 1 / 30, paused: !state.permitsIdleMotion)) { context in
        let breath = state.permitsIdleMotion ? sin(context.date.timeIntervalSinceReferenceDate * .pi / 3.2) : 0
        ZStack {
          Ellipse().fill(Color(red: 0.4, green: 0.44, blue: 0.42).opacity(0.17))
            .frame(width: 410, height: 70).blur(radius: 28).offset(y: 367)
          ZStack {
            CaptroCharacterBody()
              .fill(RadialGradient(colors: [Color(red: 1, green: 0.994, blue: 0.968),
                Color(red: 0.937, green: 0.953, blue: 0.927)],
                center: .topLeading, startRadius: 30, endRadius: 710))
              .frame(width: 686, height: 690)
            // Reference's warm cheek, lavender side, and soft upper highlights.
            Ellipse().fill(Color(red: 1, green: 0.913, blue: 0.788))
              .frame(width: 346, height: 281).offset(x: -164, y: 173)
            Ellipse().fill(Color(red: 0.873, green: 0.853, blue: 0.965))
              .frame(width: 302, height: 351).offset(x: 158, y: 51)
            Ellipse().fill(Color(red: 1, green: 1, blue: 0.98))
              .frame(width: 346, height: 186).offset(x: -115, y: -216)
            Ellipse().fill(Color(red: 0.98, green: 0.97, blue: 0.95).opacity(0.8))
              .frame(width: 85, height: 146).offset(x: 295, y: -102)
              .mask(CaptroCharacterBody().frame(width: 686, height: 690))
            face.offset(y: 28)
          }
          .scaleEffect(1 + breath * 0.006)
          .offset(y: breath * 5)
          .rotationEffect(.degrees(state.expression == .thinking && !reduceMotion ? 2 : attentiveLevel * 1.2))
        }
        .frame(width: 760, height: 820)
        .scaleEffect(scale)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
      }
    }
    .task(id: state.permitsBlinking) {
      blink = false
      guard state.permitsBlinking else { return }
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(Double.random(in: 3...6))) }
        catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.07)) { blink = true }
        do { try await Task.sleep(for: .milliseconds(70)) } catch { blink = false; return }
        withAnimation(.easeInOut(duration: 0.07)) { blink = false }
      }
    }
  }

  private var face: some View {
    VStack(spacing: 63) {
      HStack(spacing: 174) { eye; eye }
        .scaleEffect(x: 1, y: blink ? 0.08 : (state.expression == .thinking ? 0.82 : 1))
        .offset(x: attentiveLevel * 7)
      ZStack {
        if state.isSpeaking && !reduceMotion && state.playbackAmplitude > 0.008 {
          Ellipse().fill(Color(red: 0.09, green: 0.10, blue: 0.09))
            .frame(width: 48, height: 9 + min(1, max(0, state.playbackAmplitude)) * 65)
        } else {
          CaptroCharacterSmile().stroke(Color(red: 0.09, green: 0.10, blue: 0.09),
            style: StrokeStyle(lineWidth: 11, lineCap: .round))
            .frame(width: state.expression == .happy || state.expression == .joking ? 60 : 46, height: 18)
        }
      }.frame(width: 65, height: 24)
    }
  }
  private var eye: some View {
    Capsule().fill(Color(red: 0.09, green: 0.10, blue: 0.09))
      .frame(width: 41, height: 96)
      .overlay(alignment: .topLeading) {
        Ellipse().fill(.white).frame(width: 11, height: 18).offset(x: 10, y: 13)
      }
  }
  private var attentiveLevel: Double {
    guard !reduceMotion, state.expression == .attentive, !state.isSpeaking, !state.isMuted else { return 0 }
    return Double(min(1, max(0, state.microphoneAmplitude)))
  }
}

private struct CaptroCharacterBody: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0.5, y: 0))
    path.addCurve(to: CGPoint(x: 1, y: 0.5), control1: CGPoint(x: 0.8, y: 0), control2: CGPoint(x: 1, y: 0.23))
    path.addCurve(to: CGPoint(x: 0.5, y: 1), control1: CGPoint(x: 1, y: 0.81), control2: CGPoint(x: 0.8, y: 1))
    path.addCurve(to: CGPoint(x: 0, y: 0.5), control1: CGPoint(x: 0.19, y: 1), control2: CGPoint(x: 0, y: 0.82))
    path.addCurve(to: CGPoint(x: 0.5, y: 0), control1: CGPoint(x: 0, y: 0.2), control2: CGPoint(x: 0.2, y: 0))
    path.closeSubpath()
    return path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
  }
}
private struct CaptroCharacterSmile: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.midX, y: rect.height))
    return path
  }
}
