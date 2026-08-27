import SwiftUI

extension MIRACaptroStudioObject {
  var isCaptroProceduralPaper: Bool {
    switch self {
    case .decklePaper, .gridPaper, .newsprintPaper, .blushPaper,
         .midnightPaper, .textilePaper:
      return true
    default:
      return false
    }
  }

  var isCaptroProceduralDecor: Bool {
    switch self {
    case .sparkleCluster, .starburstFrame, .postageLabel,
         .wavyUnderline, .archiveStamp, .quoteMarks,
         .keepGoingBadge, .makeItCountBadge, .mainCharacterBadge,
         .plotTwistSticker, .noContextSticker, .hahaSticker,
         .moodSticker, .beSeriousSticker, .wovenSun, .wovenBird,
         .diamondTotem, .textileRibbon:
      return true
    default:
      return false
    }
  }
}

struct CaptroStudioProceduralObjectView: View {
  let object: MIRACaptroStudioObject
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      switch object {
      case .decklePaper, .gridPaper, .newsprintPaper, .blushPaper,
           .midnightPaper, .textilePaper:
        CaptroStudioPaperDecor(style: object)

      case .sparkleCluster:
        ZStack {
          Image(systemName: "sparkles")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .padding(size.width * 0.12)
          Circle()
            .fill(CaptroStudioDecorPalette.gold)
            .frame(width: size.width * 0.12)
            .offset(x: size.width * 0.32, y: -size.height * 0.28)
          Circle()
            .fill(CaptroStudioDecorPalette.coral)
            .frame(width: size.width * 0.08)
            .offset(x: -size.width * 0.34, y: size.height * 0.25)
        }

      case .starburstFrame:
        CaptroStudioBurstShape(points: 22, depth: 0.16)
          .stroke(color, lineWidth: max(2, size.width * 0.035))
          .padding(size.width * 0.06)

      case .postageLabel:
        ZStack {
          CaptroStudioDeckleShape(amplitude: 0.025)
            .fill(CaptroStudioDecorPalette.paper)
          CaptroStudioDeckleShape(amplitude: 0.025)
            .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: max(1, size.width * 0.012), dash: [5, 3]))
            .padding(size.width * 0.07)
          VStack(spacing: size.height * 0.06) {
            Text("POST")
              .font(.system(size: max(8, min(size.width * 0.16, size.height * 0.26)), weight: .black, design: .rounded))
            HStack(spacing: size.width * 0.025) {
              ForEach(0..<4, id: \.self) { _ in
                Capsule().fill(color.opacity(0.48))
              }
            }
            .frame(width: size.width * 0.54, height: max(1, size.height * 0.035))
          }
          .foregroundStyle(color)
        }

      case .wavyUnderline:
        Canvas { context, canvasSize in
          var path = Path()
          path.move(to: CGPoint(x: canvasSize.width * 0.04, y: canvasSize.height * 0.56))
          for index in 0...8 {
            let x = canvasSize.width * (0.04 + CGFloat(index) * 0.115)
            let y = canvasSize.height * (index.isMultiple(of: 2) ? 0.38 : 0.68)
            path.addQuadCurve(
              to: CGPoint(x: x, y: y),
              control: CGPoint(x: x - canvasSize.width * 0.045, y: canvasSize.height * 0.53)
            )
          }
          context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: max(2, canvasSize.height * 0.12), lineCap: .round, lineJoin: .round)
          )
        }

      case .archiveStamp:
        CaptroStudioTextSticker(
          text: "ARCHIVE 02",
          background: .clear,
          foreground: color,
          border: color.opacity(0.72),
          fontDesign: .monospaced,
          dashed: true
        )

      case .quoteMarks:
        Text("\"  \"")
          .font(.system(size: max(20, min(size.width * 0.42, size.height * 0.82)), weight: .black, design: .serif))
          .foregroundStyle(color)
          .minimumScaleFactor(0.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .keepGoingBadge:
        CaptroStudioTextSticker(
          text: "KEEP GOING",
          background: CaptroStudioDecorPalette.sage,
          foreground: CaptroStudioDecorPalette.ink,
          border: CaptroStudioDecorPalette.ink.opacity(0.72),
          fontDesign: .rounded
        )

      case .makeItCountBadge:
        CaptroStudioTextSticker(
          text: "MAKE IT COUNT",
          background: CaptroStudioDecorPalette.paper,
          foreground: CaptroStudioDecorPalette.coral,
          border: CaptroStudioDecorPalette.coral,
          fontDesign: .serif
        )

      case .mainCharacterBadge:
        CaptroStudioTextSticker(
          text: "MAIN CHARACTER",
          background: CaptroStudioDecorPalette.ink,
          foreground: CaptroStudioDecorPalette.paper,
          border: CaptroStudioDecorPalette.gold,
          fontDesign: .rounded
        )

      case .plotTwistSticker:
        ZStack {
          CaptroStudioBurstShape(points: 18, depth: 0.22)
            .fill(CaptroStudioDecorPalette.gold)
          CaptroStudioBurstShape(points: 18, depth: 0.22)
            .stroke(CaptroStudioDecorPalette.ink, lineWidth: max(1, size.width * 0.015))
          Text("PLOT\nTWIST")
            .font(.system(size: max(8, min(size.width * 0.17, size.height * 0.24)), weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(CaptroStudioDecorPalette.ink)
            .minimumScaleFactor(0.6)
            .padding(size.width * 0.16)
        }

      case .noContextSticker:
        CaptroStudioTextSticker(
          text: "NO CONTEXT",
          background: CaptroStudioDecorPalette.ink,
          foreground: .white,
          border: .clear,
          fontDesign: .monospaced
        )

      case .hahaSticker:
        ZStack {
          Text("HA")
            .offset(x: size.width * 0.10, y: size.height * 0.12)
            .foregroundStyle(CaptroStudioDecorPalette.cyan)
          Text("HA")
            .offset(x: -size.width * 0.08, y: -size.height * 0.10)
            .foregroundStyle(CaptroStudioDecorPalette.coral)
        }
        .font(.system(size: max(12, min(size.width * 0.32, size.height * 0.55)), weight: .black, design: .rounded))

      case .moodSticker:
        ZStack {
          Circle().fill(CaptroStudioDecorPalette.lilac)
          Circle().stroke(CaptroStudioDecorPalette.ink, lineWidth: max(1, size.width * 0.018))
          Text("MOOD")
            .font(.system(size: max(8, min(size.width * 0.19, size.height * 0.25)), weight: .black, design: .rounded))
            .foregroundStyle(CaptroStudioDecorPalette.ink)
            .minimumScaleFactor(0.65)
            .padding(size.width * 0.12)
        }

      case .beSeriousSticker:
        ZStack {
          CaptroStudioSpeechBubbleShape()
            .fill(CaptroStudioDecorPalette.paper)
          CaptroStudioSpeechBubbleShape()
            .stroke(CaptroStudioDecorPalette.ink, lineWidth: max(1, size.width * 0.018))
          Text("BE SERIOUS")
            .font(.system(size: max(8, min(size.width * 0.15, size.height * 0.22)), weight: .black, design: .rounded))
            .foregroundStyle(CaptroStudioDecorPalette.ink)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, size.width * 0.12)
            .padding(.bottom, size.height * 0.12)
        }

      case .wovenSun, .wovenBird, .diamondTotem, .textileRibbon:
        CaptroStudioWovenMotif(style: object)

      default:
        Color.clear
      }
    }
    .accessibilityHidden(true)
  }
}

