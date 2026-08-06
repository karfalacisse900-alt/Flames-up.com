import SwiftUI

struct MIRAWallSignatureInkView: View {
  let drawing: MIRAWallSignatureDrawing
  var tint: Color = Color(red: 0.08, green: 0.075, blue: 0.065)
  var lineWidth: CGFloat = 2.4

  var body: some View {
    Canvas { context, size in
      for stroke in drawing.strokes where !stroke.points.isEmpty {
        let points = stroke.points.map { point in
          CGPoint(
            x: CGFloat(point.x) * size.width,
            y: CGFloat(point.y) * size.height
          )
        }
        if points.count == 1, let point = points.first {
          let radius = max(1.1, lineWidth * 0.52)
          context.fill(
            Path(ellipseIn: CGRect(
              x: point.x - radius,
              y: point.y - radius,
              width: radius * 2,
              height: radius * 2
            )),
            with: .color(tint.opacity(0.92))
          )
          continue
        }

        let path = smoothedPath(points)
        context.stroke(
          path,
          with: .color(tint.opacity(0.18)),
          style: StrokeStyle(
            lineWidth: lineWidth + 1.1,
            lineCap: .round,
            lineJoin: .round
          )
        )
        context.stroke(
          path,
          with: .color(tint.opacity(0.94)),
          style: StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func smoothedPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 2 else {
      if let last = points.last { path.addLine(to: last) }
      return path
    }

    for index in 1..<(points.count - 1) {
      let point = points[index]
      let next = points[index + 1]
      let midpoint = CGPoint(x: (point.x + next.x) * 0.5, y: (point.y + next.y) * 0.5)
      path.addQuadCurve(to: midpoint, control: point)
    }
    if let last = points.last { path.addLine(to: last) }
    return path
  }
}

struct MIRAWallSignatureCaptureView: View {
  let isSaving: Bool
  let errorMessage: String?
  let onCancel: () -> Void
  let onSubmit: (MIRAWallSignatureDrawing) -> Void

  @State private var strokes: [MIRAWallSignatureStroke] = []
  @State private var activePoints: [MIRAWallSignaturePoint] = []

  private let maximumStrokeCount = 12
  private let maximumPointCount = 600
  private let maximumPointsPerStroke = 180

  var body: some View {
    VStack(spacing: 18) {
      header

      VStack(alignment: .leading, spacing: 6) {
        Text("Draw your signature")
          .font(.system(size: 24, weight: .bold, design: .serif))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text("Use your finger. Captro saves the pen strokes, not a screenshot.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      signaturePad

      HStack(spacing: 10) {
        Button {
          guard !isSaving, !strokes.isEmpty else { return }
          strokes.removeLast()
        } label: {
          Label("Undo", systemImage: "arrow.uturn.backward")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.miraPress)
        .disabled(isSaving || strokes.isEmpty)

        Button {
          guard !isSaving else { return }
          strokes.removeAll(keepingCapacity: true)
          activePoints.removeAll(keepingCapacity: true)
        } label: {
          Label("Clear", systemImage: "eraser")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.miraPress)
        .disabled(isSaving || drawing.isEmpty)
      }
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(MIRATheme.Color.textPrimary)

      if let errorMessage, !errorMessage.isEmpty {
        Text(errorMessage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        guard !drawing.isEmpty, !isSaving else { return }
        onSubmit(drawing)
      } label: {
        HStack(spacing: 10) {
          if isSaving {
            ProgressView().tint(.white)
          } else {
            Image(systemName: "pencil.and.scribble")
          }
          Text(isSaving ? "Signing..." : "Sign this note")
            .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(MIRATheme.Color.forest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .buttonStyle(.miraPress)
      .disabled(drawing.isEmpty || isSaving)
      .accessibilityHint("Adds this handwritten signature to the note.")
    }
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 22)
    .background(MIRATheme.Color.surface)
  }

  private var header: some View {
    HStack {
      Button("Cancel", action: onCancel)
        .disabled(isSaving)
      Spacer()
      Text("Signature")
        .font(.system(size: 16, weight: .bold))
      Spacer()
      Text("Cancel")
        .hidden()
        .accessibilityHidden(true)
    }
    .font(.system(size: 15, weight: .semibold))
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .frame(minHeight: 44)
  }

  private var signaturePad: some View {
    GeometryReader { proxy in
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(red: 0.973, green: 0.955, blue: 0.895))

        Canvas { context, size in
          var baseline = Path()
          baseline.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.74))
          baseline.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.74))
          context.stroke(baseline, with: .color(Color.black.opacity(0.12)), lineWidth: 0.8)

          let hash = MIRAWallNotePresentationResolver.stableHash("signature-paper")
          for index in 0..<20 {
            let x = size.width * MIRAWallMaterialNoise.unit(hash, index * 3)
            let y = size.height * MIRAWallMaterialNoise.unit(hash, index * 3 + 1)
            let length = 3 + MIRAWallMaterialNoise.unit(hash, index * 3 + 2) * 8
            var fiber = Path()
            fiber.move(to: CGPoint(x: x, y: y))
            fiber.addLine(to: CGPoint(x: x + length, y: y + 0.3))
            context.stroke(fiber, with: .color(Color.black.opacity(0.025)), lineWidth: 0.5)
          }
        }
        .allowsHitTesting(false)

        if drawing.isEmpty {
          Text("Sign here")
            .font(.system(size: 17, weight: .medium, design: .serif))
            .foregroundStyle(MIRATheme.Color.textMuted.opacity(0.72))
            .allowsHitTesting(false)
        }

        MIRAWallSignatureInkView(drawing: drawing, lineWidth: 2.65)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Color.black.opacity(0.10), lineWidth: 0.8)
      }
      .shadow(color: .black.opacity(0.07), radius: 9, y: 5)
      .contentShape(Rectangle())
      .gesture(signatureGesture(size: proxy.size))
      .accessibilityLabel("Signature drawing area")
      .accessibilityHint("Drag one finger to draw your signature.")
    }
    .frame(height: 190)
  }

  private var drawing: MIRAWallSignatureDrawing {
    let active = activePoints.count >= 2 ? [MIRAWallSignatureStroke(points: activePoints)] : []
    return MIRAWallSignatureDrawing(strokes: strokes + active)
  }

  private func signatureGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        guard !isSaving,
              size.width > 0,
              size.height > 0,
              strokes.count < maximumStrokeCount,
              totalPointCount < maximumPointCount,
              activePoints.count < maximumPointsPerStroke else { return }

        let x = min(1, max(0, Double(value.location.x / size.width)))
        let y = min(1, max(0, Double(value.location.y / size.height)))
        let point = MIRAWallSignaturePoint(x: rounded(x), y: rounded(y))
        if let last = activePoints.last {
          let dx = (point.x - last.x) * Double(size.width)
          let dy = (point.y - last.y) * Double(size.height)
          guard hypot(dx, dy) >= 1.8 else { return }
        }
        activePoints.append(point)
      }
      .onEnded { _ in
        guard !isSaving else { return }
        if activePoints.count >= 2, strokes.count < maximumStrokeCount {
          strokes.append(MIRAWallSignatureStroke(points: activePoints))
        }
        activePoints.removeAll(keepingCapacity: true)
      }
  }

  private var totalPointCount: Int {
    strokes.reduce(activePoints.count) { $0 + $1.points.count }
  }

  private func rounded(_ value: Double) -> Double {
    (value * 10_000).rounded() / 10_000
  }
}
