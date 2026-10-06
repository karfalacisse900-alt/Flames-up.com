import SwiftUI

/// Native vector layers transcribed from CaptroVoiceCharacter.svg (512-unit viewBox).
/// The SVG, not the flattened PNG's opaque color disks, defines the material.
/// Only idle motion/blinking use a clock. Speech mouth movement uses rendered audio.
struct CaptroVoiceCharacterView: View {
  let state: CaptroVoiceVisualState
  @State private var blink = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 400, geometry.size.height / 432)
      TimelineView(.animation(minimumInterval: 1 / 30, paused: !state.permitsIdleMotion)) { context in
        let breath = state.permitsIdleMotion ? sin(context.date.timeIntervalSinceReferenceDate * .pi / 3.2) : 0
        ZStack {
          Ellipse().fill(Color(red: 0.4, green: 0.44, blue: 0.42).opacity(0.16))
            .frame(width: 210, height: 36).blur(radius: 14).position(x: 256, y: 447)
          ZStack {
            CaptroCharacterBody()
              .fill(RadialGradient(stops: [
                .init(color: Color(red: 1, green: 0.992, blue: 0.969), location: 0),
                .init(color: Color(red: 0.949, green: 0.953, blue: 0.918), location: 0.58),
                .init(color: Color(red: 0.906, green: 0.933, blue: 0.910), location: 0.82),
                .init(color: Color(red: 0.867, green: 0.851, blue: 0.918), location: 1)
              ], center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: 278))
            Ellipse().fill(.white.opacity(0.20))
              .frame(width: 164, height: 88).blur(radius: 9).position(x: 195, y: 135)
              .mask(CaptroCharacterBody())
            CaptroCharacterDimple().fill(Color(red: 0.969, green: 0.957, blue: 0.937).opacity(0.78))
            face
          }
          .scaleEffect(1 + breath * 0.006)
          .offset(y: breath * 2.5)
          .rotationEffect(.degrees(state.expression == .thinking && !reduceMotion ? 2 : attentiveLevel * 1.2))
        }
        .frame(width: 512, height: 512)
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
    ZStack {
      HStack(spacing: 88) { eye; eye }
        .scaleEffect(x: 1, y: blink ? 0.08 : (state.expression == .thinking ? 0.82 : 1))
        .position(x: 256 + attentiveLevel * 3, y: 249)
      ZStack {
        if state.isSpeaking && !reduceMotion && state.playbackAmplitude > 0.008 {
          Ellipse().fill(Color(red: 0.09, green: 0.10, blue: 0.09))
            .frame(width: 24, height: 4 + min(1, max(0, state.playbackAmplitude)) * 28)
        } else {
          CaptroCharacterSmile().stroke(Color(red: 0.09, green: 0.10, blue: 0.09),
            style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .frame(width: state.expression == .happy || state.expression == .joking ? 29 : 24, height: 10)
        }
      }.frame(width: 34, height: 24).position(x: 256, y: 307)
    }
  }
  private var eye: some View {
    Capsule().fill(Color(red: 0.09, green: 0.10, blue: 0.09))
      .frame(width: 20, height: 48)
      .overlay(alignment: .topLeading) {
        Ellipse().fill(.white.opacity(0.34)).frame(width: 8, height: 14).offset(x: 3, y: 1)
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
    path.move(to: CGPoint(x: 256, y: 65))
    path.addCurve(to: CGPoint(x: 428, y: 248), control1: CGPoint(x: 365, y: 65), control2: CGPoint(x: 428, y: 137))
    path.addCurve(to: CGPoint(x: 253, y: 421), control1: CGPoint(x: 428, y: 354), control2: CGPoint(x: 359, y: 421))
    path.addCurve(to: CGPoint(x: 83, y: 251), control1: CGPoint(x: 148, y: 421), control2: CGPoint(x: 83, y: 355))
    path.addCurve(to: CGPoint(x: 256, y: 65), control1: CGPoint(x: 83, y: 143), control2: CGPoint(x: 148, y: 65))
    path.closeSubpath()
    return path.applying(CGAffineTransform(scaleX: rect.width / 512, y: rect.height / 512))
  }
}
private struct CaptroCharacterDimple: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 403, y: 180))
    path.addCurve(to: CGPoint(x: 413, y: 216), control1: CGPoint(x: 415, y: 188), control2: CGPoint(x: 419, y: 203))
    path.addCurve(to: CGPoint(x: 388, y: 234), control1: CGPoint(x: 408, y: 226), control2: CGPoint(x: 399, y: 232))
    path.addCurve(to: CGPoint(x: 392, y: 188), control1: CGPoint(x: 396, y: 220), control2: CGPoint(x: 398, y: 202))
    path.addCurve(to: CGPoint(x: 403, y: 180), control1: CGPoint(x: 395, y: 183), control2: CGPoint(x: 399, y: 180))
    path.closeSubpath()
    return path.applying(CGAffineTransform(scaleX: rect.width / 512, y: rect.height / 512))
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