private struct CaptroStudioPaperDecor: View {
  let style: MIRACaptroStudioObject

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        paperBase
        Canvas { context, canvasSize in
          switch style {
          case .gridPaper:
            let spacing = max(10, canvasSize.width / 11)
            for x in stride(from: CGFloat(0), through: canvasSize.width, by: spacing) {
              var line = Path()
              line.move(to: CGPoint(x: x, y: 0))
              line.addLine(to: CGPoint(x: x, y: canvasSize.height))
              context.stroke(line, with: .color(CaptroStudioDecorPalette.cyan.opacity(0.18)), lineWidth: 0.8)
            }
            for y in stride(from: CGFloat(0), through: canvasSize.height, by: spacing) {
              var line = Path()
              line.move(to: CGPoint(x: 0, y: y))
              line.addLine(to: CGPoint(x: canvasSize.width, y: y))
              context.stroke(line, with: .color(CaptroStudioDecorPalette.cyan.opacity(0.18)), lineWidth: 0.8)
            }

          case .newsprintPaper:
            for column in 0..<3 {
              let x = canvasSize.width * (0.08 + CGFloat(column) * 0.30)
              for row in 0..<9 {
                let y = canvasSize.height * (0.16 + CGFloat(row) * 0.075)
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x + canvasSize.width * 0.23, y: y))
                context.stroke(line, with: .color(CaptroStudioDecorPalette.ink.opacity(0.22)), lineWidth: 1)
              }
            }
            context.fill(
              Path(CGRect(x: canvasSize.width * 0.08, y: canvasSize.height * 0.07, width: canvasSize.width * 0.84, height: canvasSize.height * 0.045)),
              with: .color(CaptroStudioDecorPalette.ink.opacity(0.62))
            )

          case .blushPaper:
            for index in 0..<18 {
              let x = canvasSize.width * CGFloat((index * 37) % 101) / 101
              let y = canvasSize.height * CGFloat((index * 61) % 97) / 97
              context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: max(2, canvasSize.width * 0.018), height: max(2, canvasSize.width * 0.011))),
                with: .color(Color.white.opacity(0.22))
              )
            }

          case .midnightPaper:
            for index in 0..<30 {
              let x = canvasSize.width * CGFloat((index * 43) % 103) / 103
              let y = canvasSize.height * CGFloat((index * 29) % 89) / 89
              context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                with: .color(Color.white.opacity(index.isMultiple(of: 3) ? 0.30 : 0.12))
              )
            }

          case .textilePaper:
            let cell = max(18, canvasSize.width / 8)
            for row in 0...Int(canvasSize.height / cell) {
              for column in 0...Int(canvasSize.width / cell) {
                let center = CGPoint(x: CGFloat(column) * cell + cell / 2, y: CGFloat(row) * cell + cell / 2)
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - cell * 0.34))
                diamond.addLine(to: CGPoint(x: center.x + cell * 0.34, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + cell * 0.34))
                diamond.addLine(to: CGPoint(x: center.x - cell * 0.34, y: center.y))
                diamond.closeSubpath()
                let fill = (row + column).isMultiple(of: 2)
                  ? CaptroStudioDecorPalette.coral.opacity(0.72)
                  : CaptroStudioDecorPalette.forest.opacity(0.78)
                context.fill(diamond, with: .color(fill))
              }
            }

          default:
            for index in 0..<24 {
              let x = canvasSize.width * CGFloat((index * 47) % 97) / 97
              let y = canvasSize.height * CGFloat((index * 31) % 89) / 89
              var fiber = Path()
              fiber.move(to: CGPoint(x: x, y: y))
              fiber.addLine(to: CGPoint(x: min(canvasSize.width, x + canvasSize.width * 0.08), y: y + CGFloat(index % 3) - 1))
              context.stroke(fiber, with: .color(CaptroStudioDecorPalette.ink.opacity(0.07)), lineWidth: 0.7)
            }
          }
        }
      }
      .clipShape(style == .decklePaper ? AnyShape(CaptroStudioDeckleShape(amplitude: 0.018)) : AnyShape(Rectangle()))
      .overlay {
        if style != .decklePaper {
          Rectangle().stroke(borderColor, lineWidth: max(0.7, size.width * 0.004))
        }
      }
    }
  }

  private var paperBase: Color {
    switch style {
    case .gridPaper: return Color(red: 0.96, green: 0.95, blue: 0.90)
    case .newsprintPaper: return Color(red: 0.88, green: 0.83, blue: 0.70)
    case .blushPaper: return Color(red: 0.86, green: 0.64, blue: 0.65)
    case .midnightPaper: return Color(red: 0.08, green: 0.09, blue: 0.09)
    case .textilePaper: return Color(red: 0.84, green: 0.69, blue: 0.34)
    default: return CaptroStudioDecorPalette.paper
    }
  }

  private var borderColor: Color {
    style == .midnightPaper ? Color.white.opacity(0.18) : CaptroStudioDecorPalette.ink.opacity(0.12)
  }
}

private struct CaptroStudioTextSticker: View {
  let text: String
  let background: Color
  let foreground: Color
  let border: Color
  let fontDesign: Font.Design
  var dashed = false

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        RoundedRectangle(cornerRadius: min(7, size.height * 0.16), style: .continuous)
          .fill(background)
        RoundedRectangle(cornerRadius: min(7, size.height * 0.16), style: .continuous)
          .stroke(
            border,
            style: StrokeStyle(
              lineWidth: max(1, size.width * 0.012),
              dash: dashed ? [5, 3] : []
            )
          )
          .padding(max(1, size.width * 0.025))
        Text(text)
          .font(.system(size: max(8, min(size.width * 0.14, size.height * 0.28)), weight: .black, design: fontDesign))
          .tracking(0)
          .foregroundStyle(foreground)
          .lineLimit(1)
          .minimumScaleFactor(0.48)
          .padding(.horizontal, size.width * 0.10)
      }
    }
  }
}

private struct CaptroStudioWovenMotif: View {
  let style: MIRACaptroStudioObject

  var body: some View {
    Canvas { context, size in
      switch style {
      case .wovenSun:
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let outer = min(size.width, size.height) * 0.40
        for ray in 0..<12 {
          let angle = CGFloat(ray) * .pi * 2 / 12
          let start = CGPoint(x: center.x + cos(angle) * outer * 0.62, y: center.y + sin(angle) * outer * 0.62)
          let end = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
          var line = Path()
          line.move(to: start)
          line.addLine(to: end)
          context.stroke(line, with: .color(ray.isMultiple(of: 2) ? CaptroStudioDecorPalette.coral : CaptroStudioDecorPalette.forest), lineWidth: max(2, outer * 0.11))
        }
        context.fill(Path(ellipseIn: CGRect(x: center.x - outer * 0.55, y: center.y - outer * 0.55, width: outer * 1.1, height: outer * 1.1)), with: .color(CaptroStudioDecorPalette.gold))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - outer * 0.30, y: center.y - outer * 0.30, width: outer * 0.6, height: outer * 0.6)), with: .color(CaptroStudioDecorPalette.ink), lineWidth: max(1, outer * 0.08))

      case .wovenBird:
        var bird = Path()
        bird.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.58))
        bird.addCurve(to: CGPoint(x: size.width * 0.63, y: size.height * 0.54), control1: CGPoint(x: size.width * 0.28, y: size.height * 0.28), control2: CGPoint(x: size.width * 0.48, y: size.height * 0.32))
        bird.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.28))
        bird.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.62))
        bird.addCurve(to: CGPoint(x: size.width * 0.22, y: size.height * 0.72), control1: CGPoint(x: size.width * 0.52, y: size.height * 0.86), control2: CGPoint(x: size.width * 0.34, y: size.height * 0.80))
        bird.closeSubpath()
        context.fill(bird, with: .color(CaptroStudioDecorPalette.gold))
        context.stroke(bird, with: .color(CaptroStudioDecorPalette.ink), lineWidth: max(1, size.width * 0.018))
        for stripe in 0..<4 {
          let x = size.width * (0.36 + CGFloat(stripe) * 0.09)
          var line = Path()
          line.move(to: CGPoint(x: x, y: size.height * 0.40))
          line.addLine(to: CGPoint(x: x + size.width * 0.08, y: size.height * 0.70))
          context.stroke(line, with: .color(stripe.isMultiple(of: 2) ? CaptroStudioDecorPalette.coral : CaptroStudioDecorPalette.forest), lineWidth: max(2, size.width * 0.026))
        }

      case .diamondTotem:
        for index in 0..<3 {
          let centerY = size.height * (0.20 + CGFloat(index) * 0.30)
          let radius = min(size.width * 0.29, size.height * 0.14)
          var diamond = Path()
          diamond.move(to: CGPoint(x: size.width * 0.5, y: centerY - radius))
          diamond.addLine(to: CGPoint(x: size.width * 0.5 + radius, y: centerY))
          diamond.addLine(to: CGPoint(x: size.width * 0.5, y: centerY + radius))
          diamond.addLine(to: CGPoint(x: size.width * 0.5 - radius, y: centerY))
          diamond.closeSubpath()
          let fill = index == 0 ? CaptroStudioDecorPalette.gold : (index == 1 ? CaptroStudioDecorPalette.coral : CaptroStudioDecorPalette.forest)
          context.fill(diamond, with: .color(fill))
          context.stroke(diamond, with: .color(CaptroStudioDecorPalette.ink), lineWidth: max(1, size.width * 0.022))
          context.fill(Path(ellipseIn: CGRect(x: size.width * 0.5 - radius * 0.22, y: centerY - radius * 0.22, width: radius * 0.44, height: radius * 0.44)), with: .color(CaptroStudioDecorPalette.paper))
        }

      default:
        let cell = max(12, size.width / 8)
        for index in 0...8 {
          let x = CGFloat(index) * cell
          var chevron = Path()
          chevron.move(to: CGPoint(x: x, y: size.height * 0.18))
          chevron.addLine(to: CGPoint(x: x + cell * 0.5, y: size.height * 0.50))
          chevron.addLine(to: CGPoint(x: x, y: size.height * 0.82))
          context.stroke(chevron, with: .color(index.isMultiple(of: 3) ? CaptroStudioDecorPalette.coral : (index.isMultiple(of: 2) ? CaptroStudioDecorPalette.gold : CaptroStudioDecorPalette.forest)), lineWidth: max(3, size.height * 0.16))
        }
      }
    }
  }
}

private struct CaptroStudioDeckleShape: Shape {
  let amplitude: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.02))
    for index in 1...18 {
      let x = rect.minX + rect.width * CGFloat(index) / 18
      let y = rect.minY + rect.height * (index.isMultiple(of: 2) ? 0 : amplitude)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in 1...14 {
      let y = rect.minY + rect.height * CGFloat(index) / 14
      let x = rect.maxX - rect.width * (index.isMultiple(of: 2) ? 0 : amplitude)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: 18, through: 0, by: -1) {
      let x = rect.minX + rect.width * CGFloat(index) / 18
      let y = rect.maxY - rect.height * (index.isMultiple(of: 2) ? 0 : amplitude)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: 14, through: 0, by: -1) {
      let y = rect.minY + rect.height * CGFloat(index) / 14
      let x = rect.minX + rect.width * (index.isMultiple(of: 2) ? 0 : amplitude)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}

private struct CaptroStudioBurstShape: Shape {
  let points: Int
  let depth: CGFloat

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) * 0.49
    let inner = outer * (1 - depth)
    var path = Path()
    for index in 0..<(points * 2) {
      let radius = index.isMultiple(of: 2) ? outer : inner
      let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
      let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

private struct CaptroStudioSpeechBubbleShape: Shape {
  func path(in rect: CGRect) -> Path {
    let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.80)
    var path = Path(roundedRect: body, cornerRadius: min(7, rect.height * 0.12))
    var tail = Path()
    tail.move(to: CGPoint(x: rect.width * 0.22, y: body.maxY - 1))
    tail.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.maxY))
    tail.addLine(to: CGPoint(x: rect.width * 0.47, y: body.maxY - 1))
    tail.closeSubpath()
    path.addPath(tail)
    return path
  }
}

private enum CaptroStudioDecorPalette {
  static let paper = Color(red: 0.95, green: 0.92, blue: 0.82)
  static let ink = Color(red: 0.08, green: 0.09, blue: 0.08)
  static let gold = Color(red: 0.88, green: 0.66, blue: 0.16)
  static let coral = Color(red: 0.72, green: 0.25, blue: 0.20)
  static let forest = Color(red: 0.18, green: 0.31, blue: 0.20)
  static let sage = Color(red: 0.69, green: 0.76, blue: 0.60)
  static let lilac = Color(red: 0.75, green: 0.65, blue: 0.84)
  static let cyan = Color(red: 0.20, green: 0.69, blue: 0.78)
}
